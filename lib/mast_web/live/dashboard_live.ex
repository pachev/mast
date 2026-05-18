defmodule MastWeb.DashboardLive do
  use MastWeb, :live_view

  alias Mast.Fleet
  alias Mast.Fleet.Server

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Mast.PubSub, "servers")

    servers = Fleet.list_servers()

    {:ok,
     socket
     |> assign(:page_title, "Fleet")
     |> assign(:filter, "")
     |> assign(:server_count, length(servers))
     |> assign(:keys, [])
     |> stream(:servers, servers)}
  end

  @impl true
  def handle_info({:server_updated, server}, socket) do
    {:noreply, stream_insert(socket, :servers, server)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :form, nil)
  end

  defp apply_action(socket, :new, _params) do
    cs = Fleet.change_server(%Server{user: "ubuntu", port: 22})

    socket
    |> assign(:form, to_form(cs, as: :server))
    |> assign(:keys, Mast.Keys.list_keys())
  end

  @impl true
  def handle_event("validate", %{"server" => params}, socket) do
    cs =
      %Server{}
      |> Fleet.change_server(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs, as: :server))}
  end

  def handle_event("save", %{"server" => params}, socket) do
    case Fleet.create_server(params) do
      {:ok, server} ->
        {:noreply,
         socket
         |> stream_insert(:servers, server, at: -1)
         |> update(:server_count, &(&1 + 1))
         |> put_flash(:info, "Added #{server.name}")
         |> push_patch(to: ~p"/")}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: :server))}
    end
  end

  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, :filter, q)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/")}
  end

  def handle_event("check", %{"id" => id}, socket) do
    server = Fleet.get_server!(String.to_integer(id))

    %{server_id: server.id}
    |> Mast.Workers.ConnectionCheck.new()
    |> Oban.insert!()

    {:noreply, put_flash(socket, :info, "Checking #{server.name}…")}
  end

  # --- Render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 text-base-content py-6 px-4 sm:px-6 lg:px-10">
      <.app_chrome />

      <main class="mt-6 mx-auto max-w-7xl">
        <.card>
          <:header>
            <div>
              <h1 class="text-2xl font-semibold tracking-tight">All Systems</h1>
              <p class="text-sm text-base-content/60 mt-1">
                Updated in real time. Click on a system to view information.
              </p>
            </div>
            <div class="flex items-center gap-2">
              <form phx-change="filter" class="hidden sm:block">
                <input
                  type="text"
                  name="q"
                  value={@filter}
                  placeholder="Filter…"
                  class="input input-bordered input-sm w-48"
                />
              </form>
            </div>
          </:header>

          <.servers_table
            id="servers"
            stream={@streams.servers}
            filter={@filter}
            count={@server_count}
          />
        </.card>

        <p class="text-right text-xs text-base-content/50 mt-4">
          <span class="opacity-70">Mast</span> · v0.1
        </p>
      </main>

      <.new_server_modal :if={@live_action == :new} form={@form} keys={@keys} />
    </div>
    """
  end

  # --- Sub-components -------------------------------------------------------

  defp app_chrome(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl">
      <div class="flex items-center gap-3 rounded-2xl bg-base-100 border border-base-300 px-4 py-3 shadow-sm">
        <a href="/" class="text-xl font-bold tracking-tight pr-1">Mast</a>

        <label class="input input-sm input-bordered flex items-center gap-2 w-72 max-w-full ml-2">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            class="h-4 w-4 opacity-60"
          >
            <circle cx="11" cy="11" r="7" />
            <path d="m21 21-4.3-4.3" />
          </svg>
          <input type="search" placeholder="Search" class="grow" disabled />
          <kbd class="kbd kbd-xs">⌘</kbd>
          <kbd class="kbd kbd-xs">K</kbd>
        </label>

        <div class="ml-auto flex items-center gap-1">
          <button class="btn btn-ghost btn-sm btn-circle" title="Settings" disabled>
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              class="h-4 w-4"
            >
              <circle cx="12" cy="12" r="3" />
              <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h.01a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51h.01a1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v.01a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
            </svg>
          </button>

          <.link patch={~p"/servers/new"} class="btn btn-primary btn-sm rounded-xl ml-1">
            <span class="text-base leading-none">+</span> Add System
          </.link>
        </div>
      </div>
    </div>
    """
  end

  slot :header
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <section class="rounded-2xl bg-base-100 border border-base-300 shadow-sm overflow-hidden">
      <header :if={@header != []} class="flex items-end justify-between gap-4 px-6 pt-6 pb-4">
        {render_slot(@header)}
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :id, :string, required: true
  attr :stream, :any, required: true
  attr :filter, :string, default: ""
  attr :count, :integer, default: 0

  defp servers_table(assigns) do
    ~H"""
    <div class="px-6 pb-6">
      <div class="hidden md:grid grid-cols-12 gap-4 text-[12px] uppercase tracking-wider text-base-content/50 py-3 border-b border-base-300">
        <div class="col-span-3 flex items-center gap-2">
          <.svg_icon name="server" /> System
        </div>
        <div class="col-span-2 flex items-center gap-2">
          <.svg_icon name="cpu" /> CPU
        </div>
        <div class="col-span-2 flex items-center gap-2">
          <.svg_icon name="memory" /> Memory
        </div>
        <div class="col-span-2 flex items-center gap-2">
          <.svg_icon name="disk" /> Disk
        </div>
        <div class="col-span-1 flex items-center gap-2">
          <.svg_icon name="net" /> Net
        </div>
        <div class="col-span-2 flex items-center gap-2">
          <.svg_icon name="agent" /> Agent
        </div>
      </div>

      <div id={@id} phx-update="stream" class="divide-y divide-base-300">
        <div
          :for={{dom_id, s} <- @stream}
          id={dom_id}
          class={["py-3", hidden_if_filtered(s, @filter)]}
        >
          <.server_row server={s} />
        </div>
      </div>

      <div :if={@count == 0} class="py-16 text-center text-base-content/60">
        <p class="text-base">No systems yet.</p>
        <p class="text-sm mt-1">
          Click <span class="font-medium">Add System</span> to register your first server.
        </p>
      </div>
    </div>
    """
  end

  attr :server, :map, required: true

  defp server_row(assigns) do
    ~H"""
    <div class="grid grid-cols-12 gap-4 items-center text-sm">
      <.link
        navigate={~p"/servers/#{@server.id}"}
        class="col-span-12 md:col-span-3 flex items-center gap-3 min-w-0 hover:opacity-80"
      >
        <.status_dot status={@server.status} />
        <div class="min-w-0">
          <div class="font-medium truncate">{@server.name}</div>
          <div class="text-xs text-base-content/50 truncate">
            {@server.user}@{@server.host}:{@server.port}
          </div>
        </div>
      </.link>

      <div class="col-span-6 md:col-span-2">
        <.metric_bar value={@server.cpu} suffix="%" tone={:cpu} />
      </div>
      <div class="col-span-6 md:col-span-2">
        <.metric_bar value={@server.memory} suffix="%" tone={:mem} />
      </div>
      <div class="col-span-6 md:col-span-2">
        <.metric_bar value={@server.disk} suffix="%" tone={:disk} />
      </div>
      <div class="col-span-3 md:col-span-1 text-right md:text-left tabular-nums text-xs text-base-content/70">
        {format_net(@server.net_mb_s)}
      </div>
      <div class="col-span-3 md:col-span-2 flex items-center justify-end md:justify-start gap-2">
        <span class={agent_dot_class(@server.agent_version)} />
        <span class="text-xs tabular-nums text-base-content/70 flex-1 truncate">
          {format_last_seen(@server)}
        </span>
        <button
          type="button"
          phx-click="check"
          phx-value-id={@server.id}
          class="btn btn-ghost btn-xs"
          title="Run a connection check now"
        >
          Check
        </button>
      </div>
    </div>
    """
  end

  defp format_last_seen(%{last_seen_at: nil}), do: "never"

  defp format_last_seen(%{last_seen_at: t}) do
    diff = DateTime.diff(DateTime.utc_now(), t, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  attr :value, :any, required: true
  attr :suffix, :string, default: ""
  attr :tone, :atom, default: :cpu

  defp metric_bar(assigns) do
    pct = clamp(assigns[:value])
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div class="flex items-center gap-3">
      <span class="w-12 tabular-nums text-xs text-base-content/80">{format_pct(@value)}</span>
      <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
        <div
          class={["h-full rounded-full transition-all", bar_color(@pct)]}
          style={"width: #{@pct}%;"}
        />
      </div>
    </div>
    """
  end

  attr :status, :string, required: true

  defp status_dot(assigns) do
    ~H"""
    <span class={[
      "h-2.5 w-2.5 rounded-full shrink-0",
      dot_class(@status)
    ]} />
    """
  end

  defp dot_class("up"), do: "bg-emerald-500"
  defp dot_class("down"), do: "bg-rose-500"
  defp dot_class(_), do: "bg-base-300"

  defp agent_dot_class(nil), do: "h-2.5 w-2.5 rounded-full bg-base-300"
  defp agent_dot_class(_), do: "h-2.5 w-2.5 rounded-full bg-amber-400"

  defp bar_color(nil), do: "bg-base-300"
  defp bar_color(pct) when pct >= 80, do: "bg-amber-400"
  defp bar_color(pct) when pct >= 95, do: "bg-rose-500"
  defp bar_color(_), do: "bg-emerald-500"

  defp clamp(nil), do: 0
  defp clamp(n) when is_number(n) and n < 0, do: 0
  defp clamp(n) when is_number(n) and n > 100, do: 100
  defp clamp(n) when is_number(n), do: n
  defp clamp(_), do: 0

  defp format_pct(nil), do: "—"
  defp format_pct(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1) <> "%"
  defp format_pct(n), do: "#{n}%"

  defp format_net(nil), do: "—"
  defp format_net(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2) <> " MB/s"
  defp format_net(n), do: "#{n} MB/s"

  defp hidden_if_filtered(_server, ""), do: ""

  defp hidden_if_filtered(server, q) do
    s = String.downcase(q)

    cond do
      String.contains?(String.downcase(server.name || ""), s) -> ""
      String.contains?(String.downcase(server.host || ""), s) -> ""
      true -> "hidden"
    end
  end

  # --- New server modal ----------------------------------------------------

  attr :form, :any, required: true
  attr :keys, :list, required: true

  defp new_server_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
      phx-window-keydown="cancel"
      phx-key="escape"
    >
      <div class="w-full max-w-md rounded-2xl bg-base-100 border border-base-300 shadow-xl p-6">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-lg font-semibold">Add a system</h2>
            <p class="text-sm text-base-content/60 mt-1">
              Register a server to monitor.
            </p>
          </div>
          <.link patch={~p"/"} class="btn btn-ghost btn-sm btn-circle" aria-label="Close">✕</.link>
        </div>

        <.form
          for={@form}
          id="new-server-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-4 space-y-4"
        >
          <.input field={@form[:name]} label="Name" placeholder="web-1" required />
          <.input field={@form[:host]} label="Host" placeholder="10.0.0.7 or fqdn" required />
          <div class="grid grid-cols-2 gap-3">
            <.input field={@form[:user]} label="SSH user" placeholder="ubuntu" />
            <.input field={@form[:port]} type="number" label="Port" placeholder="22" />
          </div>

          <.input
            field={@form[:private_key_id]}
            type="select"
            label="Private key"
            prompt={
              if @keys == [],
                do: "No keys registered — add one in key management first",
                else: "— none —"
            }
            options={Enum.map(@keys, &{key_label(&1), &1.id})}
          />

          <div class="flex justify-end gap-2 pt-2">
            <.link patch={~p"/"} class="btn btn-ghost btn-sm">Cancel</.link>
            <button type="submit" class="btn btn-primary btn-sm">Add System</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp key_label(key) do
    "#{key.name} (#{key.algorithm}, #{String.slice(key.fingerprint, 0, 19)}…)"
  end

  # Tiny inline SVG icons (header row).
  attr :name, :string, required: true

  defp svg_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      class="h-3.5 w-3.5 opacity-70"
    >
      <%= case @name do %>
        <% "server" -> %>
          <rect x="3" y="4" width="18" height="6" rx="1.5" />
          <rect x="3" y="14" width="18" height="6" rx="1.5" />
          <circle cx="7" cy="7" r="0.5" fill="currentColor" />
          <circle cx="7" cy="17" r="0.5" fill="currentColor" />
        <% "cpu" -> %>
          <rect x="6" y="6" width="12" height="12" rx="1.5" />
          <rect x="9" y="9" width="6" height="6" />
          <path d="M9 3v3M12 3v3M15 3v3M9 18v3M12 18v3M15 18v3M3 9h3M3 12h3M3 15h3M18 9h3M18 12h3M18 15h3" />
        <% "memory" -> %>
          <path d="M3 8h18M3 16h18" />
          <path d="M6 8v8M10 8v8M14 8v8M18 8v8" />
        <% "disk" -> %>
          <ellipse cx="12" cy="6" rx="9" ry="3" />
          <path d="M3 6v6c0 1.7 4 3 9 3s9-1.3 9-3V6" />
          <path d="M3 12v6c0 1.7 4 3 9 3s9-1.3 9-3v-6" />
        <% "net" -> %>
          <circle cx="12" cy="12" r="9" />
          <path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" />
        <% "agent" -> %>
          <path d="M5 12a10 10 0 0 1 14 0" />
          <path d="M8.5 15.5a5 5 0 0 1 7 0" />
          <circle cx="12" cy="19" r="1.2" fill="currentColor" />
      <% end %>
    </svg>
    """
  end
end

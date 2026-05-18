defmodule MastWeb.ServerLive do
  use MastWeb, :live_view

  alias Mast.Fleet
  alias Mast.Patches.Apt
  alias Mast.Workers.{ApplyUpdates, ConnectionCheck, PatchScan}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    server = Fleet.get_server!(String.to_integer(id))

    run_id = generate_run_id()
    topic = "runs:#{run_id}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mast.PubSub, "servers")
      Phoenix.PubSub.subscribe(Mast.PubSub, topic)
    end

    {:ok,
     socket
     |> assign(:page_title, server.name)
     |> assign(:server, server)
     |> assign(:run_id, run_id)
     |> assign(:running?, false)
     |> assign(:scanning?, false)
     |> assign(:scan_error, nil)
     |> stream(:log, [])
     |> assign(:log_count, 0)}
  end

  @impl true
  def handle_info({:server_updated, %{id: id} = server}, socket) do
    if id == socket.assigns.server.id do
      {:noreply,
       socket
       |> assign(:server, server)
       |> assign(:scanning?, false)
       |> assign(:scan_error, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:scan_failed, id, reason}, socket) do
    if id == socket.assigns.server.id do
      {:noreply,
       socket
       |> assign(:scanning?, false)
       |> assign(:scan_error, reason)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:run_event, run_id, event}, socket) do
    if run_id == socket.assigns.run_id do
      {:noreply, append_event(socket, event)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("check", _, socket) do
    %{server_id: socket.assigns.server.id}
    |> ConnectionCheck.new()
    |> Oban.insert!()

    {:noreply, put_flash(socket, :info, "Checking…")}
  end

  def handle_event("scan", _, socket) do
    %{server_id: socket.assigns.server.id}
    |> PatchScan.new()
    |> Oban.insert!()

    {:noreply,
     socket
     |> assign(:scanning?, true)
     |> assign(:scan_error, nil)}
  end

  def handle_event("apply_all", _, socket) do
    enqueue_apply(socket, %{"scope" => "all"})
  end

  def handle_event("apply_package", %{"name" => name}, socket) do
    enqueue_apply(socket, %{"scope" => "package", "package" => name})
  end

  def handle_event("clear_log", _, socket) do
    {:noreply,
     socket
     |> stream(:log, [], reset: true)
     |> assign(:log_count, 0)
     |> assign(:running?, false)}
  end

  defp enqueue_apply(socket, extra) do
    args =
      Map.merge(extra, %{
        "server_id" => socket.assigns.server.id,
        "run_id" => socket.assigns.run_id
      })

    case ApplyUpdates.new(args) |> Oban.insert() do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:running?, true)
         |> stream(:log, [], reset: true)
         |> assign(:log_count, 0)
         |> put_flash(:info, "Running…")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to enqueue: #{inspect(reason)}")}
    end
  end

  defp append_event(socket, {:line, kind, data}) do
    id = socket.assigns.log_count + 1

    socket
    |> stream_insert(:log, %{id: id, kind: kind, data: String.trim_trailing(data, "\n")})
    |> assign(:log_count, id)
  end

  defp append_event(socket, {:exit, code}) do
    id = socket.assigns.log_count + 1
    label = if code == 0, do: "exit 0 (success)", else: "exit #{code} (failed)"

    socket
    |> stream_insert(:log, %{id: id, kind: :exit, data: label})
    |> assign(:log_count, id)
    |> assign(:running?, false)
  end

  defp append_event(socket, {:error, reason}) do
    id = socket.assigns.log_count + 1

    socket
    |> stream_insert(:log, %{id: id, kind: :error, data: "error: #{inspect(reason)}"})
    |> assign(:log_count, id)
    |> assign(:running?, false)
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  # ----------------------- Render --------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 text-base-content py-6 px-4 sm:px-6 lg:px-10">
      <div class="mx-auto max-w-7xl">
        <nav class="text-sm text-base-content/60 mb-4">
          <.link navigate={~p"/"} class="hover:underline">All Systems</.link>
          <span class="mx-1">/</span>
          <span class="text-base-content">{@server.name}</span>
        </nav>

        <header class="rounded-2xl bg-base-100 border border-base-300 px-6 py-5 shadow-sm flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0">
            <div class="flex items-center gap-3">
              <.status_dot status={@server.status} />
              <h1 class="text-2xl font-semibold tracking-tight truncate">{@server.name}</h1>
              <span class="badge badge-ghost badge-sm">{@server.os_id || "?"}</span>
              <span class="badge badge-ghost badge-sm">{@server.package_manager || "?"}</span>
            </div>
            <p class="text-sm text-base-content/60 mt-1">
              {@server.user}@{@server.host}:{@server.port}
              <span class="mx-2">·</span>
              <span>{last_seen(@server)}</span>
            </p>
          </div>

          <div class="flex items-center gap-2">
            <button type="button" phx-click="check" class="btn btn-ghost btn-sm">Check</button>
            <button
              type="button"
              phx-click="scan"
              class="btn btn-ghost btn-sm gap-2"
              disabled={@scanning?}
            >
              <span :if={@scanning?} class="loading loading-spinner loading-xs" />
              {if @scanning?, do: "Scanning…", else: "Scan updates"}
            </button>
          </div>
        </header>

        <section class="grid md:grid-cols-3 gap-4 mt-4">
          <.stat label="CPU" value={@server.cpu} />
          <.stat label="Memory" value={@server.memory} />
          <.stat label="Disk" value={@server.disk} />
        </section>

        <section class="mt-4 rounded-2xl bg-base-100 border border-base-300 shadow-sm overflow-hidden">
          <header class="flex items-end justify-between gap-4 px-6 pt-6 pb-3 border-b border-base-300">
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <h2 class="text-lg font-semibold">Available updates</h2>
                <span :if={@scanning?} class="badge badge-warning badge-sm gap-1">
                  <span class="loading loading-spinner loading-xs" /> scanning
                </span>
              </div>
              <p class="text-sm mt-0.5 text-base-content/60">
                <.scan_status_text
                  server={@server}
                  scanning?={@scanning?}
                  scan_error={@scan_error}
                />
              </p>
            </div>
            <button
              type="button"
              phx-click="apply_all"
              class="btn btn-primary btn-sm"
              disabled={@running? or @scanning? or (@server.updates_available || 0) == 0}
            >
              Apply All Updates
            </button>
          </header>

          <.updates_table
            server={@server}
            scanning?={@scanning?}
            running?={@running?}
          />
        </section>

        <section class="mt-4 rounded-2xl bg-base-100 border border-base-300 shadow-sm overflow-hidden">
          <header class="flex items-center justify-between px-6 pt-5 pb-3 border-b border-base-300">
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold">Run log</h2>
              <span :if={@running?} class="badge badge-warning badge-sm gap-1">
                <span class="loading loading-spinner loading-xs" /> running
              </span>
            </div>
            <button
              type="button"
              phx-click="clear_log"
              class="btn btn-ghost btn-xs"
              disabled={@log_count == 0}
            >
              Clear
            </button>
          </header>

          <div class="px-2 py-2 relative">
            <div
              :if={@log_count == 0}
              class="absolute inset-x-5 top-5 text-base-content/40 italic font-mono text-xs pointer-events-none"
            >
              idle — output will appear here when an upgrade runs.
            </div>
            <div
              id="run-log"
              phx-update="stream"
              class="font-mono text-xs bg-base-300/30 rounded-lg p-3 max-h-96 overflow-y-auto whitespace-pre-wrap break-all min-h-16"
            >
              <div
                :for={{dom_id, line} <- @streams.log}
                id={dom_id}
                class={line_class(line.kind)}
              >
                {line.data}
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :status, :string, required: true

  defp status_dot(assigns) do
    ~H"""
    <span class={[
      "h-3 w-3 rounded-full shrink-0",
      case @status do
        "up" -> "bg-emerald-500"
        "down" -> "bg-rose-500"
        _ -> "bg-base-300"
      end
    ]} />
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-2xl bg-base-100 border border-base-300 px-6 py-4 shadow-sm">
      <div class="text-xs uppercase tracking-wider text-base-content/50">{@label}</div>
      <div class="mt-1 text-2xl font-semibold tabular-nums">
        {format_pct(@value)}
      </div>
      <div class="mt-3 h-2 rounded-full bg-base-300 overflow-hidden">
        <div class={["h-full", bar_color(@value)]} style={"width: #{clamp(@value)}%"} />
      </div>
    </div>
    """
  end

  attr :server, :map, required: true
  attr :scanning?, :boolean, required: true
  attr :running?, :boolean, required: true

  defp updates_table(assigns) do
    updates = updates_list(assigns.server)
    state = empty_state(assigns.server, assigns.scanning?, updates)

    assigns = assign(assigns, updates: updates, state: state)

    ~H"""
    <div :if={@state == :scanning} class="px-6 py-12 text-center text-sm text-base-content/60">
      <span class="loading loading-spinner loading-md" />
      <p class="mt-3">Running <code>apt list --upgradable</code> — this can take a few seconds…</p>
    </div>

    <div :if={@state == :never_scanned} class="px-6 py-10 text-center text-sm text-base-content/60">
      <p>Not scanned yet.</p>
      <p class="mt-1">Click <span class="font-medium">Scan updates</span> to check.</p>
    </div>

    <div :if={@state == :clean} class="px-6 py-10 text-center text-sm">
      <p class="font-medium text-emerald-500">All up to date</p>
      <p class="text-base-content/60 mt-1">No package updates available.</p>
    </div>

    <div :if={@state == :has_updates} class="px-6 py-4 overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="text-xs uppercase tracking-wider text-base-content/50 border-b border-base-300">
            <th class="text-left py-2 pr-4">Package</th>
            <th class="text-left py-2 pr-4">Current</th>
            <th class="text-left py-2 pr-4">New</th>
            <th class="text-right py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={u <- @updates} class="border-b border-base-300/60 last:border-0">
            <td class="py-2 pr-4 font-medium">{u["package"]}</td>
            <td class="py-2 pr-4 tabular-nums text-base-content/70">{u["current_version"]}</td>
            <td class="py-2 pr-4 tabular-nums text-base-content/70">{u["new_version"]}</td>
            <td class="py-2 text-right">
              <button
                type="button"
                phx-click="apply_package"
                phx-value-name={u["package"]}
                class="btn btn-ghost btn-xs"
                disabled={@running? or @scanning? or not Apt.safe_package_name?(u["package"])}
              >
                Apply
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp empty_state(_server, true, _updates), do: :scanning
  defp empty_state(%{last_scan_at: nil}, _, _), do: :never_scanned
  defp empty_state(_, _, []), do: :clean
  defp empty_state(_, _, _), do: :has_updates

  defp updates_list(%{last_scan: %{"updates" => updates}}) when is_list(updates), do: updates
  defp updates_list(_), do: []

  attr :server, :map, required: true
  attr :scanning?, :boolean, required: true
  attr :scan_error, :any, required: true

  defp scan_status_text(assigns) do
    ~H"""
    <%= cond do %>
      <% @scan_error -> %>
        <span class="text-rose-500">Scan failed: {@scan_error}</span>
      <% @scanning? -> %>
        Scanning…
      <% @server.last_scan_at -> %>
        Last scanned {format_relative(@server.last_scan_at)}.
        <%= cond do %>
          <% (@server.updates_available || 0) == 0 -> %>
            Nothing to install.
          <% true -> %>
            {@server.updates_available} package(s) available.
        <% end %>
      <% true -> %>
        Not scanned yet. Click <span class="font-medium">Scan updates</span>.
    <% end %>
    """
  end

  defp line_class(:stdout), do: "text-base-content"
  defp line_class(:stderr), do: "text-amber-500"
  defp line_class(:exit), do: "text-emerald-500 font-semibold mt-2"
  defp line_class(:error), do: "text-rose-500 font-semibold"

  defp clamp(nil), do: 0
  defp clamp(n) when is_number(n) and n < 0, do: 0
  defp clamp(n) when is_number(n) and n > 100, do: 100
  defp clamp(n) when is_number(n), do: n
  defp clamp(_), do: 0

  defp bar_color(nil), do: "bg-base-300"
  defp bar_color(pct) when pct >= 95, do: "bg-rose-500"
  defp bar_color(pct) when pct >= 80, do: "bg-amber-400"
  defp bar_color(_), do: "bg-emerald-500"

  defp format_pct(nil), do: "—"
  defp format_pct(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1) <> "%"
  defp format_pct(n), do: "#{n}%"

  defp last_seen(%{last_seen_at: nil}), do: "never seen"
  defp last_seen(%{last_seen_at: t}), do: "last seen #{format_relative(t)}"

  defp format_relative(t) do
    diff = DateTime.diff(DateTime.utc_now(), t, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end

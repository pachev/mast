defmodule MastWeb.ServerLive do
  use MastWeb, :live_view

  alias Mast.{Apps, Fleet}
  alias Mast.Patches.Apt
  alias Mast.Workers.{ApplyUpdates, AppProbe, ConnectionCheck, PatchScan}

  @tabs ~w(overview apps logs updates settings)

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
     |> assign(:tab, "overview")
     |> assign(:run_id, run_id)
     |> assign(:running?, false)
     |> assign(:scanning?, false)
     |> assign(:scan_error, nil)
     |> assign(:probing?, false)
     |> assign(:probe_error, nil)
     |> assign(:apps, Apps.list_for_server(server.id))
     |> assign(:show_system_apps?, false)
     |> assign(:monitoring_form, monitoring_form(server))
     |> stream(:log, [])
     |> assign(:log_count, 0)}
  end

  defp monitoring_form(server) do
    server
    |> Mast.Fleet.Server.monitoring_changeset(%{})
    |> to_form(as: :monitoring)
  end

  @impl true
  def handle_params(%{"tab" => tab}, _url, socket) when tab in @tabs do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :tab, "overview")}
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

  def handle_info({:apps_updated, server_id}, socket) do
    if server_id == socket.assigns.server.id do
      {:noreply,
       socket
       |> assign(:apps, Apps.list_for_server(server_id))
       |> assign(:probing?, false)
       |> assign(:probe_error, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:apps_probe_failed, server_id, reason}, socket) do
    if server_id == socket.assigns.server.id do
      {:noreply,
       socket
       |> assign(:probing?, false)
       |> assign(:probe_error, inspect(reason))}
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
  def handle_event("set-tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply,
     socket
     |> assign(:tab, tab)
     |> push_patch(to: ~p"/servers/#{socket.assigns.server.id}?tab=#{tab}")}
  end

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

  def handle_event("toggle-system-apps", _, socket) do
    {:noreply, update(socket, :show_system_apps?, &(!&1))}
  end

  def handle_event("probe-apps", _, socket) do
    %{server_id: socket.assigns.server.id}
    |> AppProbe.new()
    |> Oban.insert!()

    {:noreply,
     socket
     |> assign(:probing?, true)
     |> assign(:probe_error, nil)}
  end

  def handle_event("save-monitoring", %{"monitoring" => params}, socket) do
    case Fleet.update_monitoring(socket.assigns.server, params) do
      {:ok, server} ->
        {:noreply,
         socket
         |> assign(:server, server)
         |> assign(:monitoring_form, monitoring_form(server))
         |> put_flash(:info, "Monitoring updated")}

      {:error, cs} ->
        {:noreply, assign(socket, :monitoring_form, to_form(cs, as: :monitoring))}
    end
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

  # ----------------------- Render -------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="servers" page_title={@server.name}>
      <nav class="text-sm text-[var(--mast-font-secondary)] mb-3">
        <.link navigate={~p"/"} class="hover:text-[var(--mast-font-primary)]">Servers</.link>
        <span class="mx-1.5">/</span>
        <span class="text-[var(--mast-font-primary)] font-mono">{@server.name}</span>
      </nav>

      <.ui_card class="mb-5" padded={false}>
        <div class="px-5 pt-5">
          <div class="flex items-start justify-between gap-4 flex-wrap">
            <div class="min-w-0">
              <div class="flex items-center gap-2.5">
                <.ui_status_dot status={@server.status} class="size-3" />
                <h1 class="font-mono text-2xl font-semibold text-[var(--mast-font-primary)] truncate">
                  {@server.name}
                </h1>
                <.ui_badge variant={status_badge(@server.status)}>
                  {status_label(@server.status)}
                </.ui_badge>
                <.ui_badge :if={@server.os_id} variant="neutral" dot={false}>
                  {@server.os_id}
                </.ui_badge>
                <.ui_badge :if={@server.package_manager} variant="neutral" dot={false}>
                  {@server.package_manager}
                </.ui_badge>
              </div>
              <p class="text-sm text-[var(--mast-font-secondary)] mt-1.5 font-mono">
                {@server.user}@{@server.host}:{@server.port}
                <span class="mx-2 text-[var(--mast-font-tertiary)]">·</span>
                <span class="font-sans">{last_seen(@server)}</span>
              </p>
            </div>

            <div class="flex items-center gap-2">
              <.ui_button variant="ghost" size="sm" icon="hero-arrow-path" phx-click="check">
                Check
              </.ui_button>
              <.ui_button
                variant="secondary"
                size="sm"
                icon="hero-magnifying-glass"
                phx-click="scan"
                loading={@scanning?}
                disabled={@scanning?}
              >
                {if @scanning?, do: "Scanning…", else: "Scan Updates"}
              </.ui_button>
              <.ui_button
                size="sm"
                icon="hero-arrow-down-tray"
                phx-click="apply_all"
                disabled={@running? or @scanning? or (@server.updates_available || 0) == 0}
                loading={@running?}
              >
                Apply Updates
              </.ui_button>
            </div>
          </div>

          <div
            :if={@scan_error}
            class="mt-4 px-3 py-2 rounded-[var(--radius-field)] bg-rose-100 dark:bg-rose-950/40 text-[var(--mast-status-offline)] text-sm flex items-center gap-2"
          >
            <span class="hero-exclamation-triangle size-4 shrink-0" /> Scan failed: {@scan_error}
          </div>

          <.ui_tabs active={@tab} class="mt-5">
            <:tab key="overview" patch={~p"/servers/#{@server.id}?tab=overview"}>Overview</:tab>
            <:tab key="apps" patch={~p"/servers/#{@server.id}?tab=apps"}>Apps</:tab>
            <:tab key="logs" patch={~p"/servers/#{@server.id}?tab=logs"}>Logs</:tab>
            <:tab
              key="updates"
              patch={~p"/servers/#{@server.id}?tab=updates"}
              count={@server.updates_available || 0}
            >
              Updates
            </:tab>
            <:tab key="settings" patch={~p"/servers/#{@server.id}?tab=settings"}>Settings</:tab>
          </.ui_tabs>
        </div>
      </.ui_card>

      <%= case @tab do %>
        <% "overview" -> %>
          <.overview_tab
            server={@server}
            streams={@streams}
            log_count={@log_count}
            apps={@apps}
          />
        <% "apps" -> %>
          <.apps_tab
            server={@server}
            apps={@apps}
            show_system_apps?={@show_system_apps?}
            probing?={@probing?}
            probe_error={@probe_error}
          />
        <% "logs" -> %>
          <.logs_tab streams={@streams} log_count={@log_count} running?={@running?} />
        <% "updates" -> %>
          <.updates_tab
            server={@server}
            scanning?={@scanning?}
            running?={@running?}
            scan_error={@scan_error}
          />
        <% "settings" -> %>
          <.settings_tab server={@server} monitoring_form={@monitoring_form} />
      <% end %>
    </Layouts.app>
    """
  end

  # ----- Overview tab -------------------------------------------------------

  attr :server, :map, required: true
  attr :streams, :map, required: true
  attr :log_count, :integer, required: true
  attr :apps, :list, required: true

  defp overview_tab(assigns) do
    ~H"""
    <section class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
      <.ui_stat label="CPU Usage" value={format_pct(@server.cpu)} sub={cpu_sub(@server.cpu)} />
      <.ui_stat
        label="Memory"
        value={format_pct(@server.memory)}
        sub="of available"
      />
      <.ui_stat label="Disk" value={format_pct(@server.disk)} sub="of total" />
      <.ui_stat
        label="Uptime"
        value={uptime_label(@server)}
        sub="last reboot"
      />
    </section>

    <section class="grid lg:grid-cols-2 gap-5">
      <.ui_card>
        <:title>Elixir Apps</:title>
        <:subtitle>{apps_subtitle(@apps, @server)}</:subtitle>

        <%= cond do %>
          <% @server.release_command in [nil, ""] -> %>
            <.ui_empty
              icon="hero-cog-6-tooth"
              title="Not configured"
              body="Set a release command in Settings to monitor apps on this host."
            />
          <% @apps == [] -> %>
            <.ui_empty
              icon="hero-cube"
              title="No apps observed yet"
              body="Mast probes every 30 seconds. Apps will appear after the first successful probe."
            />
          <% true -> %>
            <div class="space-y-2">
              <.link :for={a <- user_apps_only(@apps)} navigate={~p"/apps/#{a.id}"} class="block">
                <.ui_app_card
                  name={a.name}
                  version={a.version}
                  status={a.status}
                  uptime={format_uptime_short(a.uptime_seconds)}
                />
              </.link>
            </div>
        <% end %>
      </.ui_card>

      <.ui_card padded={false}>
        <:header>
          <div class="flex items-center justify-between gap-3 w-full">
            <div>
              <h2 class="text-base font-semibold text-[var(--mast-font-primary)]">Recent Logs</h2>
              <p class="text-xs text-[var(--mast-font-secondary)] mt-1">
                Latest activity from the run stream
              </p>
            </div>
            <.link
              patch={~p"/servers/#{@server.id}?tab=logs"}
              class="text-xs text-[var(--mast-accent)] hover:underline shrink-0"
            >
              View all →
            </.link>
          </div>
        </:header>

        <div class="bg-[var(--mast-bg-input)] mast-scroll max-h-72 overflow-y-auto">
          <div
            :if={@log_count == 0}
            class="px-4 py-8 text-center text-xs text-[var(--mast-font-tertiary)] italic"
          >
            idle — output will appear here when an upgrade runs
          </div>
          <div id="recent-log" phx-update="stream" class="py-2">
            <div :for={{dom_id, line} <- @streams.log} id={dom_id}>
              <.ui_log_entry kind={line.kind}>{line.data}</.ui_log_entry>
            </div>
          </div>
        </div>
      </.ui_card>
    </section>
    """
  end

  # ----- Apps tab -----------------------------------------------------------

  attr :server, :map, required: true
  attr :apps, :list, required: true
  attr :show_system_apps?, :boolean, required: true
  attr :probing?, :boolean, required: true
  attr :probe_error, :any, required: true

  defp apps_tab(assigns) do
    {user_apps, system_apps} = partition_apps(assigns.apps)

    visible_apps =
      if assigns.show_system_apps?, do: user_apps ++ system_apps, else: user_apps

    assigns =
      assigns
      |> assign(:user_apps, user_apps)
      |> assign(:system_apps, system_apps)
      |> assign(:visible_apps, visible_apps)

    ~H"""
    <.ui_card padded={@server.release_command in [nil, ""] or @apps == []}>
      <:title>Elixir Apps</:title>
      <:subtitle>
        <%= cond do %>
          <% @server.release_command in [nil, ""] -> %>
            Not configured. Set <code class="font-mono">release_command</code> in the Settings tab to start polling.
          <% @apps == [] -> %>
            No apps observed yet. Probe to refresh.
          <% true -> %>
            {length(@user_apps)} app{if length(@user_apps) == 1, do: "", else: "s"}
            <span :if={@system_apps != []} class="text-[var(--mast-font-tertiary)]">
              · {length(@system_apps)} OTP / library
            </span>
        <% end %>
      </:subtitle>
      <:actions>
        <.ui_button
          variant="secondary"
          size="sm"
          icon="hero-arrow-path"
          phx-click="probe-apps"
          loading={@probing?}
          disabled={@probing? or @server.release_command in [nil, ""]}
        >
          {if @probing?, do: "Probing…", else: "Probe now"}
        </.ui_button>
      </:actions>

      <div
        :if={@probe_error}
        class="mb-3 px-3 py-2 rounded-[var(--radius-field)] bg-rose-100 dark:bg-rose-950/40 text-[var(--mast-status-offline)] text-xs flex items-center gap-2"
      >
        <span class="hero-exclamation-triangle size-4 shrink-0" />
        Probe failed: {@probe_error}
      </div>

      <%= cond do %>
        <% @server.release_command in [nil, ""] -> %>
          <.ui_empty
            icon="hero-cog-6-tooth"
            title="App monitoring not configured"
            body="Open the Settings tab to set a release command. Mast will then poll this host every 30 seconds."
          />
        <% @apps == [] -> %>
          <.ui_empty
            icon="hero-cube"
            title="No apps observed yet"
            body="Click Probe now to query the host. Apps will appear once the first probe succeeds."
          />
        <% true -> %>
          <div class="space-y-2">
            <.link :for={a <- @visible_apps} navigate={~p"/apps/#{a.id}"} class="block">
              <.ui_app_card
                name={a.name}
                version={a.version}
                status={a.status}
                uptime={format_uptime_short(a.uptime_seconds)}
              />
            </.link>
          </div>

          <button
            :if={@system_apps != []}
            type="button"
            phx-click="toggle-system-apps"
            class="mt-3 text-xs text-[var(--mast-font-secondary)] hover:text-[var(--mast-font-primary)]"
          >
            {if @show_system_apps?,
              do: "Hide #{length(@system_apps)} OTP / library apps",
              else: "Show #{length(@system_apps)} OTP / library apps"}
          </button>
      <% end %>
    </.ui_card>
    """
  end

  # Apps that ship with OTP, Elixir stdlib, Phoenix, Ecto, and the common
  # release deps. Hiding these focuses the default view on apps the
  # operator actually wrote. Toggle reveals the full list.
  @system_apps MapSet.new(~w(
    asn1 bandit bcrypt_elixir cloak cloak_ecto comeonin compiler crypto
    db_connection decimal dns_cluster ecto ecto_sql eex elixir esbuild
    expo finch gettext hackney hpax idna inets jason kernel lazy_html
    logger logger_json metrics mime mimerl mint nimble_options
    nimble_pool oban os_mon parse_trans phoenix phoenix_ecto phoenix_html
    phoenix_live_dashboard phoenix_live_reload phoenix_live_view
    phoenix_pubsub phoenix_template plug plug_crypto postgrex public_key
    req runtime_tools sasl sshkit ssl ssl_verify_fun stdlib swoosh
    syntax_tools tailwind telemetry telemetry_metrics telemetry_poller
    thousand_island tzdata unicode_util_compat websock websock_adapter
    xmerl certifi
  ))

  defp partition_apps(apps) do
    Enum.split_with(apps, &(&1.name not in @system_apps))
  end

  defp format_uptime_short(nil), do: nil

  defp format_uptime_short(s) when is_integer(s) do
    cond do
      s < 60 -> "#{s}s"
      s < 3600 -> "#{div(s, 60)}m"
      s < 86_400 -> "#{div(s, 3600)}h"
      true -> "#{div(s, 86_400)}d"
    end
  end

  # ----- Logs tab -----------------------------------------------------------

  attr :streams, :map, required: true
  attr :log_count, :integer, required: true
  attr :running?, :boolean, required: true

  defp logs_tab(assigns) do
    ~H"""
    <.ui_card padded={false}>
      <:header>
        <div class="flex items-center justify-between gap-3 w-full">
          <div class="flex items-center gap-3">
            <h2 class="text-base font-semibold text-[var(--mast-font-primary)]">Run Log</h2>
            <.ui_badge :if={@running?} variant="warning">running</.ui_badge>
          </div>
          <.ui_button
            variant="ghost"
            size="sm"
            phx-click="clear_log"
            disabled={@log_count == 0}
          >
            Clear
          </.ui_button>
        </div>
      </:header>

      <div class="bg-[var(--mast-bg-input)] mast-scroll max-h-[32rem] overflow-y-auto">
        <div
          :if={@log_count == 0}
          class="px-4 py-12 text-center text-xs text-[var(--mast-font-tertiary)] italic"
        >
          idle — output will appear here when an upgrade runs
        </div>
        <div id="full-log" phx-update="stream" class="py-2">
          <div :for={{dom_id, line} <- @streams.log} id={dom_id}>
            <.ui_log_entry kind={line.kind}>{line.data}</.ui_log_entry>
          </div>
        </div>
      </div>
    </.ui_card>
    """
  end

  # ----- Updates tab --------------------------------------------------------

  attr :server, :map, required: true
  attr :scanning?, :boolean, required: true
  attr :running?, :boolean, required: true
  attr :scan_error, :any, required: true

  defp updates_tab(assigns) do
    updates = updates_list(assigns.server)
    state = empty_state(assigns.server, assigns.scanning?, updates)

    assigns = assign(assigns, updates: updates, state: state)

    ~H"""
    <.ui_card padded={false}>
      <:header>
        <div class="flex items-center justify-between gap-3 w-full">
          <div>
            <h2 class="text-base font-semibold text-[var(--mast-font-primary)]">Available Updates</h2>
            <p class="text-xs text-[var(--mast-font-secondary)] mt-1">
              <.scan_status_text server={@server} scanning?={@scanning?} scan_error={@scan_error} />
            </p>
          </div>
          <.ui_badge :if={@updates != []} variant="warning">
            {length(@updates)} packages
          </.ui_badge>
        </div>
      </:header>

      <%= case @state do %>
        <% :scanning -> %>
          <.ui_empty
            icon="hero-magnifying-glass"
            title="Scanning…"
            body="Running apt list --upgradable on the host."
          />
        <% :never_scanned -> %>
          <.ui_empty
            icon="hero-magnifying-glass"
            title="Not scanned yet"
            body="Click Scan Updates above to check the host for available packages."
          />
        <% :clean -> %>
          <.ui_empty
            icon="hero-check-circle"
            title="All up to date"
            body="No package updates are available right now."
          />
        <% :has_updates -> %>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-[var(--mast-bg-secondary)]">
                <tr class="text-xs font-medium uppercase tracking-wider text-[var(--mast-font-secondary)] border-b border-[var(--mast-border)]">
                  <th class="text-left px-5 py-2.5">Package</th>
                  <th class="text-left px-5 py-2.5">Current</th>
                  <th class="text-left px-5 py-2.5">New</th>
                  <th class="text-right px-5 py-2.5"></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={u <- @updates}
                  class="border-b border-[var(--mast-border)] last:border-0 hover:bg-[var(--mast-bg-card-hover)]"
                >
                  <td class="px-5 py-3 font-mono font-medium text-[var(--mast-font-primary)]">
                    {u["package"]}
                  </td>
                  <td class="px-5 py-3 font-mono tabular-nums text-[var(--mast-font-secondary)]">
                    {u["current_version"]}
                  </td>
                  <td class="px-5 py-3 font-mono tabular-nums text-[var(--mast-accent)]">
                    {u["new_version"]}
                  </td>
                  <td class="px-5 py-3 text-right">
                    <.ui_button
                      variant="ghost"
                      size="sm"
                      phx-click="apply_package"
                      phx-value-name={u["package"]}
                      disabled={@running? or @scanning? or not Apt.safe_package_name?(u["package"])}
                    >
                      Apply
                    </.ui_button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
      <% end %>
    </.ui_card>
    """
  end

  defp empty_state(_server, true, _updates), do: :scanning
  defp empty_state(%{last_scan_at: nil}, _, _), do: :never_scanned
  defp empty_state(_, _, []), do: :clean
  defp empty_state(_, _, _), do: :has_updates

  defp updates_list(%{last_scan: %{"updates" => updates}}) when is_list(updates), do: updates
  defp updates_list(_), do: []

  # ----- Settings tab -------------------------------------------------------

  attr :server, :map, required: true
  attr :monitoring_form, :any, required: true

  defp settings_tab(assigns) do
    ~H"""
    <div class="space-y-5">
      <.ui_card>
        <:title>Connection</:title>
        <:subtitle>SSH details for this host</:subtitle>

        <dl class="grid grid-cols-2 gap-y-3 text-sm">
          <dt class="text-[var(--mast-font-secondary)]">Host</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">{@server.host}</dd>
          <dt class="text-[var(--mast-font-secondary)]">User</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">{@server.user}</dd>
          <dt class="text-[var(--mast-font-secondary)]">Port</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">{@server.port}</dd>
          <dt class="text-[var(--mast-font-secondary)]">OS</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">{@server.os_id || "—"}</dd>
          <dt class="text-[var(--mast-font-secondary)]">Package manager</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">
            {@server.package_manager || "—"}
          </dd>
        </dl>
      </.ui_card>

      <.ui_card>
        <:title>App monitoring</:title>
        <:subtitle>
          Path to a mix release's <code class="font-mono">bin/&lt;name&gt;</code> script.
          Mast invokes <code class="font-mono">&lt;path&gt; rpc</code> over SSH to read running applications.
        </:subtitle>

        <.form
          for={@monitoring_form}
          phx-submit="save-monitoring"
          id="monitoring-form"
          class="space-y-3"
        >
          <.input
            field={@monitoring_form[:release_command]}
            label="Release command"
            placeholder="/opt/hermes/bin/hermes"
          />

          <div class="flex justify-end gap-2 pt-1">
            <.ui_button type="submit">Save</.ui_button>
          </div>
        </.form>
      </.ui_card>
    </div>
    """
  end

  # ----- bits ---------------------------------------------------------------

  attr :server, :map, required: true
  attr :scanning?, :boolean, required: true
  attr :scan_error, :any, required: true

  defp scan_status_text(assigns) do
    ~H"""
    <%= cond do %>
      <% @scan_error -> %>
        <span class="text-[var(--mast-status-offline)]">Scan failed: {@scan_error}</span>
      <% @scanning? -> %>
        Scanning…
      <% @server.last_scan_at -> %>
        Last scanned {format_relative(@server.last_scan_at)}.
        <%= if (@server.updates_available || 0) == 0 do %>
          Nothing to install.
        <% else %>
          {@server.updates_available} package(s) available.
        <% end %>
      <% true -> %>
        Not scanned yet.
    <% end %>
    """
  end

  defp status_badge("up"), do: "online"
  defp status_badge("down"), do: "offline"
  defp status_badge(_), do: "neutral"

  defp status_label("up"), do: "Online"
  defp status_label("down"), do: "Offline"
  defp status_label(_), do: "Unknown"

  defp cpu_sub(nil), do: "no data"
  defp cpu_sub(n) when is_number(n) and n >= 80, do: "high load"
  defp cpu_sub(_), do: "of capacity"

  defp uptime_label(_), do: "—"

  defp apps_subtitle(_, %{release_command: rc}) when rc in [nil, ""], do: "Not configured"
  defp apps_subtitle([], _), do: "No apps yet"

  defp apps_subtitle(apps, _) do
    {user, _} = partition_apps(apps)
    n = length(user)
    "#{n} app#{if n == 1, do: "", else: "s"} running"
  end

  defp user_apps_only(apps) do
    {user, _} = partition_apps(apps)
    user
  end

  defp format_pct(nil), do: "—"

  defp format_pct(n) when is_float(n),
    do: :erlang.float_to_binary(n, decimals: 1) <> "%"

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

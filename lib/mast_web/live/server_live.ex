defmodule MastWeb.ServerLive do
  @moduledoc """
  Server detail view. State + event handlers only; the header and each
  tab live in their own module under `MastWeb.ServerLive.*`.
  """
  use MastWeb, :live_view

  alias Mast.{Apps, Fleet}
  alias Mast.Fleet.Release
  alias Mast.Workers.{ApplyUpdates, AppProbe, ConnectionCheck, PatchScan}

  alias MastWeb.ServerLive.{
    Header,
    OverviewTab,
    ReleasesTab,
    SettingsTab,
    UpdatesTab
  }

  @tabs ~w(overview releases updates settings)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    server = Fleet.get_server!(id)

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
     |> assign(:releases, Fleet.list_releases(server))
     |> assign(:new_release_changeset, nil)
     |> assign(:show_system_apps?, false)
     |> assign(:confirm_delete?, false)
     |> assign(:confirm_name, "")
     |> assign(:updates_page, 1)
     |> assign(:updates_page_size, 10)
     |> assign(:updates_filter, "")
     |> stream(:log, [])
     |> assign(:log_count, 0)
     |> assign(:activity, load_activity(server.id))
     |> assign_series("1h")}
  end

  defp load_activity(server_id) do
    Mast.Audit.list_for_subject("Server", server_id, 10)
  end

  @ranges %{
    "1h" => {"1m", 3_600},
    "12h" => {"10m", 12 * 3_600},
    "1d" => {"20m", 86_400},
    "7d" => {"120m", 7 * 86_400},
    "30d" => {"480m", 30 * 86_400}
  }

  def ranges, do: @ranges

  defp assign_series(socket, range) do
    {bucket, seconds} = Map.fetch!(@ranges, range)
    since = DateTime.utc_now() |> DateTime.add(-seconds, :second)
    rows = Mast.Fleet.list_stats(socket.assigns.server.id, bucket, since)

    socket
    |> assign(:range, range)
    |> assign(:bucket, bucket)
    |> assign(:series, build_series(rows))
  end

  defp build_series(rows) do
    metrics = ~w(cpu memory disk_root rx_bytes_s tx_bytes_s io_r_bytes_s io_w_bytes_s load_1)

    Map.new(metrics, fn key ->
      points =
        Enum.map(rows, fn r ->
          %{t: r.recorded_at, v: r.stats[key]}
        end)
        |> Enum.filter(&is_number(&1.v))

      {key, points}
    end)
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
       |> assign(:scan_error, nil)
       |> assign(:updates_page, 1)
       |> assign(:activity, load_activity(server.id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:server_deleted, id}, socket) do
    if id == socket.assigns.server.id do
      {:noreply,
       socket
       |> put_flash(:info, "Server removed.")
       |> push_navigate(to: ~p"/")}
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

  def handle_event("open-add-release", _, socket) do
    cs = Fleet.change_release(%Release{server_id: socket.assigns.server.id})
    {:noreply, assign(socket, :new_release_changeset, cs)}
  end

  def handle_event("cancel-add-release", _, socket) do
    {:noreply, assign(socket, :new_release_changeset, nil)}
  end

  def handle_event("validate-new-release", %{"release" => attrs}, socket) do
    cs =
      %Release{server_id: socket.assigns.server.id}
      |> Fleet.change_release(Map.put(attrs, "server_id", socket.assigns.server.id))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :new_release_changeset, cs)}
  end

  def handle_event("create-release", %{"release" => attrs}, socket) do
    attrs = Map.put(attrs, "server_id", socket.assigns.server.id)

    case Fleet.create_release(attrs) do
      {:ok, _release} ->
        {:noreply,
         socket
         |> assign(:new_release_changeset, nil)
         |> assign(:releases, Fleet.list_releases(socket.assigns.server))
         |> put_flash(:info, "Release added.")}

      {:error, cs} ->
        {:noreply, assign(socket, :new_release_changeset, cs)}
    end
  end

  def handle_event("delete-release", %{"id" => id}, socket) do
    release = Fleet.get_release!(id)

    case Fleet.delete_release(release) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:releases, Fleet.list_releases(socket.assigns.server))
         |> put_flash(:info, "Release removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove Release.")}
    end
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

  def handle_event("open-delete-confirm", _, socket) do
    {:noreply,
     socket
     |> assign(:confirm_delete?, true)
     |> assign(:confirm_name, "")}
  end

  def handle_event("cancel-delete", _, socket) do
    {:noreply,
     socket
     |> assign(:confirm_delete?, false)
     |> assign(:confirm_name, "")}
  end

  def handle_event("validate-delete", %{"confirm" => %{"name" => name}}, socket) do
    {:noreply, assign(socket, :confirm_name, name)}
  end

  def handle_event("delete-server", %{"confirm" => %{"name" => name}}, socket) do
    server = socket.assigns.server

    if name == server.name do
      case Fleet.delete_server(server) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Server #{server.name} removed.")
           |> push_navigate(to: ~p"/")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not remove server.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("goto-page", %{"page" => page}, socket) do
    {:noreply, assign(socket, :updates_page, max(1, String.to_integer(page)))}
  end

  def handle_event("filter-updates", %{"q" => q}, socket) do
    {:noreply,
     socket
     |> assign(:updates_filter, q)
     |> assign(:updates_page, 1)}
  end

  def handle_event("set_range", %{"range" => range}, socket) when is_map_key(@ranges, range) do
    {:noreply, assign_series(socket, range)}
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="servers" page_title={@server.name}>
      <Header.detail_header
        server={@server}
        tab={@tab}
        scanning?={@scanning?}
        running?={@running?}
        probing?={@probing?}
        scan_error={@scan_error}
      />

      <%= case @tab do %>
        <% "overview" -> %>
          <OverviewTab.render
            server={@server}
            apps={@apps}
            releases={@releases}
            activity={@activity}
            range={@range}
            series={@series}
          />
        <% "releases" -> %>
          <ReleasesTab.render
            server={@server}
            releases={@releases}
            new_release_changeset={@new_release_changeset}
          />
        <% "updates" -> %>
          <UpdatesTab.render
            server={@server}
            scanning?={@scanning?}
            running?={@running?}
            scan_error={@scan_error}
            updates_page={@updates_page}
            updates_page_size={@updates_page_size}
            updates_filter={@updates_filter}
          />
        <% "settings" -> %>
          <SettingsTab.render
            server={@server}
            confirm_delete?={@confirm_delete?}
            confirm_name={@confirm_name}
          />
      <% end %>
    </Layouts.app>
    """
  end
end

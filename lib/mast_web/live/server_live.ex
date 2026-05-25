defmodule MastWeb.ServerLive do
  @moduledoc """
  Server detail view. State + event handlers only; the header and each
  tab live in their own module under `MastWeb.ServerLive.*`.
  """
  use MastWeb, :live_view

  alias Mast.{Apps, Fleet}
  alias Mast.Fleet.{Projects, Release}
  alias Mast.Patches.Runs
  alias Mast.Workers.{ApplyUpdates, AppProbe, ConnectionCheck, PatchScan}
  alias MastWeb.ServerLive.View

  @tabs ~w(overview releases updates settings)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    server = Fleet.get_server!(id)

    # Reattach to the last run (if any) so a reloaded page picks up an
    # in-flight apply: same topic, replayed log, modal reopened if running.
    # Reattach to the last run only on the connected mount: the static HTTP
    # render is throwaway, so there's no point reading the run row (and
    # splitting its log) twice. See AGENTS.md "Guard expensive mount work".
    run = if connected?(socket), do: Runs.get_for_server(server.id)
    run_id = if run, do: run.run_id, else: generate_run_id()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mast.PubSub, "servers")
      Phoenix.PubSub.subscribe(Mast.PubSub, "runs:#{run_id}")
    end

    {:ok,
     socket
     |> assign(:page_title, server.name)
     |> assign(:server, server)
     |> assign(:tab, "overview")
     |> assign(:run_id, run_id)
     |> assign(:running?, run_running?(run))
     |> assign_run_state(run)
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
     |> assign(:projects, Projects.list_projects())
     |> assign(:project, load_project(server))
     |> assign(:project_form, project_form(server))
     |> assign(:updates_page, 1)
     |> assign(:updates_page_size, 10)
     |> assign(:updates_filter, "")
     |> stream(:log, [])
     |> assign(:log_count, 0)
     |> hydrate_log(run)
     |> assign(:activity, load_activity(server.id))
     |> assign_series("1h")}
  end

  # Modal/status assigns derived from the (possibly nil) last run. The modal
  # only auto-opens while a run is still running; finished runs stay closed.
  defp assign_run_state(socket, run) do
    socket
    |> assign(:run_status, run_status(run))
    |> assign(:run_title, run_title(run, socket.assigns.server))
    |> assign(:show_run_log?, run_running?(run))
  end

  defp run_running?(%{status: "running"}), do: true
  defp run_running?(_), do: false

  defp run_status(%{status: "done"}), do: :done
  defp run_status(%{status: "error"}), do: :error
  defp run_status(_), do: :running

  defp run_title(run, server), do: "Applying Updates — #{scope_label(run)}#{server.name}"

  defp scope_label(%{scope: "package", package: pkg}) when is_binary(pkg), do: "#{pkg} on "
  defp scope_label(_), do: ""

  # Replay a persisted run's log into the :log stream so a reattached page
  # shows output emitted before this mount. Lines are split back out and
  # given stable ids; kind is unknown post-persistence, so render as stdout.
  defp hydrate_log(socket, %{log: log}) when is_binary(log) and log != "" do
    entries =
      log
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map(fn {data, i} -> %{id: i, kind: :stdout, data: data} end)

    socket
    |> stream(:log, entries)
    |> assign(:log_count, length(entries))
  end

  defp hydrate_log(socket, _run), do: socket

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
    until = DateTime.utc_now()
    since = DateTime.add(until, -seconds, :second)
    rows = Mast.Fleet.list_stats(socket.assigns.server.id, bucket, since)

    socket
    |> assign(:range, range)
    |> assign(:bucket, bucket)
    |> assign(:series, build_series(rows))
    |> assign(:range_since, since)
    |> assign(:range_until, until)
    |> assign(:latest_sample, latest_sample(socket.assigns.server.id))
  end

  defp latest_sample(server_id) do
    since = DateTime.utc_now() |> DateTime.add(-3_600, :second)

    Mast.Fleet.list_stats(server_id, "1m", since)
    |> List.last()
    |> case do
      nil -> %{}
      stat -> stat.stats
    end
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
       |> assign(:activity, load_activity(server.id))
       |> assign_series(socket.assigns.range)}
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

  def handle_event("close-run-log", _, socket) do
    {:noreply, assign(socket, :show_run_log?, false)}
  end

  def handle_event("clear_log", _, socket) do
    {:noreply,
     socket
     |> stream(:log, [], reset: true)
     |> assign(:log_count, 0)
     |> assign(:running?, false)}
  end

  def handle_event("update-project", %{"server" => params}, socket) do
    server = socket.assigns.server
    new_id = blank_to_nil(params["project_id"])

    result =
      case {server.project_id, new_id} do
        {same, same} -> {:ok, server}
        {_, nil} -> Projects.unassign_server(server)
        {_, id} -> Projects.assign_server(server, Projects.get_project!(id))
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:server, updated)
         |> assign(:project, load_project(updated))
         |> assign(:project_form, project_form(updated))
         |> assign(:activity, load_activity(updated.id))
         |> put_flash(:info, "Project saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update project.")}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(v), do: v

  defp project_form(server) do
    to_form(Fleet.change_server(server, %{}), as: :server)
  end

  defp load_project(%{project_id: nil}), do: nil
  defp load_project(%{project_id: id}), do: Projects.get_project!(id)

  defp enqueue_apply(socket, extra) do
    server = socket.assigns.server
    # Fresh run id per apply so the topic is unique and a prior run's tail
    # can't bleed into this one.
    run_id = generate_run_id()
    scope = Map.get(extra, "scope", "all")
    package = Map.get(extra, "package")

    args = Map.merge(extra, %{"server_id" => server.id, "run_id" => run_id})

    with {:ok, run} <-
           Runs.start_run(%{server_id: server.id, run_id: run_id, scope: scope, package: package}),
         {:ok, _job} <- Oban.insert(ApplyUpdates.new(args)) do
      Phoenix.PubSub.subscribe(Mast.PubSub, "runs:#{run_id}")

      {:noreply,
       socket
       |> assign(:run_id, run_id)
       |> assign(:running?, true)
       |> assign(:run_status, :running)
       |> assign(:run_title, run_title(run, server))
       |> assign(:show_run_log?, true)
       |> stream(:log, [], reset: true)
       |> assign(:log_count, 0)}
    else
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
    status = if code == 0, do: :done, else: :error

    socket
    |> stream_insert(:log, %{id: id, kind: :exit, data: label})
    |> assign(:log_count, id)
    |> assign(:running?, false)
    |> assign(:run_status, status)
  end

  defp append_event(socket, {:error, reason}) do
    id = socket.assigns.log_count + 1

    socket
    |> stream_insert(:log, %{id: id, kind: :error, data: "error: #{inspect(reason)}"})
    |> assign(:log_count, id)
    |> assign(:running?, false)
    |> assign(:run_status, :error)
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  @impl true
  def render(assigns), do: View.render(assigns)
end

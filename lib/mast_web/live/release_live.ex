defmodule MastWeb.ReleaseLive do
  @moduledoc """
  Detail view for one configured Release on a Server.

  Three sub-tabs:
    * Overview — probe summary + apps belonging to this Release's Server.
    * Logs — live tail of the Release's Log Source (systemd / file).
    * Settings — name, release_command, log_source, log_target.

  See ADR 0008.
  """
  use MastWeb, :live_view

  alias Mast.Apps
  alias Mast.Fleet
  alias Mast.Fleet.Release
  alias Mast.Logs
  alias Mast.Logs.Janitor
  alias Mast.Workers.AppProbe
  alias MastWeb.ReleaseLive.View

  @max_log_lines 1000

  @impl true
  def mount(%{"server_id" => server_id, "name" => name} = params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mast.PubSub, "servers")
      Process.flag(:trap_exit, true)
    end

    server = Fleet.get_server!(server_id)

    case Fleet.get_release(server, name) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Release #{inspect(name)} not found on #{server.name}.")
         |> push_navigate(to: ~p"/servers/#{server.id}")}

      %Release{} = release ->
        tab = Map.get(params, "tab", "overview")
        apps = Apps.list_for_release(release)

        {:ok,
         socket
         |> assign(:page_title, Release.effective_handle(release))
         |> assign(:server, server)
         |> assign(:release, release)
         |> assign(:handle, Release.effective_handle(release))
         |> assign(:tab, tab)
         |> assign(:apps, apps)
         |> assign(:settings_changeset, Fleet.change_release(release))
         |> assign(:log_buffer, [])
         |> assign(:log_streaming?, false)
         |> assign(:log_status, :idle)
         |> assign(:probing?, false)
         |> assign(:probe_error, nil)}
    end
  end

  @impl true
  def handle_params(%{"tab" => tab} = _params, _uri, socket),
    do: {:noreply, assign(socket, :tab, tab)}

  def handle_params(_params, _uri, socket), do: {:noreply, assign(socket, :tab, "overview")}

  @impl true
  def handle_event("save_settings", %{"release" => attrs}, socket) do
    case Fleet.update_release(socket.assigns.release, attrs) do
      {:ok, release} ->
        {:noreply,
         socket
         |> assign(:release, release)
         |> assign(:handle, Release.effective_handle(release))
         |> assign(:settings_changeset, Fleet.change_release(release))
         |> put_flash(:info, "Settings saved.")
         |> push_patch(
           to:
             ~p"/servers/#{socket.assigns.server.id}/releases/#{Release.effective_handle(release)}?tab=settings"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :settings_changeset, changeset)}
    end
  end

  def handle_event("validate_settings", %{"release" => attrs}, socket) do
    changeset =
      socket.assigns.release
      |> Fleet.change_release(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :settings_changeset, changeset)}
  end

  def handle_event("start_log_stream", _, socket) do
    {:noreply, start_stream(socket)}
  end

  def handle_event("stop_log_stream", _, socket) do
    {:noreply, stop_stream(socket)}
  end

  def handle_event("clear_log_buffer", _, socket) do
    {:noreply, assign(socket, :log_buffer, [])}
  end

  def handle_event("probe-release", _, socket) do
    release = socket.assigns.release

    if release.release_command in [nil, ""] do
      {:noreply,
       put_flash(
         socket,
         :error,
         "This Release has no release_command — set one in Settings to enable probing."
       )}
    else
      %{release_id: release.id}
      |> AppProbe.new()
      |> Oban.insert!()

      {:noreply,
       socket
       |> assign(:probing?, true)
       |> assign(:probe_error, nil)}
    end
  end

  @impl true
  def handle_info({:apps_updated, server_id}, socket) do
    if server_id == socket.assigns.server.id do
      {:noreply,
       socket
       |> assign(:apps, Apps.list_for_release(socket.assigns.release))
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

  def handle_info({:log_event, ref, event}, socket) do
    if ref == socket.assigns[:log_stream_ref] do
      {:noreply, handle_log_event(socket, event)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:EXIT, pid, _reason}, socket) do
    if pid == socket.assigns[:log_task_pid] do
      Janitor.deregister(self())

      {:noreply,
       socket
       |> assign(:log_streaming?, false)
       |> assign(:log_task_pid, nil)
       |> assign(:log_stream_ref, nil)
       |> assign(:log_status, :closed)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    stop_stream(socket)
    :ok
  end

  @impl true
  def render(assigns), do: View.render(assigns)

  # ---- Streaming helpers ---------------------------------------------------

  defp start_stream(%{assigns: %{log_streaming?: true}} = socket), do: socket

  defp start_stream(socket) do
    release = socket.assigns.release

    if release.log_source == "none" or release.log_target in [nil, ""] do
      socket
      |> put_flash(:error, "Log Source not configured for this Release.")
    else
      command = Logs.stream_command(release.log_source, release.log_target)
      server = Mast.SSH.preload_key(socket.assigns.server)
      parent = self()
      ref = make_ref()

      forward_event = fn event, _acc ->
        send(parent, {:log_event, ref, event})
        nil
      end

      task_pid =
        spawn_link(fn ->
          Mast.SSH.run_stream(server, command, forward_event, nil)
        end)

      Janitor.register(self(), task_pid)

      socket
      |> assign(:log_streaming?, true)
      |> assign(:log_task_pid, task_pid)
      |> assign(:log_stream_ref, ref)
      |> assign(:log_status, :streaming)
    end
  end

  defp stop_stream(socket) do
    pid = socket.assigns[:log_task_pid]

    if is_pid(pid) and Process.alive?(pid) do
      Process.exit(pid, :kill)
    end

    Janitor.deregister(self())

    socket
    |> assign(:log_streaming?, false)
    |> assign(:log_task_pid, nil)
    |> assign(:log_stream_ref, nil)
    |> assign(:log_status, if(socket.assigns[:log_streaming?], do: :closed, else: :idle))
  end

  defp handle_log_event(socket, {:line, stream, data}) do
    text = String.trim_trailing(data, "\n")

    line = %{
      kind: line_kind(stream),
      time: now_hhmmss(),
      text: text
    }

    append_line(socket, line)
  end

  defp handle_log_event(socket, {:exit, code}) do
    label = if code == 0, do: "stream ended (exit 0)", else: "stream ended (exit #{code})"

    socket
    |> append_line(%{kind: :exit, time: now_hhmmss(), text: label})
    |> assign(:log_status, :closed)
  end

  defp handle_log_event(socket, {:error, reason}) do
    socket
    |> append_line(%{kind: :error, time: now_hhmmss(), text: "error: #{inspect(reason)}"})
    |> assign(:log_status, :error)
  end

  defp append_line(socket, line) do
    buffer = [line | socket.assigns.log_buffer] |> Enum.take(@max_log_lines)
    assign(socket, :log_buffer, buffer)
  end

  defp line_kind(:stdout), do: :stdout
  defp line_kind(:stderr), do: :stderr
  defp line_kind(_), do: :info

  defp now_hhmmss do
    DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")
  end
end

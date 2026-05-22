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
  alias MastWeb.ReleaseLive.View

  @impl true
  def mount(%{"server_id" => server_id, "name" => name} = params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Mast.PubSub, "servers")

    server = Fleet.get_server!(String.to_integer(server_id))

    case Fleet.get_release(server, name) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Release #{inspect(name)} not found on #{server.name}.")
         |> push_navigate(to: ~p"/servers/#{server.id}")}

      %Release{} = release ->
        tab = Map.get(params, "tab", "overview")
        apps = Apps.list_for_server(server.id)

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
         |> assign(:log_status, :idle)}
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

  @impl true
  def handle_info({:apps_updated, server_id}, socket) do
    if server_id == socket.assigns.server.id do
      {:noreply, assign(socket, :apps, Apps.list_for_server(server_id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns), do: View.render(assigns)
end

defmodule MastWeb.ApplicationLive do
  @moduledoc """
  Detail view for one running OTP application (a `Mast.Apps.Application`)
  inside a Release on a Server. Routed as
  `/servers/:server_id/releases/:name/apps/:app_name`.

  State + event handlers only; markup lives in
  `MastWeb.ApplicationLive.View`.
  """
  use MastWeb, :live_view

  alias Mast.Apps
  alias Mast.Apps.Probe
  alias Mast.Fleet
  alias Mast.Fleet.Release
  alias Mast.Workers.AppProbe
  alias MastWeb.ApplicationLive.View

  @impl true
  def mount(
        %{"server_id" => server_id, "name" => release_handle, "app_name" => app_name},
        _session,
        socket
      ) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Mast.PubSub, "servers")

    server = Fleet.get_server!(String.to_integer(server_id))

    case Fleet.get_release(server, release_handle) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Release #{inspect(release_handle)} not found.")
         |> push_navigate(to: ~p"/servers/#{server.id}")}

      %Release{} = release ->
        case find_app(release, app_name) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Application #{inspect(app_name)} not found in this Release.")
             |> push_navigate(
               to: ~p"/servers/#{server.id}/releases/#{Release.effective_handle(release)}"
             )}

          app ->
            {detail, detail_error} = fetch_detail(release, app)

            {:ok,
             socket
             |> assign(:page_title, app.name)
             |> assign(:app, app)
             |> assign(:server, server)
             |> assign(:release, release)
             |> assign(:refreshing?, false)
             |> assign(:detail, detail)
             |> assign(:detail_error, detail_error)}
        end
    end
  end

  defp find_app(%Release{id: release_id}, app_name) do
    release_id
    |> Apps.list_for_release()
    |> Enum.find(&(&1.name == app_name))
  end

  defp fetch_detail(%Release{release_command: rc}, _app) when rc in [nil, ""] do
    {nil, :release_command_not_set}
  end

  defp fetch_detail(%Release{} = release, app) do
    case Probe.probe_detail(release, app.name) do
      {:ok, detail} -> {detail, nil}
      {:error, reason} -> {nil, reason}
    end
  rescue
    _ -> {nil, :probe_crashed}
  end

  @impl true
  def handle_info({:apps_updated, server_id}, socket) do
    if server_id == socket.assigns.server.id do
      case find_app(socket.assigns.release, socket.assigns.app.name) do
        nil ->
          {:noreply, socket}

        app ->
          {detail, detail_error} = fetch_detail(socket.assigns.release, app)

          {:noreply,
           socket
           |> assign(:app, app)
           |> assign(:refreshing?, false)
           |> assign(:detail, detail)
           |> assign(:detail_error, detail_error)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:apps_probe_failed, server_id, reason}, socket) do
    if server_id == socket.assigns.server.id do
      {:noreply,
       socket
       |> assign(:refreshing?, false)
       |> put_flash(:error, "Probe failed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh", _, socket) do
    %{release_id: socket.assigns.release.id}
    |> AppProbe.new()
    |> Oban.insert!()

    {:noreply, assign(socket, :refreshing?, true)}
  end

  @impl true
  def render(assigns), do: View.render(assigns)
end

defmodule MastWeb.AppLive do
  @moduledoc """
  Detail view for one running Elixir application. State + event handlers
  only; the template + display helpers live in `MastWeb.AppLive.View`.
  """
  use MastWeb, :live_view

  alias Mast.Apps
  alias Mast.Apps.Probe
  alias Mast.Workers.AppProbe
  alias MastWeb.AppLive.View

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Mast.PubSub, "servers")

    app = Apps.get_app!(String.to_integer(id))

    {detail, detail_error} = fetch_detail(app)

    {:ok,
     socket
     |> assign(:page_title, app.name)
     |> assign(:app, app)
     |> assign(:server, app.server)
     |> assign(:refreshing?, false)
     |> assign(:detail, detail)
     |> assign(:detail_error, detail_error)}
  end

  defp fetch_detail(app) do
    release = app.release

    cond do
      is_nil(release) ->
        {nil, :release_not_set}

      release.release_command in [nil, ""] ->
        {nil, :release_command_not_set}

      true ->
        case Probe.probe_detail(release, app.name) do
          {:ok, detail} -> {detail, nil}
          {:error, reason} -> {nil, reason}
        end
    end
  rescue
    _ -> {nil, :probe_crashed}
  end

  @impl true
  def handle_info({:apps_updated, server_id}, socket) do
    if server_id == socket.assigns.app.server_id do
      app = Apps.get_app!(socket.assigns.app.id)
      {detail, detail_error} = fetch_detail(app)

      {:noreply,
       socket
       |> assign(:app, app)
       |> assign(:server, app.server)
       |> assign(:refreshing?, false)
       |> assign(:detail, detail)
       |> assign(:detail_error, detail_error)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:apps_probe_failed, server_id, reason}, socket) do
    if server_id == socket.assigns.app.server_id do
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
    %{server_id: socket.assigns.app.server_id}
    |> AppProbe.new()
    |> Oban.insert!()

    {:noreply, assign(socket, :refreshing?, true)}
  end

  @impl true
  def render(assigns), do: View.render(assigns)
end

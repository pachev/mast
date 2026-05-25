defmodule MastWeb.DevUiLive do
  @moduledoc """
  Dev-only component showcase. Renders a sample of every `ui_*`
  component grouped by family inside a viewport-width frame so we can
  eyeball responsive behavior at 375 / 768 / 1024 / full without
  resizing the OS window.

  Mounted at `/dev/ui` and gated by the `:dev_routes` compile env in
  the router. Never reachable in `:prod`.
  """
  use MastWeb, :live_view

  alias MastWeb.DevUiLive.View

  @widths ~w(375 414 768 1024 1440 full)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "UI Showcase")
     |> assign(:width, "full")
     |> assign(:widths, @widths)
     |> assign(:show_modal?, false)
     |> assign(:run_log_status, nil)}
  end

  @impl true
  def handle_event("set-width", %{"width" => w}, socket) when w in @widths do
    {:noreply, assign(socket, :width, w)}
  end

  @impl true
  def handle_event("open-modal", _, socket), do: {:noreply, assign(socket, :show_modal?, true)}

  @impl true
  def handle_event("close-modal", _, socket), do: {:noreply, assign(socket, :show_modal?, false)}

  @impl true
  def handle_event("open-run-log", %{"status" => s}, socket)
      when s in ~w(running done error) do
    {:noreply, assign(socket, :run_log_status, String.to_existing_atom(s))}
  end

  @impl true
  def handle_event("close-run-log", _, socket),
    do: {:noreply, assign(socket, :run_log_status, nil)}

  @impl true
  def render(assigns), do: View.render(assigns)
end

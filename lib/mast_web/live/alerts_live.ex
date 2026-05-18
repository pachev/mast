defmodule MastWeb.AlertsLive do
  @moduledoc """
  Alerts view. Empty stub for now — the alert pipeline ships in a later
  milestone (see ADR 0004).
  """
  use MastWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Alerts")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="alerts" page_title={@page_title}>
      <.ui_page_header title="Alerts" subtitle="High-priority events that need your attention" />

      <.ui_card padded={false}>
        <.ui_empty
          icon="hero-bell-slash"
          title="No alerts yet"
          body="When CPU spikes, a release crashes, or a host falls behind on patches, it will show up here."
        />
      </.ui_card>
    </Layouts.app>
    """
  end
end

defmodule MastWeb.SettingsLive do
  @moduledoc """
  Settings stub. Wire real preferences (SSH keys, notification channels,
  theme defaults) when that work lands.
  """
  use MastWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Settings")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="settings" page_title={@page_title}>
      <.ui_page_header title="Settings" subtitle="Configure SSH keys, notifications, and more" />

      <.ui_card padded={false}>
        <.ui_empty
          icon="hero-cog-6-tooth"
          title="Settings coming soon"
          body="Key management, notification routes, and theme defaults will live here."
        />
      </.ui_card>
    </Layouts.app>
    """
  end
end

defmodule MastWeb.ServerLive.Header do
  @moduledoc """
  Page header for `MastWeb.ServerLive`: breadcrumb, status badge, title,
  scan-error banner, tab bar, and the per-tab action buttons.
  """
  use MastWeb, :html

  import MastWeb.ServerLive.Helpers

  attr :server, :map, required: true
  attr :tab, :string, required: true
  attr :scanning?, :boolean, required: true
  attr :running?, :boolean, required: true
  attr :probing?, :boolean, required: true
  attr :scan_error, :any, default: nil

  def detail_header(assigns) do
    ~H"""
    <header class="-mx-6 lg:-mx-10 -mt-6 lg:-mt-8 mb-6 px-6 lg:px-10 pt-4 pb-0 border-b border-[var(--mast-border)]">
      <div class="flex items-center justify-between gap-4 flex-wrap">
        <nav class="flex items-center gap-1.5 text-[13px]">
          <.link
            navigate={~p"/"}
            class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
          >
            Servers
          </.link>
          <span class="text-[var(--mast-font-tertiary)]">/</span>
          <.link
            patch={~p"/servers/#{@server.id}?tab=overview"}
            class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
          >
            {@server.name}
          </.link>
          <span class="text-[var(--mast-font-tertiary)]">/</span>
          <span class="text-[var(--mast-font-primary)] font-medium">{tab_label(@tab)}</span>
        </nav>

        <div class="flex items-center gap-2">
          <.ui_badge variant={status_badge(@server.status)}>
            {status_label(@server.status)}
          </.ui_badge>
          <.header_actions
            tab={@tab}
            server={@server}
            scanning?={@scanning?}
            running?={@running?}
            probing?={@probing?}
          />
        </div>
      </div>

      <div class="mt-4 flex items-center gap-3 flex-wrap">
        <h1 class="text-[22px] font-bold text-[var(--mast-font-primary)] leading-none">
          {@server.name}
        </h1>
        <p class="text-[13px] text-[var(--mast-font-secondary)] font-mono">
          {@server.host} · {@server.os_id || "—"} · {last_seen(@server)}
        </p>
      </div>

      <div
        :if={@scan_error}
        class="mt-3 px-3 py-2 rounded-[var(--radius-field)] bg-rose-100 dark:bg-rose-950/40 text-[var(--mast-status-offline)] text-sm flex items-center gap-2"
      >
        <span class="hero-exclamation-triangle size-4 shrink-0" /> Scan failed: {@scan_error}
      </div>

      <.ui_tabs active={@tab} class="mt-4 border-b-0">
        <:tab key="overview" patch={~p"/servers/#{@server.id}?tab=overview"}>Overview</:tab>
        <:tab key="releases" patch={~p"/servers/#{@server.id}?tab=releases"}>Releases</:tab>
        <:tab
          key="updates"
          patch={~p"/servers/#{@server.id}?tab=updates"}
          count={@server.updates_available || 0}
        >
          Updates
        </:tab>
        <:tab key="settings" patch={~p"/servers/#{@server.id}?tab=settings"}>Settings</:tab>
      </.ui_tabs>
    </header>
    """
  end

  attr :tab, :string, required: true
  attr :server, :map, required: true
  attr :scanning?, :boolean, required: true
  attr :running?, :boolean, required: true
  attr :probing?, :boolean, required: true

  defp header_actions(%{tab: "releases"} = assigns) do
    ~H"""
    <.ui_button
      icon="hero-signal"
      size="sm"
      phx-click="probe-apps"
      loading={@probing?}
    >
      {if @probing?, do: "Probing…", else: "Probe All"}
    </.ui_button>
    """
  end

  defp header_actions(%{tab: "updates"} = assigns) do
    ~H"""
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
      Apply All Updates
    </.ui_button>
    """
  end

  defp header_actions(%{tab: "logs"} = assigns) do
    ~H"""
    <.ui_button variant="secondary" size="sm" icon="hero-arrow-path" phx-click="check">
      Check
    </.ui_button>
    """
  end

  defp header_actions(%{tab: "settings"} = assigns) do
    ~H""
  end

  # Overview tab — show all the boring ones.
  defp header_actions(assigns) do
    ~H"""
    <.ui_button variant="secondary" size="sm" icon="hero-arrow-path" phx-click="check">
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
    """
  end
end

defmodule MastWeb.Layouts do
  @moduledoc """
  Application layouts. The `app/1` function renders the sidebar shell
  used by every LiveView. See `docs/UI.md` for the design system.
  """
  use MastWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the sidebar app shell around the LiveView's content.

      <Layouts.app flash={@flash} current_scope={@current_scope} active="dashboard" page_title="Fleet">
        ...
      </Layouts.app>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :active, :string, default: "dashboard"
  attr :page_title, :string, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer bg-[var(--mast-bg-primary)] text-[var(--mast-font-primary)]">
      <input id="app-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex min-h-screen">
        <.ui_sidebar active={@active}>
          <:nav key="dashboard" navigate={~p"/"} icon="hero-squares-2x2">Dashboard</:nav>
          <:nav key="servers" navigate={~p"/"} icon="hero-server-stack">Servers</:nav>
          <:nav key="alerts" navigate={~p"/alerts"} icon="hero-bell-alert">Alerts</:nav>
          <:nav key="audit" navigate={~p"/audit"} icon="hero-document-text">Audit</:nav>
          <:nav key="settings" navigate={~p"/settings"} icon="hero-cog-6-tooth">Settings</:nav>
          <:footer>
            <.theme_toggle />
            <span class="text-[10px] text-[var(--mast-font-tertiary)] font-mono">
              v{Mast.version()}
            </span>
          </:footer>
        </.ui_sidebar>

        <div class="flex-1 min-w-0 flex flex-col">
          <header class="lg:hidden flex items-center gap-3 h-14 px-4 border-b border-[var(--mast-border)] bg-[var(--mast-bg-sidebar)]">
            <label
              for="app-drawer"
              class="p-2 -ml-2 rounded-[var(--radius-field)] text-[var(--mast-font-secondary)] hover:text-[var(--mast-font-primary)] hover:bg-[var(--mast-bg-card-hover)] cursor-pointer"
              aria-label="Open menu"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </label>
            <div class="flex items-center gap-2">
              <img src="/images/favicon.svg" alt="" class="size-6 rounded-md" />
              <span class="text-sm font-semibold tracking-tight">Mast</span>
            </div>
          </header>

          <main class="flex-1 min-w-0 px-4 py-5 sm:px-6 sm:py-6 lg:px-10 lg:py-8">
            <div class="mx-auto max-w-7xl">
              {render_slot(@inner_block)}
            </div>
          </main>
        </div>
      </div>

      <.ui_mobile_drawer toggle_id="app-drawer" active={@active}>
        <:nav key="dashboard" navigate={~p"/"} icon="hero-squares-2x2">Dashboard</:nav>
        <:nav key="servers" navigate={~p"/"} icon="hero-server-stack">Servers</:nav>
        <:nav key="alerts" navigate={~p"/alerts"} icon="hero-bell-alert">Alerts</:nav>
        <:nav key="audit" navigate={~p"/audit"} icon="hero-document-text">Audit</:nav>
        <:nav key="settings" navigate={~p"/settings"} icon="hero-cog-6-tooth">Settings</:nav>
        <:footer>
          <.theme_toggle />
          <span class="text-[10px] text-[var(--mast-font-tertiary)] font-mono">
            v{Mast.version()}
          </span>
        </:footer>
      </.ui_mobile_drawer>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders flash messages — both the runtime flashes and the LiveView
  reconnection error placeholders.
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          MastWeb.CoreComponents.show(".phx-client-error #client-error")
          |> Phoenix.LiveView.JS.remove_attribute("hidden")
        }
        phx-connected={
          MastWeb.CoreComponents.hide("#client-error")
          |> Phoenix.LiveView.JS.set_attribute({"hidden", ""})
        }
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          MastWeb.CoreComponents.show(".phx-server-error #server-error")
          |> Phoenix.LiveView.JS.remove_attribute("hidden")
        }
        phx-connected={
          MastWeb.CoreComponents.hide("#server-error")
          |> Phoenix.LiveView.JS.set_attribute({"hidden", ""})
        }
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Theme toggle: system / light / dark. Pairs with the script in `root.html.heex`.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 bg-[var(--mast-bg-tertiary)] rounded-full p-0.5">
      <button
        class="size-7 rounded-full flex items-center justify-center text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)] data-[active=true]:bg-[var(--mast-bg-card)] data-[active=true]:text-[var(--mast-font-primary)] data-[active=true]:shadow-sm"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="System theme"
      >
        <.icon name="hero-computer-desktop" class="size-3.5" />
      </button>
      <button
        class="size-7 rounded-full flex items-center justify-center text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)] data-[active=true]:bg-[var(--mast-bg-card)] data-[active=true]:text-[var(--mast-font-primary)] data-[active=true]:shadow-sm"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
      >
        <.icon name="hero-sun" class="size-3.5" />
      </button>
      <button
        class="size-7 rounded-full flex items-center justify-center text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)] data-[active=true]:bg-[var(--mast-bg-card)] data-[active=true]:text-[var(--mast-font-primary)] data-[active=true]:shadow-sm"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
      >
        <.icon name="hero-moon" class="size-3.5" />
      </button>
    </div>
    """
  end
end

defmodule MastWeb.Components.UI.Navigation do
  @moduledoc """
  Navigation chrome: sidebar, tab bar, page header.
  """
  use Phoenix.Component

  @doc """
  Underlined tab bar driven by an `active` assign + `phx-click` events.

      <.ui_tabs active={@tab}>
        <:tab key="overview" event="set-tab">Overview</:tab>
        <:tab key="apps" event="set-tab" count={3}>Apps</:tab>
        <:tab key="updates" event="set-tab">Updates</:tab>
      </.ui_tabs>
  """
  attr :active, :string, required: true
  attr :class, :any, default: nil

  slot :tab, required: true do
    attr :key, :string, required: true
    attr :event, :string
    attr :navigate, :string
    attr :patch, :string
    attr :count, :integer
  end

  def ui_tabs(assigns) do
    ~H"""
    <div class={["flex items-center gap-1 border-b border-[var(--mast-border)]", @class]}>
      <%= for tab <- @tab do %>
        <% active? = tab.key == @active %>
        <%= cond do %>
          <% tab[:navigate] -> %>
            <.link
              navigate={tab.navigate}
              class={tab_classes(active?)}
            >
              {render_slot(tab)}
              <span :if={tab[:count]} class={tab_count_classes(active?)}>{tab.count}</span>
            </.link>
          <% tab[:patch] -> %>
            <.link
              patch={tab.patch}
              class={tab_classes(active?)}
            >
              {render_slot(tab)}
              <span :if={tab[:count]} class={tab_count_classes(active?)}>{tab.count}</span>
            </.link>
          <% true -> %>
            <button
              type="button"
              phx-click={tab[:event] || "set-tab"}
              phx-value-tab={tab.key}
              class={tab_classes(active?)}
            >
              {render_slot(tab)}
              <span :if={tab[:count]} class={tab_count_classes(active?)}>{tab.count}</span>
            </button>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp tab_classes(active?) do
    base =
      "inline-flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium leading-none " <>
        "border-b-2 -mb-px transition-colors"

    state =
      if active? do
        "border-[var(--mast-accent)] text-[var(--mast-font-primary)]"
      else
        "border-transparent text-[var(--mast-font-secondary)] hover:text-[var(--mast-font-primary)]"
      end

    base <> " " <> state
  end

  defp tab_count_classes(active?) do
    base = "ml-1 text-[10px] font-semibold px-1.5 py-0.5 rounded-full leading-none"

    if active? do
      base <> " bg-[var(--mast-accent-muted)] text-[var(--mast-accent)]"
    else
      base <> " bg-[var(--mast-bg-tertiary)] text-[var(--mast-font-secondary)]"
    end
  end

  @doc """
  Application sidebar. Renders the logo, primary nav links, and a footer
  slot for things like the theme toggle.

      <.ui_sidebar active="dashboard">
        <:nav key="dashboard" navigate={~p"/"} icon="hero-squares-2x2">Dashboard</:nav>
        <:nav key="servers" navigate={~p"/servers"} icon="hero-server">Servers</:nav>
        <:footer>
          <.theme_toggle />
        </:footer>
      </.ui_sidebar>
  """
  attr :active, :string, default: "dashboard"
  attr :class, :any, default: nil

  slot :nav, required: true do
    attr :key, :string, required: true
    attr :navigate, :string
    attr :icon, :string
  end

  slot :footer

  def ui_sidebar(assigns) do
    ~H"""
    <aside class={[
      "w-56 shrink-0 h-screen sticky top-0 flex flex-col",
      "bg-[var(--mast-bg-sidebar)] border-r border-[var(--mast-border)]",
      @class
    ]}>
      <div class="flex items-center gap-2.5 px-4 h-14 border-b border-[var(--mast-border)]">
        <img src="/images/favicon.svg" alt="Mast" class="size-7 rounded-md" />
        <span class="text-base font-semibold text-[var(--mast-font-primary)] tracking-tight">
          Mast
        </span>
      </div>

      <nav class="flex-1 px-3 py-3 space-y-0.5 overflow-y-auto">
        <%= for n <- @nav do %>
          <% active? = n.key == @active %>
          <.link
            navigate={n[:navigate] || "#"}
            class={[
              "flex items-center gap-2.5 px-3 h-9 rounded-[var(--radius-field)]",
              "text-sm font-medium leading-none transition-colors",
              if active? do
                "bg-[var(--mast-accent-muted)] text-[var(--mast-accent)]"
              else
                "text-[var(--mast-font-secondary)] hover:bg-[var(--mast-bg-card-hover)] hover:text-[var(--mast-font-primary)]"
              end
            ]}
          >
            <span :if={n[:icon]} class={[n.icon, "size-4 shrink-0"]} />
            {render_slot(n)}
          </.link>
        <% end %>
      </nav>

      <div
        :if={@footer != []}
        class="px-3 py-3 border-t border-[var(--mast-border)] flex items-center justify-between gap-2"
      >
        {render_slot(@footer)}
      </div>
    </aside>
    """
  end

  @doc """
  Page header: title + subtitle on the left, free-form actions on the right.
  Sits above content inside the main column.

      <.ui_page_header title="Fleet Overview" subtitle="6 servers across 3 regions">
        <:actions>
          <.ui_search name="q" />
          <.ui_button icon="hero-plus" navigate={~p"/servers/new"}>Add Server</.ui_button>
        </:actions>
      </.ui_page_header>
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :class, :any, default: nil

  slot :actions

  def ui_page_header(assigns) do
    ~H"""
    <div class={[
      "flex items-end justify-between gap-4 flex-wrap pb-5",
      @class
    ]}>
      <div class="min-w-0">
        <h1 class="text-2xl font-semibold tracking-tight text-[var(--mast-font-primary)] leading-tight">
          {@title}
        </h1>
        <p :if={@subtitle} class="mt-1 text-sm text-[var(--mast-font-secondary)]">
          {@subtitle}
        </p>
      </div>
      <div :if={@actions != []} class="flex items-center gap-2 flex-wrap">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end
end

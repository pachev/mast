defmodule MastWeb.Components.UI.Containers do
  @moduledoc """
  Surface containers: cards, modals, empty states, chart wrappers.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Card surface with optional header (title/subtitle/actions) and footer.

      <.ui_card>
        <:header>
          <:title>Servers</:title>
          <:subtitle>6 across 3 regions</:subtitle>
          <:actions>
            <.ui_button size="sm">Add</.ui_button>
          </:actions>
        </:header>
        ... content ...
      </.ui_card>
  """
  attr :class, :any, default: nil
  attr :padded, :boolean, default: true

  slot :header do
    attr :class, :any
  end

  slot :title
  slot :subtitle
  slot :actions
  slot :inner_block, required: true
  slot :footer

  def ui_card(assigns) do
    ~H"""
    <section class={[
      "bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
      "rounded-[var(--radius-box)] shadow-sm overflow-hidden",
      @class
    ]}>
      <header
        :if={@header != [] or @title != [] or @subtitle != [] or @actions != []}
        class="flex items-start justify-between gap-4 px-5 pt-5 pb-3"
      >
        <div :if={@title != [] or @subtitle != []} class={["min-w-0", @actions == [] && "flex-1"]}>
          <h2
            :if={@title != []}
            class="text-base font-semibold text-[var(--mast-font-primary)] leading-tight"
          >
            {render_slot(@title)}
          </h2>
          <p :if={@subtitle != []} class="text-xs text-[var(--mast-font-secondary)] mt-1">
            {render_slot(@subtitle)}
          </p>
        </div>
        <div :for={h <- @header} class="flex-1">{render_slot(h)}</div>
        <div :if={@actions != []} class="flex items-center gap-2 shrink-0">
          {render_slot(@actions)}
        </div>
      </header>

      <div class={if @padded, do: "px-5 pb-5", else: ""}>
        {render_slot(@inner_block)}
      </div>

      <footer
        :if={@footer != []}
        class="px-5 py-3 border-t border-[var(--mast-border)] bg-[var(--mast-bg-secondary)]"
      >
        {render_slot(@footer)}
      </footer>
    </section>
    """
  end

  @doc """
  Centered empty-state block with optional icon, title, body, and CTA.

      <.ui_empty
        icon="hero-server"
        title="No alerts yet"
        body="When something needs attention, it'll show here."
      >
        <.ui_button>Add Server</.ui_button>
      </.ui_empty>
  """
  attr :icon, :string, default: "hero-inbox"
  attr :title, :string, required: true
  attr :body, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block

  def ui_empty(assigns) do
    ~H"""
    <div class={["flex flex-col items-center text-center py-12 px-6", @class]}>
      <div class="size-12 rounded-full bg-[var(--mast-bg-tertiary)] flex items-center justify-center mb-4">
        <span class={[@icon, "size-5 text-[var(--mast-font-tertiary)]"]} />
      </div>
      <h3 class="text-sm font-semibold text-[var(--mast-font-primary)]">{@title}</h3>
      <p :if={@body} class="mt-1 text-xs text-[var(--mast-font-secondary)] max-w-sm">
        {@body}
      </p>
      <div :if={@inner_block != []} class="mt-5">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Centered modal. Closes via the `on_cancel` JS command (patch back to a
  parent route, etc.).

      <.ui_modal :if={@show} id="confirm" on_cancel={JS.patch(~p"/")}>
        <:title>Delete server</:title>
        <:subtitle>This action cannot be undone.</:subtitle>
        Confirmation copy or form here.
        <:footer>
          <.ui_button variant="secondary" phx-click={JS.patch(~p"/")}>Cancel</.ui_button>
          <.ui_button variant="destructive" phx-click="delete">Delete</.ui_button>
        </:footer>
      </.ui_modal>
  """
  attr :id, :string, required: true
  attr :on_cancel, JS, default: %JS{}
  attr :class, :any, default: nil

  slot :title
  slot :subtitle
  slot :inner_block, required: true
  slot :footer

  def ui_modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
      phx-window-keydown={@on_cancel}
      phx-key="escape"
    >
      <div
        class={[
          "w-full max-w-md bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
          "rounded-[var(--radius-box)] shadow-xl overflow-hidden",
          @class
        ]}
        phx-click-away={@on_cancel}
      >
        <header
          :if={@title != [] or @subtitle != []}
          class="flex items-start justify-between gap-4 px-5 pt-5 pb-3"
        >
          <div class="min-w-0">
            <h2
              :if={@title != []}
              class="text-base font-semibold text-[var(--mast-font-primary)] leading-tight"
            >
              {render_slot(@title)}
            </h2>
            <p :if={@subtitle != []} class="text-xs text-[var(--mast-font-secondary)] mt-1">
              {render_slot(@subtitle)}
            </p>
          </div>
          <button
            type="button"
            phx-click={@on_cancel}
            class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)] -mt-1 -mr-1 p-1"
            aria-label="Close"
          >
            <span class="hero-x-mark size-4" />
          </button>
        </header>

        <div class="px-5 pb-5">
          {render_slot(@inner_block)}
        </div>

        <footer
          :if={@footer != []}
          class="flex items-center justify-end gap-2 px-5 py-3 border-t border-[var(--mast-border)] bg-[var(--mast-bg-secondary)]"
        >
          {render_slot(@footer)}
        </footer>
      </div>
    </div>
    """
  end

  @doc """
  Bordered card with a title row + a body that's typically a chart, image,
  or placeholder. Renders a fixed-height body so charts have predictable
  vertical space.

      <.ui_chart_card title="Memory over time">
        <:badge>Last 24h</:badge>
        <div class="h-[180px] flex items-center justify-center text-[var(--mast-font-tertiary)]">
          chart goes here
        </div>
      </.ui_chart_card>
  """
  attr :title, :string, required: true
  attr :class, :any, default: nil
  slot :badge
  slot :inner_block, required: true

  def ui_chart_card(assigns) do
    ~H"""
    <section class={[
      "bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
      "rounded-[var(--radius-box)] p-5 shadow-sm",
      @class
    ]}>
      <header class="flex items-center gap-3 mb-4">
        <h3 class="text-[15px] font-semibold text-[var(--mast-font-primary)]">{@title}</h3>
        <span class="flex-1" />
        <span :if={@badge != []} class="text-xs text-[var(--mast-font-tertiary)]">
          {render_slot(@badge)}
        </span>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end
end

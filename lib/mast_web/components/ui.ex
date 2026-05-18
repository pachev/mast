defmodule MastWeb.Components.UI do
  @moduledoc """
  Mast design-system components. Maps the pencil component library
  (`components.pen`) to Phoenix function components.

  Token reference: see `docs/UI.md` for usage patterns and the full
  catalog. Tokens themselves live in `assets/css/app.css` under
  `:root` and `[data-theme=dark]` as `--mast-*` variables, with the
  daisyUI theme retuned to match.

  Import this module wherever you render LiveView templates. It is
  already wired into `MastWeb` html_helpers.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  # =========================================================================
  # Button
  # =========================================================================

  @doc """
  Renders a button.

      <.ui_button>Save</.ui_button>
      <.ui_button variant="secondary" size="sm">Cancel</.ui_button>
      <.ui_button variant="destructive" loading>Deleting...</.ui_button>
      <.ui_button icon="hero-arrow-down-tray">Apply Updates</.ui_button>
      <.ui_button navigate={~p"/"}>Home</.ui_button>
  """
  attr :variant, :string,
    default: "primary",
    values: ~w(primary secondary ghost destructive)

  attr :size, :string, default: "md", values: ~w(md sm)
  attr :icon, :string, default: nil
  attr :loading, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(href navigate patch method form name value type)
  slot :inner_block, required: true

  def ui_button(assigns) do
    assigns = assign(assigns, :classes, button_classes(assigns))

    ~H"""
    <%= cond do %>
      <% @rest[:href] || @rest[:navigate] || @rest[:patch] -> %>
        <.link class={@classes} {@rest}>
          <.ui_button_inner icon={@icon} loading={@loading}>
            {render_slot(@inner_block)}
          </.ui_button_inner>
        </.link>
      <% true -> %>
        <button class={@classes} disabled={@disabled or @loading} {@rest}>
          <.ui_button_inner icon={@icon} loading={@loading}>
            {render_slot(@inner_block)}
          </.ui_button_inner>
        </button>
    <% end %>
    """
  end

  attr :icon, :string, default: nil
  attr :loading, :boolean, default: false
  slot :inner_block, required: true

  defp ui_button_inner(assigns) do
    ~H"""
    <span :if={@loading} class="hero-arrow-path size-3.5 motion-safe:animate-spin shrink-0" />
    <span :if={@icon && !@loading} class={[@icon, "size-3.5 shrink-0"]} />
    {render_slot(@inner_block)}
    """
  end

  defp button_classes(%{
         variant: variant,
         size: size,
         class: extra,
         loading: loading,
         disabled: disabled
       }) do
    base =
      "inline-flex items-center justify-center gap-1.5 font-medium leading-none whitespace-nowrap " <>
        "rounded-[var(--radius-field)] transition-colors duration-150 " <>
        "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 " <>
        "focus-visible:outline-[var(--mast-accent)] " <>
        "disabled:cursor-not-allowed"

    size_cls =
      case size do
        "sm" -> "h-7 px-2.5 text-[11px]"
        _ -> "h-9 px-4 text-[13px]"
      end

    variant_cls =
      case variant do
        "primary" ->
          "bg-[var(--mast-accent)] text-[var(--mast-accent-text)] hover:bg-[var(--mast-accent-hover)] " <>
            "disabled:opacity-40"

        "secondary" ->
          "bg-[var(--mast-bg-card)] text-[var(--mast-font-primary)] border border-[var(--mast-border)] " <>
            "hover:bg-[var(--mast-bg-card-hover)] disabled:opacity-50"

        "ghost" ->
          "bg-transparent text-[var(--mast-font-secondary)] " <>
            "hover:bg-[var(--mast-bg-card-hover)] hover:text-[var(--mast-font-primary)] " <>
            "disabled:opacity-50"

        "destructive" ->
          "bg-[var(--mast-status-offline)] text-white hover:opacity-90 disabled:opacity-50"
      end

    state_cls = if loading or disabled, do: "pointer-events-none", else: ""

    [base, size_cls, variant_cls, state_cls, extra]
  end

  # =========================================================================
  # Badge
  # =========================================================================

  @doc """
  Pill badge with optional status dot.

      <.ui_badge variant="online">Online</.ui_badge>
      <.ui_badge variant="warning">3 updates</.ui_badge>
      <.ui_badge variant="neutral" dot={false}>v0.4.0</.ui_badge>
  """
  attr :variant, :string,
    default: "neutral",
    values: ~w(online offline warning neutral accent)

  attr :size, :string, default: "md", values: ~w(md sm)
  attr :dot, :boolean, default: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def ui_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full leading-none",
      badge_size(@size),
      badge_variant(@variant),
      @class
    ]}>
      <span
        :if={@dot && @variant != "neutral"}
        class={["size-1.5 rounded-full shrink-0", badge_dot(@variant)]}
      />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_size("sm"), do: "h-5 px-2 gap-1 text-[11px] font-normal"
  defp badge_size(_), do: "h-6 px-2.5 gap-1.5 text-[11px] font-medium"

  defp badge_variant("online"),
    do: "bg-[var(--mast-accent-muted)] text-[var(--mast-accent)]"

  defp badge_variant("offline"),
    do: "bg-rose-100 text-[var(--mast-status-offline)] dark:bg-rose-950/40"

  defp badge_variant("warning"),
    do: "bg-amber-100 text-[var(--mast-status-warning)] dark:bg-amber-950/40"

  defp badge_variant("accent"),
    do: "bg-[var(--mast-accent)] text-[var(--mast-accent-text)]"

  defp badge_variant(_),
    do: "bg-[var(--mast-bg-tertiary)] text-[var(--mast-font-secondary)]"

  defp badge_dot("online"), do: "bg-[var(--mast-status-online)]"
  defp badge_dot("offline"), do: "bg-[var(--mast-status-offline)]"
  defp badge_dot("warning"), do: "bg-[var(--mast-status-warning)]"
  defp badge_dot(_), do: "bg-[var(--mast-font-tertiary)]"

  # =========================================================================
  # Status dot (standalone)
  # =========================================================================

  attr :status, :string, default: "unknown"
  attr :class, :any, default: nil

  def ui_status_dot(assigns) do
    ~H"""
    <span class={[
      "inline-block size-2.5 rounded-full shrink-0",
      status_dot_color(@status),
      @class
    ]} />
    """
  end

  defp status_dot_color("up"), do: "bg-[var(--mast-status-online)]"
  defp status_dot_color("online"), do: "bg-[var(--mast-status-online)]"
  defp status_dot_color("down"), do: "bg-[var(--mast-status-offline)]"
  defp status_dot_color("offline"), do: "bg-[var(--mast-status-offline)]"
  defp status_dot_color("warning"), do: "bg-[var(--mast-status-warning)]"
  defp status_dot_color(_), do: "bg-[var(--mast-font-tertiary)]"

  # =========================================================================
  # Inputs (raw — for forms use `MastWeb.CoreComponents.input/1`)
  # =========================================================================

  @doc """
  Search-style input with leading icon. Self-contained, no form wrapping.

      <form phx-change="filter">
        <.ui_search name="q" value={@filter} placeholder="Search servers..." />
      </form>
  """
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: "Search..."
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled autofocus)

  def ui_search(assigns) do
    ~H"""
    <label class={[
      "flex items-center gap-2 h-10 px-3 rounded-[var(--radius-field)]",
      "bg-[var(--mast-bg-input)] border border-[var(--mast-border)]",
      "focus-within:border-[var(--mast-border-focus)] transition-colors",
      @class
    ]}>
      <span class="hero-magnifying-glass size-4 text-[var(--mast-font-tertiary)] shrink-0" />
      <input
        type="search"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        class="flex-1 bg-transparent outline-none text-sm placeholder:text-[var(--mast-font-tertiary)] text-[var(--mast-font-primary)]"
        {@rest}
      />
    </label>
    """
  end

  # =========================================================================
  # Card
  # =========================================================================

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

  # =========================================================================
  # Stat card
  # =========================================================================

  @doc """
  Single KPI card: label + big number + optional trend/sub-label.

      <.ui_stat label="Total Servers" value={6} />
      <.ui_stat label="Online" value={5} tone="online" />
      <.ui_stat label="Updates Available" value={12} tone="warning" />
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil
  attr :tone, :string, default: "default", values: ~w(default online warning offline accent)
  attr :class, :any, default: nil

  def ui_stat(assigns) do
    ~H"""
    <div class={[
      "bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
      "rounded-[var(--radius-box)] px-5 py-4 shadow-sm",
      @class
    ]}>
      <div class="text-xs font-medium uppercase tracking-wider text-[var(--mast-font-secondary)]">
        {@label}
      </div>
      <div class={["mt-1 text-3xl font-semibold tabular-nums leading-none", stat_tone(@tone)]}>
        {@value}
      </div>
      <div :if={@sub} class="mt-2 text-xs text-[var(--mast-font-tertiary)]">
        {@sub}
      </div>
    </div>
    """
  end

  defp stat_tone("online"), do: "text-[var(--mast-status-online)]"
  defp stat_tone("warning"), do: "text-[var(--mast-status-warning)]"
  defp stat_tone("offline"), do: "text-[var(--mast-status-offline)]"
  defp stat_tone("accent"), do: "text-[var(--mast-accent)]"
  defp stat_tone(_), do: "text-[var(--mast-font-primary)]"

  # =========================================================================
  # Metric bar (CPU/mem/disk)
  # =========================================================================

  @doc """
  Horizontal usage bar with leading numeric label.

      <.ui_metric label="CPU" value={68} />
      <.ui_metric label="Memory" value={9.4} max={16} suffix="GB" />
  """
  attr :label, :string, default: nil
  attr :value, :any, required: true
  attr :max, :integer, default: 100
  attr :suffix, :string, default: "%"
  attr :class, :any, default: nil

  def ui_metric(assigns) do
    pct = metric_pct(assigns.value, assigns.max)

    assigns =
      assigns
      |> assign(:pct, pct)
      |> assign(:tone, metric_tone(pct))

    ~H"""
    <div class={["space-y-1.5", @class]}>
      <div
        :if={@label}
        class="flex items-center justify-between text-xs text-[var(--mast-font-secondary)]"
      >
        <span>{@label}</span>
        <span class="tabular-nums font-medium text-[var(--mast-font-primary)]">
          {format_metric(@value, @suffix, @max)}
        </span>
      </div>
      <div class="h-1.5 rounded-full bg-[var(--mast-bg-tertiary)] overflow-hidden">
        <div
          class={["h-full rounded-full transition-all duration-300", @tone]}
          style={"width: #{@pct}%;"}
        />
      </div>
    </div>
    """
  end

  defp metric_pct(nil, _), do: 0

  defp metric_pct(v, max) when is_number(v) and is_number(max) and max > 0 do
    v |> Kernel./(max) |> Kernel.*(100) |> min(100) |> max(0)
  end

  defp metric_pct(_, _), do: 0

  defp metric_tone(pct) when pct >= 90, do: "bg-[var(--mast-status-offline)]"
  defp metric_tone(pct) when pct >= 75, do: "bg-[var(--mast-status-warning)]"
  defp metric_tone(_), do: "bg-[var(--mast-chart-blue)]"

  defp format_metric(nil, _, _), do: "—"

  defp format_metric(v, "%", _) when is_float(v),
    do: :erlang.float_to_binary(v, decimals: 1) <> "%"

  defp format_metric(v, "%", _), do: "#{v}%"

  defp format_metric(v, suffix, max) when is_number(v) and is_number(max) do
    "#{trim_num(v)} / #{trim_num(max)} #{suffix}"
  end

  defp format_metric(v, suffix, _), do: "#{v} #{suffix}"

  defp trim_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp trim_num(n), do: "#{n}"

  # =========================================================================
  # Tab bar
  # =========================================================================

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

  # =========================================================================
  # Empty state
  # =========================================================================

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

  # =========================================================================
  # Modal
  # =========================================================================

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

  # =========================================================================
  # Sidebar nav
  # =========================================================================

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

  # =========================================================================
  # Page header bar
  # =========================================================================

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

  # =========================================================================
  # Server card (dashboard tile)
  # =========================================================================

  @doc """
  Compact server card with status, CPU/Mem/Disk metrics, and last-seen.

      <.ui_server_card server={s} />
  """
  attr :server, :map, required: true
  attr :class, :any, default: nil

  def ui_server_card(assigns) do
    ~H"""
    <.link
      navigate={"/servers/#{@server.id}"}
      class={[
        "block bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
        "rounded-[var(--radius-box)] p-4 shadow-sm transition-colors",
        "hover:border-[var(--mast-accent)] hover:bg-[var(--mast-bg-card-hover)]",
        @class
      ]}
    >
      <div class="flex items-center justify-between gap-3 mb-3">
        <div class="flex items-center gap-2 min-w-0">
          <.ui_status_dot status={@server.status} />
          <span class="font-mono text-sm font-medium text-[var(--mast-font-primary)] truncate">
            {@server.name}
          </span>
        </div>
        <.ui_badge variant={server_badge_variant(@server.status)}>
          {server_status_label(@server.status)}
        </.ui_badge>
      </div>

      <div class="space-y-2">
        <.ui_metric label="CPU" value={@server.cpu} />
        <.ui_metric label="MEM" value={@server.memory} />
        <.ui_metric label="DISK" value={@server.disk} />
      </div>
    </.link>
    """
  end

  defp server_badge_variant("up"), do: "online"
  defp server_badge_variant("down"), do: "offline"
  defp server_badge_variant(_), do: "neutral"

  defp server_status_label("up"), do: "Online"
  defp server_status_label("down"), do: "Offline"
  defp server_status_label(_), do: "Unknown"

  # =========================================================================
  # Elixir app card
  # =========================================================================

  @doc """
  Card representing one Elixir release running on a server.

      <.ui_app_card name="mast_web" version="0.4.0" status="running" />
  """
  attr :name, :string, required: true
  attr :version, :string, default: nil
  attr :status, :string, default: "running"
  attr :uptime, :string, default: nil

  def ui_app_card(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3 px-4 py-3 bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-field)]">
      <div class="flex items-center gap-3 min-w-0">
        <div class="size-8 rounded-md bg-[var(--mast-accent-muted)] flex items-center justify-center shrink-0">
          <span class="text-[var(--mast-accent)] font-mono text-xs font-semibold">
            {String.first(@name) |> String.upcase()}
          </span>
        </div>
        <div class="min-w-0">
          <div class="font-mono text-sm font-medium text-[var(--mast-font-primary)] truncate">
            {@name}
          </div>
          <div class="text-xs text-[var(--mast-font-tertiary)] truncate">
            <span :if={@version}>v{@version}</span>
            <span :if={@version && @uptime} class="mx-1">·</span>
            <span :if={@uptime}>up {@uptime}</span>
          </div>
        </div>
      </div>
      <.ui_badge variant={app_status_variant(@status)}>
        {String.capitalize(@status)}
      </.ui_badge>
    </div>
    """
  end

  defp app_status_variant("running"), do: "online"
  defp app_status_variant("stopped"), do: "offline"
  defp app_status_variant("pending"), do: "warning"
  defp app_status_variant(_), do: "neutral"

  @doc """
  Compact row representation of an Elixir release. Designed to live
  stacked inside a card (see Apps tab on ServerLive).

      <.ui_app_row name="mast_web" meta="v0.4.0 · mast@web-prod-1 · OTP 28" status="running" />
  """
  attr :name, :string, required: true
  attr :meta, :string, default: nil
  attr :status, :string, default: "running"
  attr :class, :any, default: nil

  def ui_app_row(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 px-3 py-3 rounded-[var(--radius-field)]",
      "bg-[var(--mast-bg-secondary)]",
      @class
    ]}>
      <div class="flex-1 min-w-0">
        <div class="font-mono text-[13px] font-semibold text-[var(--mast-font-primary)] truncate">
          {@name}
        </div>
        <div :if={@meta} class="text-[11px] text-[var(--mast-font-tertiary)] truncate mt-0.5">
          {@meta}
        </div>
      </div>
      <.ui_badge variant={app_status_variant(@status)} size="sm">{@status}</.ui_badge>
    </div>
    """
  end

  @doc """
  Card title row with an accent icon, label, and right-aligned count.
  Use as the title slot of `ui_card/1` when you want the design's icon-led
  card header style (e.g. Elixir Apps, Recent Logs).

      <.ui_card>
        <:title>
          <.ui_card_title icon="hero-cube" color="purple">
            Elixir Apps
            <:meta>3 running</:meta>
          </.ui_card_title>
        </:title>
        ...
      </.ui_card>
  """
  attr :icon, :string, required: true
  attr :color, :string, default: "purple", values: ~w(purple green blue orange accent)
  slot :inner_block, required: true
  slot :meta

  def ui_card_title(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-2 w-full">
      <span class={[@icon, "size-4 shrink-0", card_title_color(@color)]} />
      <span class="text-[14px] font-semibold text-[var(--mast-font-primary)]">
        {render_slot(@inner_block)}
      </span>
      <span class="flex-1" />
      <span :if={@meta != []} class="text-[12px] text-[var(--mast-font-tertiary)]">
        {render_slot(@meta)}
      </span>
    </span>
    """
  end

  defp card_title_color("purple"), do: "text-[var(--mast-chart-purple)]"
  defp card_title_color("green"), do: "text-[var(--mast-chart-green)]"
  defp card_title_color("blue"), do: "text-[var(--mast-chart-blue)]"
  defp card_title_color("orange"), do: "text-[var(--mast-chart-orange)]"
  defp card_title_color(_), do: "text-[var(--mast-accent)]"

  @doc """
  Tiny pill chip: status dot + label. Used in the Dependencies grid where
  showing 60 apps as full rows is overkill.

      <.ui_chip status="running">phoenix</.ui_chip>
      <.ui_chip status="warning">postgrex</.ui_chip>
  """
  attr :status, :string, default: "running"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def ui_chip(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 h-6 px-2.5 rounded-full",
      "text-[11px] font-mono leading-none",
      chip_variant(@status),
      @class
    ]}>
      <span class={["size-1.5 rounded-full shrink-0", chip_dot(@status)]} />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp chip_variant("running"), do: "bg-[var(--mast-accent-muted)] text-[var(--mast-accent)]"

  defp chip_variant("warning"),
    do: "bg-amber-100 text-[var(--mast-status-warning)] dark:bg-amber-950/40"

  defp chip_variant(_), do: "bg-[var(--mast-bg-tertiary)] text-[var(--mast-font-secondary)]"

  defp chip_dot("running"), do: "bg-[var(--mast-status-online)]"
  defp chip_dot("warning"), do: "bg-[var(--mast-status-warning)]"
  defp chip_dot(_), do: "bg-[var(--mast-status-offline)]"

  @doc """
  Single labeled metric tile (no bar). Used in dense metric rows like
  the Release card's Memory / Processes / Msg Queue strip.

      <.ui_metric_tile label="Memory" value="106 MB" />
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :class, :any, default: nil

  def ui_metric_tile(assigns) do
    ~H"""
    <div class={["flex-1 text-center", @class]}>
      <div class="text-[11px] text-[var(--mast-font-tertiary)] uppercase tracking-wider">
        {@label}
      </div>
      <div class="font-mono text-lg font-semibold text-[var(--mast-font-primary)] mt-1">
        {@value}
      </div>
    </div>
    """
  end

  @doc """
  Prominent card for a single Elixir release. Renders the release name and
  version next to a hexagon glyph, a right-side status badge, a horizontal
  metric row (Memory / Processes / Msg Queue), and a footer line for
  uptime + OTP version.

      <.ui_release_card
        name="hermes"
        node_name="hermes@ip-..."
        version="0.1.0"
        status="running"
        memory_mb={106.0}
        processes={536}
        msg_queue={0}
        uptime_seconds={576_000}
        otp_release="28"
      />
  """
  attr :name, :string, required: true
  attr :version, :string, default: nil
  attr :node_name, :string, default: nil
  attr :status, :string, default: "running"
  attr :memory_mb, :any, default: nil
  attr :processes, :any, default: nil
  attr :msg_queue, :any, default: nil
  attr :uptime_seconds, :any, default: nil
  attr :otp_release, :string, default: nil
  attr :rest, :global, include: ~w(href navigate patch)

  def ui_release_card(assigns) do
    body =
      ~H"""
      <div class="flex items-start justify-between gap-4">
        <div class="flex items-start gap-3 min-w-0">
          <div class="size-9 rounded-md bg-[var(--mast-accent-muted)] flex items-center justify-center shrink-0">
            <span class="hero-cube size-5 text-[var(--mast-chart-purple)]" />
          </div>
          <div class="min-w-0">
            <div class="font-mono text-[15px] font-semibold text-[var(--mast-font-primary)] truncate">
              {@name}
            </div>
            <div class="text-xs text-[var(--mast-font-tertiary)] truncate mt-0.5 font-mono">
              <span :if={@version}>v{@version}</span>
              <span :if={@version && @node_name} class="mx-1">·</span>
              <span :if={@node_name}>{@node_name}</span>
            </div>
          </div>
        </div>
        <.ui_badge variant={release_status_variant(@status)} size="sm">{@status}</.ui_badge>
      </div>

      <hr class="border-t border-[var(--mast-border)] my-4" />

      <div class="flex items-center gap-4">
        <.ui_metric_tile label="Memory" value={format_memory(@memory_mb)} />
        <.ui_metric_tile label="Processes" value={format_count(@processes)} />
        <.ui_metric_tile label="Msg Queue" value={format_count(@msg_queue)} />
      </div>

      <hr
        :if={@uptime_seconds || @otp_release}
        class="border-t border-[var(--mast-border)] my-4"
      />

      <div
        :if={@uptime_seconds || @otp_release}
        class="flex items-center gap-2 text-xs text-[var(--mast-font-tertiary)]"
      >
        <span class="hero-clock size-3.5" />
        <span :if={@uptime_seconds}>up {format_uptime(@uptime_seconds)}</span>
        <span :if={@uptime_seconds && @otp_release} class="mx-1">·</span>
        <span :if={@otp_release}>OTP {@otp_release}</span>
      </div>
      """

    classes =
      "block bg-[var(--mast-bg-card)] border border-[var(--mast-border)] " <>
        "rounded-[var(--radius-box)] p-4 shadow-sm transition-colors " <>
        "hover:border-[var(--mast-accent)]"

    assigns = assign(assigns, :classes, classes) |> assign(:body, body)

    ~H"""
    <%= cond do %>
      <% @rest[:navigate] || @rest[:patch] || @rest[:href] -> %>
        <.link class={@classes} {@rest}>{@body}</.link>
      <% true -> %>
        <div class={@classes}>{@body}</div>
    <% end %>
    """
  end

  defp release_status_variant("running"), do: "online"
  defp release_status_variant("unreachable"), do: "warning"
  defp release_status_variant("stopped"), do: "offline"
  defp release_status_variant(_), do: "neutral"

  defp format_memory(nil), do: "—"
  defp format_memory(n) when is_number(n), do: "#{trunc(n)} MB"
  defp format_memory(_), do: "—"

  defp format_count(nil), do: "—"
  defp format_count(n) when is_number(n), do: Integer.to_string(trunc(n))
  defp format_count(_), do: "—"

  defp format_uptime(nil), do: "—"

  defp format_uptime(s) when is_integer(s) do
    cond do
      s < 60 -> "#{s}s"
      s < 3600 -> "#{div(s, 60)}m"
      s < 86_400 -> "#{div(s, 3600)}h #{rem(div(s, 60), 60)}m"
      true -> "#{div(s, 86_400)} days"
    end
  end

  @doc """
  Big-number stat tile (icon + label + mono value + sub-label). Designed
  for dense KPI rows on detail pages like AppLive.

      <.ui_stat_tile icon="hero-cpu-chip" label="Memory" value="106.0 MB" sub="Total VM allocation" />
      <.ui_stat_tile label="Msg Queue" value="0" sub="Mailbox backlog" tone="accent" />
  """
  attr :icon, :string, default: nil
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil
  attr :tone, :string, default: "default", values: ~w(default accent warning online offline)
  attr :class, :any, default: nil

  def ui_stat_tile(assigns) do
    ~H"""
    <div class={[
      "bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
      "rounded-[var(--radius-box)] p-5 shadow-sm",
      @class
    ]}>
      <div class="flex items-center gap-1.5 text-[var(--mast-font-secondary)]">
        <span :if={@icon} class={[@icon, "size-3.5"]} />
        <span class="text-xs font-medium uppercase tracking-wider">{@label}</span>
      </div>
      <div class={[
        "font-mono text-[28px] font-bold tabular-nums leading-tight mt-2",
        stat_tile_tone(@tone)
      ]}>
        {@value}
      </div>
      <div :if={@sub} class="text-[11px] text-[var(--mast-font-tertiary)] mt-1">
        {@sub}
      </div>
    </div>
    """
  end

  defp stat_tile_tone("accent"), do: "text-[var(--mast-accent)]"
  defp stat_tile_tone("warning"), do: "text-[var(--mast-status-warning)]"
  defp stat_tile_tone("online"), do: "text-[var(--mast-status-online)]"
  defp stat_tile_tone("offline"), do: "text-[var(--mast-status-offline)]"
  defp stat_tile_tone(_), do: "text-[var(--mast-font-primary)]"

  @doc """
  Key/value table inside a bordered card. Each row is a fixed 44px tall
  with a thin divider; the header row is 48px. Last row has no border.

      <.ui_kv_table title="Application Info">
        <:row label="Node">hermes@ip-...</:row>
        <:row label="Status">
          <.ui_badge variant="online">running</.ui_badge>
        </:row>
        <:row label="Version">0.1.0</:row>
      </.ui_kv_table>
  """
  attr :title, :string, required: true
  attr :class, :any, default: nil

  slot :row, required: true do
    attr :label, :string, required: true
  end

  def ui_kv_table(assigns) do
    ~H"""
    <div class={[
      "bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
      "rounded-[var(--radius-box)] overflow-hidden",
      @class
    ]}>
      <div class="h-12 px-5 flex items-center border-b border-[var(--mast-border)]">
        <h3 class="text-[14px] font-semibold text-[var(--mast-font-primary)]">{@title}</h3>
      </div>
      <div
        :for={{row, idx} <- Enum.with_index(@row)}
        class={[
          "h-11 px-5 flex items-center gap-4",
          idx < length(@row) - 1 && "border-b border-[var(--mast-border)]"
        ]}
      >
        <span class="text-[13px] font-medium text-[var(--mast-font-secondary)] w-40 shrink-0">
          {row.label}
        </span>
        <span class="text-[13px] font-mono text-[var(--mast-font-primary)] flex-1 min-w-0 truncate">
          {render_slot(row)}
        </span>
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

  # =========================================================================
  # Log entry row
  # =========================================================================

  @doc """
  Single line in a streaming log panel.

      <.ui_log_entry time="14:22:01" kind={:info}>
        Started apt update
      </.ui_log_entry>
  """
  attr :time, :string, default: nil
  attr :kind, :atom, default: :info, values: [:info, :stdout, :stderr, :exit, :error]
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def ui_log_entry(assigns) do
    ~H"""
    <div class={[
      "flex gap-3 px-3 py-1 font-mono text-xs leading-relaxed",
      log_kind_color(@kind),
      @class
    ]}>
      <span :if={@time} class="text-[var(--mast-font-tertiary)] shrink-0 select-none">
        {@time}
      </span>
      <span class="whitespace-pre-wrap break-all flex-1">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  defp log_kind_color(:stdout), do: "text-[var(--mast-font-primary)]"
  defp log_kind_color(:stderr), do: "text-[var(--mast-status-warning)]"
  defp log_kind_color(:exit), do: "text-[var(--mast-status-online)] font-semibold"
  defp log_kind_color(:error), do: "text-[var(--mast-status-offline)] font-semibold"
  defp log_kind_color(_), do: "text-[var(--mast-font-secondary)]"

  # =========================================================================
  # Audit event row
  # =========================================================================

  @doc """
  Single row in the audit log: actor, action verb, target, timestamp.

      <.ui_audit_row variant="action" actor="System" verb="scanned" target="web-prod-1" time="2m ago" />
      <.ui_audit_row variant="failure" actor="System" verb="failed to connect" target="db-prod-1" time="5m ago" />
  """
  attr :variant, :string,
    default: "action",
    values: ~w(action failure scan create delete key-create)

  attr :actor, :string, required: true
  attr :verb, :string, required: true
  attr :target, :string, default: nil
  attr :time, :string, required: true
  attr :detail, :string, default: nil

  def ui_audit_row(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 px-4 py-3 border-b border-[var(--mast-border)] last:border-0 hover:bg-[var(--mast-bg-card-hover)]",
      audit_row_bg(@variant)
    ]}>
      <div class="size-8 rounded-full bg-[var(--mast-bg-tertiary)] flex items-center justify-center shrink-0">
        <span class={[audit_icon(@variant), "size-4", audit_icon_color(@variant)]} />
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 flex-wrap text-sm">
          <span class="font-medium text-[var(--mast-font-primary)]">{@actor}</span>
          <.ui_badge variant={audit_badge_variant(@variant)} dot={false}>
            {audit_label(@variant)}
          </.ui_badge>
          <span class="text-[var(--mast-font-secondary)]">{@verb}</span>
          <span :if={@target} class="font-mono text-[var(--mast-font-primary)]">{@target}</span>
        </div>
        <div :if={@detail} class="text-xs text-[var(--mast-font-tertiary)] mt-0.5 truncate">
          {@detail}
        </div>
      </div>
      <div class="text-xs text-[var(--mast-font-tertiary)] tabular-nums shrink-0">{@time}</div>
    </div>
    """
  end

  defp audit_icon("scan"), do: "hero-magnifying-glass"
  defp audit_icon("create"), do: "hero-plus"
  defp audit_icon("delete"), do: "hero-trash"
  defp audit_icon("failure"), do: "hero-exclamation-triangle"
  defp audit_icon("key-create"), do: "hero-key"
  defp audit_icon(_), do: "hero-bolt"

  # Matches the pencil design: failure + delete rows get a subtle rose tint.
  defp audit_row_bg("failure"), do: "bg-rose-50/70 dark:bg-rose-950/20"
  defp audit_row_bg("delete"), do: "bg-rose-50/70 dark:bg-rose-950/20"
  defp audit_row_bg(_), do: ""

  defp audit_icon_color("failure"), do: "text-[var(--mast-status-offline)]"
  defp audit_icon_color("delete"), do: "text-[var(--mast-status-offline)]"
  defp audit_icon_color("scan"), do: "text-[var(--mast-chart-blue)]"
  defp audit_icon_color("create"), do: "text-[var(--mast-status-online)]"
  defp audit_icon_color("key-create"), do: "text-[var(--mast-chart-purple)]"
  defp audit_icon_color(_), do: "text-[var(--mast-font-secondary)]"

  defp audit_badge_variant("failure"), do: "offline"
  defp audit_badge_variant("create"), do: "online"
  defp audit_badge_variant("scan"), do: "neutral"
  defp audit_badge_variant("delete"), do: "offline"
  defp audit_badge_variant("key-create"), do: "accent"
  defp audit_badge_variant(_), do: "neutral"

  defp audit_label("scan"), do: "scan"
  defp audit_label("create"), do: "create"
  defp audit_label("delete"), do: "delete"
  defp audit_label("failure"), do: "failure"
  defp audit_label("key-create"), do: "key.create"
  defp audit_label(_), do: "action"

  # =========================================================================
  # JS helpers
  # =========================================================================

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 200,
      transition: {"transition-all ease-out duration-200", "opacity-0", "opacity-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 150,
      transition: {"transition-all ease-in duration-150", "opacity-100", "opacity-0"}
    )
  end
end

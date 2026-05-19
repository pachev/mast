defmodule MastWeb.Components.UI.Feedback do
  @moduledoc """
  Status/feedback components: badges, status dots, chips.
  """
  use Phoenix.Component

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
end

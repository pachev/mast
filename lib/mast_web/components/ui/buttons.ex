defmodule MastWeb.Components.UI.Buttons do
  @moduledoc """
  Button components. See `MastWeb.Components.UI` for the full design-system
  entrypoint.
  """
  use Phoenix.Component

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
end

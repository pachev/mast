defmodule MastWeb.Components.UI.Forms do
  @moduledoc """
  Form widgets. For full Phoenix form inputs use `MastWeb.CoreComponents.input/1`.
  """
  use Phoenix.Component

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
end

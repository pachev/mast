defmodule MastWeb.Components.UI.JS do
  @moduledoc """
  JS command helpers for show/hide transitions used by the design system.
  """
  alias Phoenix.LiveView.JS

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

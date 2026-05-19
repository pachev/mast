defmodule MastWeb.ServerLive.LogsTab do
  @moduledoc """
  Logs tab for `MastWeb.ServerLive`: streaming run log.
  """
  use MastWeb, :html

  attr :streams, :map, required: true
  attr :log_count, :integer, required: true
  attr :running?, :boolean, required: true

  def render(assigns) do
    ~H"""
    <.ui_card padded={false}>
      <:header>
        <div class="flex items-center justify-between gap-3 w-full">
          <div class="flex items-center gap-3">
            <h2 class="text-base font-semibold text-[var(--mast-font-primary)]">Run Log</h2>
            <.ui_badge :if={@running?} variant="warning">running</.ui_badge>
          </div>
          <.ui_button
            variant="ghost"
            size="sm"
            phx-click="clear_log"
            disabled={@log_count == 0}
          >
            Clear
          </.ui_button>
        </div>
      </:header>

      <div class="bg-[var(--mast-bg-input)] mast-scroll max-h-[32rem] overflow-y-auto">
        <div
          :if={@log_count == 0}
          class="px-4 py-12 text-center text-xs text-[var(--mast-font-tertiary)] italic"
        >
          idle — output will appear here when an upgrade runs
        </div>
        <div id="full-log" phx-update="stream" class="py-2">
          <div :for={{dom_id, line} <- @streams.log} id={dom_id}>
            <.ui_log_entry kind={line.kind}>{line.data}</.ui_log_entry>
          </div>
        </div>
      </div>
    </.ui_card>
    """
  end
end

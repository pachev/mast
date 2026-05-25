defmodule MastWeb.Components.UI.RunLog do
  @moduledoc """
  Streaming run-log modal for apply-updates jobs. Renders the chrome (status
  badge, scrollable mono log region, footer) and takes the log entries as its
  inner block so the LiveView owns the stream. See the `Modal/LogStream`
  family in `components.pen`.
  """
  use Phoenix.Component

  import MastWeb.Components.UI.Buttons
  import MastWeb.Components.UI.Feedback

  @doc """
  Centered modal that streams a command's output.

      <.ui_run_log_modal
        id="apply-log"
        title="Applying Updates — web-1"
        status={@run_status}
        empty?={@log_count == 0}
        on_close={JS.push("close-run-log")}
      >
        <div id="apply-log-lines" phx-update="stream">
          <.ui_log_entry :for={{dom_id, e} <- @streams.log} id={dom_id} kind={e.kind}>
            {e.data}
          </.ui_log_entry>
        </div>
      </.ui_run_log_modal>

  `status` is `:running | :done | :error`. The footer button reads "Close"
  while running or on error, "Done" on success; both fire `on_close`.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :status, :atom, default: :running, values: [:running, :done, :error]
  attr :empty?, :boolean, default: false
  attr :on_close, Phoenix.LiveView.JS, default: %Phoenix.LiveView.JS{}
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def ui_run_log_modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
      phx-window-keydown={@on_close}
      phx-key="escape"
    >
      <div
        class={[
          "w-full max-w-2xl max-h-[85vh] bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
          "rounded-[var(--radius-box)] shadow-xl overflow-hidden flex flex-col",
          @class
        ]}
        phx-click-away={@on_close}
      >
        <header class="flex items-start justify-between gap-4 px-5 pt-5 pb-3 shrink-0">
          <div class="min-w-0 flex items-center gap-3 flex-wrap">
            <h2 class="text-base font-semibold text-[var(--mast-font-primary)] leading-tight min-w-0 truncate">
              {@title}
            </h2>
            <.status_badge status={@status} />
          </div>
          <button
            type="button"
            phx-click={@on_close}
            class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)] -mt-1 -mr-1 p-1 min-w-0"
            aria-label="Close"
          >
            <span class="hero-x-mark size-4" />
          </button>
        </header>

        <div class="px-5 pb-3 flex-1 min-h-0 flex flex-col">
          <div
            id={"#{@id}-scroll"}
            phx-hook="RunLogAutoScroll"
            class="bg-[var(--mast-bg-input)] border border-[var(--mast-border)] rounded-[var(--radius-md)] flex-1 min-h-0 overflow-y-auto py-2"
          >
            <div
              :if={@empty?}
              class="px-4 py-6 text-center text-[13px] text-[var(--mast-font-tertiary)]"
            >
              Waiting for output…
            </div>
            {render_slot(@inner_block)}
          </div>
        </div>

        <footer class="flex items-center justify-end gap-2 px-5 py-3 border-t border-[var(--mast-border)] bg-[var(--mast-bg-secondary)] shrink-0">
          <.ui_button variant="secondary" size="sm" phx-click={@on_close}>
            {if @status == :done, do: "Done", else: "Close"}
          </.ui_button>
        </footer>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".RunLogAutoScroll">
      export default {
        mounted() {
          this.scrollToBottom()
        },
        updated() {
          // Only stick to the bottom if the user hasn't scrolled up.
          if (this.pinned()) this.scrollToBottom()
        },
        pinned() {
          const el = this.el
          return el.scrollHeight - el.scrollTop - el.clientHeight < 40
        },
        scrollToBottom() {
          this.el.scrollTop = this.el.scrollHeight
        }
      }
    </script>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(%{status: :done} = assigns) do
    ~H"""
    <.ui_badge variant="online" size="sm">Completed</.ui_badge>
    """
  end

  defp status_badge(%{status: :error} = assigns) do
    ~H"""
    <.ui_badge variant="offline" size="sm">Failed</.ui_badge>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <.ui_badge variant="warning" size="sm">
      <span class="size-1.5 rounded-full bg-[var(--mast-status-warning)] animate-pulse" /> Running
    </.ui_badge>
    """
  end
end

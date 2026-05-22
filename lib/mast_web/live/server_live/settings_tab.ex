defmodule MastWeb.ServerLive.SettingsTab do
  @moduledoc """
  Settings tab for `MastWeb.ServerLive`: connection info, danger-zone
  remove flow. Release-level config (release_command, log_source, log_target)
  lives on `MastWeb.ReleaseLive` since ADR 0008.
  """
  use MastWeb, :html

  attr :server, :map, required: true
  attr :confirm_delete?, :boolean, required: true
  attr :confirm_name, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <.ui_card>
        <:title>Connection</:title>
        <:subtitle>SSH details for this host</:subtitle>

        <dl class="grid grid-cols-2 gap-y-3 text-sm">
          <dt class="text-[var(--mast-font-secondary)]">Host</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">{@server.host}</dd>
          <dt class="text-[var(--mast-font-secondary)]">User</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">{@server.user}</dd>
          <dt class="text-[var(--mast-font-secondary)]">Port</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">{@server.port}</dd>
          <dt class="text-[var(--mast-font-secondary)]">OS</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">{@server.os_id || "—"}</dd>
          <dt class="text-[var(--mast-font-secondary)]">Package manager</dt>
          <dd class="font-mono text-[var(--mast-font-primary)]">
            {@server.package_manager || "—"}
          </dd>
        </dl>
      </.ui_card>

      <div class="rounded-[var(--radius-box)] border border-[var(--mast-status-offline)] bg-[var(--mast-bg-card)] p-6">
        <div class="flex items-center justify-between gap-4 flex-wrap">
          <div class="min-w-0">
            <h3 class="text-base font-semibold text-[var(--mast-status-offline)]">Danger zone</h3>
            <p class="text-xs text-[var(--mast-font-secondary)] mt-1">
              Removing this server will delete all associated data, including update history, audit logs, and app monitoring configuration. This action cannot be undone.
            </p>
          </div>
          <.ui_button
            variant="destructive"
            size="sm"
            icon="hero-trash"
            phx-click="open-delete-confirm"
          >
            Remove Server
          </.ui_button>
        </div>
      </div>

      <.ui_modal :if={@confirm_delete?} id="confirm-delete" on_cancel={JS.push("cancel-delete")}>
        <:title>Remove {@server.name}?</:title>
        <:subtitle>
          This permanently deletes the server and all of its history. Type the server name to confirm.
        </:subtitle>

        <.form
          for={%{}}
          as={:confirm}
          id="confirm-delete-form"
          phx-change="validate-delete"
          phx-submit="delete-server"
          class="space-y-3"
        >
          <input
            type="text"
            name="confirm[name]"
            value={@confirm_name}
            autocomplete="off"
            placeholder={@server.name}
            class="w-full font-mono text-sm bg-[var(--mast-bg-input)] border border-[var(--mast-border)] rounded-[var(--radius-field)] px-3 py-2 text-[var(--mast-font-primary)] focus:outline-none focus:border-[var(--mast-accent)]"
          />

          <div class="flex items-center justify-end gap-2 pt-1">
            <.ui_button type="button" variant="secondary" phx-click="cancel-delete">
              Cancel
            </.ui_button>
            <.ui_button type="submit" variant="destructive" disabled={@confirm_name != @server.name}>
              Remove Server
            </.ui_button>
          </div>
        </.form>
      </.ui_modal>
    </div>
    """
  end
end

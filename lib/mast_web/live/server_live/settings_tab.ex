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
  attr :projects, :list, required: true
  attr :project_form, :any, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <.ui_kv_table title="Connection">
        <:row label="Host">{@server.host}</:row>
        <:row label="User">{@server.user}</:row>
        <:row label="Port">{@server.port}</:row>
        <:row label="OS">{@server.os_id || "—"}</:row>
        <:row label="Package manager">{@server.package_manager || "—"}</:row>
      </.ui_kv_table>

      <div class="rounded-[var(--radius-box)] border border-[var(--mast-border)] bg-[var(--mast-bg-card)] p-5 sm:p-6">
        <div class="flex items-start justify-between gap-4 flex-wrap mb-4">
          <div class="min-w-0">
            <h3 class="text-base font-semibold text-[var(--mast-font-primary)]">Project</h3>
            <p class="text-xs text-[var(--mast-font-secondary)] mt-1">
              Group this server with others under a Project. Reassignment is recorded as an audit event.
            </p>
          </div>
        </div>

        <.form
          for={@project_form}
          id="server-project-form"
          phx-submit="update-project"
          class="space-y-4"
        >
          <.input
            field={@project_form[:project_id]}
            type="select"
            label="Project"
            prompt="— none —"
            options={Enum.map(@projects, &{&1.name, &1.id})}
          />
          <div class="flex justify-end">
            <.ui_button type="submit" form="server-project-form">Save</.ui_button>
          </div>
        </.form>
      </div>

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

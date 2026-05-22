defmodule MastWeb.ServerLive.ReleasesTab do
  @moduledoc """
  Releases tab for `MastWeb.ServerLive`. Lists configured Releases on
  this Server with effective handle, release_command, log_source, and
  links to ReleaseLive. Supports add and remove.
  """
  use MastWeb, :html

  alias Mast.Fleet.Release

  attr :server, :map, required: true
  attr :releases, :list, required: true
  attr :new_release_changeset, :map, default: nil

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-start gap-3">
        <span class="hero-cube size-6 text-[var(--mast-chart-purple)] shrink-0 mt-1" />
        <div class="flex-1 min-w-0">
          <h2 class="text-lg font-bold text-[var(--mast-font-primary)] leading-tight">
            Releases
          </h2>
          <p class="text-[13px] text-[var(--mast-font-secondary)] mt-0.5">
            {summary(@releases)}
          </p>
        </div>
        <.ui_button
          icon="hero-plus"
          size="sm"
          phx-click="open-add-release"
        >
          Add Release
        </.ui_button>
      </div>

      <.ui_card :if={@releases == []} padded={false}>
        <.ui_empty
          icon="hero-cube"
          title="No Releases configured"
          body="Click Add Release to configure one. Releases can be probed via release_command, watched via Log Source, or both."
        />
      </.ui_card>

      <ul :if={@releases != []} class="space-y-2">
        <li
          :for={release <- @releases}
          class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] p-4"
        >
          <div class="flex items-center gap-4">
            <div class="flex-1 min-w-0">
              <.link
                navigate={~p"/servers/#{@server.id}/releases/#{Release.effective_handle(release)}"}
                class="block"
              >
                <div class="font-mono text-[14px] font-semibold text-[var(--mast-font-primary)]">
                  {Release.effective_handle(release)}
                </div>
                <div class="font-mono text-[12px] text-[var(--mast-font-secondary)] truncate">
                  {release.release_command || "(no release_command)"}
                </div>
              </.link>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <.ui_badge variant={log_badge(release.log_source)} size="sm">
                {log_label(release)}
              </.ui_badge>
              <button
                type="button"
                phx-click="delete-release"
                phx-value-id={release.id}
                data-confirm={"Remove Release '#{Release.effective_handle(release)}' from #{@server.name}?"}
                class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-status-offline)]"
                title="Remove"
              >
                <span class="hero-trash size-4" />
              </button>
            </div>
          </div>
        </li>
      </ul>

      <.ui_modal
        :if={@new_release_changeset}
        id="add-release-modal"
        on_cancel={JS.push("cancel-add-release")}
      >
        <:title>Add Release</:title>
        <.form
          :let={f}
          for={@new_release_changeset}
          as={:release}
          phx-submit="create-release"
          phx-change="validate-new-release"
          class="space-y-4"
        >
          <div>
            <label class="block text-[13px] font-medium text-[var(--mast-font-primary)] mb-1">
              Name (optional)
            </label>
            <input
              type="text"
              name={f[:name].name}
              value={Phoenix.HTML.Form.normalize_value("text", f[:name].value)}
              placeholder="leave blank to derive from release_command"
              class="w-full px-3 py-2 rounded-[var(--radius-field)] bg-[var(--mast-bg-input)] border border-[var(--mast-border)] font-mono text-[13px]"
            />
            <.changeset_error field={f[:name]} />
          </div>

          <div>
            <label class="block text-[13px] font-medium text-[var(--mast-font-primary)] mb-1">
              Release Command (optional)
            </label>
            <input
              type="text"
              name={f[:release_command].name}
              value={Phoenix.HTML.Form.normalize_value("text", f[:release_command].value)}
              placeholder="/opt/myapp/current/bin/myapp"
              class="w-full px-3 py-2 rounded-[var(--radius-field)] bg-[var(--mast-bg-input)] border border-[var(--mast-border)] font-mono text-[13px]"
            />
            <.changeset_error field={f[:release_command]} />
          </div>

          <div>
            <label class="block text-[13px] font-medium text-[var(--mast-font-primary)] mb-1">
              Log Source
            </label>
            <select
              name={f[:log_source].name}
              class="w-full px-3 py-2 rounded-[var(--radius-field)] bg-[var(--mast-bg-input)] border border-[var(--mast-border)] text-[13px]"
            >
              <option value="none" selected={f[:log_source].value in [nil, "none"]}>None</option>
              <option value="systemd" selected={f[:log_source].value == "systemd"}>systemd</option>
              <option value="file" selected={f[:log_source].value == "file"}>file</option>
            </select>
          </div>

          <div>
            <label class="block text-[13px] font-medium text-[var(--mast-font-primary)] mb-1">
              Log Target
            </label>
            <input
              type="text"
              name={f[:log_target].name}
              value={Phoenix.HTML.Form.normalize_value("text", f[:log_target].value)}
              placeholder="systemd unit name or absolute file path"
              class="w-full px-3 py-2 rounded-[var(--radius-field)] bg-[var(--mast-bg-input)] border border-[var(--mast-border)] font-mono text-[13px]"
            />
            <.changeset_error field={f[:log_target]} />
          </div>

          <div class="flex items-center justify-end gap-2 pt-2">
            <.ui_button variant="secondary" type="button" phx-click="cancel-add-release">
              Cancel
            </.ui_button>
            <.ui_button type="submit" icon="hero-check">Add Release</.ui_button>
          </div>
        </.form>
      </.ui_modal>
    </div>
    """
  end

  attr :field, :map, required: true

  defp changeset_error(assigns) do
    ~H"""
    <p :for={msg <- errs(@field)} class="mt-1 text-[12px] text-[var(--mast-status-offline)]">
      {msg}
    </p>
    """
  end

  defp errs(%{errors: errors}) when is_list(errors) do
    Enum.map(errors, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end

  defp errs(_), do: []

  defp summary([]), do: "no Releases configured"
  defp summary([_]), do: "1 Release configured"
  defp summary(list), do: "#{length(list)} Releases configured"

  defp log_badge("none"), do: "neutral"
  defp log_badge(_), do: "online"

  defp log_label(%Release{log_source: "none"}), do: "no log source"
  defp log_label(%Release{log_source: source, log_target: target}), do: "#{source}: #{target}"
end

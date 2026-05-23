defmodule MastWeb.SettingsLive.ProjectsTab do
  @moduledoc """
  Projects tab on the Settings page. List, inline-create, edit (rename +
  recolor), and delete Projects. Mirrors the SSH Keys tab pattern.

  Pure render module; event handlers live on `MastWeb.SettingsLive`.
  """
  use MastWeb, :html

  alias Mast.Fleet.Project

  attr :projects, :list, required: true
  attr :server_counts, :map, required: true
  attr :show_new_project, :boolean, required: true
  attr :project_form, :any, required: true
  attr :editing_project_id, :any, required: true
  attr :edit_project_form, :any, required: true

  def projects_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center gap-3 flex-wrap">
        <h2 class="text-base font-semibold text-[var(--mast-font-primary)]">Projects</h2>
        <span class="text-[13px] text-[var(--mast-font-tertiary)]">
          {length(@projects)} {if length(@projects) == 1, do: "project", else: "projects"}
        </span>
        <span class="flex-1" />
        <.ui_button icon="hero-plus" size="sm" phx-click="toggle-new-project">
          {if @show_new_project, do: "Cancel", else: "Add Project"}
        </.ui_button>
      </div>

      <div
        :if={@show_new_project}
        class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] p-4 sm:p-5"
      >
        <.form
          for={@project_form}
          id="new-project-form"
          phx-change="validate-project"
          phx-submit="save-project"
          class="space-y-3"
        >
          <.input
            field={@project_form[:name]}
            label="Project name"
            placeholder="blog"
            required
          />
          <.input
            field={@project_form[:description]}
            label="Description (optional)"
            placeholder="Customer-facing blog stack"
          />
          <.color_picker field={@project_form[:color]} />
          <div class="flex justify-end gap-2 pt-1">
            <.ui_button type="button" variant="secondary" phx-click="toggle-new-project">
              Cancel
            </.ui_button>
            <.ui_button type="submit" form="new-project-form">Save project</.ui_button>
          </div>
        </.form>
      </div>

      <%= if @projects == [] do %>
        <div class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] overflow-hidden">
          <.ui_empty
            icon="hero-folder"
            title="No projects yet"
            body="Group related servers into a Project to organize the Fleet view."
          />
        </div>
      <% else %>
        <ul
          id="projects-list"
          class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] divide-y divide-[var(--mast-border)] overflow-hidden"
        >
          <li :for={p <- @projects} class="px-3 sm:px-4 py-3">
            <%= if @editing_project_id == p.id do %>
              <.form
                for={@edit_project_form}
                id={"edit-project-form-#{p.id}"}
                phx-change="validate-edit-project"
                phx-submit="update-project"
                class="space-y-3"
              >
                <.input field={@edit_project_form[:name]} label="Name" required />
                <.input field={@edit_project_form[:description]} label="Description" />
                <.color_picker field={@edit_project_form[:color]} />
                <div class="flex justify-end gap-2">
                  <.ui_button
                    type="button"
                    variant="secondary"
                    size="sm"
                    phx-click="cancel-edit-project"
                  >
                    Cancel
                  </.ui_button>
                  <.ui_button type="submit" size="sm" form={"edit-project-form-#{p.id}"}>
                    Save
                  </.ui_button>
                </div>
              </.form>
            <% else %>
              <div class="flex items-center gap-3 flex-wrap">
                <span
                  class={["inline-block size-3 rounded-full shrink-0", color_swatch(p.color)]}
                  aria-hidden="true"
                />
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="font-mono text-sm font-medium text-[var(--mast-font-primary)] truncate">
                      {p.name}
                    </span>
                    <span class="text-xs text-[var(--mast-font-tertiary)] tabular-nums">
                      {server_count_label(@server_counts, p.id)}
                    </span>
                  </div>
                  <p
                    :if={p.description not in [nil, ""]}
                    class="text-xs text-[var(--mast-font-secondary)] mt-0.5 truncate"
                  >
                    {p.description}
                  </p>
                </div>
                <div class="flex items-center gap-1 shrink-0">
                  <button
                    type="button"
                    phx-click="edit-project"
                    phx-value-id={p.id}
                    class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)] p-2 -m-1"
                    aria-label={"Edit project #{p.name}"}
                  >
                    <span class="hero-pencil-square size-4" />
                  </button>
                  <button
                    type="button"
                    phx-click="delete-project"
                    phx-value-id={p.id}
                    data-confirm={"Delete project #{p.name}? Servers will be unassigned but kept."}
                    class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-status-offline)] p-2 -m-1"
                    aria-label={"Delete project #{p.name}"}
                  >
                    <span class="hero-trash size-4" />
                  </button>
                </div>
              </div>
            <% end %>
          </li>
        </ul>
      <% end %>

      <div class="flex items-start gap-3 px-4 py-3 bg-[var(--mast-bg-secondary)] rounded-[var(--radius-field)] text-[13px] text-[var(--mast-font-secondary)]">
        <span class="hero-information-circle size-4 shrink-0 mt-0.5" />
        <p class="leading-relaxed">
          Projects are an organizational lens over the Fleet. Deleting a Project leaves its Servers in place; they go back to being ungrouped.
        </p>
      </div>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp color_picker(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-[var(--mast-font-primary)] mb-1.5">
        Color (optional)
      </label>
      <div class="flex items-center gap-2 flex-wrap">
        <label class="inline-flex items-center cursor-pointer">
          <input
            type="radio"
            name={@field.name}
            value=""
            checked={@field.value in [nil, ""]}
            class="sr-only peer"
          />
          <span
            class="inline-flex size-7 items-center justify-center rounded-full border border-[var(--mast-border)] text-[var(--mast-font-tertiary)] peer-checked:ring-2 peer-checked:ring-[var(--mast-accent)] peer-checked:ring-offset-2 peer-checked:ring-offset-[var(--mast-bg-card)]"
            aria-label="No color"
          >
            <span class="hero-no-symbol size-3.5" />
          </span>
        </label>

        <label :for={c <- Project.colors()} class="inline-flex items-center cursor-pointer">
          <input
            type="radio"
            name={@field.name}
            value={c}
            checked={to_string(@field.value) == c}
            class="sr-only peer"
          />
          <span
            class={[
              "inline-block size-7 rounded-full border border-[var(--mast-border)]",
              "peer-checked:ring-2 peer-checked:ring-[var(--mast-accent)] peer-checked:ring-offset-2 peer-checked:ring-offset-[var(--mast-bg-card)]",
              color_swatch(c)
            ]}
            aria-label={c}
          />
        </label>
      </div>
      <p
        :for={msg <- field_errors(@field)}
        class="text-xs text-[var(--mast-status-offline)] mt-1"
      >
        {msg}
      </p>
    </div>
    """
  end

  defp field_errors(%Phoenix.HTML.FormField{errors: errors}) do
    Enum.map(errors, fn {msg, _opts} -> msg end)
  end

  @doc "Tailwind background class for a Project color preset."
  def color_swatch(nil), do: "bg-[var(--mast-bg-secondary)]"
  def color_swatch(""), do: "bg-[var(--mast-bg-secondary)]"
  def color_swatch("slate"), do: "bg-slate-500"
  def color_swatch("indigo"), do: "bg-indigo-500"
  def color_swatch("emerald"), do: "bg-emerald-500"
  def color_swatch("amber"), do: "bg-amber-500"
  def color_swatch("rose"), do: "bg-rose-500"
  def color_swatch("violet"), do: "bg-violet-500"
  def color_swatch(_), do: "bg-[var(--mast-bg-secondary)]"

  defp server_count_label(counts, project_id) do
    n = Map.get(counts, project_id, 0)
    "#{n} #{if n == 1, do: "server", else: "servers"}"
  end
end

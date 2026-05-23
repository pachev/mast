defmodule MastWeb.SettingsLive do
  @moduledoc """
  App-level settings page. Currently exposes two tabs:

  - `general` — placeholder for future preferences (theme defaults,
    notification routes).
  - `keys` — SSH key management: list, add, delete keys. Mirrors the
    pencil design (frame "Settings").

  Key creation reuses the inline form pattern from the Add Server modal.
  """
  use MastWeb, :live_view

  import MastWeb.SettingsLive.ProjectsTab, only: [projects_tab: 1]

  alias Mast.Fleet.Project
  alias Mast.Fleet.Projects
  alias Mast.Keys
  alias Mast.Keys.PrivateKey

  @tabs ~w(general keys projects)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:tab, "general")
     |> assign(:show_new_key, false)
     |> assign(:key_form, nil)
     |> assign(:show_new_project, false)
     |> assign(:project_form, nil)
     |> assign(:editing_project_id, nil)
     |> assign(:edit_project_form, nil)
     |> load_keys()
     |> load_projects()}
  end

  defp load_keys(socket) do
    socket
    |> assign(:keys, Keys.list_keys())
    |> assign(:server_counts, Keys.server_counts())
  end

  defp load_projects(socket) do
    socket
    |> assign(:projects, Projects.list_projects())
    |> assign(:project_server_counts, Projects.server_counts())
  end

  @impl true
  def handle_params(%{"tab" => tab}, _url, socket) when tab in @tabs do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :tab, "general")}
  end

  @impl true
  def handle_event("toggle-new-key", _, socket) do
    show? = not socket.assigns.show_new_key

    key_form =
      if show? do
        to_form(PrivateKey.changeset(%PrivateKey{}, %{}), as: :key)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:show_new_key, show?)
     |> assign(:key_form, key_form)}
  end

  def handle_event("validate-key", %{"key" => params}, socket) do
    cs =
      %PrivateKey{}
      |> PrivateKey.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :key_form, to_form(cs, as: :key))}
  end

  def handle_event("save-key", %{"key" => params}, socket) do
    case Keys.create_key(params) do
      {:ok, _key} ->
        {:noreply,
         socket
         |> assign(:show_new_key, false)
         |> assign(:key_form, nil)
         |> put_flash(:info, "Key added.")
         |> load_keys()}

      {:error, cs} ->
        {:noreply, assign(socket, :key_form, to_form(cs, as: :key))}
    end
  end

  def handle_event("delete-key", %{"id" => id}, socket) do
    key = Keys.get_key!(id)

    case Keys.delete_key(key) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Key #{key.name} removed.")
         |> load_keys()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove key (in use?).")}
    end
  end

  # --- Project events ------------------------------------------------------

  def handle_event("toggle-new-project", _, socket) do
    show? = not socket.assigns.show_new_project

    project_form =
      if show? do
        to_form(Projects.change_project(%Project{}), as: :project)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:show_new_project, show?)
     |> assign(:project_form, project_form)}
  end

  def handle_event("validate-project", %{"project" => params}, socket) do
    cs =
      %Project{}
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :project_form, to_form(cs, as: :project))}
  end

  def handle_event("save-project", %{"project" => params}, socket) do
    case Projects.create_project(params) do
      {:ok, _p} ->
        {:noreply,
         socket
         |> assign(:show_new_project, false)
         |> assign(:project_form, nil)
         |> put_flash(:info, "Project added.")
         |> load_projects()}

      {:error, cs} ->
        {:noreply, assign(socket, :project_form, to_form(cs, as: :project))}
    end
  end

  def handle_event("edit-project", %{"id" => id}, socket) do
    project = Projects.get_project!(id)

    {:noreply,
     socket
     |> assign(:editing_project_id, project.id)
     |> assign(:edit_project_form, to_form(Projects.change_project(project), as: :project))}
  end

  def handle_event("cancel-edit-project", _, socket) do
    {:noreply,
     socket
     |> assign(:editing_project_id, nil)
     |> assign(:edit_project_form, nil)}
  end

  def handle_event("validate-edit-project", %{"project" => params}, socket) do
    project = Projects.get_project!(socket.assigns.editing_project_id)

    cs =
      project
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :edit_project_form, to_form(cs, as: :project))}
  end

  def handle_event("update-project", %{"project" => params}, socket) do
    project = Projects.get_project!(socket.assigns.editing_project_id)

    case Projects.update_project(project, params) do
      {:ok, _p} ->
        {:noreply,
         socket
         |> assign(:editing_project_id, nil)
         |> assign(:edit_project_form, nil)
         |> put_flash(:info, "Project updated.")
         |> load_projects()}

      {:error, cs} ->
        {:noreply, assign(socket, :edit_project_form, to_form(cs, as: :project))}
    end
  end

  def handle_event("delete-project", %{"id" => id}, socket) do
    project = Projects.get_project!(id)

    case Projects.delete_project(project) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project #{project.name} removed.")
         |> load_projects()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove project.")}
    end
  end

  # --- Render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="settings" page_title={@page_title}>
      <header class="-mx-6 lg:-mx-10 -mt-6 lg:-mt-8 mb-6 px-6 lg:px-10 pt-4 pb-0 border-b border-[var(--mast-border)]">
        <div class="flex items-start gap-3">
          <span class="hero-cog-6-tooth size-6 text-[var(--mast-font-primary)] shrink-0 mt-1" />
          <div>
            <h1 class="text-[22px] font-bold text-[var(--mast-font-primary)] leading-none">
              Settings
            </h1>
            <p class="text-[13px] text-[var(--mast-font-secondary)] mt-1">
              Manage your Mast configuration
            </p>
          </div>
        </div>

        <.ui_tabs active={@tab} class="mt-4 border-b-0">
          <:tab key="general" patch={~p"/settings?tab=general"}>General</:tab>
          <:tab key="keys" patch={~p"/settings?tab=keys"}>SSH Keys</:tab>
          <:tab key="projects" patch={~p"/settings?tab=projects"}>Projects</:tab>
        </.ui_tabs>
      </header>

      <%= case @tab do %>
        <% "keys" -> %>
          <.keys_tab
            keys={@keys}
            server_counts={@server_counts}
            show_new_key={@show_new_key}
            key_form={@key_form}
          />
        <% "projects" -> %>
          <.projects_tab
            projects={@projects}
            server_counts={@project_server_counts}
            show_new_project={@show_new_project}
            project_form={@project_form}
            editing_project_id={@editing_project_id}
            edit_project_form={@edit_project_form}
          />
        <% _ -> %>
          <.ui_card padded={false}>
            <.ui_empty
              icon="hero-cog-6-tooth"
              title="General settings coming soon"
              body="Notification routes and theme defaults will live here."
            />
          </.ui_card>
      <% end %>
    </Layouts.app>
    """
  end

  attr :keys, :list, required: true
  attr :server_counts, :map, required: true
  attr :show_new_key, :boolean, required: true
  attr :key_form, :any, required: true

  defp keys_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center gap-3">
        <h2 class="text-base font-semibold text-[var(--mast-font-primary)]">SSH Keys</h2>
        <span class="text-[13px] text-[var(--mast-font-tertiary)]">
          {length(@keys)} {if length(@keys) == 1, do: "key", else: "keys"}
        </span>
        <span class="flex-1" />
        <.ui_button icon="hero-plus" size="sm" phx-click="toggle-new-key">
          {if @show_new_key, do: "Cancel", else: "Add Key"}
        </.ui_button>
      </div>

      <div
        :if={@show_new_key}
        class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] p-5"
      >
        <.form
          for={@key_form}
          id="new-key-form"
          phx-change="validate-key"
          phx-submit="save-key"
          class="space-y-3"
        >
          <.input field={@key_form[:name]} label="Key name" placeholder="prod ed25519" required />
          <.input
            field={@key_form[:body]}
            type="textarea"
            label="PEM body"
            placeholder="-----BEGIN OPENSSH PRIVATE KEY-----"
            rows="6"
            required
          />
          <div class="flex justify-end gap-2 pt-1">
            <.ui_button type="button" variant="secondary" phx-click="toggle-new-key">
              Cancel
            </.ui_button>
            <.ui_button type="submit" form="new-key-form">Save key</.ui_button>
          </div>
        </.form>
      </div>

      <%= if @keys == [] do %>
        <div class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] overflow-hidden">
          <.ui_empty
            icon="hero-key"
            title="No SSH keys yet"
            body="Add an Ed25519 or RSA private key to connect to your servers."
          />
        </div>
      <% else %>
        <.ui_table id="ssh-keys" rows={@keys} size="sm">
          <:col :let={k} label="Name">
            <span class="inline-flex items-center gap-2 font-mono font-medium text-[var(--mast-font-primary)]">
              <span class="hero-key size-4 text-[var(--mast-font-tertiary)]" />
              {k.name}
            </span>
          </:col>
          <:col :let={k} label="Type">
            <.ui_badge variant={algo_variant(k.algorithm)} dot={false}>
              {k.algorithm || "—"}
            </.ui_badge>
          </:col>
          <:col
            :let={k}
            label="Fingerprint"
            class="font-mono text-xs text-[var(--mast-font-secondary)]"
          >
            {short_fp(k.fingerprint)}
          </:col>
          <:col
            :let={k}
            label="Servers"
            class="font-mono text-[var(--mast-font-primary)] tabular-nums"
          >
            {server_count_label(@server_counts, k.id)}
          </:col>
          <:col :let={k} label="Created" class="text-xs text-[var(--mast-font-secondary)]">
            {format_date(k.inserted_at)}
          </:col>
          <:col :let={k} align="right">
            <button
              type="button"
              phx-click="delete-key"
              phx-value-id={k.id}
              data-confirm={"Delete key #{k.name}? Servers using it will lose their key reference."}
              class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-status-offline)] p-1"
              aria-label="Delete key"
            >
              <span class="hero-trash size-4" />
            </button>
          </:col>
        </.ui_table>
      <% end %>

      <div class="flex items-start gap-3 px-4 py-3 bg-[var(--mast-bg-secondary)] rounded-[var(--radius-field)] text-[13px] text-[var(--mast-font-secondary)]">
        <span class="hero-information-circle size-4 shrink-0 mt-0.5" />
        <p class="leading-relaxed">
          SSH keys are encrypted at rest using Cloak. Private key material is only decrypted in memory when connecting to a server. Mast supports Ed25519 and RSA keys.
        </p>
      </div>
    </div>
    """
  end

  defp algo_variant("ed25519"), do: "online"
  defp algo_variant("rsa"), do: "warning"
  defp algo_variant(_), do: "neutral"

  defp short_fp(nil), do: "—"

  defp short_fp(fp) when is_binary(fp) do
    if String.length(fp) > 40, do: String.slice(fp, 0, 40) <> "…", else: fp
  end

  defp server_count_label(counts, key_id) do
    n = Map.get(counts, key_id, 0)
    "#{n} #{if n == 1, do: "server", else: "servers"}"
  end

  defp format_date(nil), do: "—"

  defp format_date(%DateTime{} = t) do
    Calendar.strftime(t, "%b %-d, %Y")
  end
end

defmodule MastWeb.DashboardLive do
  use MastWeb, :live_view

  alias Mast.Fleet
  alias Mast.Fleet.{Project, Projects, Server}
  alias Mast.Keys
  alias Mast.Keys.PrivateKey
  alias Mast.Workers.ConnectionCheck

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Mast.PubSub, "servers")

    servers = Fleet.list_servers()

    {:ok,
     socket
     |> assign(:page_title, "Fleet")
     |> assign(:filter, "")
     |> assign(:servers, servers)
     |> assign(:keys, [])
     |> assign(:projects, Projects.list_projects())
     |> assign(:collapsed_groups, MapSet.new())
     |> assign(:form, nil)
     |> assign(:key_form, nil)
     |> assign(:show_new_key, false)
     |> assign(:project_form, nil)
     |> assign(:show_new_project, false)}
  end

  @impl true
  def handle_info({:server_updated, server}, socket) do
    servers =
      Enum.map(socket.assigns.servers, fn s ->
        if s.id == server.id, do: server, else: s
      end)

    {:noreply, assign(socket, :servers, servers)}
  end

  def handle_info({:server_deleted, id}, socket) do
    servers = Enum.reject(socket.assigns.servers, &(&1.id == id))
    {:noreply, assign(socket, :servers, servers)}
  end

  # The "servers" topic also carries per-server scan/probe/run events meant for
  # MastWeb.ServerLive. Ignore them here rather than crashing the dashboard.
  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:form, nil)
    |> assign(:show_new_key, false)
    |> assign(:key_form, nil)
    |> assign(:show_new_project, false)
    |> assign(:project_form, nil)
  end

  defp apply_action(socket, :new, _params) do
    cs = Fleet.change_server(%Server{user: "ubuntu", port: 22})

    socket
    |> assign(:form, to_form(cs, as: :server))
    |> assign(:keys, Keys.list_keys())
    |> assign(:projects, Projects.list_projects())
    |> assign(:show_new_key, false)
    |> assign(:key_form, nil)
    |> assign(:show_new_project, false)
    |> assign(:project_form, nil)
  end

  @impl true
  def handle_event("validate", %{"server" => params}, socket) do
    cs =
      %Server{}
      |> Fleet.change_server(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs, as: :server))}
  end

  def handle_event("save", %{"server" => params}, socket) do
    case Fleet.create_server(params) do
      {:ok, server} ->
        # Run a connection check now instead of waiting up to a minute for
        # the next cron tick. The card stays greyed out until we have metrics.
        %{server_id: server.id}
        |> ConnectionCheck.new()
        |> Oban.insert()

        {:noreply,
         socket
         |> assign(:servers, socket.assigns.servers ++ [server])
         |> put_flash(:info, "Added #{server.name}")
         |> push_patch(to: ~p"/")}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: :server))}
    end
  end

  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, :filter, q)}
  end

  def handle_event("toggle-project-group", %{"id" => id}, socket) do
    collapsed =
      if MapSet.member?(socket.assigns.collapsed_groups, id) do
        MapSet.delete(socket.assigns.collapsed_groups, id)
      else
        MapSet.put(socket.assigns.collapsed_groups, id)
      end

    {:noreply, assign(socket, :collapsed_groups, collapsed)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/")}
  end

  def handle_event("toggle_new_key", _, socket) do
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

  def handle_event("validate_key", %{"key" => params}, socket) do
    cs =
      %PrivateKey{}
      |> PrivateKey.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :key_form, to_form(cs, as: :key))}
  end

  def handle_event("save_key", %{"key" => params}, socket) do
    case Keys.create_key(params) do
      {:ok, key} ->
        keys = Keys.list_keys()

        form =
          socket.assigns.form
          |> server_form_with(:private_key_id, key.id)

        {:noreply,
         socket
         |> assign(:keys, keys)
         |> assign(:form, form)
         |> assign(:show_new_key, false)
         |> assign(:key_form, nil)}

      {:error, cs} ->
        {:noreply, assign(socket, :key_form, to_form(cs, as: :key))}
    end
  end

  def handle_event("toggle_new_project", _, socket) do
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

  def handle_event("validate_project", %{"project" => params}, socket) do
    cs =
      %Project{}
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :project_form, to_form(cs, as: :project))}
  end

  def handle_event("save_project", %{"project" => params}, socket) do
    case Projects.create_project(params) do
      {:ok, project} ->
        projects = Projects.list_projects()

        form =
          socket.assigns.form
          |> server_form_with(:project_id, project.id)

        {:noreply,
         socket
         |> assign(:projects, projects)
         |> assign(:form, form)
         |> assign(:show_new_project, false)
         |> assign(:project_form, nil)}

      {:error, cs} ->
        {:noreply, assign(socket, :project_form, to_form(cs, as: :project))}
    end
  end

  # --- Render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    visible = filtered(assigns.servers, assigns.filter)
    stats = fleet_stats(assigns.servers)
    {grouped, ungrouped} = group_by_project(visible, assigns.projects)

    assigns =
      assigns
      |> assign(:visible_servers, visible)
      |> assign(:stats, stats)
      |> assign(:grouped, grouped)
      |> assign(:ungrouped, ungrouped)

    ~H"""
    <Layouts.app flash={@flash} active="dashboard" page_title={@page_title}>
      <.ui_page_header
        title="Fleet Overview"
        subtitle={fleet_subtitle(@stats)}
      >
        <:actions>
          <form phx-change="filter" class="hidden sm:block">
            <.ui_search name="q" value={@filter} placeholder="Search servers..." class="w-64" />
          </form>
          <.ui_button icon="hero-plus" navigate={~p"/servers/new"}>Add Server</.ui_button>
        </:actions>
      </.ui_page_header>

      <section class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <.ui_stat label="Total Servers" value={@stats.total} />
        <.ui_stat label="Online" value={@stats.online} tone="online" />
        <.ui_stat
          label="Updates Available"
          value={@stats.updates}
          tone={if @stats.updates > 0, do: "warning", else: "default"}
        />
        <.ui_stat label="Releases" value={@stats.releases} />
      </section>

      <section class="mb-4">
        <h2 class="text-sm font-semibold text-[var(--mast-font-primary)] mb-3">Servers</h2>

        <div :if={@visible_servers == [] and @servers == []}>
          <.ui_card padded={false}>
            <.ui_empty
              icon="hero-server"
              title="No servers yet"
              body="Register your first server to start monitoring its health and applying updates."
            >
              <.ui_button icon="hero-plus" navigate={~p"/servers/new"}>Add Server</.ui_button>
            </.ui_empty>
          </.ui_card>
        </div>

        <div
          :if={@visible_servers == [] and @servers != []}
          class="text-sm text-[var(--mast-font-secondary)] py-12 text-center"
        >
          No servers match "{@filter}".
        </div>

        <div :if={@visible_servers != []} class="space-y-5">
          <div :for={{project, members} <- @grouped} class="space-y-3">
            <.ui_project_group_header
              name={project.name}
              color={project.color}
              count={length(members)}
              expanded?={not MapSet.member?(@collapsed_groups, project.id)}
              toggle={%{"phx-click" => "toggle-project-group", "phx-value-id" => project.id}}
            />
            <div
              :if={not MapSet.member?(@collapsed_groups, project.id)}
              class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3"
            >
              <.ui_server_card :for={s <- members} server={s} />
            </div>
          </div>

          <div
            :if={@ungrouped != []}
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3"
          >
            <.ui_server_card :for={s <- @ungrouped} server={s} />
          </div>
        </div>
      </section>

      <.ui_modal
        :if={@live_action == :new}
        id="new-server-modal"
        on_cancel={Phoenix.LiveView.JS.patch(~p"/")}
      >
        <:title>Add a server</:title>
        <:subtitle>Register a host to monitor.</:subtitle>

        <.form
          for={@form}
          id="new-server-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-3"
        >
          <.input field={@form[:name]} label="Name" placeholder="web-1" required />
          <.input field={@form[:host]} label="Host" placeholder="10.0.0.7 or fqdn" required />
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <.input field={@form[:user]} label="SSH user" placeholder="ubuntu" />
            <.input field={@form[:port]} type="number" label="Port" placeholder="22" />
          </div>
          <.input
            field={@form[:private_key_id]}
            type="select"
            label="Private key"
            prompt={if @keys == [], do: "No keys registered yet", else: "— none —"}
            options={Enum.map(@keys, &{key_label(&1), &1.id})}
          />

          <button
            type="button"
            phx-click="toggle_new_key"
            class="text-xs text-[var(--mast-accent)] hover:underline"
          >
            {if @show_new_key, do: "Cancel adding new key", else: "Add new key"}
          </button>

          <.input
            field={@form[:project_id]}
            type="select"
            label="Project"
            prompt={if @projects == [], do: "No projects yet", else: "— none —"}
            options={Enum.map(@projects, &{&1.name, &1.id})}
          />

          <button
            type="button"
            phx-click="toggle_new_project"
            class="text-xs text-[var(--mast-accent)] hover:underline"
          >
            {if @show_new_project, do: "Cancel adding new project", else: "Add new project"}
          </button>
        </.form>

        <div :if={@show_new_key} class="mt-3 pt-3 border-t border-[var(--mast-border)]">
          <.form
            for={@key_form}
            id="new-key-form"
            phx-change="validate_key"
            phx-submit="save_key"
            class="space-y-2"
          >
            <div
              :for={msg <- key_form_errors(@key_form)}
              class="text-xs text-[var(--mast-status-error)]"
            >
              {msg}
            </div>
            <.input field={@key_form[:name]} label="Key name" placeholder="prod ed25519" required />
            <.input
              field={@key_form[:body]}
              type="textarea"
              label="PEM body"
              placeholder="-----BEGIN OPENSSH PRIVATE KEY-----"
              rows="6"
              required
            />
            <.ui_button type="submit" form="new-key-form">Save key</.ui_button>
          </.form>
        </div>

        <div :if={@show_new_project} class="mt-3 pt-3 border-t border-[var(--mast-border)]">
          <.form
            for={@project_form}
            id="new-project-form"
            phx-change="validate_project"
            phx-submit="save_project"
            class="space-y-2"
          >
            <.input field={@project_form[:name]} label="Project name" placeholder="blog" required />
            <.input
              field={@project_form[:description]}
              label="Description (optional)"
              placeholder="Customer-facing blog stack"
            />
            <.input
              field={@project_form[:color]}
              type="select"
              label="Color (optional)"
              prompt="— none —"
              options={Enum.map(Project.colors(), &{&1, &1})}
            />
            <.ui_button type="submit" form="new-project-form">Save project</.ui_button>
          </.form>
        </div>

        <:footer>
          <.ui_button variant="secondary" phx-click={Phoenix.LiveView.JS.patch(~p"/")}>
            Cancel
          </.ui_button>
          <.ui_button type="submit" form="new-server-form">Add Server</.ui_button>
        </:footer>
      </.ui_modal>
    </Layouts.app>
    """
  end

  # --- helpers --------------------------------------------------------------

  defp filtered(servers, ""), do: servers

  defp filtered(servers, q) do
    s = String.downcase(q)

    Enum.filter(servers, fn srv ->
      String.contains?(String.downcase(srv.name || ""), s) or
        String.contains?(String.downcase(srv.host || ""), s)
    end)
  end

  defp group_by_project(servers, projects) do
    by_project = Enum.group_by(servers, & &1.project_id)

    grouped =
      projects
      |> Enum.map(fn p -> {p, Map.get(by_project, p.id, [])} end)
      |> Enum.reject(fn {_p, members} -> members == [] end)

    ungrouped = Map.get(by_project, nil, [])
    {grouped, ungrouped}
  end

  defp fleet_stats(servers) do
    %{
      total: length(servers),
      online: Enum.count(servers, &(&1.status == "up")),
      updates: Enum.reduce(servers, 0, fn s, acc -> acc + (s.updates_available || 0) end),
      releases: Fleet.count_all_releases()
    }
  end

  defp fleet_subtitle(%{total: 0}), do: "Register your first server below"

  defp fleet_subtitle(%{total: n, online: online}) do
    "#{n} server#{if n == 1, do: "", else: "s"} · #{online} online"
  end

  defp key_form_errors(form) do
    rendered_fields = [:name, :body]

    form.errors
    |> Enum.reject(fn {field, _} -> field in rendered_fields end)
    |> Enum.map(fn {_field, {msg, _opts}} -> msg end)
  end

  defp server_form_with(form, field, value) do
    params =
      form.params
      |> Map.new()
      |> Map.put(to_string(field), to_string(value))

    %Server{}
    |> Fleet.change_server(params)
    |> to_form(as: :server)
  end

  defp key_label(key) do
    "#{key.name} (#{key.algorithm}, #{String.slice(key.fingerprint, 0, 19)}…)"
  end
end

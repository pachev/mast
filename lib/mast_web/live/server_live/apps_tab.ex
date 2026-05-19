defmodule MastWeb.ServerLive.AppsTab do
  @moduledoc """
  Apps tab for `MastWeb.ServerLive`: your release, dependencies grid.
  """
  use MastWeb, :html

  import MastWeb.ServerLive.Helpers

  attr :server, :map, required: true
  attr :apps, :list, required: true
  attr :show_system_apps?, :boolean, required: true
  attr :probing?, :boolean, required: true
  attr :probe_error, :any, required: true

  def render(assigns) do
    your_release = your_release(assigns.apps, assigns.server)
    deps = Enum.reject(assigns.apps, &(your_release && &1.id == your_release.id))
    last_probe = last_probed_at(assigns.apps)

    assigns =
      assigns
      |> assign(:your_release, your_release)
      |> assign(:deps, deps)
      |> assign(:last_probe, last_probe)

    ~H"""
    <div class="space-y-6">
      <div
        :if={@probe_error}
        class="px-3 py-2 rounded-[var(--radius-field)] bg-rose-100 dark:bg-rose-950/40 text-[var(--mast-status-offline)] text-xs flex items-center gap-2"
      >
        <span class="hero-exclamation-triangle size-4 shrink-0" /> Probe failed: {@probe_error}
      </div>

      <%= cond do %>
        <% @server.release_command in [nil, ""] -> %>
          <.ui_card padded={false}>
            <.ui_empty
              icon="hero-cog-6-tooth"
              title="App monitoring not configured"
              body="Open the Settings tab to set a release command. Mast will then poll this host every 30 seconds."
            />
          </.ui_card>
        <% @apps == [] -> %>
          <.ui_card padded={false}>
            <.ui_empty
              icon="hero-cube"
              title="No apps observed yet"
              body="Click Probe Now in the header to query the host. Apps will appear once the first probe succeeds."
            />
          </.ui_card>
        <% true -> %>
          <div class="flex items-start gap-3">
            <span class="hero-cube size-6 text-[var(--mast-chart-purple)] shrink-0 mt-1" />
            <div class="flex-1 min-w-0">
              <h2 class="text-lg font-bold text-[var(--mast-font-primary)] leading-tight">
                Elixir Applications
              </h2>
              <p class="text-[13px] text-[var(--mast-font-secondary)] mt-0.5">
                {summary_subtitle(@your_release, @deps)}
              </p>
            </div>
            <span :if={@last_probe} class="text-xs text-[var(--mast-font-tertiary)] shrink-0 mt-1">
              Last probed: {format_relative(@last_probe)}
            </span>
          </div>

          <section :if={@your_release}>
            <h3 class="text-[15px] font-semibold text-[var(--mast-font-primary)] mb-3">
              Your Release
            </h3>
            <.ui_release_card
              navigate={~p"/apps/#{@your_release.id}"}
              name={@your_release.name}
              version={@your_release.version}
              node_name={@your_release.node_name}
              status={@your_release.status}
              memory_mb={@your_release.memory_mb}
              processes={@your_release.processes}
              msg_queue={@your_release.msg_queue}
              uptime_seconds={@your_release.uptime_seconds}
              otp_release={@your_release.otp_release}
            />
          </section>

          <section :if={@deps != []}>
            <h3 class="text-[15px] font-semibold text-[var(--mast-font-primary)] mb-3">
              Dependencies
            </h3>
            <.dependencies_card deps={@deps} expanded?={@show_system_apps?} />
          </section>
      <% end %>
    </div>
    """
  end

  attr :deps, :list, required: true
  attr :expanded?, :boolean, required: true

  defp dependencies_card(assigns) do
    ~H"""
    <div class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] overflow-hidden">
      <button
        type="button"
        phx-click="toggle-system-apps"
        class="w-full flex items-center gap-2 px-4 py-3 border-b border-[var(--mast-border)] hover:bg-[var(--mast-bg-card-hover)] transition-colors"
      >
        <span class="hero-cube-transparent size-4 text-[var(--mast-font-secondary)]" />
        <span class="text-[13px] font-medium text-[var(--mast-font-primary)]">
          {length(@deps)} OTP applications running
        </span>
        <span class="flex-1" />
        <.ui_badge variant="online" size="sm">all healthy</.ui_badge>
        <span class={[
          "size-4 text-[var(--mast-font-tertiary)] transition-transform",
          if(@expanded?, do: "hero-chevron-up", else: "hero-chevron-down")
        ]} />
      </button>

      <div class="p-4">
        <div class="flex flex-wrap gap-2">
          <.link
            :for={dep <- chips_to_show(@deps, @expanded?)}
            navigate={~p"/apps/#{dep.id}"}
          >
            <.ui_chip status={dep.status}>{dep.name}</.ui_chip>
          </.link>
        </div>

        <button
          :if={not @expanded? and length(@deps) > preview_count()}
          type="button"
          phx-click="toggle-system-apps"
          class="mt-3 text-[13px] text-[var(--mast-accent)] font-medium hover:underline"
        >
          +{length(@deps) - preview_count()} more
        </button>
      </div>
    </div>
    """
  end

  defp preview_count, do: 14

  defp chips_to_show(deps, true), do: deps
  defp chips_to_show(deps, false), do: Enum.take(deps, preview_count())

  # The operator's release is the app whose name matches the basename of
  # `release_command` (e.g. /opt/hermes/current/bin/hermes -> "hermes").
  defp your_release(apps, %{release_command: rc}) when is_binary(rc) and rc != "" do
    name = Path.basename(rc)
    Enum.find(apps, &(&1.name == name))
  end

  defp your_release(_, _), do: nil

  defp summary_subtitle(nil, deps), do: "#{length(deps)} apps observed"

  defp summary_subtitle(_release, deps) do
    "1 release, #{length(deps)} dependencies running on this node"
  end

  defp last_probed_at(apps) do
    apps
    |> Enum.map(& &1.last_seen_at)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      times -> Enum.max(times, DateTime)
    end
  end
end

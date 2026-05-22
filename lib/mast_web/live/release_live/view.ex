defmodule MastWeb.ReleaseLive.View do
  @moduledoc """
  Render template + display helpers for `MastWeb.ReleaseLive`.

  State + event handlers live in the LiveView module; this file owns the
  markup for the Overview, Logs, and Settings sub-tabs.
  """
  use MastWeb, :html

  import MastWeb.ServerLive.Helpers, only: [partition_apps: 1]

  alias Mast.Fleet.Release

  attr :flash, :map, required: true
  attr :server, :map, required: true
  attr :release, :map, required: true
  attr :handle, :string, required: true
  attr :tab, :string, required: true
  attr :apps, :list, required: true
  attr :settings_changeset, :map, required: true
  attr :log_buffer, :list, default: []
  attr :log_streaming?, :boolean, default: false
  attr :log_status, :atom, default: :idle

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="servers" page_title={@handle}>
      <header class="-mx-6 lg:-mx-10 -mt-6 lg:-mt-8 mb-6 px-6 lg:px-10 pt-4 pb-0 border-b border-[var(--mast-border)]">
        <div class="flex items-center justify-between gap-4 flex-wrap">
          <nav class="flex items-center gap-1.5 text-[13px]">
            <.link
              navigate={~p"/"}
              class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
            >
              Servers
            </.link>
            <span class="text-[var(--mast-font-tertiary)]">/</span>
            <.link
              navigate={~p"/servers/#{@server.id}?tab=overview"}
              class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
            >
              {@server.name}
            </.link>
            <span class="text-[var(--mast-font-tertiary)]">/</span>
            <.link
              navigate={~p"/servers/#{@server.id}?tab=releases"}
              class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
            >
              Releases
            </.link>
            <span class="text-[var(--mast-font-tertiary)]">/</span>
            <span class="text-[var(--mast-font-primary)] font-medium">{@handle}</span>
          </nav>

          <div class="flex items-center gap-2">
            <.ui_badge variant={log_source_badge(@release.log_source)}>
              {log_source_label(@release.log_source)}
            </.ui_badge>
          </div>
        </div>

        <div class="mt-4">
          <h1 class="text-[24px] font-semibold text-[var(--mast-font-primary)]">{@handle}</h1>
          <p class="text-[13px] text-[var(--mast-font-secondary)] font-mono">
            {@release.release_command || "(no release_command — logs only)"}
          </p>
        </div>

        <.ui_tabs active={@tab} class="mt-4 border-b-0">
          <:tab key="overview" patch={~p"/servers/#{@server.id}/releases/#{@handle}?tab=overview"}>
            Overview
          </:tab>
          <:tab key="logs" patch={~p"/servers/#{@server.id}/releases/#{@handle}?tab=logs"}>
            Logs
          </:tab>
          <:tab key="settings" patch={~p"/servers/#{@server.id}/releases/#{@handle}?tab=settings"}>
            Settings
          </:tab>
        </.ui_tabs>
      </header>

      <.overview_tab :if={@tab == "overview"} apps={@apps} release={@release} />
      <.logs_tab
        :if={@tab == "logs"}
        release={@release}
        log_buffer={@log_buffer}
        log_streaming?={@log_streaming?}
        log_status={@log_status}
      />
      <.settings_tab
        :if={@tab == "settings"}
        changeset={@settings_changeset}
      />
    </Layouts.app>
    """
  end

  # ---- Overview ----------------------------------------------------------

  defp overview_tab(assigns) do
    main = main_release_app(assigns.release, assigns.apps)
    deps = Enum.reject(assigns.apps, &(main && &1.id == main.id))
    {user_deps, system_deps} = partition_apps(deps)

    assigns =
      assigns
      |> assign(:main, main)
      |> assign(:user_deps, user_deps)
      |> assign(:system_deps, system_deps)

    ~H"""
    <section class="space-y-6">
      <div :if={@release.release_command in [nil, ""]}>
        <.ui_empty
          icon="hero-information-circle"
          title="Probe not configured"
          body="This Release has no release_command set, so Mast cannot run bin/<release> rpc to read its applications."
        />
      </div>

      <div :if={@release.release_command not in [nil, ""] and @apps == []}>
        <.ui_empty
          icon="hero-signal-slash"
          title="No applications observed yet"
          body="The probe has not produced any observations for this Release. Click Probe All on the Server's Releases tab."
        />
      </div>

      <section :if={@main}>
        <div class="mb-3">
          <.ui_card_title icon="hero-cube" color="purple">Main Release</.ui_card_title>
        </div>
        <.link navigate={~p"/apps/#{@main.id}"} class="block">
          <.ui_release_card
            name={@main.name}
            version={@main.version}
            node_name={@main.node_name}
            status={@main.status}
            memory_mb={@main.memory_mb}
            processes={@main.processes}
            msg_queue={@main.msg_queue}
            uptime_seconds={@main.uptime_seconds}
            otp_release={@main.otp_release}
          />
        </.link>
      </section>

      <section :if={@user_deps != [] or @system_deps != []}>
        <div class="mb-3">
          <.ui_card_title icon="hero-cube-transparent" color="blue">
            Dependencies
            <:meta>
              {length(@user_deps) + length(@system_deps)} OTP applications
            </:meta>
          </.ui_card_title>
        </div>

        <div class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] p-4 space-y-3">
          <div :if={@user_deps != []}>
            <p class="text-[12px] font-medium text-[var(--mast-font-secondary)] mb-2">
              Project dependencies
            </p>
            <div class="flex flex-wrap gap-2">
              <.link
                :for={dep <- @user_deps}
                navigate={~p"/apps/#{dep.id}"}
              >
                <.ui_chip status={dep.status}>{dep.name}</.ui_chip>
              </.link>
            </div>
          </div>

          <div :if={@system_deps != []}>
            <p class="text-[12px] font-medium text-[var(--mast-font-secondary)] mb-2 mt-3">
              OTP / stdlib
            </p>
            <div class="flex flex-wrap gap-2">
              <.link
                :for={dep <- @system_deps}
                navigate={~p"/apps/#{dep.id}"}
              >
                <.ui_chip status={dep.status}>{dep.name}</.ui_chip>
              </.link>
            </div>
          </div>
        </div>
      </section>
    </section>
    """
  end

  # The "main" app for a Release is the OTP application whose name matches
  # the basename of `release_command` (e.g. /opt/hermes-toy/bin/hermes_toy
  # -> "hermes_toy"). The Release's display name/handle may differ from
  # the OTP app name (operator chose "toy"; the mix project shipped
  # :hermes_toy), so don't match on handle.
  defp main_release_app(%Release{release_command: rc}, apps)
       when is_binary(rc) and rc != "" do
    basename = Path.basename(rc)
    Enum.find(apps, &(&1.name == basename))
  end

  defp main_release_app(_, _), do: nil

  # ---- Logs --------------------------------------------------------------

  defp logs_tab(assigns) do
    ~H"""
    <section>
      <div :if={@release.log_source == "none"}>
        <.ui_empty
          icon="hero-document-text"
          title="No Log Source configured"
          body="Set a Log Source on the Settings tab to stream logs from this Release."
        />
      </div>

      <div :if={@release.log_source != "none"} class="space-y-3">
        <div class="flex items-center justify-between gap-2 text-[13px] text-[var(--mast-font-secondary)]">
          <div class="flex items-center gap-2">
            <span class="hero-terminal size-4" />
            <span class="font-mono">
              {@release.log_source}: {@release.log_target}
            </span>
          </div>
          <div class="flex items-center gap-2">
            <span class={[
              "size-2 rounded-full",
              log_status_dot(@log_status)
            ]} />
            <span>{log_status_label(@log_status)}</span>
            <button
              :if={@log_streaming?}
              type="button"
              phx-click="stop_log_stream"
              class="ml-2 text-[12px] underline hover:text-[var(--mast-font-primary)]"
            >
              Stop
            </button>
            <button
              :if={not @log_streaming?}
              type="button"
              phx-click="start_log_stream"
              class="ml-2 text-[12px] underline hover:text-[var(--mast-font-primary)]"
            >
              Start
            </button>
          </div>
        </div>

        <div
          id="log-buffer"
          phx-hook="LogAutoScroll"
          class="bg-[var(--mast-bg-input)] border border-[var(--mast-border)] rounded-[var(--radius-md)] h-[60vh] overflow-y-auto py-2"
        >
          <div
            :if={@log_buffer == []}
            class="px-4 py-6 text-center text-[13px] text-[var(--mast-font-tertiary)]"
          >
            Waiting for output…
          </div>
          <.ui_log_entry :for={line <- Enum.reverse(@log_buffer)} kind={line.kind} time={line.time}>
            {line.text}
          </.ui_log_entry>
        </div>
      </div>
    </section>
    """
  end

  # ---- Settings ----------------------------------------------------------

  defp settings_tab(assigns) do
    ~H"""
    <section class="max-w-2xl">
      <div class="mb-4">
        <.ui_card_title icon="hero-cog-6-tooth">Settings</.ui_card_title>
      </div>
      <.form
        :let={f}
        for={@changeset}
        as={:release}
        phx-change="validate_settings"
        phx-submit="save_settings"
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
          <.form_error field={f[:name]} />
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
          <.form_error field={f[:release_command]} />
          <p class="mt-1 text-[12px] text-[var(--mast-font-tertiary)]">
            Absolute path to `bin/&lt;release&gt;`. Leave blank to disable probes (logs-only Release).
          </p>
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
          <.form_error field={f[:log_source]} />
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
          <.form_error field={f[:log_target]} />
        </div>

        <div class="flex items-center gap-2 pt-2">
          <.ui_button type="submit" icon="hero-check">Save</.ui_button>
        </div>
      </.form>
    </section>
    """
  end

  attr :field, :map, required: true

  defp form_error(assigns) do
    ~H"""
    <p :for={msg <- field_errors(@field)} class="mt-1 text-[12px] text-[var(--mast-status-offline)]">
      {msg}
    </p>
    """
  end

  defp field_errors(%{errors: errors}) when is_list(errors) do
    Enum.map(errors, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end

  defp field_errors(_), do: []

  # ---- Labels / helpers --------------------------------------------------

  defp log_source_badge("none"), do: "neutral"
  defp log_source_badge(_), do: "online"

  defp log_source_label("none"), do: "no log source"
  defp log_source_label(source), do: "logs: #{source}"

  defp log_status_dot(:streaming), do: "bg-[var(--mast-status-online)] animate-pulse"
  defp log_status_dot(:error), do: "bg-[var(--mast-status-offline)]"
  defp log_status_dot(_), do: "bg-[var(--mast-font-tertiary)]"

  defp log_status_label(:streaming), do: "streaming"
  defp log_status_label(:error), do: "error"
  defp log_status_label(:closed), do: "closed"
  defp log_status_label(_), do: "idle"

  @doc false
  def page_title(%Release{} = release), do: Release.effective_handle(release) || "Release"
end

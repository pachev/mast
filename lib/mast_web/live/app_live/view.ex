defmodule MastWeb.AppLive.View do
  @moduledoc """
  Render template + display helpers for `MastWeb.AppLive`.

  Kept out of the LiveView module itself so neither file balloons. The
  LiveView owns state + event handlers; this owns markup + formatters.
  """
  use MastWeb, :html

  @doc """
  Top-level page template. Renders the App Detail design (pencil
  `v24vn`): header band with breadcrumb + status badge + Probe Now,
  4-up stat row, Memory-over-time chart placeholder, Application Info
  key/value table.
  """
  attr :flash, :map, required: true
  attr :app, :map, required: true
  attr :server, :map, required: true
  attr :refreshing?, :boolean, required: true

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="servers" page_title={@app.name}>
      <.detail_header app={@app} server={@server} refreshing?={@refreshing?} />

      <section class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <.ui_stat_tile
          icon="hero-cpu-chip"
          label="Memory"
          value={format_mb(@app.memory_mb)}
          sub="Total VM allocation"
        />
        <.ui_stat_tile
          icon="hero-bolt"
          label="Processes"
          value={format_int(@app.processes)}
          sub="Active BEAM processes"
        />
        <.ui_stat_tile
          icon="hero-clock"
          label="Uptime"
          value={format_uptime(@app.uptime_seconds)}
          sub="Since last restart"
        />
        <.ui_stat_tile
          icon="hero-inbox"
          label="Msg Queue"
          value={format_int(@app.msg_queue)}
          sub="Mailbox backlog"
          tone={if(zero?(@app.msg_queue), do: "accent", else: "warning")}
        />
      </section>

      <section class="mb-6">
        <.ui_chart_card title="Memory over time">
          <:badge>Last 24h</:badge>
          <div class="h-[180px] rounded-[var(--radius-sm)] bg-[var(--mast-bg-secondary)] flex items-center justify-center">
            <span class="text-[13px] text-[var(--mast-font-tertiary)]">
              Memory telemetry chart coming soon
            </span>
          </div>
        </.ui_chart_card>
      </section>

      <.ui_kv_table title="Application Info">
        <:row label="Node">{@app.node_name || "—"}</:row>
        <:row label="Status">
          <.ui_badge variant={status_variant(@app.status)} size="sm">{@app.status}</.ui_badge>
        </:row>
        <:row label="Version">{@app.version || "—"}</:row>
        <:row label="Uptime">{format_uptime_long(@app.uptime_seconds)}</:row>
        <:row label="OTP Release">{@app.otp_release || "—"}</:row>
        <:row label="Release Path">{release_path(@server)}</:row>
      </.ui_kv_table>
    </Layouts.app>
    """
  end

  # ---- Header band ---------------------------------------------------------

  attr :app, :map, required: true
  attr :server, :map, required: true
  attr :refreshing?, :boolean, required: true

  defp detail_header(assigns) do
    ~H"""
    <header class="-mx-6 lg:-mx-10 -mt-6 lg:-mt-8 mb-6 px-6 lg:px-10 pt-4 pb-4 border-b border-[var(--mast-border)]">
      <div class="flex items-center gap-1.5 text-[13px]">
        <.link
          navigate={~p"/"}
          class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
        >
          Servers
        </.link>
        <span class="text-[var(--mast-font-tertiary)]">/</span>
        <.link
          navigate={~p"/servers/#{@server.id}"}
          class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
        >
          {@server.name}
        </.link>
        <span class="text-[var(--mast-font-tertiary)]">/</span>
        <.link
          navigate={~p"/servers/#{@server.id}?tab=apps"}
          class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
        >
          Apps
        </.link>
        <span class="text-[var(--mast-font-tertiary)]">/</span>
        <span class="text-[var(--mast-font-primary)] font-medium">{@app.name}</span>

        <span class="flex-1" />

        <.ui_badge variant={status_variant(@app.status)}>{@app.status}</.ui_badge>
      </div>

      <div class="mt-4 flex items-center gap-3">
        <div class="size-9 rounded-[var(--radius-md)] bg-[var(--mast-chart-purple)] flex items-center justify-center shrink-0">
          <span class="hero-cube size-5 text-white" />
        </div>
        <div class="min-w-0">
          <h1 class="font-mono text-[22px] font-bold text-[var(--mast-font-primary)] leading-none">
            {@app.name}
          </h1>
          <p class="mt-1 text-[13px] text-[var(--mast-font-secondary)] truncate">
            <span :if={@app.version} class="font-mono">v{@app.version}</span>
            <span :if={@app.version && @app.node_name} class="mx-1">·</span>
            <span :if={@app.node_name} class="font-mono">{@app.node_name}</span>
            <span :if={@app.otp_release} class="mx-1">·</span>
            <span :if={@app.otp_release}>OTP {@app.otp_release}</span>
          </p>
        </div>

        <span class="flex-1" />

        <.ui_button
          size="sm"
          icon="hero-signal"
          phx-click="refresh"
          loading={@refreshing?}
          disabled={@refreshing?}
        >
          {if @refreshing?, do: "Probing…", else: "Probe Now"}
        </.ui_button>
      </div>
    </header>
    """
  end

  # ---- Display helpers -----------------------------------------------------

  defp status_variant("running"), do: "online"
  defp status_variant("unreachable"), do: "warning"
  defp status_variant("stopped"), do: "offline"
  defp status_variant(_), do: "neutral"

  defp format_mb(nil), do: "—"
  defp format_mb(n) when is_number(n), do: "#{trim_float(n)} MB"
  defp format_mb(_), do: "—"

  defp format_int(nil), do: "—"
  defp format_int(n) when is_number(n), do: Integer.to_string(trunc(n))
  defp format_int(_), do: "—"

  defp zero?(0), do: true
  defp zero?(_), do: false

  defp format_uptime(nil), do: "—"

  defp format_uptime(s) when is_integer(s) do
    cond do
      s < 60 -> "#{s} sec"
      s < 3600 -> "#{div(s, 60)} min"
      s < 86_400 -> "#{div(s, 3600)} hr"
      true -> "#{div(s, 86_400)} days"
    end
  end

  # Longer form for the kv table row.
  defp format_uptime_long(nil), do: "—"

  defp format_uptime_long(s) when is_integer(s) do
    cond do
      s < 60 -> "#{s} seconds"
      s < 3600 -> "#{div(s, 60)} minutes"
      s < 86_400 -> "#{div(s, 3600)} hours, #{rem(div(s, 60), 60)} minutes"
      true -> "#{div(s, 86_400)} days, #{rem(div(s, 3600), 24)} hours"
    end
  end

  defp release_path(%{release_command: rc}) when is_binary(rc) and rc != "" do
    # /opt/hermes/current/bin/hermes -> /opt/hermes/current
    rc |> Path.dirname() |> Path.dirname()
  end

  defp release_path(_), do: "—"

  defp trim_float(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp trim_float(n), do: "#{n}"
end

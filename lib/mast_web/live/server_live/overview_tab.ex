defmodule MastWeb.ServerLive.OverviewTab do
  @moduledoc """
  Overview tab for `MastWeb.ServerLive`: 4-up KPI row + Releases and
  Recent Activity cards.
  """
  use MastWeb, :html

  import MastWeb.ServerLive.Helpers

  alias Mast.Fleet.Release
  alias MastWeb.Audit.Presenter

  attr :server, :map, required: true
  attr :apps, :list, required: true
  attr :releases, :list, required: true
  attr :activity, :list, required: true
  attr :range, :string, required: true
  attr :series, :map, required: true
  attr :range_since, :any, default: nil
  attr :range_until, :any, default: nil
  attr :latest_sample, :map, default: %{}

  def render(assigns) do
    ~H"""
    <section class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
      <.ui_stat
        label="CPU Usage"
        value={format_pct(@server.cpu)}
        sub={cpu_sub(@server)}
        progress={progress_int(@server.cpu)}
        bar_tone={progress_tone(@server.cpu)}
      />
      <.ui_stat
        label="Memory"
        value={memory_value(@server)}
        sub={memory_sub(@server)}
        progress={progress_int(@server.memory)}
        bar_tone={progress_tone(@server.memory)}
      />
      <.ui_stat
        label="Disk"
        value={disk_value(@server)}
        sub={disk_sub(@server)}
        progress={progress_int(@server.disk)}
        bar_tone={progress_tone(@server.disk)}
      />
      <.ui_stat
        label="Network"
        value={network_value(@latest_sample)}
        sub={network_sub(@latest_sample)}
      />
    </section>

    <section class="mb-5">
      <form
        id="range-form"
        phx-change="set_range"
        class="flex items-center justify-between gap-3 mb-3"
      >
        <h2 class="text-base font-semibold text-[var(--mast-font-primary)]">
          Metrics history
        </h2>
        <label class="flex items-center gap-2 text-xs text-[var(--mast-font-tertiary)]">
          Range
          <select
            name="range"
            class="bg-[var(--mast-bg-secondary)] text-[var(--mast-font-primary)] border border-[var(--mast-border)] rounded-[var(--radius-sm)] px-2 py-1 text-xs"
          >
            <option value="1h" selected={@range == "1h"}>Last 1h</option>
            <option value="12h" selected={@range == "12h"}>Last 12h</option>
            <option value="1d" selected={@range == "1d"}>Last 24h</option>
            <option value="7d" selected={@range == "7d"}>Last 7d</option>
            <option value="30d" selected={@range == "30d"}>Last 30d</option>
          </select>
        </label>
      </form>

      <div class="grid lg:grid-cols-2 gap-3">
        <.ui_chart_card title="CPU over time">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart
            id={"chart-cpu-#{@server.id}"}
            points={@series["cpu"]}
            color="blue"
            label="CPU %"
            unit="%"
            y_format="percent"
            since={@range_since}
            until={@range_until}
          />
        </.ui_chart_card>
        <.ui_chart_card title="Memory over time">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart
            id={"chart-memory-#{@server.id}"}
            points={@series["memory"]}
            color="purple"
            label="Memory %"
            unit="%"
            y_format="percent"
            since={@range_since}
            until={@range_until}
          />
        </.ui_chart_card>
        <.ui_chart_card title="Disk over time">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart
            id={"chart-disk-#{@server.id}"}
            points={@series["disk_root"]}
            color="green"
            label="Disk %"
            unit="%"
            y_format="percent"
            since={@range_since}
            until={@range_until}
          />
        </.ui_chart_card>
        <.ui_chart_card title="Load avg (1m)">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart
            id={"chart-load-#{@server.id}"}
            points={@series["load_1"]}
            color="blue"
            label="Load 1m"
            since={@range_since}
            until={@range_until}
          />
        </.ui_chart_card>
        <.ui_chart_card title="Bandwidth (rx + tx)">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart
            id={"chart-bandwidth-#{@server.id}"}
            series={[
              %{name: "rx", color: "blue", points: to_mb_s(@series["rx_bytes_s"] || [])},
              %{name: "tx", color: "purple", points: to_mb_s(@series["tx_bytes_s"] || [])}
            ]}
            label="MB/s"
            unit=" MB/s"
            y_format="mb_s"
            since={@range_since}
            until={@range_until}
          />
        </.ui_chart_card>
        <.ui_chart_card title="Disk I/O (read + write)">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart
            id={"chart-disk-io-#{@server.id}"}
            series={[
              %{name: "read", color: "green", points: to_mb_s(@series["io_r_bytes_s"] || [])},
              %{name: "write", color: "blue", points: to_mb_s(@series["io_w_bytes_s"] || [])}
            ]}
            label="MB/s"
            unit=" MB/s"
            y_format="mb_s"
            since={@range_since}
            until={@range_until}
          />
        </.ui_chart_card>
      </div>
    </section>

    <section class="grid lg:grid-cols-2 gap-5">
      <.ui_card>
        <:title>
          <.ui_card_title icon="hero-cube" color="purple">
            Elixir Releases
            <:meta>{overview_releases_meta(@releases)}</:meta>
          </.ui_card_title>
        </:title>

        <%= cond do %>
          <% @releases == [] -> %>
            <.ui_empty
              icon="hero-cube"
              title="No Releases configured"
              body="Open the Releases tab to add one."
            />
          <% true -> %>
            <div class="space-y-2">
              <.link
                :for={r <- @releases}
                navigate={~p"/servers/#{@server.id}/releases/#{Release.effective_handle(r)}"}
                class="block"
              >
                <.ui_app_row
                  name={Release.effective_handle(r) || "—"}
                  meta={release_meta(r)}
                  status={release_status(r, @apps)}
                />
              </.link>
            </div>
        <% end %>
      </.ui_card>

      <.ui_card padded={false}>
        <:header>
          <div class="flex items-center justify-between gap-3 w-full">
            <div>
              <h2 class="text-base font-semibold text-[var(--mast-font-primary)]">
                Recent Activity
              </h2>
              <p class="text-xs text-[var(--mast-font-secondary)] mt-1">
                Recent audit events for this server
              </p>
            </div>
            <.link
              navigate={~p"/audit"}
              class="text-xs text-[var(--mast-accent)] hover:underline shrink-0"
            >
              View all →
            </.link>
          </div>
        </:header>

        <div class="max-h-72 overflow-y-auto">
          <div
            :if={@activity == []}
            class="px-4 py-8 text-center text-xs text-[var(--mast-font-tertiary)] italic"
          >
            No activity yet for this server.
          </div>

          <.ui_audit_row
            :for={e <- present_activity(@activity)}
            variant={e.variant}
            actor={e.actor}
            verb={e.verb}
            target={e.target}
            time={e.time}
            detail={e.detail}
          />
        </div>
      </.ui_card>
    </section>
    """
  end

  defp present_activity(events), do: Enum.map(events, &Presenter.present/1)

  defp range_label("1h"), do: "Last 1h"
  defp range_label("12h"), do: "Last 12h"
  defp range_label("1d"), do: "Last 24h"
  defp range_label("7d"), do: "Last 7d"
  defp range_label("30d"), do: "Last 30d"
  defp range_label(_), do: ""

  defp to_mb_s(points) do
    Enum.map(points, fn %{t: t, v: v} -> %{t: t, v: v / 1_000_000} end)
  end

  defp cpu_sub(%{cpu: nil}), do: "no data"

  defp cpu_sub(%{cpu_cores: cores}) when is_integer(cores) and cores > 0,
    do: "of #{cores} #{pluralize_cores(cores)}"

  defp cpu_sub(_), do: "of capacity"

  defp pluralize_cores(1), do: "core"
  defp pluralize_cores(_), do: "cores"

  defp network_value(%{"rx_bytes_s" => rx, "tx_bytes_s" => tx})
       when is_number(rx) and is_number(tx) do
    "#{fmt_mb_s((rx + tx) / 1_000_000)} MB/s"
  end

  defp network_value(_), do: "—"

  defp network_sub(%{"rx_bytes_s" => rx, "tx_bytes_s" => tx})
       when is_number(rx) and is_number(tx) do
    "↓ #{fmt_mb_s(rx / 1_000_000)} · ↑ #{fmt_mb_s(tx / 1_000_000)}"
  end

  defp network_sub(_), do: "no data"

  defp fmt_mb_s(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp fmt_mb_s(_), do: "0.00"

  defp progress_int(n) when is_number(n), do: round(n)
  defp progress_int(_), do: nil

  defp progress_tone(n) when is_number(n) and n >= 90, do: "offline"
  defp progress_tone(n) when is_number(n) and n >= 75, do: "warning"
  defp progress_tone(_), do: "accent"

  defp memory_value(%{memory_used_mb: used, memory_total_mb: total})
       when is_integer(used) and is_integer(total) and total > 0 do
    "#{fmt_gb_from_mb(used)} / #{fmt_gb_from_mb(total)} GB"
  end

  defp memory_value(%{memory: pct}), do: format_pct(pct)

  defp memory_sub(%{memory: pct}) when is_number(pct), do: pct_sub(pct)
  defp memory_sub(_), do: "no data"

  defp disk_value(%{disk_used_gb: used, disk_total_gb: total})
       when is_number(used) and is_number(total) and total > 0 do
    "#{fmt_gb(used)} / #{fmt_gb(total)} GB"
  end

  defp disk_value(%{disk: pct}), do: format_pct(pct)

  defp disk_sub(%{disk: pct}) when is_number(pct), do: pct_sub(pct)
  defp disk_sub(_), do: "no data"

  defp pct_sub(pct), do: "#{:erlang.float_to_binary(pct * 1.0, decimals: 1)}% used"

  defp fmt_gb_from_mb(mb) when is_integer(mb), do: fmt_gb(mb / 1024)
  defp fmt_gb_from_mb(_), do: "—"

  defp fmt_gb(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)
  defp fmt_gb(_), do: "—"

  defp overview_releases_meta([]), do: "none configured"
  defp overview_releases_meta([_]), do: "1 configured"
  defp overview_releases_meta(list), do: "#{length(list)} configured"

  defp release_meta(%Release{log_source: "none", release_command: nil}), do: "no probe · no logs"

  defp release_meta(%Release{log_source: "none", release_command: rc}) when is_binary(rc),
    do: "probe only"

  defp release_meta(%Release{log_source: source, release_command: nil}),
    do: "logs only · #{source}"

  defp release_meta(%Release{log_source: source}), do: "probe + #{source} logs"

  # The Release is "up" if its main App row (App.name == basename of
  # release_command, AND App.release_id == release.id) is running.
  defp release_status(%Release{id: release_id, release_command: rc}, apps)
       when is_binary(rc) and rc != "" do
    basename = Path.basename(rc)

    case Enum.find(apps, &(&1.release_id == release_id and &1.name == basename)) do
      nil -> "unknown"
      main -> main.status
    end
  end

  defp release_status(_, _), do: "unknown"
end

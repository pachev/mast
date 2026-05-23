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

  def render(assigns) do
    ~H"""
    <section class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
      <.ui_stat
        label="CPU Usage"
        value={format_pct(@server.cpu)}
        sub={cpu_sub(@server.cpu)}
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
        label="Load Avg"
        value={load_avg_label(@server)}
        sub={load_avg_sub(@server)}
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
          <.line_chart points={@series["cpu"]} color="blue" label="CPU %" unit="%" />
        </.ui_chart_card>
        <.ui_chart_card title="Memory over time">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart points={@series["memory"]} color="purple" label="Memory %" unit="%" />
        </.ui_chart_card>
        <.ui_chart_card title="Disk over time">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart points={@series["disk_root"]} color="green" label="Disk %" unit="%" />
        </.ui_chart_card>
        <.ui_chart_card title="Load avg (1m)">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart points={@series["load_1"]} color="blue" label="Load 1m" />
        </.ui_chart_card>
        <.ui_chart_card title="Bandwidth (rx + tx)">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart
            points={combine_pair(@series["rx_bytes_s"], @series["tx_bytes_s"])}
            color="purple"
            label="MB/s"
            unit=" MB/s"
          />
        </.ui_chart_card>
        <.ui_chart_card title="Disk I/O (read + write)">
          <:badge>{range_label(@range)}</:badge>
          <.line_chart
            points={combine_pair(@series["io_r_bytes_s"], @series["io_w_bytes_s"])}
            color="green"
            label="MB/s"
            unit=" MB/s"
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

  # Sums two byte-rate series timepoint-by-timepoint, converting bytes/s to
  # decimal MB/s for display.
  defp combine_pair(nil, nil), do: []
  defp combine_pair(a, nil), do: to_mb_s(a || [])
  defp combine_pair(nil, b), do: to_mb_s(b || [])

  defp combine_pair(a, b) do
    by_t = Map.new(b, &{&1.t, &1.v})

    Enum.map(a, fn %{t: t, v: v} ->
      total = v + Map.get(by_t, t, 0)
      %{t: t, v: total / 1_000_000}
    end)
  end

  defp to_mb_s(points) do
    Enum.map(points, fn %{t: t, v: v} -> %{t: t, v: v / 1_000_000} end)
  end

  defp cpu_sub(nil), do: "no data"
  defp cpu_sub(n) when is_number(n) and n >= 80, do: "high load"
  defp cpu_sub(_), do: "of capacity"

  defp load_avg_label(%{load_1: l1, load_5: l5, load_15: l15})
       when is_number(l1) and is_number(l5) and is_number(l15) do
    "#{fmt_load(l1)} #{fmt_load(l5)} #{fmt_load(l15)}"
  end

  defp load_avg_label(_), do: "—"

  defp load_avg_sub(%{load_1: l1}) when is_number(l1), do: "1m / 5m / 15m"
  defp load_avg_sub(_), do: "no data"

  defp fmt_load(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp fmt_load(n), do: to_string(n)

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

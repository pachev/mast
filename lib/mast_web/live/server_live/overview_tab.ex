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
  # release_command) is running. Otherwise neutral.
  defp release_status(%Release{release_command: rc}, apps) when is_binary(rc) and rc != "" do
    basename = Path.basename(rc)

    case Enum.find(apps, &(&1.name == basename)) do
      nil -> "unknown"
      main -> main.status
    end
  end

  defp release_status(_, _), do: "unknown"
end

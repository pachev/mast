defmodule MastWeb.ServerLive.Helpers do
  @moduledoc """
  Display helpers shared across `MastWeb.ServerLive` tab modules.
  """

  @doc "Status badge variant for a server."
  def status_badge("up"), do: "online"
  def status_badge("down"), do: "offline"
  def status_badge(_), do: "neutral"

  @doc "Human label for a server status."
  def status_label("up"), do: "Online"
  def status_label("down"), do: "Offline"
  def status_label(_), do: "Unknown"

  @doc "Title-case label for a tab key."
  def tab_label("overview"), do: "Overview"
  def tab_label("releases"), do: "Releases"
  def tab_label("logs"), do: "Logs"
  def tab_label("updates"), do: "Updates"
  def tab_label("settings"), do: "Settings"
  def tab_label(_), do: "Overview"

  @doc "Percent formatter that handles nil and floats."
  def format_pct(nil), do: "—"

  def format_pct(n) when is_float(n),
    do: :erlang.float_to_binary(n, decimals: 1) <> "%"

  def format_pct(n), do: "#{n}%"

  @doc ~S("last seen Xm ago" / "never seen" line for the header.)
  def last_seen(%{last_seen_at: nil}), do: "never seen"
  def last_seen(%{last_seen_at: t}), do: "last seen #{format_relative(t)}"

  @doc "Relative duration string from a DateTime to now."
  def format_relative(t) do
    diff = DateTime.diff(DateTime.utc_now(), t, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  @doc "Compact uptime label (90s -> \"1m\", etc)."
  def format_uptime_short(nil), do: nil

  def format_uptime_short(s) when is_integer(s) do
    cond do
      s < 60 -> "#{s}s"
      s < 3600 -> "#{div(s, 60)}m"
      s < 86_400 -> "#{div(s, 3600)}h"
      true -> "#{div(s, 86_400)}d"
    end
  end

  # Apps that ship with OTP, Elixir stdlib, Phoenix, Ecto, and the common
  # release deps. Hiding these focuses the default view on apps the operator
  # actually wrote.
  @system_apps MapSet.new(~w(
    asn1 bandit bcrypt_elixir cloak cloak_ecto comeonin compiler crypto
    db_connection decimal dns_cluster ecto ecto_sql eex elixir esbuild
    expo finch gettext hackney hpax idna inets jason kernel lazy_html
    logger logger_json metrics mime mimerl mint nimble_options
    nimble_pool oban os_mon parse_trans phoenix phoenix_ecto phoenix_html
    phoenix_live_dashboard phoenix_live_reload phoenix_live_view
    phoenix_pubsub phoenix_template plug plug_crypto postgrex public_key
    req runtime_tools sasl sshkit ssl ssl_verify_fun stdlib swoosh
    syntax_tools tailwind telemetry telemetry_metrics telemetry_poller
    thousand_island tzdata unicode_util_compat websock websock_adapter
    xmerl certifi
  ))

  @doc "Split apps into {user, system} based on the @system_apps list."
  def partition_apps(apps) do
    Enum.split_with(apps, &(&1.name not in @system_apps))
  end

  @doc "Only the operator-authored apps (user side of partition_apps/1)."
  def user_apps_only(apps) do
    {user, _} = partition_apps(apps)
    user
  end

  @doc "One-line meta string for an app row (version · node · up …)."
  def app_meta_line(app, _server) do
    [
      version_label(app.version),
      app.node_name,
      uptime_meta(app.uptime_seconds)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp version_label(nil), do: nil
  defp version_label(""), do: nil
  defp version_label(v), do: "v#{v}"

  defp uptime_meta(nil), do: nil
  defp uptime_meta(s) when is_integer(s), do: "up #{format_uptime_short(s)}"
end

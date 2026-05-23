defmodule MastWeb.Components.UI.Domain do
  @moduledoc """
  Mast-specific composed components: server cards, app cards/rows,
  release cards, log entries, audit rows.
  """
  use Phoenix.Component

  import MastWeb.Components.UI.Feedback
  import MastWeb.Components.UI.Data

  @doc """
  Compact server card with status, CPU/Mem/Disk metrics, and last-seen.

      <.ui_server_card server={s} />
  """
  attr :server, :map, required: true
  attr :class, :any, default: nil

  def ui_server_card(assigns) do
    ~H"""
    <.link
      navigate={"/servers/#{@server.id}"}
      class={[
        "block bg-[var(--mast-bg-card)] border border-[var(--mast-border)]",
        "rounded-[var(--radius-box)] p-4 sm:p-5 shadow-sm transition-colors",
        "hover:border-[var(--mast-accent)] hover:bg-[var(--mast-bg-card-hover)]",
        @class
      ]}
    >
      <div class="flex items-start justify-between gap-3 mb-3">
        <div class="flex items-center gap-3 min-w-0">
          <span
            class="hidden sm:inline-flex size-9 rounded-md bg-[var(--mast-bg-secondary)] items-center justify-center shrink-0"
            aria-hidden="true"
          >
            <span class="hero-server size-4 text-[var(--mast-font-tertiary)]" />
          </span>
          <div class="min-w-0">
            <div class="font-mono text-sm font-semibold text-[var(--mast-font-primary)] truncate">
              {@server.name}
            </div>
            <div class="text-[11px] text-[var(--mast-font-tertiary)] font-mono truncate">
              {@server.host}
            </div>
          </div>
        </div>
        <.ui_badge variant={server_badge_variant(@server.status)}>
          {server_status_label(@server.status)}
        </.ui_badge>
      </div>

      <div class="flex items-center gap-2 flex-wrap text-[11px] text-[var(--mast-font-tertiary)] mb-3 min-w-0">
        <span class="truncate">{@server.os_id || "—"}</span>
        <span aria-hidden="true">·</span>
        <span class="truncate">{card_last_seen(@server.last_seen_at)}</span>
      </div>

      <div class="grid grid-cols-3 gap-3">
        <.ui_metric label="CPU" value={@server.cpu} />
        <.ui_metric label="MEM" value={@server.memory} />
        <.ui_metric label="DISK" value={@server.disk} />
      </div>
    </.link>
    """
  end

  defp card_last_seen(nil), do: "never seen"

  defp card_last_seen(%DateTime{} = t) do
    diff = DateTime.diff(DateTime.utc_now(), t, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp server_badge_variant("up"), do: "online"
  defp server_badge_variant("down"), do: "offline"
  defp server_badge_variant(_), do: "neutral"

  defp server_status_label("up"), do: "Online"
  defp server_status_label("down"), do: "Offline"
  defp server_status_label(_), do: "Unknown"

  @doc """
  Card representing one Elixir release running on a server.

      <.ui_app_card name="mast_web" version="0.4.0" status="running" />
  """
  attr :name, :string, required: true
  attr :version, :string, default: nil
  attr :status, :string, default: "running"
  attr :uptime, :string, default: nil

  def ui_app_card(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3 px-4 py-3 bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-field)]">
      <div class="flex items-center gap-3 min-w-0">
        <div class="size-8 rounded-md bg-[var(--mast-accent-muted)] flex items-center justify-center shrink-0">
          <span class="text-[var(--mast-accent)] font-mono text-xs font-semibold">
            {String.first(@name) |> String.upcase()}
          </span>
        </div>
        <div class="min-w-0">
          <div class="font-mono text-sm font-medium text-[var(--mast-font-primary)] truncate">
            {@name}
          </div>
          <div class="text-xs text-[var(--mast-font-tertiary)] truncate">
            <span :if={@version}>v{@version}</span>
            <span :if={@version && @uptime} class="mx-1">·</span>
            <span :if={@uptime}>up {@uptime}</span>
          </div>
        </div>
      </div>
      <.ui_badge variant={app_status_variant(@status)}>
        {String.capitalize(@status)}
      </.ui_badge>
    </div>
    """
  end

  defp app_status_variant("running"), do: "online"
  defp app_status_variant("stopped"), do: "offline"
  defp app_status_variant("pending"), do: "warning"
  defp app_status_variant(_), do: "neutral"

  @doc """
  Compact row representation of an Elixir release. Designed to live
  stacked inside a card (see Apps tab on ServerLive).

      <.ui_app_row name="mast_web" meta="v0.4.0 · mast@web-prod-1 · OTP 28" status="running" />
  """
  attr :name, :string, required: true
  attr :meta, :string, default: nil
  attr :status, :string, default: "running"
  attr :class, :any, default: nil

  def ui_app_row(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 px-3 py-3 rounded-[var(--radius-field)]",
      "bg-[var(--mast-bg-secondary)]",
      @class
    ]}>
      <div class="flex-1 min-w-0">
        <div class="font-mono text-[13px] font-semibold text-[var(--mast-font-primary)] truncate">
          {@name}
        </div>
        <div :if={@meta} class="text-[11px] text-[var(--mast-font-tertiary)] truncate mt-0.5">
          {@meta}
        </div>
      </div>
      <.ui_badge variant={app_status_variant(@status)} size="sm">{@status}</.ui_badge>
    </div>
    """
  end

  @doc """
  Prominent card for a single Elixir release. Renders the release name and
  version next to a hexagon glyph, a right-side status badge, a horizontal
  metric row (Memory / Processes / Msg Queue), and a footer line for
  uptime + OTP version.

      <.ui_release_card
        name="hermes"
        node_name="hermes@ip-..."
        version="0.1.0"
        status="running"
        memory_mb={106.0}
        processes={536}
        msg_queue={0}
        uptime_seconds={576_000}
        otp_release="28"
      />
  """
  attr :name, :string, required: true
  attr :version, :string, default: nil
  attr :node_name, :string, default: nil
  attr :status, :string, default: "running"
  attr :memory_mb, :any, default: nil
  attr :processes, :any, default: nil
  attr :msg_queue, :any, default: nil
  attr :uptime_seconds, :any, default: nil
  attr :otp_release, :string, default: nil
  attr :rest, :global, include: ~w(href navigate patch)

  def ui_release_card(assigns) do
    body =
      ~H"""
      <div class="flex items-start justify-between gap-4">
        <div class="flex items-start gap-3 min-w-0">
          <div class="size-9 rounded-md bg-[var(--mast-accent-muted)] flex items-center justify-center shrink-0">
            <span class="hero-cube size-5 text-[var(--mast-chart-purple)]" />
          </div>
          <div class="min-w-0">
            <div class="font-mono text-[15px] font-semibold text-[var(--mast-font-primary)] truncate">
              {@name}
            </div>
            <div class="text-xs text-[var(--mast-font-tertiary)] truncate mt-0.5 font-mono">
              <span :if={@version}>v{@version}</span>
              <span :if={@version && @node_name} class="mx-1">·</span>
              <span :if={@node_name}>{@node_name}</span>
            </div>
          </div>
        </div>
        <.ui_badge variant={release_status_variant(@status)} size="sm">{@status}</.ui_badge>
      </div>

      <hr class="border-t border-[var(--mast-border)] my-4" />

      <div class="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4">
        <.ui_metric_tile label="Memory" value={format_memory(@memory_mb)} />
        <.ui_metric_tile label="Processes" value={format_count(@processes)} />
        <.ui_metric_tile label="Msg Queue" value={format_count(@msg_queue)} />
      </div>

      <hr
        :if={@uptime_seconds || @otp_release}
        class="border-t border-[var(--mast-border)] my-4"
      />

      <div
        :if={@uptime_seconds || @otp_release}
        class="flex items-center gap-2 text-xs text-[var(--mast-font-tertiary)]"
      >
        <span class="hero-clock size-3.5" />
        <span :if={@uptime_seconds}>up {format_uptime(@uptime_seconds)}</span>
        <span :if={@uptime_seconds && @otp_release} class="mx-1">·</span>
        <span :if={@otp_release}>OTP {@otp_release}</span>
      </div>
      """

    classes =
      "block bg-[var(--mast-bg-card)] border border-[var(--mast-border)] " <>
        "rounded-[var(--radius-box)] p-4 shadow-sm transition-colors " <>
        "hover:border-[var(--mast-accent)]"

    assigns = assign(assigns, :classes, classes) |> assign(:body, body)

    ~H"""
    <%= cond do %>
      <% @rest[:navigate] || @rest[:patch] || @rest[:href] -> %>
        <.link class={@classes} {@rest}>{@body}</.link>
      <% true -> %>
        <div class={@classes}>{@body}</div>
    <% end %>
    """
  end

  defp release_status_variant("running"), do: "online"
  defp release_status_variant("unreachable"), do: "warning"
  defp release_status_variant("stopped"), do: "offline"
  defp release_status_variant(_), do: "neutral"

  defp format_memory(nil), do: "—"
  defp format_memory(n) when is_number(n), do: "#{trunc(n)} MB"
  defp format_memory(_), do: "—"

  defp format_count(nil), do: "—"
  defp format_count(n) when is_number(n), do: Integer.to_string(trunc(n))
  defp format_count(_), do: "—"

  defp format_uptime(nil), do: "—"

  defp format_uptime(s) when is_integer(s) do
    cond do
      s < 60 -> "#{s}s"
      s < 3600 -> "#{div(s, 60)}m"
      s < 86_400 -> "#{div(s, 3600)}h #{rem(div(s, 60), 60)}m"
      true -> "#{div(s, 86_400)} days"
    end
  end

  @doc """
  Single line in a streaming log panel.

      <.ui_log_entry time="14:22:01" kind={:info}>
        Started apt update
      </.ui_log_entry>
  """
  attr :time, :string, default: nil
  attr :kind, :atom, default: :info, values: [:info, :stdout, :stderr, :exit, :error]
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def ui_log_entry(assigns) do
    ~H"""
    <div class={[
      "flex gap-3 px-3 py-1 font-mono text-xs leading-relaxed",
      log_kind_color(@kind),
      @class
    ]}>
      <span :if={@time} class="text-[var(--mast-font-tertiary)] shrink-0 select-none">
        {@time}
      </span>
      <span class="whitespace-pre-wrap break-all flex-1">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  defp log_kind_color(:stdout), do: "text-[var(--mast-font-primary)]"
  defp log_kind_color(:stderr), do: "text-[var(--mast-status-warning)]"
  defp log_kind_color(:exit), do: "text-[var(--mast-status-online)] font-semibold"
  defp log_kind_color(:error), do: "text-[var(--mast-status-offline)] font-semibold"
  defp log_kind_color(_), do: "text-[var(--mast-font-secondary)]"

  @doc """
  Single row in the audit log: actor, action verb, target, timestamp.

      <.ui_audit_row variant="action" actor="System" verb="scanned" target="web-prod-1" time="2m ago" />
      <.ui_audit_row variant="failure" actor="System" verb="failed to connect" target="db-prod-1" time="5m ago" />
  """
  attr :variant, :string,
    default: "action",
    values: ~w(action failure scan create delete key-create)

  attr :actor, :string, required: true
  attr :verb, :string, required: true
  attr :target, :string, default: nil
  attr :time, :string, required: true
  attr :detail, :string, default: nil

  def ui_audit_row(assigns) do
    ~H"""
    <div class={[
      "flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3 px-4 py-3 border-b border-[var(--mast-border)] last:border-0 hover:bg-[var(--mast-bg-card-hover)]",
      audit_row_bg(@variant)
    ]}>
      <div class="flex items-start gap-3 flex-1 min-w-0">
        <div class="size-8 rounded-full bg-[var(--mast-bg-tertiary)] flex items-center justify-center shrink-0">
          <span class={[audit_icon(@variant), "size-4", audit_icon_color(@variant)]} />
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap text-sm">
            <span class="font-medium text-[var(--mast-font-primary)]">{@actor}</span>
            <.ui_badge variant={audit_badge_variant(@variant)} dot={false}>
              {audit_label(@variant)}
            </.ui_badge>
            <span class="text-[var(--mast-font-secondary)]">{@verb}</span>
            <span :if={@target} class="font-mono text-[var(--mast-font-primary)]">{@target}</span>
          </div>
          <div :if={@detail} class="text-xs text-[var(--mast-font-tertiary)] mt-0.5 truncate">
            {@detail}
          </div>
        </div>
      </div>
      <div class="text-xs text-[var(--mast-font-tertiary)] tabular-nums shrink-0 pl-11 sm:pl-0">
        {@time}
      </div>
    </div>
    """
  end

  defp audit_icon("scan"), do: "hero-magnifying-glass"
  defp audit_icon("create"), do: "hero-plus"
  defp audit_icon("delete"), do: "hero-trash"
  defp audit_icon("failure"), do: "hero-exclamation-triangle"
  defp audit_icon("key-create"), do: "hero-key"
  defp audit_icon(_), do: "hero-bolt"

  defp audit_row_bg("failure"), do: "bg-rose-50/70 dark:bg-rose-950/20"
  defp audit_row_bg("delete"), do: "bg-rose-50/70 dark:bg-rose-950/20"
  defp audit_row_bg(_), do: ""

  defp audit_icon_color("failure"), do: "text-[var(--mast-status-offline)]"
  defp audit_icon_color("delete"), do: "text-[var(--mast-status-offline)]"
  defp audit_icon_color("scan"), do: "text-[var(--mast-chart-blue)]"
  defp audit_icon_color("create"), do: "text-[var(--mast-status-online)]"
  defp audit_icon_color("key-create"), do: "text-[var(--mast-chart-purple)]"
  defp audit_icon_color(_), do: "text-[var(--mast-font-secondary)]"

  defp audit_badge_variant("failure"), do: "offline"
  defp audit_badge_variant("create"), do: "online"
  defp audit_badge_variant("scan"), do: "neutral"
  defp audit_badge_variant("delete"), do: "offline"
  defp audit_badge_variant("key-create"), do: "accent"
  defp audit_badge_variant(_), do: "neutral"

  defp audit_label("scan"), do: "scan"
  defp audit_label("create"), do: "create"
  defp audit_label("delete"), do: "delete"
  defp audit_label("failure"), do: "failure"
  defp audit_label("key-create"), do: "key.create"
  defp audit_label(_), do: "action"

  @doc """
  Collapsible group header used to group servers by Project on the
  Fleet page. Matches the `ProjectGroup/Header` pen component.

      <.ui_project_group_header
        name="blog"
        color="emerald"
        count={2}
        expanded?={true}
        toggle={%{"phx-click" => "toggle-project", "phx-value-id" => p.id}}
      />

  `toggle` is a map of HTML attributes (typically `phx-click`/`phx-value-*`)
  spread onto the clickable row. Pass an empty map for a static header.
  """
  attr :name, :string, required: true
  attr :color, :any, default: nil
  attr :count, :integer, required: true
  attr :expanded?, :boolean, default: true
  attr :toggle, :map, default: %{}

  def ui_project_group_header(assigns) do
    ~H"""
    <div
      {@toggle}
      role={if @toggle == %{}, do: nil, else: "button"}
      tabindex={if @toggle == %{}, do: nil, else: "0"}
      aria-expanded={if @toggle == %{}, do: nil, else: to_string(@expanded?)}
      class={[
        "flex items-center gap-2 sm:gap-3 px-2 sm:px-3 py-2 -mx-2 sm:-mx-3 rounded-[var(--radius-field)]",
        "select-none",
        if(@toggle == %{},
          do: "cursor-default",
          else: "cursor-pointer hover:bg-[var(--mast-bg-card-hover)]"
        )
      ]}
    >
      <span
        class={[
          "hero-chevron-down size-4 shrink-0 text-[var(--mast-font-tertiary)] transition-transform",
          if(@expanded?, do: "rotate-0", else: "-rotate-90")
        ]}
        aria-hidden="true"
      />
      <span
        class={["inline-block size-2.5 rounded-full shrink-0", project_color_bg(@color)]}
        aria-hidden="true"
      />
      <span class="font-mono text-sm font-semibold text-[var(--mast-font-primary)] truncate min-w-0">
        {@name}
      </span>
      <span class="flex-1" />
      <span class="text-xs text-[var(--mast-font-tertiary)] tabular-nums whitespace-nowrap">
        {@count} {if @count == 1, do: "server", else: "servers"}
      </span>
    </div>
    """
  end

  @doc """
  Small Project chip — used as a badge near the Server detail header
  and inside server cards when grouping is disabled. Color tints from
  the preset palette.

      <.ui_project_badge name="blog" color="emerald" />
  """
  attr :name, :string, required: true
  attr :color, :any, default: nil
  attr :class, :any, default: nil

  def ui_project_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full",
        "text-[11px] font-medium whitespace-nowrap max-w-[12rem] truncate",
        project_badge_classes(@color),
        @class
      ]}
      title={"Project: " <> @name}
    >
      <span
        class={["inline-block size-1.5 rounded-full shrink-0", project_color_bg(@color)]}
        aria-hidden="true"
      />
      {@name}
    </span>
    """
  end

  @doc "Tailwind background class for a Project color preset."
  def project_color_bg(nil), do: "bg-[var(--mast-font-tertiary)]"
  def project_color_bg(""), do: "bg-[var(--mast-font-tertiary)]"
  def project_color_bg("slate"), do: "bg-slate-500"
  def project_color_bg("indigo"), do: "bg-indigo-500"
  def project_color_bg("emerald"), do: "bg-emerald-500"
  def project_color_bg("amber"), do: "bg-amber-500"
  def project_color_bg("rose"), do: "bg-rose-500"
  def project_color_bg("violet"), do: "bg-violet-500"
  def project_color_bg(_), do: "bg-[var(--mast-font-tertiary)]"

  defp project_badge_classes(nil),
    do: "bg-[var(--mast-bg-secondary)] text-[var(--mast-font-secondary)]"

  defp project_badge_classes(""),
    do: "bg-[var(--mast-bg-secondary)] text-[var(--mast-font-secondary)]"

  defp project_badge_classes("slate"), do: "bg-slate-100 text-slate-700"
  defp project_badge_classes("indigo"), do: "bg-indigo-100 text-indigo-700"
  defp project_badge_classes("emerald"), do: "bg-emerald-100 text-emerald-700"
  defp project_badge_classes("amber"), do: "bg-amber-100 text-amber-700"
  defp project_badge_classes("rose"), do: "bg-rose-100 text-rose-700"
  defp project_badge_classes("violet"), do: "bg-violet-100 text-violet-700"

  defp project_badge_classes(_),
    do: "bg-[var(--mast-bg-secondary)] text-[var(--mast-font-secondary)]"
end

defmodule MastWeb.DevUiLive.View do
  @moduledoc """
  Render template for the dev-only `/dev/ui` showcase. Kept separate
  from `MastWeb.DevUiLive` so the LiveView module stays focused on
  state and event handling.
  """
  use MastWeb, :html

  @doc """
  Top-level showcase page. Expects `:width`, `:widths`, `:show_modal?`
  assigns.
  """
  attr :width, :string, required: true
  attr :widths, :list, required: true
  attr :show_modal?, :boolean, default: false

  def render(assigns) do
    ~H"""
    <Layouts.app flash={%{}} active="dev-ui" page_title="UI Showcase">
      <.ui_page_header
        title="Component showcase"
        subtitle="Dev-only. Pick a width to preview responsive behavior."
      >
        <:actions>
          <.width_toggle width={@width} widths={@widths} />
        </:actions>
      </.ui_page_header>

      <div class="mx-auto" style={frame_style(@width)}>
        <div class={["space-y-10", frame_classes(@width)]}>
          <.section title="Buttons" id="section-buttons">
            <.buttons_demo />
          </.section>

          <.section title="Feedback" id="section-feedback">
            <.feedback_demo />
          </.section>

          <.section title="Forms" id="section-forms">
            <.forms_demo />
          </.section>

          <.section title="Containers" id="section-containers">
            <.containers_demo show_modal?={@show_modal?} />
          </.section>

          <.section title="Navigation" id="section-navigation">
            <.navigation_demo />
          </.section>

          <.section title="Data" id="section-data">
            <.data_demo />
          </.section>

          <.section title="Table" id="section-table">
            <.table_demo />
          </.section>

          <.section title="Domain" id="section-domain">
            <.domain_demo />
          </.section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp frame_style("full"), do: nil
  defp frame_style(w), do: "max-width: #{w}px;"

  defp frame_classes("full"), do: "w-full"

  defp frame_classes(w),
    do: "w-full max-w-[#{w}px] mx-auto border-x border-dashed border-[var(--mast-border)]"

  attr :width, :string, required: true
  attr :widths, :list, required: true

  defp width_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 bg-[var(--mast-bg-tertiary)] rounded-full p-0.5">
      <button
        :for={w <- @widths}
        type="button"
        phx-click="set-width"
        phx-value-width={w}
        class={[
          "px-3 h-7 rounded-full text-xs font-medium leading-none tabular-nums",
          if w == @width do
            "bg-[var(--mast-bg-card)] text-[var(--mast-font-primary)] shadow-sm"
          else
            "text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
          end
        ]}
      >
        {if w == "full", do: "full", else: w}
      </button>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :id, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section id={@id} class="space-y-3">
      <h2 class="text-sm font-semibold uppercase tracking-wider text-[var(--mast-font-tertiary)]">
        {@title}
      </h2>
      <div class="space-y-4">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  defp buttons_demo(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2">
      <.ui_button>Primary</.ui_button>
      <.ui_button variant="secondary">Secondary</.ui_button>
      <.ui_button variant="ghost">Ghost</.ui_button>
      <.ui_button variant="destructive">Destructive</.ui_button>
      <.ui_button icon="hero-plus">With icon</.ui_button>
      <.ui_button size="sm">Small</.ui_button>
      <.ui_button loading>Loading</.ui_button>
      <.ui_button disabled>Disabled</.ui_button>
    </div>
    """
  end

  defp feedback_demo(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <.ui_badge variant="online">online</.ui_badge>
      <.ui_badge variant="offline">offline</.ui_badge>
      <.ui_badge variant="warning">warning</.ui_badge>
      <.ui_badge variant="accent">accent</.ui_badge>
      <.ui_badge variant="neutral" dot={false}>neutral</.ui_badge>
      <.ui_status_dot status="up" />
      <.ui_status_dot status="down" />
      <.ui_status_dot status="unknown" />
      <.ui_chip status="running">running</.ui_chip>
      <.ui_chip status="stopped">stopped</.ui_chip>
    </div>
    """
  end

  defp forms_demo(assigns) do
    ~H"""
    <form phx-change="noop" class="max-w-md space-y-3">
      <.ui_search name="q" placeholder="Search packages..." />
    </form>
    """
  end

  attr :show_modal?, :boolean, required: true

  defp containers_demo(assigns) do
    ~H"""
    <div class="grid gap-4 md:grid-cols-2">
      <.ui_card>
        <:title>Card title</:title>
        <:subtitle>With a subtitle line</:subtitle>
        <:actions>
          <.ui_button size="sm" variant="ghost">Action one</.ui_button>
          <.ui_button size="sm">Action two</.ui_button>
        </:actions>
        Card body content goes here. Should sit below header on narrow widths.
      </.ui_card>

      <.ui_card>
        <:title>Plain card</:title>
        Body only, no actions.
      </.ui_card>

      <.ui_chart_card title="Memory over time">
        <:badge>Last 24h</:badge>
        <div class="h-[140px] flex items-center justify-center text-[var(--mast-font-tertiary)] text-xs">
          chart placeholder
        </div>
      </.ui_chart_card>

      <.ui_empty
        icon="hero-server"
        title="No alerts yet"
        body="When something needs attention, it'll show here."
      >
        <.ui_button size="sm">Add Server</.ui_button>
      </.ui_empty>
    </div>

    <div class="flex items-center gap-3">
      <.ui_button phx-click="open-modal" variant="secondary">Open modal</.ui_button>
      <span class="text-xs text-[var(--mast-font-tertiary)]">
        Modal body has its own scroll region.
      </span>
    </div>

    <.ui_modal :if={@show_modal?} id="dev-modal" on_cancel={JS.push("close-modal")}>
      <:title>Modal title</:title>
      <:subtitle>Use Esc or click outside to close.</:subtitle>
      <div class="space-y-3 text-sm text-[var(--mast-font-secondary)]">
        <p :for={i <- 1..20}>
          Paragraph {i}. Modal body content should scroll within the panel rather than
          pushing the page below the fold on tall content.
        </p>
      </div>
      <:footer>
        <.ui_button variant="secondary" phx-click="close-modal">Cancel</.ui_button>
        <.ui_button phx-click="close-modal">Confirm</.ui_button>
      </:footer>
    </.ui_modal>
    """
  end

  defp navigation_demo(assigns) do
    ~H"""
    <.ui_tabs active="overview">
      <:tab key="overview" event="noop">Overview</:tab>
      <:tab key="apps" event="noop" count={3}>Apps</:tab>
      <:tab key="updates" event="noop" count={12}>Updates</:tab>
      <:tab key="audit" event="noop">Audit</:tab>
      <:tab key="settings" event="noop">Settings</:tab>
      <:tab key="releases" event="noop">Releases</:tab>
    </.ui_tabs>

    <p class="text-xs text-[var(--mast-font-tertiary)]">
      Six tabs should scroll horizontally on narrow widths, not wrap.
    </p>

    <p class="text-xs text-[var(--mast-font-tertiary)]">
      Page header above is itself an example; sidebar lives in the app layout.
    </p>
    """
  end

  defp data_demo(assigns) do
    ~H"""
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <.ui_stat label="Total Servers" value={6} />
      <.ui_stat label="Online" value={5} tone="online" />
      <.ui_stat label="Updates Available" value={12} tone="warning" />
      <.ui_stat label="With usage bar" value={68} progress={68} sub="68% of capacity" />
    </div>

    <div class="grid gap-4 sm:grid-cols-2">
      <.ui_card>
        <:title>Metrics</:title>
        <.ui_metric label="CPU" value={68} />
        <.ui_metric label="Memory" value={9.4} max={16} suffix="GB" />
        <.ui_metric label="Disk" value={92} />
      </.ui_card>

      <.ui_card padded={false}>
        <:title>
          <.ui_card_title icon="hero-cube" color="purple">
            Card title with icon
            <:meta>3 running</:meta>
          </.ui_card_title>
        </:title>
        <div class="px-5 pb-5 grid grid-cols-3 gap-2 sm:gap-4">
          <.ui_metric_tile label="Memory" value="106 MB" />
          <.ui_metric_tile label="Procs" value="536" />
          <.ui_metric_tile label="Queue" value="0" />
        </div>
      </.ui_card>
    </div>

    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <.ui_stat_tile icon="hero-cpu-chip" label="Memory" value="106 MB" sub="VM allocation" />
      <.ui_stat_tile label="Processes" value="536" sub="Active" tone="accent" />
      <.ui_stat_tile label="Msg Queue" value="0" sub="Backlog" />
    </div>

    <.ui_kv_table title="Application Info">
      <:row label="Node">hermes@ip-10-0-0-42.us-west-2.compute.internal</:row>
      <:row label="Status">
        <.ui_badge variant="online">running</.ui_badge>
      </:row>
      <:row label="Version">0.1.0</:row>
      <:row label="OTP Release">28</:row>
    </.ui_kv_table>
    """
  end

  defp table_demo(assigns) do
    rows =
      for i <- 1..23 do
        %{
          "package" => "openssl-#{i}",
          "current" => "3.0.#{i}",
          "next" => "3.0.#{i + 1}"
        }
      end

    assigns = assign(assigns, :rows, Enum.take(rows, 10)) |> assign(:total, length(rows))

    ~H"""
    <.ui_table id="dev-table" rows={@rows} size="sm" zebra>
      <:col :let={row} label="Package">{row["package"]}</:col>
      <:col :let={row} label="Current">{row["current"]}</:col>
      <:col :let={row} label="Next">{row["next"]}</:col>
      <:col :let={_row}>
        <.ui_button size="sm" variant="ghost">Apply</.ui_button>
      </:col>
      <:action_bar>
        <.ui_search name="q" />
        <.ui_badge>{@total} packages</.ui_badge>
        <.ui_badge variant="warning">3 outdated</.ui_badge>
      </:action_bar>
      <:pagination page={1} page_size={10} total={@total} event="noop" />
    </.ui_table>
    """
  end

  defp domain_demo(assigns) do
    server = %{
      id: "00000000-0000-0000-0000-000000000000",
      name: "web-prod-1",
      status: "up",
      cpu: 42,
      memory: 78,
      disk: 60
    }

    assigns = assign(assigns, :server, server)

    ~H"""
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <.ui_server_card server={@server} />
      <.ui_server_card server={
        %{@server | name: "db-prod-1", status: "down", cpu: 0, memory: 0, disk: 0}
      } />
      <.ui_server_card server={
        %{@server | name: "edge-eu-1", status: "unknown", cpu: 12, memory: 30, disk: 18}
      } />
    </div>

    <.ui_card>
      <:title>Apps on this server</:title>
      <div class="space-y-2">
        <.ui_app_card name="mast_web" version="0.4.0" status="running" uptime="6d 4h" />
        <.ui_app_card name="hermes" version="0.1.0" status="stopped" />
        <.ui_app_card name="prometheus_exporter" status="pending" />
      </div>
    </.ui_card>

    <.ui_card padded={false}>
      <:title>App rows</:title>
      <div class="space-y-1 px-5 pb-5">
        <.ui_app_row name="mast_web" meta="v0.4.0 · web-prod-1 · OTP 28" status="running" />
        <.ui_app_row name="hermes" meta="v0.1.0 · web-prod-1 · OTP 28" status="stopped" />
      </div>
    </.ui_card>

    <.ui_release_card
      name="hermes"
      version="0.1.0"
      node_name="hermes@ip-10-0-0-42.us-west-2.compute.internal"
      status="running"
      memory_mb={106.0}
      processes={536}
      msg_queue={0}
      uptime_seconds={576_000}
      otp_release="28"
    />

    <.ui_card padded={false}>
      <:title>Audit log</:title>
      <div>
        <.ui_audit_row variant="scan" actor="System" verb="scanned" target="web-prod-1" time="2m ago" />
        <.ui_audit_row
          variant="create"
          actor="pj"
          verb="added server"
          target="db-prod-1"
          time="1h ago"
        />
        <.ui_audit_row
          variant="failure"
          actor="System"
          verb="failed to connect"
          target="db-prod-1"
          time="5m ago"
          detail="nxdomain — DNS lookup failed"
        />
        <.ui_audit_row
          variant="key-create"
          actor="pj"
          verb="registered key"
          target="hermes-key"
          time="3h ago"
        />
      </div>
    </.ui_card>

    <.ui_card padded={false}>
      <:title>Log stream</:title>
      <div class="px-2 pb-3">
        <.ui_log_entry time="14:22:01" kind={:info}>Started apt update</.ui_log_entry>
        <.ui_log_entry time="14:22:03" kind={:stdout}>Reading package lists... Done</.ui_log_entry>
        <.ui_log_entry time="14:22:04" kind={:stderr}>W: Some warning from apt</.ui_log_entry>
        <.ui_log_entry time="14:22:05" kind={:exit}>Process exited 0</.ui_log_entry>
        <.ui_log_entry time="14:22:06" kind={:error}>Job failed</.ui_log_entry>
      </div>
    </.ui_card>
    """
  end
end

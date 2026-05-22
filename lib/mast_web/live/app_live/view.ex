defmodule MastWeb.AppLive.View do
  @moduledoc """
  Render template + display helpers for `MastWeb.AppLive`.

  Kept out of the LiveView module itself so neither file balloons. The
  LiveView owns state + event handlers; this owns markup + formatters.
  """
  use MastWeb, :html

  @doc """
  Top-level page template. Renders the App Detail design (pencil
  `v24vn` + Observer view `PCua4` / fallback `ynkPW`): header band with
  breadcrumb + status badge + Probe Now, 4-up stat row, Application Info
  key/value table, and the Observer sections when `:detail` is loaded.
  """
  attr :flash, :map, required: true
  attr :app, :map, required: true
  attr :server, :map, required: true
  attr :release, :any, default: nil
  attr :refreshing?, :boolean, required: true
  attr :detail, :map, default: nil
  attr :detail_error, :any, default: nil

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="servers" page_title={@app.name}>
      <.detail_header app={@app} server={@server} release={@release} refreshing?={@refreshing?} />

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

      <.observer_fallback_banner :if={@detail_error == :observer_backend_unavailable} />

      <.system_snapshot :if={@detail} sys={@detail.sys_info} />
      <.sup_tree :if={@detail} tree={@detail.sup_tree} />
      <.top_processes :if={@detail} memory={@detail.top_memory} msgq={@detail.top_msgq} />
    </Layouts.app>
    """
  end

  # ---- Observer sections ---------------------------------------------------

  defp observer_fallback_banner(assigns) do
    ~H"""
    <section class="mt-6 mb-6">
      <div class="flex items-center gap-3 rounded-[var(--radius-md)] bg-[var(--mast-bg-secondary)] border border-[var(--mast-border)] px-4 py-3">
        <span class="hero-information-circle size-5 text-[var(--mast-font-secondary)] shrink-0" />
        <p class="text-[13px] text-[var(--mast-font-secondary)]">
          Detailed metrics unavailable. Add <code class="font-mono">:runtime_tools</code>
          to your release's <code class="font-mono">extra_applications</code>
          — see the <a
            href="https://github.com/pachev/mast#making-your-elixir-app-monitorable"
            class="underline hover:text-[var(--mast-font-primary)]"
            target="_blank"
            rel="noopener"
          >
            README
          </a>.
        </p>
      </div>
    </section>
    """
  end

  attr :sys, :map, required: true

  defp system_snapshot(assigns) do
    ~H"""
    <section class="mt-6 rounded-[var(--radius-lg)] bg-[var(--mast-bg-card)] border border-[var(--mast-border)] p-5">
      <header class="flex items-center mb-4">
        <h3 class="text-[15px] font-semibold text-[var(--mast-font-primary)]">System snapshot</h3>
        <span class="flex-1" />
        <.ui_badge variant="online" size="sm">live</.ui_badge>
      </header>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="space-y-3">
          <.snapshot_row label="Scheduler utilization">
            <div class="flex items-center gap-2 w-full">
              <div class="flex-1 h-1.5 rounded-full bg-[var(--mast-bg-secondary)] overflow-hidden">
                <div
                  class="h-full bg-[var(--mast-accent)]"
                  style={"width: #{clamp_pct(@sys[:scheduler_utilization])}%"}
                />
              </div>
              <span class="font-mono text-[13px] tabular-nums w-12 text-right">
                {format_pct(@sys[:scheduler_utilization])}
              </span>
            </div>
          </.snapshot_row>
          <.snapshot_row label="Atom count">
            <span class="font-mono text-[13px] tabular-nums">{format_int(@sys[:atom_count])}</span>
          </.snapshot_row>
          <.snapshot_row label="Port count">
            <span class="font-mono text-[13px] tabular-nums">{format_int(@sys[:port_count])}</span>
          </.snapshot_row>
          <.snapshot_row label="Processes">
            <span class="font-mono text-[13px] tabular-nums">{format_int(@sys[:process_count])}</span>
          </.snapshot_row>
          <.snapshot_row label="ETS tables">
            <span class="font-mono text-[13px] tabular-nums">{format_int(@sys[:ets_count])}</span>
          </.snapshot_row>
        </div>

        <div>
          <p class="text-[13px] text-[var(--mast-font-secondary)] mb-2">Memory by category</p>
          <.memory_breakdown categories={@sys[:memory_by_category] || %{}} />
        </div>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp snapshot_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class="text-[13px] text-[var(--mast-font-secondary)] w-44 shrink-0">{@label}</span>
      <div class="flex-1">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :categories, :map, required: true

  defp memory_breakdown(assigns) do
    cats = [
      {:processes, "Processes", "var(--mast-chart-purple)"},
      {:atom, "Atom", "var(--mast-chart-blue)"},
      {:binary, "Binary", "var(--mast-chart-orange)"},
      {:ets, "ETS", "var(--mast-chart-green)"},
      {:code, "Code", "var(--mast-chart-pink)"}
    ]

    total =
      cats
      |> Enum.map(fn {k, _, _} -> Map.get(assigns.categories, k) || 0 end)
      |> Enum.sum()

    assigns = assign(assigns, :cats, cats) |> assign(:total, total)

    ~H"""
    <div class="space-y-2">
      <div class="flex h-3 rounded-full overflow-hidden bg-[var(--mast-bg-secondary)]">
        <div
          :for={{key, _label, color} <- @cats}
          class="h-full"
          style={"width: #{pct_of(Map.get(@categories, key), @total)}%; background-color: #{color};"}
        />
      </div>
      <ul class="grid grid-cols-2 gap-x-4 gap-y-1 text-[12px]">
        <li :for={{key, label, color} <- @cats} class="flex items-center gap-2">
          <span class="size-2 rounded-sm shrink-0" style={"background-color: #{color};"} />
          <span class="text-[var(--mast-font-secondary)]">{label}</span>
          <span class="flex-1" />
          <span class="font-mono tabular-nums text-[var(--mast-font-primary)]">
            {format_bytes(Map.get(@categories, key))}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  attr :tree, :list, required: true

  defp sup_tree(assigns) do
    ~H"""
    <section class="mt-6 rounded-[var(--radius-lg)] bg-[var(--mast-bg-card)] border border-[var(--mast-border)] p-5">
      <header class="mb-3 flex items-center gap-2">
        <h3 class="text-[15px] font-semibold text-[var(--mast-font-primary)]">Supervision tree</h3>
        <span class="text-[12px] text-[var(--mast-font-tertiary)]">(depth capped at 3)</span>
      </header>
      <div :if={@tree == []} class="text-[13px] text-[var(--mast-font-tertiary)]">
        No supervision tree reported.
      </div>
      <ul :if={@tree != []} class="space-y-0">
        <.tree_node :for={node <- @tree} node={node} />
      </ul>
    </section>
    """
  end

  attr :node, :map, required: true

  defp tree_node(assigns) do
    has_children? = assigns.node[:children] && assigns.node[:children] != []
    assigns = assign(assigns, :has_children?, has_children?)

    ~H"""
    <li>
      <%= if @has_children? do %>
        <details
          class="[&[open]>summary>.sup-chevron]:rotate-90"
          open={(@node[:depth] || 0) < 1}
        >
          <summary
            class="flex items-center gap-2 h-9 cursor-pointer list-none text-[13px] hover:bg-[var(--mast-bg-secondary)] rounded-[var(--radius-sm)]"
            style={"padding-left: #{8 + (@node[:depth] || 0) * 20}px; padding-right: 8px;"}
          >
            <span class="sup-chevron hero-chevron-right size-3.5 text-[var(--mast-font-tertiary)] shrink-0 transition-transform" />
            <span class="hero-cube size-4 text-[var(--mast-accent)] shrink-0" />
            <span class="font-mono text-[var(--mast-font-primary)] truncate">
              {@node[:name] || "anonymous"}
            </span>
            <span class="text-[11px] text-[var(--mast-font-tertiary)] tabular-nums">
              {length(@node[:children])}
            </span>
            <span class="flex-1" />
            <span class="font-mono text-[12px] text-[var(--mast-font-tertiary)]">{@node[:pid]}</span>
          </summary>
          <ul>
            <.tree_node :for={child <- @node[:children]} node={child} />
          </ul>
        </details>
      <% else %>
        <div
          class="flex items-center gap-2 h-9 text-[13px]"
          style={"padding-left: #{8 + (@node[:depth] || 0) * 20 + 18}px; padding-right: 8px;"}
        >
          <span class={
            if @node[:type] == "supervisor",
              do: "hero-cube size-4 text-[var(--mast-accent)] shrink-0",
              else: "hero-bullet size-4 text-[var(--mast-font-tertiary)] shrink-0"
          } />
          <span class="font-mono text-[var(--mast-font-primary)] truncate">
            {@node[:name] || "anonymous"}
          </span>
          <span class="flex-1" />
          <span class="font-mono text-[12px] text-[var(--mast-font-tertiary)]">{@node[:pid]}</span>
        </div>
      <% end %>
    </li>
    """
  end

  attr :memory, :list, required: true
  attr :msgq, :list, required: true

  defp top_processes(assigns) do
    ~H"""
    <section class="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-4">
      <.proc_table
        title="Top by memory"
        rows={@memory}
        value_label="Memory"
        value_fn={&format_bytes(&1[:memory])}
      />
      <.proc_table
        title="Top by message queue"
        rows={@msgq}
        value_label="Queue"
        value_fn={&format_int(&1[:msg_queue_len])}
      />
    </section>
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :value_label, :string, required: true
  attr :value_fn, :any, required: true

  defp proc_table(assigns) do
    ~H"""
    <div class="rounded-[var(--radius-lg)] bg-[var(--mast-bg-card)] border border-[var(--mast-border)] overflow-hidden">
      <header class="flex items-center h-12 px-4 border-b border-[var(--mast-border)]">
        <h3 class="text-[14px] font-semibold text-[var(--mast-font-primary)]">{@title}</h3>
      </header>
      <div :if={@rows == []} class="px-4 py-6 text-[13px] text-[var(--mast-font-tertiary)]">
        No processes reported.
      </div>
      <table :if={@rows != []} class="w-full text-[12px]">
        <thead>
          <tr class="text-left text-[var(--mast-font-tertiary)]">
            <th class="font-medium px-4 py-2">Process</th>
            <th class="font-medium px-4 py-2 text-right">{@value_label}</th>
            <th class="font-medium px-4 py-2 text-right">Reductions</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={row <- @rows}
            class="border-t border-[var(--mast-border)]"
          >
            <td class="px-4 py-2 font-mono truncate max-w-[180px]">
              {row[:name] || row[:pid]}
            </td>
            <td class="px-4 py-2 text-right font-mono tabular-nums">{@value_fn.(row)}</td>
            <td class="px-4 py-2 text-right font-mono tabular-nums text-[var(--mast-font-secondary)]">
              {format_int(row[:reductions])}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp pct_of(nil, _), do: 0
  defp pct_of(_, 0), do: 0
  defp pct_of(v, total) when is_number(v), do: Float.round(v / total * 100, 2)
  defp pct_of(_, _), do: 0

  defp clamp_pct(nil), do: 0
  defp clamp_pct(v) when is_number(v), do: max(0, min(100, v))
  defp clamp_pct(_), do: 0

  defp format_pct(nil), do: "—"
  defp format_pct(v) when is_number(v), do: "#{:erlang.float_to_binary(v / 1, decimals: 1)}%"

  defp format_bytes(nil), do: "—"

  defp format_bytes(n) when is_number(n) do
    cond do
      n >= 1_073_741_824 -> "#{trim_float(n / 1_073_741_824)} GB"
      n >= 1_048_576 -> "#{trim_float(n / 1_048_576)} MB"
      n >= 1024 -> "#{trim_float(n / 1024)} KB"
      true -> "#{trunc(n)} B"
    end
  end

  defp format_bytes(_), do: "—"

  # ---- Header band ---------------------------------------------------------

  attr :app, :map, required: true
  attr :server, :map, required: true
  attr :release, :any, default: nil
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
          navigate={~p"/servers/#{@server.id}?tab=releases"}
          class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
        >
          Releases
        </.link>
        <%= if @release do %>
          <span class="text-[var(--mast-font-tertiary)]">/</span>
          <.link
            navigate={
              ~p"/servers/#{@server.id}/releases/#{Mast.Fleet.Release.effective_handle(@release)}"
            }
            class="text-[var(--mast-font-tertiary)] hover:text-[var(--mast-font-primary)]"
          >
            {Mast.Fleet.Release.effective_handle(@release)}
          </.link>
        <% end %>
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

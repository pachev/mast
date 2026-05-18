defmodule MastWeb.AppLive do
  @moduledoc """
  Detail view for one running Elixir application.

  Reads the persisted snapshot from `Mast.Apps`. The "Refresh" button
  enqueues an `AppProbe` job for the parent server, which updates this
  row via the PubSub broadcast.
  """
  use MastWeb, :live_view

  alias Mast.Apps

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Mast.PubSub, "servers")

    app = Apps.get_app!(String.to_integer(id))

    {:ok,
     socket
     |> assign(:page_title, app.name)
     |> assign(:app, app)
     |> assign(:refreshing?, false)}
  end

  @impl true
  def handle_info({:apps_updated, server_id}, socket) do
    if server_id == socket.assigns.app.server_id do
      app = Apps.get_app!(socket.assigns.app.id)
      {:noreply, socket |> assign(:app, app) |> assign(:refreshing?, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:apps_probe_failed, server_id, reason}, socket) do
    if server_id == socket.assigns.app.server_id do
      {:noreply,
       socket
       |> assign(:refreshing?, false)
       |> put_flash(:error, "Probe failed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh", _, socket) do
    %{server_id: socket.assigns.app.server_id}
    |> Mast.Workers.AppProbe.new()
    |> Oban.insert!()

    {:noreply, assign(socket, :refreshing?, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="servers" page_title={@app.name}>
      <nav class="text-sm text-[var(--mast-font-secondary)] mb-3">
        <.link navigate={~p"/"} class="hover:text-[var(--mast-font-primary)]">Servers</.link>
        <span class="mx-1.5">/</span>
        <.link
          navigate={~p"/servers/#{@app.server_id}?tab=apps"}
          class="hover:text-[var(--mast-font-primary)]"
        >
          {@app.server.name}
        </.link>
        <span class="mx-1.5">/</span>
        <span class="text-[var(--mast-font-primary)] font-mono">{@app.name}</span>
      </nav>

      <.ui_card class="mb-5">
        <:title>{@app.name}</:title>
        <:subtitle>
          <span class="font-mono">{@app.node_name}</span>
          <span class="mx-2 text-[var(--mast-font-tertiary)]">·</span>
          <.link navigate={~p"/servers/#{@app.server_id}"} class="hover:underline">
            {@app.server.name}
          </.link>
        </:subtitle>
        <:actions>
          <.ui_badge variant={status_variant(@app.status)}>{String.capitalize(@app.status)}</.ui_badge>
          <.ui_button
            variant="secondary"
            size="sm"
            icon="hero-arrow-path"
            phx-click="refresh"
            loading={@refreshing?}
            disabled={@refreshing?}
          >
            Refresh
          </.ui_button>
        </:actions>

        <dl class="grid grid-cols-2 lg:grid-cols-4 gap-y-4 text-sm">
          <div>
            <dt class="text-xs uppercase tracking-wider text-[var(--mast-font-secondary)]">Version</dt>
            <dd class="font-mono text-[var(--mast-font-primary)] mt-1">{@app.version || "—"}</dd>
          </div>
          <div>
            <dt class="text-xs uppercase tracking-wider text-[var(--mast-font-secondary)]">Memory</dt>
            <dd class="font-mono text-[var(--mast-font-primary)] mt-1">
              {format_mb(@app.memory_mb)}
            </dd>
          </div>
          <div>
            <dt class="text-xs uppercase tracking-wider text-[var(--mast-font-secondary)]">Processes</dt>
            <dd class="font-mono text-[var(--mast-font-primary)] mt-1">
              {@app.processes || "—"}
            </dd>
          </div>
          <div>
            <dt class="text-xs uppercase tracking-wider text-[var(--mast-font-secondary)]">Uptime</dt>
            <dd class="font-mono text-[var(--mast-font-primary)] mt-1">
              {format_uptime(@app.uptime_seconds)}
            </dd>
          </div>
        </dl>
      </.ui_card>

      <.ui_card :if={@app.last_seen_at}>
        <:title>Last probe</:title>
        <:subtitle>{format_relative(@app.last_seen_at)}</:subtitle>

        <pre class="font-mono text-xs text-[var(--mast-font-secondary)] bg-[var(--mast-bg-input)] rounded-[var(--radius-field)] p-3 overflow-x-auto"><%= Jason.encode!(@app.last_probe || %{}, pretty: true) %></pre>
      </.ui_card>
    </Layouts.app>
    """
  end

  defp status_variant("running"), do: "online"
  defp status_variant("stopped"), do: "offline"
  defp status_variant("unreachable"), do: "warning"
  defp status_variant(_), do: "neutral"

  defp format_mb(nil), do: "—"
  defp format_mb(n) when is_number(n), do: "#{n} MB"

  defp format_uptime(nil), do: "—"

  defp format_uptime(s) when is_integer(s) do
    cond do
      s < 60 -> "#{s}s"
      s < 3600 -> "#{div(s, 60)}m #{rem(s, 60)}s"
      s < 86_400 -> "#{div(s, 3600)}h #{rem(div(s, 60), 60)}m"
      true -> "#{div(s, 86_400)}d #{rem(div(s, 3600), 24)}h"
    end
  end

  defp format_relative(t) do
    diff = DateTime.diff(DateTime.utc_now(), t, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end

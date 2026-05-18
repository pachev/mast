defmodule MastWeb.AuditLive do
  @moduledoc """
  Audit log view. Currently renders mock entries — wire to a real audit
  table when that schema lands (see `gh issue` for tracking).
  """
  use MastWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit")
     |> assign(:filter, "")
     |> assign(:events, mock_events())}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, :filter, q)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="audit" page_title={@page_title}>
      <.ui_page_header title="Audit Log" subtitle="Track system events and changes over time">
        <:actions>
          <.ui_button variant="secondary" icon="hero-arrow-down-tray">Export</.ui_button>
        </:actions>
      </.ui_page_header>

      <.ui_card padded={false}>
        <div class="px-4 py-3 border-b border-[var(--mast-border)] flex items-center gap-3 flex-wrap">
          <form phx-change="filter" class="flex-1 min-w-64">
            <.ui_search name="q" value={@filter} placeholder="Search events..." />
          </form>
          <.ui_badge variant="neutral" dot={false}>{length(@events)} events</.ui_badge>
        </div>

        <div>
          <.ui_audit_row
            :for={e <- filter_events(@events, @filter)}
            variant={e.variant}
            actor={e.actor}
            verb={e.verb}
            target={e.target}
            time={e.time}
            detail={e.detail}
          />
        </div>
      </.ui_card>
    </Layouts.app>
    """
  end

  defp filter_events(events, ""), do: events

  defp filter_events(events, q) do
    s = String.downcase(q)

    Enum.filter(events, fn e ->
      String.contains?(String.downcase(e.verb), s) or
        String.contains?(String.downcase(e.target || ""), s) or
        String.contains?(String.downcase(e.actor), s)
    end)
  end

  defp mock_events do
    [
      %{
        variant: "scan",
        actor: "System",
        verb: "scanned",
        target: "web-prod-1",
        time: "2m ago",
        detail: "12 packages available"
      },
      %{
        variant: "action",
        actor: "System",
        verb: "applied 10 updates on",
        target: "web-prod-1",
        time: "8m ago",
        detail: nil
      },
      %{
        variant: "create",
        actor: "System",
        verb: "added monitor for",
        target: "fleet",
        time: "1h ago",
        detail: nil
      },
      %{
        variant: "failure",
        actor: "System",
        verb: "ssh key deploy failed on",
        target: "api-prod-2",
        time: "2h ago",
        detail: "Permission denied (publickey)"
      },
      %{
        variant: "action",
        actor: "System",
        verb: "apt smart list for",
        target: "upgradable packages",
        time: "4h ago",
        detail: nil
      },
      %{
        variant: "create",
        actor: "System",
        verb: "removed old staging from",
        target: "fleet",
        time: "yesterday",
        detail: nil
      },
      %{
        variant: "delete",
        actor: "System",
        verb: "deleted SSH key",
        target: "legacy",
        time: "2d ago",
        detail: nil
      },
      %{
        variant: "action",
        actor: "System",
        verb: "applied 3 updates on",
        target: "staging-1",
        time: "3d ago",
        detail: nil
      },
      %{
        variant: "key-create",
        actor: "System",
        verb: "registered ed25519 key",
        target: "deploy-2025",
        time: "1w ago",
        detail: nil
      }
    ]
  end
end

defmodule MastWeb.AuditLive do
  @moduledoc """
  Audit log view. Renders rows from `audit_events`, newest first.

  Presentation is derived from `event_type` + `metadata`. The schema
  intentionally has no presentation concern — adding a new event type
  here is a one-liner in `present/1` plus a `variant_for/1` clause.
  """
  use MastWeb, :live_view

  alias Mast.Audit
  alias MastWeb.Audit.Presenter

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit")
     |> assign(:filter, "")
     |> assign(:events, load_events())}
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
          <.ui_badge variant="neutral" dot={false}>
            {length(filter_events(@events, @filter))} events
          </.ui_badge>
        </div>

        <div
          :if={@events == []}
          class="px-6 py-12 text-center text-sm text-[var(--mast-font-secondary)]"
        >
          No audit events yet.
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

  defp load_events do
    Audit.list_recent(200) |> Enum.map(&Presenter.present/1)
  end

  defp filter_events(events, ""), do: events

  defp filter_events(events, q) do
    s = String.downcase(q)

    Enum.filter(events, fn e ->
      String.contains?(String.downcase(e.verb), s) or
        String.contains?(String.downcase(e.target || ""), s) or
        String.contains?(String.downcase(e.actor), s) or
        String.contains?(String.downcase(e.detail || ""), s)
    end)
  end
end

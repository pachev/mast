defmodule MastWeb.AuditLive do
  @moduledoc """
  Audit log view. Renders rows from `audit_events`, newest first.

  Presentation is derived from `event_type` + `metadata`. Filters narrow
  by `event_type`, `subject_type`, or a free-text search across the
  presented fields.
  """
  use MastWeb, :live_view

  alias Mast.Audit
  alias MastWeb.Audit.Presenter

  @event_type_options [
    {"All events", ""},
    {"Server added", "server.created"},
    {"Server removed", "server.deleted"},
    {"Key registered", "key.created"},
    {"Key deleted", "key.deleted"},
    {"Patch scan", "scan.run"},
    {"Apply updates", "apply.run"}
  ]

  @subject_type_options [
    {"All subjects", ""},
    {"Servers", "Server"},
    {"Private keys", "PrivateKey"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit")
     |> assign(:query, "")
     |> assign(:event_type, "")
     |> assign(:subject_type, "")
     |> assign(:events, Audit.list_recent(200))}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, :query, q)}
  end

  def handle_event("apply_filters", %{"filters" => f}, socket) do
    {:noreply,
     socket
     |> assign(:event_type, Map.get(f, "event_type", ""))
     |> assign(:subject_type, Map.get(f, "subject_type", ""))}
  end

  @impl true
  def render(assigns) do
    visible =
      assigns.events
      |> filter_by_type(assigns.event_type)
      |> filter_by_subject(assigns.subject_type)
      |> Enum.map(&Presenter.present/1)
      |> filter_by_query(assigns.query)

    assigns = assign(assigns, :visible, visible)

    ~H"""
    <Layouts.app flash={@flash} active="audit" page_title={@page_title}>
      <.ui_page_header title="Audit Log" subtitle="Track system events and changes across your fleet">
        <:actions>
          <.ui_badge variant="neutral" dot={false}>{length(@visible)} events</.ui_badge>
          <.ui_button variant="secondary" icon="hero-arrow-down-tray">Export</.ui_button>
        </:actions>
      </.ui_page_header>

      <div class="flex items-center gap-3 flex-wrap mb-4">
        <form phx-change="filter" class="flex-1 min-w-64">
          <.ui_search name="q" value={@query} placeholder="Search events..." />
        </form>

        <form id="audit-filters" phx-change="apply_filters" class="flex items-center gap-2">
          <select name="filters[event_type]" class="select select-sm w-40">
            <option
              :for={{label, value} <- event_type_options()}
              value={value}
              selected={value == @event_type}
            >
              {label}
            </option>
          </select>
          <select name="filters[subject_type]" class="select select-sm w-40">
            <option
              :for={{label, value} <- subject_type_options()}
              value={value}
              selected={value == @subject_type}
            >
              {label}
            </option>
          </select>
        </form>
      </div>

      <div class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] overflow-hidden">
        <div
          :if={@visible == []}
          class="px-6 py-12 text-center text-sm text-[var(--mast-font-secondary)]"
        >
          {empty_message(@events)}
        </div>

        <.ui_audit_row
          :for={e <- @visible}
          variant={e.variant}
          actor={e.actor}
          verb={e.verb}
          target={e.target}
          time={e.time}
          detail={e.detail}
        />
      </div>
    </Layouts.app>
    """
  end

  defp event_type_options, do: @event_type_options
  defp subject_type_options, do: @subject_type_options

  defp filter_by_type(events, ""), do: events
  defp filter_by_type(events, type), do: Enum.filter(events, &(&1.event_type == type))

  defp filter_by_subject(events, ""), do: events
  defp filter_by_subject(events, type), do: Enum.filter(events, &(&1.subject_type == type))

  defp filter_by_query(events, ""), do: events

  defp filter_by_query(events, q) do
    s = String.downcase(q)

    Enum.filter(events, fn e ->
      String.contains?(String.downcase(e.verb), s) or
        String.contains?(String.downcase(e.target || ""), s) or
        String.contains?(String.downcase(e.actor), s) or
        String.contains?(String.downcase(e.detail || ""), s)
    end)
  end

  defp empty_message([]), do: "No audit events yet."
  defp empty_message(_), do: "No events match these filters."
end

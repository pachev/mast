defmodule MastWeb.AuditLive do
  @moduledoc """
  Audit log view. Renders rows from `audit_events`, newest first, with
  cursor-based pagination. Filters and search push down into SQL via
  `Mast.Audit.list_page/1`.
  """
  use MastWeb, :live_view

  alias Mast.Audit
  alias MastWeb.Audit.Presenter

  @default_page_size 50
  @max_page_size 200

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
    {:ok, assign(socket, :page_title, "Audit")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "")
    event_type = Map.get(params, "event_type", "")
    subject_type = Map.get(params, "subject_type", "")
    page_size = parse_page_size(Map.get(params, "page_size"))

    %{events: events, next_cursor: next_cursor} =
      Audit.list_page(
        limit: page_size,
        query: query,
        event_type: event_type,
        subject_type: subject_type
      )

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:event_type, event_type)
     |> assign(:subject_type, subject_type)
     |> assign(:page_size, page_size)
     |> assign(:events, events)
     |> assign(:next_cursor, next_cursor)}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: path_for(socket, %{"q" => q}))}
  end

  def handle_event("apply_filters", %{"filters" => f}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         path_for(socket, %{
           "event_type" => Map.get(f, "event_type", ""),
           "subject_type" => Map.get(f, "subject_type", "")
         })
     )}
  end

  def handle_event("load_more", _params, %{assigns: %{next_cursor: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more", _params, socket) do
    %{events: more, next_cursor: next_cursor} =
      Audit.list_page(
        limit: socket.assigns.page_size,
        cursor: socket.assigns.next_cursor,
        query: socket.assigns.query,
        event_type: socket.assigns.event_type,
        subject_type: socket.assigns.subject_type
      )

    {:noreply,
     socket
     |> assign(:events, socket.assigns.events ++ more)
     |> assign(:next_cursor, next_cursor)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :visible, Enum.map(assigns.events, &Presenter.present/1))

    ~H"""
    <Layouts.app flash={@flash} active="audit" page_title={@page_title}>
      <.ui_page_header title="Audit Log" subtitle="Track system events and changes across your fleet">
        <:actions>
          <.ui_badge variant="neutral" dot={false}>{count_label(@visible, @next_cursor)}</.ui_badge>
          <.ui_button variant="secondary" icon="hero-arrow-down-tray">Export</.ui_button>
        </:actions>
      </.ui_page_header>

      <div class="flex items-center gap-3 flex-wrap mb-4">
        <form phx-change="filter" phx-debounce="200" class="flex-1 min-w-64">
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
          {empty_message(@query, @event_type, @subject_type)}
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

      <div :if={@next_cursor} class="flex justify-center mt-4">
        <.ui_button variant="secondary" phx-click="load_more">Load more</.ui_button>
      </div>
    </Layouts.app>
    """
  end

  defp event_type_options, do: @event_type_options
  defp subject_type_options, do: @subject_type_options

  defp count_label(visible, nil), do: "#{length(visible)} events"
  defp count_label(visible, _cursor), do: "newest #{length(visible)}"

  defp empty_message("", "", ""), do: "No audit events yet."
  defp empty_message(_, _, _), do: "No events match these filters."

  defp parse_page_size(nil), do: @default_page_size
  defp parse_page_size(""), do: @default_page_size

  defp parse_page_size(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} when n > 0 -> min(n, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp path_for(socket, overrides) do
    params =
      %{
        "q" => socket.assigns.query,
        "event_type" => socket.assigns.event_type,
        "subject_type" => socket.assigns.subject_type
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> Map.new()

    case params do
      empty when empty == %{} -> ~p"/audit"
      params -> ~p"/audit?#{params}"
    end
  end
end

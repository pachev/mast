defmodule MastWeb.AuditLive do
  @moduledoc """
  Audit log view. Renders rows from `audit_events`, newest first.

  Presentation is derived from `event_type` + `metadata`. The schema
  intentionally has no presentation concern — adding a new event type
  here is a one-liner in `present/1` plus a `variant_for/1` clause.
  """
  use MastWeb, :live_view

  alias Mast.Audit

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
    Audit.list_recent(200) |> Enum.map(&present/1)
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

  # Maps a raw Audit.Event row to the shape `ui_audit_row` expects.
  defp present(event) do
    %{
      variant: variant_for(event.event_type),
      actor: actor_label(event.actor_id),
      verb: verb_for(event.event_type),
      target: target_for(event),
      time: relative_time(event.inserted_at),
      detail: detail_for(event)
    }
  end

  defp variant_for("key.created"), do: "key-create"
  defp variant_for("key.deleted"), do: "delete"
  defp variant_for("server.created"), do: "create"
  defp variant_for("server.deleted"), do: "delete"
  defp variant_for("scan.run"), do: "scan"
  defp variant_for("apply.run"), do: "action"
  defp variant_for(_), do: "action"

  defp verb_for("key.created"), do: "registered SSH key"
  defp verb_for("key.deleted"), do: "deleted SSH key"
  defp verb_for("server.created"), do: "added server"
  defp verb_for("server.deleted"), do: "removed server"
  defp verb_for("scan.run"), do: "scanned"
  defp verb_for("apply.run"), do: "applied updates on"
  defp verb_for(type), do: type

  defp target_for(%{metadata: %{"server_name" => name}}) when is_binary(name), do: name
  defp target_for(%{metadata: %{"name" => name}}) when is_binary(name), do: name
  defp target_for(%{subject_type: t, subject_id: id}) when not is_nil(id), do: "#{t}##{id}"
  defp target_for(_), do: nil

  defp detail_for(%{event_type: "scan.run", metadata: meta}) do
    case meta do
      %{"outcome" => "ok", "updates_available" => n} -> "#{n} packages available"
      %{"outcome" => "error", "reason" => reason} -> reason
      %{"outcome" => "skip", "reason" => reason} -> reason
      _ -> nil
    end
  end

  defp detail_for(%{event_type: "apply.run", metadata: meta}) do
    case meta do
      %{"outcome" => "exit", "exit_code" => 0} -> "exit 0"
      %{"outcome" => "exit", "exit_code" => code} -> "exit #{code}"
      %{"outcome" => "error", "reason" => reason} -> reason
      _ -> nil
    end
  end

  defp detail_for(%{event_type: "key.created", metadata: %{"fingerprint" => fp}})
       when is_binary(fp),
       do: fp

  defp detail_for(_), do: nil

  defp actor_label(0), do: "System"
  defp actor_label(nil), do: "System"
  defp actor_label(id), do: "User ##{id}"

  defp relative_time(dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      seconds < 604_800 -> "#{div(seconds, 86_400)}d ago"
      true -> Calendar.strftime(dt, "%Y-%m-%d")
    end
  end
end

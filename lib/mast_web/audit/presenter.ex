defmodule MastWeb.Audit.Presenter do
  @moduledoc """
  Maps a raw `Mast.Audit.Event` to the shape `ui_audit_row` expects.

  Lives in `MastWeb` because it's a presentation concern. The audit
  schema itself stays free of UI knowledge.
  """

  @doc """
  Returns a map with `:variant`, `:actor`, `:verb`, `:target`, `:time`,
  `:detail` derived from `event_type` + `metadata`.
  """
  def present(event) do
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

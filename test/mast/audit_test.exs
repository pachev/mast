defmodule Mast.AuditTest do
  use Mast.DataCase, async: true

  alias Mast.Audit
  alias Mast.Audit.Event

  describe "log/1" do
    test "inserts an event with the required fields" do
      attrs = %{
        event_type: "test.example",
        subject_type: "Server",
        subject_id: 42,
        metadata: %{note: "hello"}
      }

      assert {:ok, %Event{} = event} = Audit.log(attrs)
      assert event.id
      assert event.event_type == "test.example"
      assert event.subject_type == "Server"
      assert event.subject_id == 42
      assert %DateTime{} = event.inserted_at

      reloaded = Mast.Repo.get!(Event, event.id)
      assert reloaded.metadata == %{"note" => "hello"}
    end

    test "returns an error changeset when event_type is missing" do
      assert {:error, %Ecto.Changeset{} = cs} = Audit.log(%{metadata: %{}})
      assert "can't be blank" in errors_on(cs).event_type
    end

    test "defaults metadata to an empty map" do
      assert {:ok, event} = Audit.log(%{event_type: "test.empty"})
      reloaded = Mast.Repo.get!(Event, event.id)
      assert reloaded.metadata == %{}
    end
  end

  describe "multi_log/3" do
    test "commits an audit event alongside a successful business operation" do
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:business, fn _repo, _changes -> {:ok, :did_work} end)
        |> Audit.multi_log(:audit, %{event_type: "biz.created"})

      assert {:ok, %{audit: %Event{} = event}} = Mast.Repo.transaction(multi)
      assert event.event_type == "biz.created"
    end

    test "rolls back the audit event if the business operation fails" do
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:business, fn _repo, _changes -> {:error, :nope} end)
        |> Audit.multi_log(:audit, %{event_type: "biz.created"})

      assert {:error, :business, :nope, _changes} = Mast.Repo.transaction(multi)
      assert Mast.Repo.aggregate(Event, :count) == 0
    end

    test "accepts a function that derives attrs from prior multi changes" do
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:business, fn _repo, _changes -> {:ok, %{id: 123}} end)
        |> Audit.multi_log(:audit, fn %{business: biz} ->
          %{
            event_type: "biz.created",
            subject_type: "Biz",
            subject_id: biz.id,
            metadata: %{ref: biz.id}
          }
        end)

      assert {:ok, %{audit: %Event{} = event}} = Mast.Repo.transaction(multi)
      reloaded = Mast.Repo.get!(Event, event.id)
      assert reloaded.subject_id == 123
      assert reloaded.metadata == %{"ref" => 123}
    end
  end

  describe "list_recent/1" do
    test "returns events newest first up to the limit" do
      for n <- 1..5 do
        Audit.log(%{event_type: "test.event_#{n}"})
      end

      events = Audit.list_recent(3)
      assert length(events) == 3
      assert hd(events).event_type == "test.event_5"
    end

    test "defaults to 50 when no limit is given" do
      for _ <- 1..3, do: Audit.log(%{event_type: "x"})
      assert length(Audit.list_recent()) == 3
    end
  end
end

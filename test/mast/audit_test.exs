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

  describe "list_for_subject/3" do
    test "returns only events matching the subject, newest first" do
      Audit.log(%{event_type: "a", subject_type: "Server", subject_id: 1})
      Audit.log(%{event_type: "b", subject_type: "Server", subject_id: 1})
      Audit.log(%{event_type: "c", subject_type: "Server", subject_id: 2})

      events = Audit.list_for_subject("Server", 1, 10)
      assert length(events) == 2
      assert Enum.all?(events, &(&1.subject_id == 1))
      assert hd(events).event_type == "b"
    end

    test "honors the limit" do
      for n <- 1..5 do
        Audit.log(%{event_type: "e#{n}", subject_type: "Server", subject_id: 7})
      end

      assert length(Audit.list_for_subject("Server", 7, 3)) == 3
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

  describe "list_page/1" do
    test "returns a page with events newest first and a next_cursor when more exist" do
      for n <- 1..5, do: Audit.log(%{event_type: "test.e#{n}"})

      assert %{events: events, next_cursor: cursor} = Audit.list_page(limit: 2)
      assert length(events) == 2
      assert hd(events).event_type == "test.e5"
      assert is_binary(cursor)
    end

    test "next_cursor is nil when the page exhausts the table" do
      for n <- 1..3, do: Audit.log(%{event_type: "test.e#{n}"})

      assert %{events: events, next_cursor: nil} = Audit.list_page(limit: 10)
      assert length(events) == 3
    end

    test "cursor pages through results without duplicates or gaps" do
      for n <- 1..7, do: Audit.log(%{event_type: "test.e#{n}"})

      %{events: page1, next_cursor: c1} = Audit.list_page(limit: 3)
      %{events: page2, next_cursor: c2} = Audit.list_page(limit: 3, cursor: c1)
      %{events: page3, next_cursor: c3} = Audit.list_page(limit: 3, cursor: c2)

      ids = Enum.map(page1 ++ page2 ++ page3, & &1.id)
      assert length(ids) == 7
      assert ids == Enum.uniq(ids)
      assert ids == Enum.sort(ids, :desc)
      assert c3 == nil
    end

    test "filters by event_type in SQL" do
      Audit.log(%{event_type: "key.created"})
      Audit.log(%{event_type: "scan.run"})
      Audit.log(%{event_type: "scan.run"})

      %{events: events} = Audit.list_page(event_type: "scan.run", limit: 50)
      assert length(events) == 2
      assert Enum.all?(events, &(&1.event_type == "scan.run"))
    end

    test "filters by subject_type in SQL" do
      Audit.log(%{event_type: "key.created", subject_type: "PrivateKey", subject_id: 1})
      Audit.log(%{event_type: "scan.run", subject_type: "Server", subject_id: 1})

      %{events: events} = Audit.list_page(subject_type: "Server", limit: 50)
      assert length(events) == 1
      assert hd(events).subject_type == "Server"
    end

    test "query filter does an ILIKE on event_type" do
      Audit.log(%{event_type: "key.created"})
      Audit.log(%{event_type: "scan.run"})

      %{events: events} = Audit.list_page(query: "scan", limit: 50)
      assert length(events) == 1
      assert hd(events).event_type == "scan.run"
    end

    test "filters apply across cursor pages" do
      for _ <- 1..4, do: Audit.log(%{event_type: "scan.run"})
      for _ <- 1..2, do: Audit.log(%{event_type: "key.created"})

      %{events: p1, next_cursor: c1} = Audit.list_page(event_type: "scan.run", limit: 3)

      %{events: p2, next_cursor: c2} =
        Audit.list_page(event_type: "scan.run", limit: 3, cursor: c1)

      assert length(p1) == 3
      assert length(p2) == 1
      assert c2 == nil
      assert Enum.all?(p1 ++ p2, &(&1.event_type == "scan.run"))
    end
  end
end

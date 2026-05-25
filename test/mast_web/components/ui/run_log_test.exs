defmodule MastWeb.Components.UI.RunLogTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias MastWeb.Components.UI.RunLog

  # The component renders the chrome (header badge, scroll region, footer) and
  # takes the log entries as its inner block, so the LiveView owns the stream.
  defp render_modal(status, opts \\ []) do
    assigns = %{
      id: "run-log",
      title: "Applying Updates — web-1",
      status: status,
      empty?: Keyword.get(opts, :empty?, false),
      body: Keyword.get(opts, :body, "")
    }

    render_component(
      fn assigns ->
        ~H"""
        <RunLog.ui_run_log_modal
          id={@id}
          title={@title}
          status={@status}
          empty?={@empty?}
          on_close={%Phoenix.LiveView.JS{}}
        >
          {Phoenix.HTML.raw(@body)}
        </RunLog.ui_run_log_modal>
        """
      end,
      assigns
    )
  end

  describe "ui_run_log_modal/1" do
    test "renders the title and the running badge" do
      html = render_modal(:running)
      assert html =~ "Applying Updates — web-1"
      assert html =~ "Running"
    end

    test "renders log entries passed as the inner block" do
      html = render_modal(:running, body: "<div>Reading package lists...</div>")
      assert html =~ "Reading package lists..."
    end

    test "done status shows a completed badge" do
      assert render_modal(:done) =~ "Completed"
    end

    test "error status shows a failed badge" do
      assert render_modal(:error) =~ "Failed"
    end

    test "wires the autoscroll hook on the log region" do
      assert render_modal(:running) =~ ~s(phx-hook="RunLogAutoScroll")
    end

    test "shows a waiting placeholder when empty" do
      assert render_modal(:running, empty?: true) =~ "Waiting for output"
    end
  end
end

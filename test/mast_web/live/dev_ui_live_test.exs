defmodule MastWeb.DevUiLiveTest do
  @moduledoc """
  Smoke test for the dev-only component showcase at `/dev/ui`. The page
  renders a sample of every `ui_*` component inside a width-frame so we
  can eyeball responsive behavior without resizing the OS window.
  """
  use MastWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "/dev/ui" do
    test "renders with section headers for each component family", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/dev/ui")

      # Each component family gets a section so engineers can scan the page.
      assert html =~ "Buttons"
      assert html =~ "Feedback"
      assert html =~ "Forms"
      assert html =~ "Containers"
      assert html =~ "Navigation"
      assert html =~ "Data"
      assert html =~ "Table"
      assert html =~ "Domain"

      # Width toggle covers phone (375), large phone (414), tablet (768),
      # small laptop (1024), and large desktop (1440).
      for w <- ~w(375 414 768 1024 1440) do
        assert html =~ ~s(phx-value-width="#{w}")
      end

      # Default frame is full-width — switching to mobile applies the max-w class.
      html_375 =
        view
        |> element("button[phx-value-width='375']")
        |> render_click()

      assert html_375 =~ "max-w-[375px]"
    end

    test "renders previews for the new Project components", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dev/ui")

      # ProjectGroup/Header (pen) preview.
      assert html =~ "Project group header"
      # Project badge preview.
      assert html =~ "Project badge"
    end
  end
end

defmodule MastWeb.Components.UI.ResponsiveTest do
  @moduledoc """
  Asserts mobile-friendly class hooks are present on the shared UI
  components. We only check for the responsive prefixes (e.g. `sm:`,
  `md:`, `flex-col`) — the visual outcome is validated by walking the
  app at ~375px in the browser.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MastWeb.Components.UI.Containers
  alias MastWeb.Components.UI.Data
  alias MastWeb.Components.UI.Domain
  alias MastWeb.Components.UI.Navigation
  alias MastWeb.Components.UI.Table

  describe "ui_table action_bar" do
    test "wraps and search grows full-width on narrow screens" do
      html =
        render_component(&Table.ui_table/1, %{
          id: "t",
          rows: [],
          col: [%{label: "A", inner_block: fn _, _ -> "a" end}],
          action_bar: [%{inner_block: fn _, _ -> "bar" end}]
        })

      assert html =~ "flex-wrap"
    end
  end

  describe "ui_table pagination" do
    test "stacks counter and controls on narrow widths" do
      html =
        render_component(&Table.ui_table/1, %{
          id: "t",
          rows: Enum.map(1..30, &%{n: &1}),
          col: [%{label: "N", inner_block: fn _, row -> "#{row.n}" end}],
          pagination: [%{page: 1, page_size: 10, total: 30, event: "go"}]
        })

      assert html =~ "flex-col sm:flex-row"
    end

    test "hides numbered page buttons on xs in favor of Prev/Next" do
      html =
        render_component(&Table.ui_table/1, %{
          id: "t",
          rows: Enum.map(1..30, &%{n: &1}),
          col: [%{label: "N", inner_block: fn _, row -> "#{row.n}" end}],
          pagination: [%{page: 1, page_size: 10, total: 30, event: "go"}]
        })

      # Numbered pages container must be hidden below sm
      assert html =~ "hidden sm:flex"
    end
  end

  describe "ui_sidebar" do
    test "hidden below lg, shown lg and up — iPad portrait gets the drawer" do
      html =
        render_component(&Navigation.ui_sidebar/1, %{
          active: "dashboard",
          nav: [
            %{
              key: "dashboard",
              navigate: "/",
              icon: "hero-squares-2x2",
              inner_block: fn _, _ -> "Dashboard" end
            }
          ]
        })

      assert html =~ "hidden lg:flex"
    end
  end

  describe "ui_mobile_drawer" do
    test "renders daisyUI drawer-side that's lg:hidden" do
      html =
        render_component(&Navigation.ui_mobile_drawer/1, %{
          toggle_id: "app-drawer",
          active: "dashboard",
          nav: [
            %{
              key: "dashboard",
              navigate: "/",
              icon: "hero-squares-2x2",
              inner_block: fn _, _ -> "Dashboard" end
            }
          ]
        })

      assert html =~ "drawer-side"
      assert html =~ "drawer-overlay"
      assert html =~ "lg:hidden"
      # Label points at the toggle checkbox so clicking it closes the drawer
      assert html =~ ~s(for="app-drawer")
    end
  end

  describe "ui_tabs" do
    test "scrolls horizontally and prevents wrap" do
      html =
        render_component(&Navigation.ui_tabs/1, %{
          active: "a",
          tab: [
            %{key: "a", event: "set", inner_block: fn _, _ -> "A" end},
            %{key: "b", event: "set", inner_block: fn _, _ -> "B" end}
          ]
        })

      assert html =~ "overflow-x-auto"
      assert html =~ "whitespace-nowrap"
    end
  end

  describe "ui_page_header" do
    test "stacks actions on narrow, side-by-side on sm+" do
      html =
        render_component(&Navigation.ui_page_header/1, %{
          title: "Hi",
          actions: [%{inner_block: fn _, _ -> "x" end}]
        })

      assert html =~ "flex-col sm:flex-row"
    end
  end

  describe "ui_card header" do
    test "stacks title above actions on narrow" do
      html =
        render_component(&Containers.ui_card/1, %{
          title: [%{inner_block: fn _, _ -> "T" end}],
          actions: [%{inner_block: fn _, _ -> "A" end}],
          inner_block: [%{inner_block: fn _, _ -> "body" end}]
        })

      assert html =~ "flex-col sm:flex-row"
    end
  end

  describe "ui_modal" do
    test "body has internal scroll region" do
      html =
        render_component(&Containers.ui_modal/1, %{
          id: "m",
          inner_block: [%{inner_block: fn _, _ -> "body" end}]
        })

      assert html =~ "overflow-y-auto"
      assert html =~ "max-h"
    end
  end

  describe "ui_kv_table" do
    test "rows stack label above value on narrow" do
      html =
        render_component(&Data.ui_kv_table/1, %{
          title: "Info",
          row: [%{label: "Node", inner_block: fn _, _ -> "n@h" end}]
        })

      assert html =~ "flex-col sm:flex-row"
    end
  end

  describe "ui_release_card" do
    test "metric strip stacks on narrow, row on sm+" do
      html =
        render_component(&Domain.ui_release_card/1, %{
          name: "app",
          version: "0.1.0",
          status: "running",
          memory_mb: 100,
          processes: 10,
          msg_queue: 0
        })

      assert html =~ "flex-col sm:flex-row"
    end
  end

  describe "ui_card_title" do
    test "wraps on narrow widths instead of cramping with a flex-1 spacer" do
      html =
        render_component(&Data.ui_card_title/1, %{
          icon: "hero-cube",
          color: "purple",
          inner_block: [%{inner_block: fn _, _ -> "Card title with icon" end}],
          meta: [%{inner_block: fn _, _ -> "3 running" end}]
        })

      # No flex-1 spacer that forces title + meta to share width.
      refute html =~ "flex-1"
      # Wraps when out of room.
      assert html =~ "flex-wrap"
      # Meta is pushed right via margin, not a spacer.
      assert html =~ "ml-auto"
    end
  end

  describe "ui_audit_row" do
    test "stacks time under body on narrow" do
      html =
        render_component(&Domain.ui_audit_row/1, %{
          actor: "System",
          verb: "scanned",
          target: "web-prod-1",
          time: "2m ago"
        })

      assert html =~ "flex-col sm:flex-row"
    end
  end
end

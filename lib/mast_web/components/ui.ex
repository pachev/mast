defmodule MastWeb.Components.UI do
  @moduledoc """
  Mast design-system component entrypoint. Maps the pencil component
  library (`components.pen`) to Phoenix function components.

  Token reference: see `docs/UI.md` for usage patterns and the full
  catalog. Tokens themselves live in `assets/css/app.css` under
  `:root` and `[data-theme=dark]` as `--mast-*` variables, with the
  daisyUI theme retuned to match.

  ## Usage

      use MastWeb.Components.UI

  brings every `ui_*` component plus the `show/2` and `hide/2` JS
  helpers into scope. Already wired into `MastWeb` html_helpers, so
  templates can call `<.ui_button>` etc. without any imports.

  ## Module map

  - `MastWeb.Components.UI.Buttons` — `ui_button`
  - `MastWeb.Components.UI.Feedback` — `ui_badge`, `ui_status_dot`, `ui_chip`
  - `MastWeb.Components.UI.Forms` — `ui_search`
  - `MastWeb.Components.UI.Containers` — `ui_card`, `ui_empty`, `ui_modal`, `ui_chart_card`
  - `MastWeb.Components.UI.Navigation` — `ui_tabs`, `ui_sidebar`, `ui_page_header`
  - `MastWeb.Components.UI.Data` — `ui_stat`, `ui_metric`, `ui_metric_tile`, `ui_stat_tile`, `ui_kv_table`, `ui_card_title`
  - `MastWeb.Components.UI.Table` — `ui_table`
  - `MastWeb.Components.UI.Domain` — `ui_server_card`, `ui_app_card`, `ui_app_row`, `ui_release_card`, `ui_log_entry`, `ui_audit_row`
  - `MastWeb.Components.UI.JS` — `show/2`, `hide/2`
  """

  defmacro __using__(_) do
    quote do
      import MastWeb.Components.UI.Buttons
      import MastWeb.Components.UI.Feedback
      import MastWeb.Components.UI.Forms
      import MastWeb.Components.UI.Containers
      import MastWeb.Components.UI.Navigation
      import MastWeb.Components.UI.Data
      import MastWeb.Components.UI.Table
      import MastWeb.Components.UI.Domain
      import MastWeb.Components.UI.Charts
      import MastWeb.Components.UI.JS
    end
  end
end

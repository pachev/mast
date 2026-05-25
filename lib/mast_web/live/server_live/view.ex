defmodule MastWeb.ServerLive.View do
  @moduledoc """
  Render template for `MastWeb.ServerLive`. State + event handlers live in the
  LiveView module; this file owns the top-level markup (run-log modal, header,
  tab dispatch). Each tab's body lives in its own `MastWeb.ServerLive.*` module.
  """
  use MastWeb, :html

  alias MastWeb.ServerLive.{Header, OverviewTab, ReleasesTab, SettingsTab, UpdatesTab}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="servers" page_title={@server.name}>
      <.ui_run_log_modal
        :if={@show_run_log?}
        id="apply-run-log"
        title={@run_title}
        status={@run_status}
        empty?={@log_count == 0}
        on_close={JS.push("close-run-log")}
      >
        <div id="apply-run-log-lines" phx-update="stream">
          <div :for={{dom_id, e} <- @streams.log} id={dom_id}>
            <.ui_log_entry kind={e.kind}>{e.data}</.ui_log_entry>
          </div>
        </div>
      </.ui_run_log_modal>

      <Header.detail_header
        server={@server}
        tab={@tab}
        scanning?={@scanning?}
        running?={@running?}
        probing?={@probing?}
        scan_error={@scan_error}
        project={@project}
      />

      <%= case @tab do %>
        <% "overview" -> %>
          <OverviewTab.render
            server={@server}
            apps={@apps}
            releases={@releases}
            activity={@activity}
            range={@range}
            series={@series}
            range_since={@range_since}
            range_until={@range_until}
            latest_sample={@latest_sample}
          />
        <% "releases" -> %>
          <ReleasesTab.render
            server={@server}
            releases={@releases}
            new_release_changeset={@new_release_changeset}
          />
        <% "updates" -> %>
          <UpdatesTab.render
            server={@server}
            scanning?={@scanning?}
            running?={@running?}
            scan_error={@scan_error}
            updates_page={@updates_page}
            updates_page_size={@updates_page_size}
            updates_filter={@updates_filter}
          />
        <% "settings" -> %>
          <SettingsTab.render
            server={@server}
            confirm_delete?={@confirm_delete?}
            confirm_name={@confirm_name}
            projects={@projects}
            project_form={@project_form}
          />
      <% end %>
    </Layouts.app>
    """
  end
end

defmodule MastWeb.ServerLive.UpdatesTab do
  @moduledoc """
  Updates tab for `MastWeb.ServerLive`: scan state + paginated package
  table.
  """
  use MastWeb, :html

  import MastWeb.ServerLive.Helpers

  alias Mast.Patches.Apt

  attr :server, :map, required: true
  attr :scanning?, :boolean, required: true
  attr :running?, :boolean, required: true
  attr :scan_error, :any, required: true
  attr :updates_page, :integer, required: true
  attr :updates_page_size, :integer, required: true
  attr :updates_filter, :string, required: true

  def render(assigns) do
    all = updates_list(assigns.server)
    filtered = filter_updates(all, assigns.updates_filter)
    state = empty_state(assigns.server, assigns.scanning?, all)

    page = assigns.updates_page
    page_size = assigns.updates_page_size
    total = length(filtered)
    page_rows = filtered |> Enum.drop((page - 1) * page_size) |> Enum.take(page_size)

    assigns =
      assigns
      |> assign(:updates, all)
      |> assign(:filtered_total, total)
      |> assign(:page_rows, page_rows)
      |> assign(:state, state)

    ~H"""
    <.ui_card padded={false}>
      <:header>
        <div class="flex items-center justify-between gap-3 w-full">
          <div>
            <h2 class="text-base font-semibold text-[var(--mast-font-primary)]">Available Updates</h2>
            <p class="text-xs text-[var(--mast-font-secondary)] mt-1">
              <.scan_status_text server={@server} scanning?={@scanning?} scan_error={@scan_error} />
            </p>
          </div>
          <.ui_badge :if={@updates != []} variant="warning">
            {length(@updates)} packages
          </.ui_badge>
        </div>
      </:header>

      <%= case @state do %>
        <% :scanning -> %>
          <.ui_empty
            icon="hero-magnifying-glass"
            title="Scanning…"
            body="Running apt list --upgradable on the host."
          />
        <% :never_scanned -> %>
          <.ui_empty
            icon="hero-magnifying-glass"
            title="Not scanned yet"
            body="Click Scan Updates above to check the host for available packages."
          />
        <% :clean -> %>
          <.ui_empty
            icon="hero-check-circle"
            title="All up to date"
            body="No package updates are available right now."
          />
        <% :has_updates -> %>
          <form id="updates-filter" phx-change="filter-updates" class="contents">
            <.ui_table id="updates-table" rows={@page_rows} size="sm">
              <:action_bar>
                <.ui_search
                  name="q"
                  value={@updates_filter}
                  placeholder="Filter packages..."
                  class="h-9 w-64"
                />
                <span class="flex-1" />
                <span class="text-xs text-[var(--mast-font-secondary)]">
                  {@filtered_total} package{if @filtered_total == 1, do: "", else: "s"}
                </span>
              </:action_bar>

              <:col
                :let={u}
                label="Package"
                class="font-mono font-medium text-[var(--mast-font-primary)]"
              >
                {u["package"]}
              </:col>
              <:col
                :let={u}
                label="Current"
                class="font-mono tabular-nums text-[var(--mast-font-secondary)]"
              >
                {u["current_version"]}
              </:col>
              <:col :let={u} label="New" class="font-mono tabular-nums text-[var(--mast-accent)]">
                {u["new_version"]}
              </:col>
              <:col :let={u} align="right">
                <.ui_button
                  variant="ghost"
                  size="sm"
                  phx-click="apply_package"
                  phx-value-name={u["package"]}
                  disabled={@running? or @scanning? or not Apt.safe_package_name?(u["package"])}
                >
                  Apply
                </.ui_button>
              </:col>

              <:pagination
                page={@updates_page}
                page_size={@updates_page_size}
                total={@filtered_total}
                event="goto-page"
              />
            </.ui_table>
          </form>
      <% end %>
    </.ui_card>
    """
  end

  attr :server, :map, required: true
  attr :scanning?, :boolean, required: true
  attr :scan_error, :any, required: true

  defp scan_status_text(assigns) do
    ~H"""
    <%= cond do %>
      <% @scan_error -> %>
        <span class="text-[var(--mast-status-offline)]">Scan failed: {@scan_error}</span>
      <% @scanning? -> %>
        Scanning…
      <% @server.last_scan_at -> %>
        Last scanned {format_relative(@server.last_scan_at)}.
        <%= if (@server.updates_available || 0) == 0 do %>
          Nothing to install.
        <% else %>
          {@server.updates_available} package(s) available.
        <% end %>
      <% true -> %>
        Not scanned yet.
    <% end %>
    """
  end

  defp filter_updates(updates, ""), do: updates
  defp filter_updates(updates, nil), do: updates

  defp filter_updates(updates, q) do
    q = String.downcase(q)
    Enum.filter(updates, fn u -> String.contains?(String.downcase(u["package"] || ""), q) end)
  end

  defp empty_state(_server, true, _updates), do: :scanning
  defp empty_state(%{last_scan_at: nil}, _, _), do: :never_scanned
  defp empty_state(_, _, []), do: :clean
  defp empty_state(_, _, _), do: :has_updates

  defp updates_list(%{last_scan: %{"updates" => updates}}) when is_list(updates), do: updates
  defp updates_list(_), do: []
end

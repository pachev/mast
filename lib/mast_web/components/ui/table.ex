defmodule MastWeb.Components.UI.Table do
  @moduledoc """
  Paginated daisyUI table component.
  """
  use Phoenix.Component

  @doc """
  Paginated daisyUI table.

      <.ui_table id="updates" rows={@page_rows} size="sm" zebra>
        <:col label="Package" :let={row}>{row["package"]}</:col>
        <:col label="Current" :let={row}>{row["current_version"]}</:col>
        <:col :let={row}>
          <.ui_button size="sm" variant="ghost" phx-click="apply_package">Apply</.ui_button>
        </:col>
        <:action_bar>
          <.ui_search name="q" />
          <.ui_badge>{@total} packages</.ui_badge>
        </:action_bar>
        <:pagination page={@page} page_size={@page_size} total={@total} event="goto-page" />
      </.ui_table>

  Uses daisyUI table classes (`table`, `table-zebra`, `table-sm|md|lg`,
  `table-pin-rows`). Wrap the search input in a parent form with
  `phx-change` to filter.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :zebra, :boolean, default: true
  attr :pin_rows, :boolean, default: false
  attr :empty, :string, default: "Nothing to show."

  slot :col do
    attr :label, :string
    attr :align, :string, values: ~w(left right center)
    attr :class, :any
  end

  slot :action_bar

  slot :pagination do
    attr :page, :integer
    attr :page_size, :integer
    attr :total, :integer
    attr :event, :string
  end

  def ui_table(assigns) do
    ~H"""
    <div
      id={@id}
      class="bg-[var(--mast-bg-card)] border border-[var(--mast-border)] rounded-[var(--radius-box)] overflow-hidden"
    >
      <div
        :if={@action_bar != []}
        class="px-4 py-3 border-b border-[var(--mast-border)] flex items-center gap-3"
      >
        {render_slot(@action_bar)}
      </div>

      <div class="overflow-x-auto">
        <table class={[
          "table w-full",
          @zebra && "table-zebra",
          @pin_rows && "table-pin-rows",
          "table-#{@size}"
        ]}>
          <thead class="bg-[var(--mast-bg-secondary)] text-[var(--mast-font-secondary)]">
            <tr>
              <th
                :for={col <- @col}
                class={[
                  "text-xs font-semibold uppercase tracking-wider",
                  ui_table_align_class(col)
                ]}
              >
                {col[:label]}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@rows == []}>
              <td
                colspan={length(@col)}
                class="text-center text-[var(--mast-font-tertiary)] italic py-8"
              >
                {@empty}
              </td>
            </tr>
            <tr :for={row <- @rows} class="hover:bg-[var(--mast-bg-card-hover)]">
              <td :for={col <- @col} class={[ui_table_align_class(col), col[:class]]}>
                {render_slot(col, row)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.ui_table_pagination :for={p <- @pagination} {p} />
    </div>
    """
  end

  defp ui_table_align_class(%{align: "right"}), do: "text-right"
  defp ui_table_align_class(%{align: "center"}), do: "text-center"
  defp ui_table_align_class(_), do: "text-left"

  attr :page, :integer, required: true
  attr :page_size, :integer, required: true
  attr :total, :integer, required: true
  attr :event, :string, required: true

  defp ui_table_pagination(assigns) do
    pages = ui_table_page_count(assigns.total, assigns.page_size)
    {from, to} = ui_table_range(assigns.page, assigns.page_size, assigns.total)

    assigns =
      assigns
      |> assign(:pages, pages)
      |> assign(:from, from)
      |> assign(:to, to)
      |> assign(:numbers, ui_table_page_numbers(assigns.page, pages))

    ~H"""
    <div
      :if={@total > 0}
      class="px-4 py-3 border-t border-[var(--mast-border)] flex items-center justify-between gap-3 text-xs text-[var(--mast-font-secondary)]"
    >
      <span>Showing {@from}-{@to} of {@total}</span>

      <div :if={@pages > 1} class="flex items-center gap-1">
        <button
          type="button"
          phx-click={@event}
          phx-value-page={@page - 1}
          disabled={@page <= 1}
          class="h-8 px-3 rounded-[var(--radius-field)] border border-[var(--mast-border)] hover:bg-[var(--mast-bg-card-hover)] disabled:opacity-40 disabled:cursor-not-allowed"
        >
          Previous
        </button>

        <%= for n <- @numbers do %>
          <%= if n == :gap do %>
            <span class="h-8 w-8 inline-flex items-center justify-center">…</span>
          <% else %>
            <button
              type="button"
              phx-click={@event}
              phx-value-page={n}
              class={[
                "h-8 w-8 rounded-[var(--radius-field)] tabular-nums",
                if(n == @page,
                  do: "bg-[var(--mast-accent)] text-[var(--mast-accent-text)]",
                  else: "hover:bg-[var(--mast-bg-card-hover)]"
                )
              ]}
            >
              {n}
            </button>
          <% end %>
        <% end %>

        <button
          type="button"
          phx-click={@event}
          phx-value-page={@page + 1}
          disabled={@page >= @pages}
          class="h-8 px-3 rounded-[var(--radius-field)] border border-[var(--mast-border)] hover:bg-[var(--mast-bg-card-hover)] disabled:opacity-40 disabled:cursor-not-allowed"
        >
          Next
        </button>
      </div>
    </div>
    """
  end

  defp ui_table_page_count(0, _), do: 1
  defp ui_table_page_count(total, size), do: max(1, ceil_div(total, size))
  defp ceil_div(a, b), do: div(a + b - 1, b)

  defp ui_table_range(_page, _size, 0), do: {0, 0}

  defp ui_table_range(page, size, total) do
    from = (page - 1) * size + 1
    to = min(page * size, total)
    {from, to}
  end

  defp ui_table_page_numbers(_current, total) when total <= 7,
    do: Enum.to_list(1..total)

  defp ui_table_page_numbers(current, total) do
    candidates =
      [1, total, current, current - 1, current + 1]
      |> Enum.filter(&(&1 >= 1 and &1 <= total))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.reduce(candidates, [], fn n, acc ->
      case acc do
        [] -> [n]
        [prev | _] when n - prev > 1 -> [n, :gap | acc]
        _ -> [n | acc]
      end
    end)
    |> Enum.reverse()
  end
end

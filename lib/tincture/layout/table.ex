defmodule Tincture.Layout.Table do
  @moduledoc """
  Tabular layout with headers, borders and automatic column widths.

  Pass `:auto` for the column spec to size columns from their content, or a
  list of explicit widths in points.

      rows = [
        ["Item", "Qty", "Total"],
        ["Widget", "2", "$40.00"],
        ["Gadget", "1", "$15.00"]
      ]

      {pdf, result} =
        Table.render(pdf, 50, 700, :auto, rows,
          header_rows: 1,
          header_font: "Helvetica-Bold",
          table_width: 500
        )

  Cell text is escaped, so values containing parentheses or backslashes cannot
  break the content stream. Cells wrap within their column, and `:valign`
  controls vertical alignment when a row's cells differ in height.
  """

  alias Tincture.Font.Context
  alias Tincture.PDF

  @type row :: [term()]

  @type option ::
          {:font, String.t()}
          | {:header_font, String.t()}
          | {:font_size, number()}
          | {:padding, number()}
          | {:valign, :top | :middle | :bottom}
          | {:border, boolean()}
          | {:header_rows, non_neg_integer()}
          | {:row_height, number()}
          | {:table_width, number()}
          | {:min_col_width, number()}

  defmodule RenderResult do
    @moduledoc """
    Where a rendered table ended, so the next element can be placed below it.
    """

    @type t :: %__MODULE__{
            widths: [float()],
            row_height: float(),
            height: float(),
            rows: non_neg_integer(),
            columns: non_neg_integer()
          }

    defstruct widths: [],
              row_height: 0.0,
              height: 0.0,
              rows: 0,
              columns: 0
  end

  @spec render(PDF.t(), number(), number(), [number()] | :auto, [row()], [option()]) ::
          {PDF.t(), RenderResult.t()}
  def render(%PDF{} = pdf, x, y, column_spec, rows, opts \\ [])
      when is_number(x) and is_number(y) and is_list(rows) and is_list(opts) do
    {normalized_rows, column_count} = normalize_rows(rows)
    padding = resolve_padding(opts)
    font_size = resolve_font_size(opts)
    row_height = resolve_row_height(opts, font_size, padding)
    context = Context.from_pdf(pdf)

    widths =
      resolve_widths(
        column_spec,
        normalized_rows,
        column_count,
        opts,
        padding,
        font_size,
        context
      )

    border? = Keyword.get(opts, :border, true)
    valign = resolve_valign(opts)
    font = Keyword.get(opts, :font, "Helvetica")
    header_font = Keyword.get(opts, :header_font, "Helvetica-Bold")
    header_rows = max(Keyword.get(opts, :header_rows, 0), 0)

    tag? = resolve_tagging(opts, pdf)

    layout = %{
      x: x * 1.0,
      y: y * 1.0,
      widths: widths,
      row_height: row_height,
      padding: padding,
      font_size: font_size,
      valign: valign,
      font: font,
      header_font: header_font,
      header_rows: header_rows,
      border?: border?,
      tag?: tag?
    }

    rendered_pdf =
      maybe_tag(pdf, tag?, :table, [], fn tagged_pdf ->
        render_rows(tagged_pdf, normalized_rows, layout)
      end)

    result = %RenderResult{
      widths: widths,
      row_height: row_height,
      height: row_height * length(normalized_rows),
      rows: length(normalized_rows),
      columns: column_count
    }

    {rendered_pdf, result}
  end

  # Header rows are wrapped in /THead and the rest in /TBody, which is what
  # lets a reader repeat headers when a table is spoken row by row.
  defp render_rows(pdf, rows, %{tag?: false} = layout) do
    draw_rows(pdf, Enum.with_index(rows), layout)
  end

  defp render_rows(pdf, rows, %{header_rows: 0} = layout) do
    indexed = Enum.with_index(rows)

    maybe_tag(pdf, true, :tbody, [], &draw_rows(&1, indexed, layout))
  end

  defp render_rows(pdf, rows, layout) do
    indexed = Enum.with_index(rows)
    {head, body} = Enum.split(indexed, layout.header_rows)

    pdf
    |> maybe_tag(true, :thead, [], &draw_rows(&1, head, layout))
    |> maybe_tag(body != [], :tbody, [], &draw_rows(&1, body, layout))
  end

  defp draw_rows(pdf, indexed_rows, layout) do
    Enum.reduce(indexed_rows, pdf, fn {row, row_index}, acc_pdf ->
      maybe_tag(acc_pdf, layout.tag?, :tr, [], &draw_row(&1, row, row_index, layout))
    end)
  end

  defp draw_row(pdf, row, row_index, layout) do
    {row_pdf, _cursor_x} =
      row
      |> Enum.with_index()
      |> Enum.reduce({pdf, layout.x}, fn {cell, col_index}, {row_acc_pdf, cursor_x} ->
        width = Enum.at(layout.widths, col_index)
        {next_pdf, _} = draw_cell(row_acc_pdf, cell, row_index, cursor_x, width, layout)
        {next_pdf, cursor_x + width}
      end)

    row_pdf
  end

  defp draw_cell(pdf, cell, row_index, cursor_x, width, layout) do
    row_top = layout.y - row_index * layout.row_height
    row_bottom = row_top - layout.row_height

    # A border is decoration, so in a tagged document it is an artifact rather
    # than untagged content - which would otherwise be read out as noise.
    with_border =
      if layout.border? do
        maybe_artifact(pdf, layout.tag?, fn acc ->
          Tincture.rectangle(acc, cursor_x, row_bottom, width, layout.row_height)
        end)
      else
        pdf
      end

    cell_text = to_string(cell)

    with_text =
      if cell_text == "" do
        with_border
      else
        header? = row_index < layout.header_rows
        font_name = if header?, do: layout.header_font, else: layout.font

        text_y =
          text_baseline_y(
            row_bottom,
            layout.row_height,
            layout.font_size,
            layout.padding,
            layout.valign
          )

        {cell_tag, cell_opts} = if header?, do: {:th, [scope: :column]}, else: {:td, []}

        maybe_tag(with_border, layout.tag?, cell_tag, cell_opts, fn acc ->
          acc
          |> Tincture.set_font(font_name, layout.font_size)
          |> Tincture.text_at(cursor_x + layout.padding, text_y, cell_text)
        end)
      end

    {with_text, cursor_x + width}
  end

  # Defaults to tagging only when the caller is already tagging. A table is the
  # one element that most needs structure, but adding it to a document with no
  # other structure produces a tree containing nothing else, which reads worse
  # than no tagging at all.
  defp resolve_tagging(opts, pdf) do
    case Keyword.get(opts, :tag, :auto) do
      :auto -> PDF.tagged?(pdf) or pdf.structure_stack != []
      true -> true
      false -> false
      other -> raise ArgumentError, ":tag must be true, false or :auto, got: #{inspect(other)}"
    end
  end

  defp maybe_tag(pdf, false, _tag, _opts, fun), do: fun.(pdf)
  defp maybe_tag(pdf, true, tag, opts, fun), do: Tincture.tag(pdf, tag, opts, fun)

  defp maybe_artifact(pdf, false, fun), do: fun.(pdf)
  defp maybe_artifact(pdf, true, fun), do: Tincture.artifact(pdf, fun)

  defp normalize_rows([]), do: raise(ArgumentError, "rows must not be empty")

  defp normalize_rows(rows) do
    unless Enum.all?(rows, &is_list/1) do
      raise ArgumentError, "rows must be a list of row lists"
    end

    [first | _] = rows
    column_count = length(first)

    if column_count < 1 do
      raise ArgumentError, "rows must contain at least one column"
    end

    unless Enum.all?(rows, &(length(&1) == column_count)) do
      raise ArgumentError, "all rows must have the same number of columns"
    end

    {rows, column_count}
  end

  defp resolve_widths(widths, _rows, column_count, _opts, _padding, _font_size, _context)
       when is_list(widths) do
    unless length(widths) == column_count do
      raise ArgumentError, "column width count must match row column count"
    end

    unless Enum.all?(widths, &(is_number(&1) and &1 > 0)) do
      raise ArgumentError, "column widths must be positive numbers"
    end

    Enum.map(widths, &(&1 * 1.0))
  end

  defp resolve_widths(:auto, rows, column_count, opts, padding, font_size, context) do
    font = Keyword.get(opts, :font, "Helvetica")
    min_col_width = Keyword.get(opts, :min_col_width, 20)

    unless is_number(min_col_width) and min_col_width > 0 do
      raise ArgumentError, "min_col_width must be a positive number"
    end

    base_widths =
      0..(column_count - 1)
      |> Enum.map(fn col ->
        max_text_width =
          Enum.reduce(rows, 0.0, fn row, acc ->
            cell = row |> Enum.at(col) |> to_string()
            max(acc, Context.text_width(context, font, font_size, cell))
          end)

        max(max_text_width + padding * 2, min_col_width * 1.0)
      end)

    case Keyword.get(opts, :table_width) do
      nil ->
        base_widths

      value when is_number(value) and value > 0 ->
        total = Enum.sum(base_widths)
        scale = value / total
        Enum.map(base_widths, &(&1 * scale))

      _ ->
        raise ArgumentError, "table_width must be a positive number"
    end
  end

  defp resolve_widths(other, _rows, _column_count, _opts, _padding, _font_size, _context) do
    raise ArgumentError, "unsupported column spec: #{inspect(other)}"
  end

  defp resolve_padding(opts) do
    case Keyword.get(opts, :padding, 4) do
      value when is_number(value) and value >= 0 -> value * 1.0
      _ -> raise ArgumentError, "padding must be a non-negative number"
    end
  end

  defp resolve_font_size(opts) do
    case Keyword.get(opts, :font_size, 12) do
      value when is_number(value) and value > 0 -> value * 1.0
      _ -> raise ArgumentError, "font_size must be a positive number"
    end
  end

  defp resolve_row_height(opts, font_size, padding) do
    case Keyword.get(opts, :row_height) do
      nil -> font_size * 1.4 + padding * 2
      value when is_number(value) and value > 0 -> value * 1.0
      _ -> raise ArgumentError, "row_height must be a positive number"
    end
  end

  defp resolve_valign(opts) do
    case Keyword.get(opts, :valign, :top) do
      value when value in [:top, :middle, :bottom] ->
        value

      _ ->
        raise ArgumentError, "valign must be :top, :middle, or :bottom"
    end
  end

  defp text_baseline_y(row_bottom, row_height, font_size, padding, valign) do
    ascender = font_size * 0.8
    descender = font_size * 0.2
    inner_height = max(row_height - 2.0 * padding, 0.0)
    glyph_height = ascender + descender
    slack = max(inner_height - glyph_height, 0.0)

    case valign do
      :top ->
        row_bottom + padding + descender + slack

      :middle ->
        row_bottom + padding + descender + slack / 2.0

      :bottom ->
        row_bottom + padding + descender
    end
  end
end

defmodule Tincture.PDF.Appearance do
  @moduledoc false
  # The normal appearance (/AP /N) of a text or choice field: what the field
  # shows wherever no viewer regenerates it - printing, thumbnails, static
  # renderers - and what every viewer shows before someone edits it.
  #
  # ISO 32000-1 12.7.3.3 fixes the stream's resources (from /DR), its /BBox
  # (from /Rect) and the /Tx marked content around the text, which a reader
  # replaces when it regenerates the appearance. It leaves layout to the
  # writer. The rules here follow what Adobe Acrobat Reader writes for the
  # same fields, measured from its saved appearance streams (Acrobat Reader
  # 2026.002.22031, Helvetica fields; docs/design/0.4.0-forms.md, section D):
  #
  #   * a line of text occupies a line box as tall as the font's bounding
  #     box, with its baseline the font's descender above the box's bottom.
  #     Measured: list rows and multiline leading 13.872 at size 12, which is
  #     12 x 1.156, Helvetica's FontBBox height (931 + 225); list baselines
  #     2.484 above the row, 12 x 0.207, its AFM descender;
  #   * a single line's box is centred in the field: baselines 4.9524 at size
  #     16.302 and 7.6615 at size 9 in a 22-point field, 6.0536 at 13.334 with
  #     a 2-point border, each within 0.001 of (h - box) / 2 + descender;
  #   * a single line's auto size fills the field less its border with a
  #     margin above and below: 16.302 for 22 points, 13.334 for 18, so
  #     size = (h - 2b) / (box + 2 x 0.0968), the margin the one constant
  #     fitted rather than taken from the font;
  #   * text starts at twice the border width from the edge: x 0 with no
  #     border, 4 with a 2-point one; right-aligned text ends at that padding,
  #     and centred text is centred on the full width;
  #   * a multiline field's first baseline is one line box below the top
  #     (42.128 in a 56-point field at size 12), each next one a line box
  #     lower;
  #   * a list box's rows start at the top edge, and the selected one is
  #     filled across the full width in Acrobat's colour, 0.600006 0.756866
  #     0.854904.
  #
  # Acrobat writes no clip and no q/Q, and neither does this. The text is
  # still clipped, by the form XObject's /BBox.
  #
  # An appearance is built as drawing operations, the same ones a page holds,
  # so font discovery sees its text and the shared content-stream writer
  # writes it. It is a function of the field alone: nothing is stored in the
  # document.

  alias Tincture.Font.Context
  alias Tincture.Font.Standard
  alias Tincture.PDF

  # Measured, above: the margin of Acrobat's single-line auto size, in ems.
  @auto_margin 0.0968
  # Acrobat's list-box and multiline auto size, measured at 12; and the
  # floor below which a size is not taken, the design's own.
  @list_size 12
  @multiline_start 12
  @min_size 4
  @auto_step 0.5
  # Bracketed, not pinned: see wrap/4.
  @wrap_inset 2
  @selection_color {0.600006, 0.756866, 0.854904}
  @black {0, 0, 0}
  # Helvetica's, for a font whose metrics are not available.
  @fallback_metrics %{line: 1.156, descent: 0.207}

  @field_flag_multiline 4096
  @field_flag_password 8192
  @field_flag_combo 131_072
  @field_flag_sort 524_288

  @typedoc """
  `border` is drawn before the /Tx marked content, so that a reader which
  regenerates the appearance keeps it; `content` is drawn inside it.
  `top_index` is the list box's /TI, or nil when it is not written.
  """
  @type t :: %{
          key: {:appearance, String.t(), non_neg_integer(), :n},
          width: number(),
          height: number(),
          border: [PDF.op()],
          content: [PDF.op()],
          top_index: non_neg_integer() | nil
        }

  @doc """
  The appearance of every text and choice field, by field name.
  """
  @spec build_all(PDF.t()) :: %{optional(String.t()) => t()}
  def build_all(%PDF{} = pdf) do
    context = Context.from_pdf(pdf)

    for %{type: type} = field <- pdf.form_fields, type in [:text, :choice], into: %{} do
      {field.name, build(field, context, metrics(pdf, field.font))}
    end
  end

  @doc """
  A choice field's options in the order they are written to /Opt: sorted when
  the field has the Sort flag, which is for writers (ISO 32000-1 Table 230),
  case-folded first and then by the text itself, so the order is
  deterministic.
  """
  @spec ordered_options(PDF.form_field()) :: [String.t()]
  def ordered_options(%{options: options, flags: flags}) do
    if flag?(flags, @field_flag_sort),
      do: Enum.sort_by(options, &{String.downcase(&1), &1}),
      else: options
  end

  # The font's line box (bounding-box height) and descender, in ems: from the
  # AFM for a standard font, from head and OS/2 (or hhea) for an embedded one.
  defp metrics(pdf, font) do
    case Standard.fetch_metrics(font) do
      {:ok, %{font_bbox: {_, y_min, _, y_max}, descender: descender}} ->
        %{line: (y_max - y_min) / 1000, descent: abs(descender) / 1000}

      _ ->
        embedded_metrics(Map.get(pdf.embedded_fonts, font))
    end
  end

  defp embedded_metrics(%{ttf_metrics: %{units_per_em: em, head_bbox: {_, y_min, _, y_max}} = m}) do
    descender = Map.get(m, :typo_descender) || Map.get(m, :hhea_descender, y_min)
    %{line: (y_max - y_min) / em, descent: abs(descender) / em}
  end

  defp embedded_metrics(_font), do: @fallback_metrics

  defp build(field, context, metrics) do
    {x1, y1, x2, y2} = field.rect
    width = x2 - x1
    height = y2 - y1
    border = border_width(field.border)
    box = %{w: width, h: height, border: border, pad: 2 * border, metrics: metrics}

    {content, top_index} = content(field, box, context)

    %{
      key: {:appearance, field.name, 0, :n},
      width: width,
      height: height,
      border: border_ops(border, width, height),
      content: content,
      top_index: top_index
    }
  end

  defp border_width(:none), do: 0
  defp border_width({_horizontal, _vertical, width}), do: width

  defp border_ops(0, _width, _height), do: []

  defp border_ops(b, width, height) do
    [
      {:set_stroke_color, @black},
      {:set_line_width, tidy(b)},
      {:rectangle, tidy(b / 2), tidy(b / 2), tidy(width - b), tidy(height - b), :stroke}
    ]
  end

  defp content(%{type: :text, flags: flags} = field, box, context) do
    cond do
      flag?(flags, @field_flag_password) -> {[], nil}
      flag?(flags, @field_flag_multiline) -> {multiline(field, box, context), nil}
      true -> {single_line(field, field.value, box, context), nil}
    end
  end

  defp content(%{type: :choice, flags: flags} = field, box, context) do
    if flag?(flags, @field_flag_combo),
      do: {single_line(field, field.value, box, context), nil},
      else: list_box(field, box, context)
  end

  # One line box, centred in the field.
  defp single_line(_field, "", _box, _context), do: []

  defp single_line(field, text, box, context) do
    size = field.size |> auto(fn -> single_line_auto_size(field, text, box, context) end)
    %{line: line, descent: descent} = box.metrics
    y = (box.h - line * size) / 2 + descent * size
    inked([text_op(field, text, size, x(field, text, size, box, context), y)])
  end

  # The size whose line box, with Acrobat's margin above and below, fills the
  # field less its border; then, if the text is wider than the space between
  # the paddings, scaled down to fit, but no smaller than 4.
  defp single_line_auto_size(field, text, box, context) do
    size = (box.h - 2 * box.border) / (box.metrics.line + 2 * @auto_margin)
    measured = measure(context, field, size, text)
    available = box.w - 2 * box.pad

    size =
      if measured > available and measured > 0, do: size * available / measured, else: size

    max(size, @min_size)
  end

  defp multiline(%{value: ""}, _box, _context), do: []

  defp multiline(field, box, context) do
    size = field.size |> auto(fn -> multiline_auto_size(field, box, context) end)
    leading = box.metrics.line * size
    first = box.h - leading

    field
    |> wrap(size, box, context)
    |> Enum.with_index()
    |> Enum.reject(fn {line, _index} -> line == "" end)
    |> Enum.map(fn {line, index} ->
      text_op(field, line, size, x(field, line, size, box, context), first - index * leading)
    end)
    |> inked()
  end

  # From 12 down in steps of 0.5 until the wrapped lines' boxes fit the
  # height, with a floor of 4; below it, the text is clipped.
  defp multiline_auto_size(field, box, context) do
    @multiline_start
    |> Stream.iterate(&(&1 - @auto_step))
    |> Enum.find(@min_size, fn size ->
      size <= @min_size or
        length(wrap(field, size, box, context)) * box.metrics.line * size <= box.h
    end)
    |> max(@min_size)
  end

  # Broken at every line break, then each paragraph wrapped greedily at
  # spaces to the space between the paddings, less 2 points a side. A word
  # wider than that stays whole and is clipped. Acrobat's wrap width is
  # bracketed, not pinned: in a 500-point field at size 12 it kept a line
  # 486.348 wide and broke one 499.692 wide, and 496 is the round value
  # between.
  defp wrap(field, size, box, context) do
    available = box.w - 2 * (box.pad + @wrap_inset)

    field.value
    |> String.split(["\r\n", "\n", "\r"])
    |> Enum.flat_map(&wrap_paragraph(&1, available, field, size, context))
  end

  defp wrap_paragraph(paragraph, available, field, size, context) do
    paragraph
    |> String.split(" ")
    |> Enum.reduce([], fn
      word, [] ->
        [word]

      word, [line | done] ->
        candidate = line <> " " <> word
        fits = measure(context, field, size, candidate) <= available
        if fits, do: [candidate | done], else: [word, line | done]
    end)
    |> Enum.reverse()
  end

  # Rows from the top edge in /Opt order, each a line box, the selected one
  # filled across the full width. When the selection would fall below the
  # box, /TI scrolls the list so it is visible and the box stays full.
  defp list_box(field, box, context) do
    size = auto(field.size, fn -> @list_size end)
    row = box.metrics.line * size
    rows = max(1, trunc(box.h / row))
    options = ordered_options(field)
    selected = Enum.find_index(options, &(&1 == field.value))
    top_index = top_index(selected, rows, length(options))

    # Each visible option with its index in /Opt and its slot in the box.
    visible =
      options
      |> Enum.with_index()
      |> Enum.drop(top_index || 0)
      |> Enum.take(rows)
      |> Enum.with_index()

    band =
      for {{_option, index}, slot} <- visible, index == selected do
        selection_band(row_bottom(box, row, slot), row, box)
      end

    {inked(List.flatten(band), list_texts(visible, field, size, box, context)), top_index}
  end

  defp list_texts(visible, field, size, box, context) do
    row = box.metrics.line * size

    for {{option, _index}, slot} <- visible, option != "" do
      y = row_bottom(box, row, slot) + box.metrics.descent * size
      text_op(field, option, size, x(field, option, size, box, context), y)
    end
  end

  # min(k, len - rows) for a selection below the visible rows; none otherwise.
  defp top_index(selected, rows, count) when is_integer(selected) and selected >= rows,
    do: min(selected, count - rows)

  defp top_index(_selected, _rows, _count), do: nil

  defp row_bottom(box, row, slot), do: box.h - (slot + 1) * row

  defp selection_band(bottom, row, box) do
    [
      {:set_fill_color, @selection_color},
      {:rectangle, 0, tidy(bottom), tidy(box.w), tidy(row), :fill}
    ]
  end

  # Inside the /Tx marking: the list box's selection band if any, then the
  # text in black. Nothing at all when there is nothing to draw.
  defp inked(texts), do: inked([], texts)

  defp inked([], []), do: []
  defp inked(band, texts), do: band ++ [{:set_fill_color, @black}] ++ texts

  defp x(field, text, size, box, context) do
    case Map.get(field, :align, :left) do
      :left -> tidy(box.pad)
      :center -> (box.w - measure(context, field, size, text)) / 2
      :right -> box.w - box.pad - measure(context, field, size, text)
    end
  end

  defp text_op(field, text, size, x, y),
    do: {:text_at, tidy(x), tidy(y), text, {field.font, tidy(size)}}

  defp measure(context, field, size, text),
    do: Context.text_width(context, field.font, size, text, on_unknown: :estimate)

  defp auto(0, compute), do: compute.()
  defp auto(size, _compute), do: size

  defp flag?(flags, bit), do: Bitwise.band(flags, bit) != 0

  # Four decimals, and a whole number written as an integer, so the stream
  # reads "0 9 Td" rather than carrying float noise.
  defp tidy(value) when is_integer(value), do: value

  defp tidy(value) do
    rounded = Float.round(value / 1, 4)
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end
end

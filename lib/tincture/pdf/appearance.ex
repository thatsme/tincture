defmodule Tincture.PDF.Appearance do
  @moduledoc false
  # The normal appearance (/AP /N) of a text or choice field: what the field
  # shows wherever no viewer regenerates it - printing, thumbnails, static
  # renderers - and what every viewer shows before someone edits it.
  #
  # ISO 32000-1 12.7.3.3 fixes the stream's resources (from /DR), its /BBox
  # (from /Rect) and the /Tx marked content around the text, which a reader
  # replaces when it regenerates the appearance. It leaves layout to the
  # writer: placement, padding, leading and the auto size are this module's
  # own rules, set out in docs/design/0.4.0-forms.md, section D.
  #
  # An appearance is built as drawing operations, the same ones a page holds,
  # so font discovery sees its text and the shared content-stream writer
  # writes it. It is a function of the field alone: nothing is stored in the
  # document.

  alias Tincture.Font.Context
  alias Tincture.PDF

  @max_auto_size 12
  @min_size 4
  @line_factor 1.15
  @auto_step 0.5
  @selection_color {0.6, 0.75, 0.9}
  @black {0, 0, 0}

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
      {field.name, build(field, context)}
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

  defp build(field, context) do
    {x1, y1, x2, y2} = field.rect
    width = x2 - x1
    height = y2 - y1
    border = border_width(field.border)
    box = %{w: width, h: height, inset: max(border, 1), pad: max(border, 1) + 1}

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

  # One line, centred vertically on TextExtent's box: ascent 0.75 and descent
  # 0.25 of the size.
  defp single_line(_field, "", _box, _context), do: []

  defp single_line(field, text, box, context) do
    size = field.size |> auto(fn -> single_line_auto_size(field, text, box, context) end)
    y = (box.h - size) / 2 + 0.25 * size
    framed([text_op(field, text, size, x(field, text, size, box, context), y)], box)
  end

  # The largest size up to 12 whose line fits the height; then, if the text
  # is wider than the box, scaled down to fit, but no smaller than 4.
  defp single_line_auto_size(field, text, box, context) do
    size = min(@max_auto_size, (box.h - 2 * box.inset) / @line_factor)
    measured = measure(context, field, size, text)
    available = box.w - 2 * box.pad

    size =
      if measured > available and measured > 0, do: size * available / measured, else: size

    max(size, @min_size)
  end

  defp multiline(%{value: ""}, _box, _context), do: []

  defp multiline(field, box, context) do
    size = field.size |> auto(fn -> multiline_auto_size(field, box, context) end)
    leading = @line_factor * size
    first = box.h - box.inset - 0.75 * size - (leading - size) / 2

    field
    |> wrap(size, box, context)
    |> Enum.with_index()
    |> Enum.reject(fn {line, _index} -> line == "" end)
    |> Enum.map(fn {line, index} ->
      text_op(field, line, size, x(field, line, size, box, context), first - index * leading)
    end)
    |> framed(box)
  end

  # From 12 down in steps of 0.5 until the wrapped text fits the height, with
  # a floor of 4; below it, the text is clipped.
  defp multiline_auto_size(field, box, context) do
    available = box.h - 2 * box.inset

    @max_auto_size
    |> Stream.iterate(&(&1 - @auto_step))
    |> Enum.find(@min_size, fn size ->
      size <= @min_size or
        length(wrap(field, size, box, context)) * @line_factor * size <= available
    end)
    |> max(@min_size)
  end

  # Broken at every line break, then each paragraph wrapped greedily at
  # spaces to the box's width. A word wider than the box stays whole and is
  # clipped.
  defp wrap(field, size, box, context) do
    available = box.w - 2 * box.pad

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

  # Rows top to bottom in /Opt order, the selected one on a filled band. When
  # the selection would fall below the box, /TI scrolls the list so it is
  # visible and the box stays full.
  defp list_box(field, box, context) do
    size = auto(field.size, fn -> @max_auto_size end)
    row = @line_factor * size
    rows = max(1, trunc((box.h - 2 * box.inset) / row))
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

    {framed(List.flatten(band), list_texts(visible, field, size, box, context), box), top_index}
  end

  defp list_texts(visible, field, size, box, context) do
    row = @line_factor * size

    for {{option, _index}, slot} <- visible, option != "" do
      y = row_bottom(box, row, slot) + (row - size) / 2 + 0.25 * size
      text_op(field, option, size, x(field, option, size, box, context), y)
    end
  end

  # min(k, len - rows) for a selection below the visible rows; none otherwise.
  defp top_index(selected, rows, count) when is_integer(selected) and selected >= rows,
    do: min(selected, count - rows)

  defp top_index(_selected, _rows, _count), do: nil

  defp row_bottom(box, row, slot), do: box.h - box.inset - (slot + 1) * row

  defp selection_band(bottom, row, box) do
    [
      {:set_fill_color, @selection_color},
      {:rectangle, tidy(box.inset), tidy(bottom), tidy(box.w - 2 * box.inset), tidy(row), :fill}
    ]
  end

  # Inside the /Tx marking: the clip to the box less its inset, the list
  # box's selection band if any, then the text in black. Nothing at all when
  # there is nothing to draw.
  defp framed(texts, box), do: framed([], texts, box)

  defp framed([], [], _box), do: []

  defp framed(band, texts, box) do
    [
      :save_state,
      {:rectangle, tidy(box.inset), tidy(box.inset), tidy(box.w - 2 * box.inset),
       tidy(box.h - 2 * box.inset), :none},
      :clip
    ] ++ band ++ [{:set_fill_color, @black}] ++ texts ++ [:restore_state]
  end

  defp x(field, text, size, box, context) do
    case Map.get(field, :align, :left) do
      :left -> box.pad
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
  # reads "2 9 Td" rather than carrying float noise.
  defp tidy(value) when is_integer(value), do: value

  defp tidy(value) do
    rounded = Float.round(value / 1, 4)
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end
end

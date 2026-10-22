defmodule Tincture.PDF.Ops do
  @moduledoc false

  alias Tincture.Font
  alias Tincture.PDF
  alias Tincture.PDF.Image

  @spec set_font(PDF.t(), String.t(), number()) :: PDF.t()
  def set_font(%PDF{} = pdf, font_name, size)
      when is_binary(font_name) and byte_size(font_name) > 0 and is_number(size) and size > 0 do
    if Font.font_available?(font_name) or Map.has_key?(pdf.embedded_fonts, font_name) do
      %PDF{pdf | current_font: {font_name, size}}
    else
      raise ArgumentError, "unknown font: #{font_name}"
    end
  end

  @spec text_at(PDF.t(), number(), number(), String.t()) :: PDF.t()
  def text_at(%PDF{} = pdf, x, y, text)
      when is_number(x) and is_number(y) and is_binary(text) do
    op = {:text_at, x, y, text, pdf.current_font}
    PDF.append_current_op(pdf, op)
  end

  @spec text_at_rotated(PDF.t(), number(), number(), number(), String.t()) :: PDF.t()
  def text_at_rotated(%PDF{} = pdf, x, y, angle_degrees, text)
      when is_number(x) and is_number(y) and is_number(angle_degrees) and is_binary(text) do
    op = {:text_at_rotated, x, y, angle_degrees, text, pdf.current_font}
    PDF.append_current_op(pdf, op)
  end

  @spec line(PDF.t(), number(), number(), number(), number(), PDF.paint()) :: PDF.t()
  def line(%PDF{} = pdf, x1, y1, x2, y2, paint \\ :stroke)
      when is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2) do
    PDF.append_current_op(pdf, {:line, x1, y1, x2, y2, normalize_paint(paint)})
  end

  @spec rectangle(PDF.t(), number(), number(), number(), number(), PDF.paint()) :: PDF.t()
  def rectangle(%PDF{} = pdf, x, y, width, height, paint \\ :stroke)
      when is_number(x) and is_number(y) and is_number(width) and is_number(height) do
    PDF.append_current_op(pdf, {:rectangle, x, y, width, height, normalize_paint(paint)})
  end

  @spec circle(PDF.t(), number(), number(), number(), PDF.paint()) :: PDF.t()
  def circle(%PDF{} = pdf, cx, cy, radius, paint \\ :stroke)
      when is_number(cx) and is_number(cy) and is_number(radius) and radius > 0 do
    PDF.append_current_op(pdf, {:circle, cx, cy, radius, normalize_paint(paint)})
  end

  # A path-painting operator ends the path, so a shape can be stroked, filled
  # or both - but only once. Emitting `S` unconditionally, as these did
  # before, made a filled rectangle impossible: the following `f` had no path
  # left to act on and silently did nothing.
  defp normalize_paint(paint)
       when paint in [:stroke, :fill, :fill_and_stroke, :fill_even_odd, :none],
       do: paint

  defp normalize_paint(other) do
    raise ArgumentError,
          "paint must be :stroke, :fill, :fill_and_stroke, :fill_even_odd or :none, " <>
            "got: #{inspect(other)}"
  end

  @spec set_stroke_color(PDF.t(), {number(), number(), number()}) :: PDF.t()
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def set_stroke_color(%PDF{} = pdf, {r, g, b})
      when is_number(r) and is_number(g) and is_number(b) and r >= 0 and r <= 1 and g >= 0 and
             g <= 1 and b >= 0 and b <= 1 do
    PDF.append_current_op(pdf, {:set_stroke_color, {r, g, b}})
  end

  @spec set_fill_color(PDF.t(), {number(), number(), number()}) :: PDF.t()
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def set_fill_color(%PDF{} = pdf, {r, g, b})
      when is_number(r) and is_number(g) and is_number(b) and r >= 0 and r <= 1 and g >= 0 and
             g <= 1 and b >= 0 and b <= 1 do
    PDF.append_current_op(pdf, {:set_fill_color, {r, g, b}})
  end

  @spec set_alpha(PDF.t(), number(), number()) :: PDF.t()
  def set_alpha(%PDF{} = pdf, fill_alpha, stroke_alpha)
      when is_number(fill_alpha) and fill_alpha >= 0 and fill_alpha <= 1 and
             is_number(stroke_alpha) and stroke_alpha >= 0 and stroke_alpha <= 1 do
    PDF.append_current_op(pdf, {:set_alpha, fill_alpha, stroke_alpha})
  end

  # `sh` paints the current clip region rather than a path, so the operation
  # carries the rectangle it should fill and the serialiser wraps it in its own
  # q/re/W n/Q. Doing it here rather than asking the caller to clip keeps the
  # gradient a single reversible step: clipping is state that outlives the call
  # that set it, and a stray clip is invisible until something later fails to
  # draw.
  @spec shading(PDF.t(), number(), number(), number(), number(), map()) :: PDF.t()
  def shading(%PDF{} = pdf, x, y, width, height, %{} = shading)
      when is_number(x) and is_number(y) and is_number(width) and is_number(height) and
             width > 0 and height > 0 do
    PDF.append_current_op(pdf, {:shading, x, y, width, height, shading})
  end

  @spec move_to(PDF.t(), number(), number()) :: PDF.t()
  def move_to(%PDF{} = pdf, x, y) when is_number(x) and is_number(y) do
    PDF.append_current_op(pdf, {:move_to, x, y})
  end

  @spec line_to(PDF.t(), number(), number()) :: PDF.t()
  def line_to(%PDF{} = pdf, x, y) when is_number(x) and is_number(y) do
    PDF.append_current_op(pdf, {:line_to, x, y})
  end

  @spec bezier(PDF.t(), number(), number(), number(), number(), number(), number()) :: PDF.t()
  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  def bezier(%PDF{} = pdf, x1, y1, x2, y2, x3, y3)
      when is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2) and is_number(x3) and
             is_number(y3) do
    PDF.append_current_op(pdf, {:bezier, x1, y1, x2, y2, x3, y3})
  end

  @spec stroke(PDF.t()) :: PDF.t()
  def stroke(%PDF{} = pdf), do: paint_open_path(pdf, :stroke, "stroke/1", ":stroke")

  @spec fill(PDF.t()) :: PDF.t()
  def fill(%PDF{} = pdf), do: paint_open_path(pdf, :fill, "fill/1", ":fill")

  @spec fill_even_odd(PDF.t()) :: PDF.t()
  def fill_even_odd(%PDF{} = pdf),
    do: paint_open_path(pdf, :fill_even_odd, "fill_even_odd/1", ":fill_even_odd")

  @spec clip(PDF.t()) :: PDF.t()
  def clip(%PDF{} = pdf), do: paint_open_path(pdf, :clip, "clip/1", ":none")

  @spec clip_even_odd(PDF.t()) :: PDF.t()
  def clip_even_odd(%PDF{} = pdf),
    do: paint_open_path(pdf, :clip_even_odd, "clip_even_odd/1", ":none")

  # A painting or clipping operator with no path open is invalid where it is
  # written (ISO 32000-1 §8.2, Figure 9): viewers skip it, so it never did
  # anything, and the usual cause is a shape that already painted itself
  # with its default :stroke. It is refused, with a message naming the fix.
  defp paint_open_path(%PDF{} = pdf, op, function, paint) do
    if path_open?(PDF.stream_operations(pdf, PDF.current_stream(pdf))) do
      PDF.append_current_op(pdf, op)
    else
      raise ArgumentError,
            "Tincture.#{function} was called with no open path, so there is nothing to " <>
              "#{if op in [:clip, :clip_even_odd], do: "clip to", else: "paint"}. A shape " <>
              "paints itself: pass its own paint argument (for example " <>
              "rectangle(pdf, x, y, w, h, #{paint})) instead, or start a path with move_to/3."
    end
  end

  # The path is open after move_to, line_to, bezier, or a shape drawn with
  # paint: :none, and closed by any painting or clipping operator - including
  # the one a shape writes for itself. Everything else leaves it as it was.
  # Also read by form XObjects, at the end of a callback and at a placement.
  @spec path_open?([PDF.op()]) :: boolean()
  def path_open?(ops) do
    {open?} =
      ops
      |> Enum.reverse()
      |> Enum.find_value({false}, fn op ->
        case path_kind(op) do
          :construction -> {true}
          :paint -> {false}
          nil -> nil
        end
      end)

    open?
  end

  defp path_kind({path_op, _x, _y}) when path_op in [:move_to, :line_to], do: :construction
  defp path_kind({:bezier, _x1, _y1, _x2, _y2, _x3, _y3}), do: :construction
  defp path_kind({:line, _x1, _y1, _x2, _y2, paint}), do: shape_kind(paint)
  defp path_kind({:rectangle, _x, _y, _w, _h, paint}), do: shape_kind(paint)
  defp path_kind({:circle, _cx, _cy, _r, paint}), do: shape_kind(paint)

  defp path_kind(op) when op in [:stroke, :fill, :fill_even_odd, :clip, :clip_even_odd],
    do: :paint

  defp path_kind(_op), do: nil

  defp shape_kind(:none), do: :construction
  defp shape_kind(_paint), do: :paint

  # A content tag or an artifact that closes while a path started inside it
  # is still open writes its EMC inside the path object (ISO 32000-1,
  # Figure 9). W5 checks only at the open, so this checks at the close. 0.4.0
  # raises; until then the call warns, and is written as before.
  @doc false
  @spec warn_closed_over_path(PDF.t(), String.t(), String.t()) :: :ok
  def warn_closed_over_path(%PDF{} = pdf, closed, block) do
    if path_started_inside_marked_content?(PDF.page_operations(pdf, pdf.current_page)) do
      IO.warn(
        "#{closed} with a path still open, so its end would be written inside the path, " <>
          "where PDF does not allow it. Paint the path with stroke/1, fill/1 or clip/1 " <>
          "before the #{block} closes. This will raise in 0.4.0."
      )
    end

    :ok
  end

  # Whether the path was open when the closing tag opened is read from the
  # operations already recorded, so nothing is stored for it. From the open
  # path's first construction operator on, a BDC means the innermost open tag
  # opened inside the path (W5's case, warned at the open), and an EMC means
  # an inner tag has already closed over the path (warned there). With
  # neither, the tag closing now is the first to close over a path started
  # inside it.
  defp path_started_inside_marked_content?(ops) do
    ops
    |> Enum.reverse()
    |> Enum.take_while(&(path_kind(&1) != :paint))
    |> Enum.reverse()
    |> Enum.drop_while(&(path_kind(&1) != :construction))
    |> case do
      [] -> false
      since_path_start -> not Enum.any?(since_path_start, &marked_content?/1)
    end
  end

  defp marked_content?({:begin_marked_content, _tag, _mcid}), do: true
  defp marked_content?({:begin_artifact}), do: true
  defp marked_content?({:end_marked_content}), do: true
  defp marked_content?(_op), do: false

  # A path object may hold only path construction until it is painted (ISO
  # 32000-1, Figure 9). Text, an image, a gradient, a q or Q, or marked
  # content written while a path is open lands inside it. Colour and line
  # settings do not: they are written before the path (PathState). 0.4.0
  # raises; until then the call warns, and is written as before.
  @doc false
  @spec warn_open_path(PDF.t(), String.t(), String.t()) :: :ok
  def warn_open_path(%PDF{} = pdf, caller, what) do
    if path_open?(PDF.stream_operations(pdf, PDF.current_stream(pdf))) do
      IO.warn(
        "#{caller} was called while a path is open, so #{what} would be written inside " <>
          "the path, where PDF does not allow it. A path holds only path construction " <>
          "until stroke/1, fill/1 or clip/1 paints it, or a shape's own paint argument " <>
          "does: paint the path first, or draw this before starting it. This will raise " <>
          "in 0.4.0."
      )
    end

    :ok
  end

  # A page left, or a document exported, with a path nothing painted: the
  # content stream would end inside the path object, so it is ended with `n`
  # (PathState), and the call warns. 0.4.0 raises.
  @doc false
  @spec warn_unpainted_path(PDF.t(), String.t()) :: :ok
  def warn_unpainted_path(%PDF{} = pdf, caller) do
    if path_open?(PDF.page_operations(pdf, pdf.current_page)) do
      IO.warn(
        "#{caller} was called while a path is open on page #{pdf.current_page} that nothing " <>
          "has painted. A path draws nothing until stroke/1, fill/1 or clip/1 paints it, so " <>
          "it is ended unpainted. Paint it, or remove it. This will raise in 0.4.0."
      )
    end

    :ok
  end

  @spec set_line_width(PDF.t(), number()) :: PDF.t()
  def set_line_width(%PDF{} = pdf, width) when is_number(width) and width >= 0 do
    PDF.append_current_op(pdf, {:set_line_width, width})
  end

  @spec set_line_cap(PDF.t(), 0 | 1 | 2) :: PDF.t()
  def set_line_cap(%PDF{} = pdf, cap) when cap in [0, 1, 2] do
    PDF.append_current_op(pdf, {:set_line_cap, cap})
  end

  @spec set_line_join(PDF.t(), 0 | 1 | 2) :: PDF.t()
  def set_line_join(%PDF{} = pdf, join) when join in [0, 1, 2] do
    PDF.append_current_op(pdf, {:set_line_join, join})
  end

  @spec set_dash(PDF.t(), [number()], number()) :: PDF.t()
  def set_dash(%PDF{} = pdf, pattern, phase)
      when is_list(pattern) and pattern != [] and is_number(phase) and phase >= 0 do
    if Enum.all?(pattern, &is_number/1) do
      PDF.append_current_op(pdf, {:set_dash, pattern, phase})
    else
      raise ArgumentError, "dash pattern must contain only numbers"
    end
  end

  @spec set_miter_limit(PDF.t(), number()) :: PDF.t()
  def set_miter_limit(%PDF{} = pdf, limit) when is_number(limit) and limit > 0 do
    PDF.append_current_op(pdf, {:set_miter_limit, limit})
  end

  @spec save_state(PDF.t()) :: PDF.t()
  def save_state(%PDF{} = pdf) do
    PDF.append_current_op(pdf, :save_state)
  end

  @spec restore_state(PDF.t()) :: PDF.t()
  def restore_state(%PDF{} = pdf) do
    PDF.append_current_op(pdf, :restore_state)
  end

  @spec image_jpeg(PDF.t(), number(), number(), number(), number(), Path.t()) :: PDF.t()
  def image_jpeg(%PDF{} = pdf, x, y, width, height, path)
      when is_number(x) and is_number(y) and is_number(width) and width > 0 and is_number(height) and
             height > 0 and is_binary(path) do
    image = Image.load_jpeg!(path)
    {pdf, image_id} = PDF.register_image(pdf, image)
    PDF.append_current_op(pdf, {:image, x, y, width, height, image_id})
  end

  @spec image_png(PDF.t(), number(), number(), number(), number(), Path.t()) :: PDF.t()
  def image_png(%PDF{} = pdf, x, y, width, height, path)
      when is_number(x) and is_number(y) and is_number(width) and width > 0 and is_number(height) and
             height > 0 and is_binary(path) do
    image = Image.load_png!(path)
    {pdf, image_id} = PDF.register_image(pdf, image)
    PDF.append_current_op(pdf, {:image, x, y, width, height, image_id})
  end
end

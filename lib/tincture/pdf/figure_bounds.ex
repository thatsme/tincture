defmodule Tincture.PDF.FigureBounds do
  @moduledoc false

  # The bounding box a tagged figure declares in its layout attributes
  # (ISO 32000-1 Table 344, BBox): the rectangle that completely encloses its
  # visible content, in default user space.
  #
  # It is computed by replaying a page's operations, so it sees exactly what
  # the serialiser will draw. Tincture has no operation that changes the
  # current transformation matrix - the one `cm` it writes is an image's own
  # placement, inside its own q/Q - so default user space is the space every
  # coordinate is already in, and only the line width has to be tracked
  # through q/Q.
  #
  # The result is conservative rather than tight. A Bezier contributes the
  # hull of its control points, and stroked geometry is inflated by half the
  # line width on every side, which covers butt, round and projecting caps but
  # not a long miter spike at a sharp corner. Text contributes the same
  # estimate a text link's clickable area uses (`TextExtent`): metric width,
  # three quarters of the size above the baseline and a quarter below, with
  # the corners rotated for rotated text.

  alias Tincture.PDF
  alias Tincture.PDF.TextExtent

  @type bbox :: {number(), number(), number(), number()}
  @type result :: {:ok, bbox()} | :no_content

  @typedoc "Measures text: `(font_name, size, text) -> {width, ascent, descent}`."
  @type measure :: (String.t(), number(), String.t() -> {number(), number(), number()})

  # PDF's initial line width (ISO 32000-1 Table 52).
  @default_line_width 1.0

  @doc """
  The bounding box of the marked content `mcid` opened in `ops`.

  `ops` runs from the start of the page to the point where the figure closes,
  so the marked content is open at the end of the list. `measure` gives the
  extent of a run of text, which needs the document's fonts.
  """
  @spec compute([PDF.op()], non_neg_integer(), measure()) :: result()
  def compute(ops, mcid, measure) do
    initial = %{
      widths: [@default_line_width],
      path: [],
      depth: nil,
      box: nil,
      measure: measure
    }

    case Enum.reduce(ops, initial, &step(&1, &2, mcid)) do
      %{box: nil} -> :no_content
      %{box: box} -> {:ok, box}
    end
  end

  # Marked content nests: once inside the figure, every BDC/BMC deepens and
  # every EMC returns, and the figure ends at the EMC matching its own BDC.
  defp step({:begin_marked_content, _tag, mcid}, %{depth: nil} = state, mcid),
    do: %{state | depth: 0}

  defp step({:begin_marked_content, _tag, _other}, %{depth: depth} = state, _mcid)
       when is_integer(depth),
       do: %{state | depth: depth + 1}

  defp step({:begin_artifact}, %{depth: depth} = state, _mcid) when is_integer(depth),
    do: %{state | depth: depth + 1}

  defp step({:end_marked_content}, %{depth: 0} = state, _mcid), do: %{state | depth: :closed}

  defp step({:end_marked_content}, %{depth: depth} = state, _mcid)
       when is_integer(depth) and depth > 0,
       do: %{state | depth: depth - 1}

  defp step({:set_line_width, width}, %{widths: [_current | saved]} = state, _mcid),
    do: %{state | widths: [width | saved]}

  defp step(:save_state, %{widths: [current | _saved] = widths} = state, _mcid),
    do: %{state | widths: [current | widths]}

  # An unbalanced Q is the caller's error; the serialiser writes it anyway, and
  # a reader keeps the outermost state, so this does too.
  defp step(:restore_state, %{widths: [_current | [_ | _] = saved]} = state, _mcid),
    do: %{state | widths: saved}

  defp step({:move_to, x, y}, state, _mcid), do: add_path(state, [{x, y}])
  defp step({:line_to, x, y}, state, _mcid), do: add_path(state, [{x, y}])

  defp step({:bezier, x1, y1, x2, y2, x3, y3}, state, _mcid),
    do: add_path(state, [{x1, y1}, {x2, y2}, {x3, y3}])

  defp step({:line, x1, y1, x2, y2, paint}, state, _mcid),
    do: state |> add_path([{x1, y1}, {x2, y2}]) |> paint(paint)

  defp step({:rectangle, x, y, width, height, paint}, state, _mcid),
    do: state |> add_path([{x, y}, {x + width, y + height}]) |> paint(paint)

  defp step({:circle, cx, cy, radius, paint}, state, _mcid),
    do:
      state |> add_path([{cx - radius, cy - radius}, {cx + radius, cy + radius}]) |> paint(paint)

  defp step(:stroke, state, _mcid), do: paint(state, :stroke)
  defp step(:fill, state, _mcid), do: paint(state, :fill)
  defp step(:fill_even_odd, state, _mcid), do: paint(state, :fill)

  # A clip ends the path without painting it.
  defp step(clip, state, _mcid) when clip in [:clip, :clip_even_odd], do: %{state | path: []}

  defp step({:image, x, y, width, height, _image_id}, state, _mcid),
    do: include(state, [{x, y}, {x + width, y + height}], 0)

  defp step({:shading, x, y, width, height, _shading}, state, _mcid),
    do: include(state, [{x, y}, {x + width, y + height}], 0)

  defp step({:text_at, x, y, text, font}, state, _mcid),
    do: include_text(state, x, y, 0, text, font)

  defp step({:text_at_rotated, x, y, angle_degrees, text, font}, state, _mcid),
    do: include_text(state, x, y, angle_degrees, text, font)

  defp step(_other, state, _mcid), do: state

  defp add_path(state, points), do: %{state | path: points ++ state.path}

  # Measured only inside the figure: measuring needs the fonts, and text
  # elsewhere on the page contributes nothing.
  defp include_text(%{depth: depth} = state, x, y, angle_degrees, text, {font_name, size})
       when is_integer(depth) do
    extent = state.measure.(font_name, size, text)
    include(state, TextExtent.corners(extent, x, y, angle_degrees), 0)
  end

  defp include_text(state, _x, _y, _angle_degrees, _text, _font), do: state

  defp paint(state, :none), do: state

  defp paint(%{path: points, widths: [width | _saved]} = state, paint) do
    inflation = if paint in [:stroke, :fill_and_stroke], do: width / 2, else: 0
    %{include(state, points, inflation) | path: []}
  end

  defp include(state, [], _inflation), do: state

  defp include(%{depth: depth} = state, points, inflation) when is_integer(depth) do
    xs = Enum.map(points, &elem(&1, 0))
    ys = Enum.map(points, &elem(&1, 1))

    box =
      {Enum.min(xs) - inflation, Enum.min(ys) - inflation, Enum.max(xs) + inflation,
       Enum.max(ys) + inflation}

    %{state | box: union(state.box, box)}
  end

  defp include(state, _points, _inflation), do: state

  defp union(nil, box), do: box

  defp union({l1, b1, r1, t1}, {l2, b2, r2, t2}),
    do: {min(l1, l2), min(b1, b2), max(r1, r2), max(t1, t2)}
end

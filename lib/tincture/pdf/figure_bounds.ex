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
  # not a long miter spike at a sharp corner.

  alias Tincture.PDF

  @type bbox :: {number(), number(), number(), number()}
  @type result :: {:ok, bbox()} | :contains_text | :no_content

  # PDF's initial line width (ISO 32000-1 Table 52).
  @default_line_width 1.0

  @doc """
  The bounding box of the marked content `mcid` opened in `ops`.

  `ops` runs from the start of the page to the point where the figure closes,
  so the marked content is open at the end of the list. Text inside the
  figure makes the box unknowable here, since a glyph's extent is not its
  advance width.
  """
  @spec compute([PDF.op()], non_neg_integer()) :: result()
  def compute(ops, mcid) do
    initial = %{
      widths: [@default_line_width],
      path: [],
      depth: nil,
      box: nil,
      text?: false
    }

    state = Enum.reduce(ops, initial, &step(&1, &2, mcid))

    cond do
      state.text? -> :contains_text
      state.box == nil -> :no_content
      true -> {:ok, state.box}
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

  defp step(text, %{depth: depth} = state, _mcid)
       when is_integer(depth) and elem(text, 0) in [:text_at, :text_at_rotated],
       do: %{state | text?: true}

  defp step(_other, state, _mcid), do: state

  defp add_path(state, points), do: %{state | path: points ++ state.path}

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

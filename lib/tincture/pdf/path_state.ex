defmodule Tincture.PDF.PathState do
  @moduledoc false

  # The order in which a content stream's operations are written, so that a
  # path object holds only what ISO 32000-1 allows in it.
  #
  # Figure 9 ("Graphics Objects", page 113) allows only path construction
  # inside a path object, then optionally W or W*, then a path-painting
  # operator that ends it. The operations are recorded in call order; this
  # decides the written order, and nothing else:
  #
  #   * a colour, line-style or alpha setter called while a path is open is
  #     written just before the path's first construction operator. §8.2
  #     (page 114) permits it: a writer "may change an arrangement of
  #     graphics state operators to any other arrangement that achieves the
  #     same values of the relevant graphics state parameters for each
  #     graphics object", and between the two points there is only path
  #     construction;
  #   * a shape drawn with paint: :none writes only its construction, and the
  #     path stays open for the next paint or clip. If something else comes
  #     first - an operation that is not path construction, painting or a
  #     setter, or the end of the stream - the path is ended there with `n`,
  #     followed by any setters, which is what :none always wrote;
  #   * a path built with move_to/line_to/bezier and never painted is ended
  #     with `n` at the end of the stream, which would otherwise end inside
  #     the path object.
  #
  # An operation that is neither construction, painting nor a setter, met
  # while such a path is open, is written where it was called, as before:
  # that is the case Tincture warns about.

  @setters [
    :set_fill_color,
    :set_stroke_color,
    :set_line_width,
    :set_line_cap,
    :set_line_join,
    :set_dash,
    :set_miter_limit,
    :set_alpha
  ]

  @paints [:stroke, :fill, :fill_even_odd, :clip, :clip_even_odd]

  @doc false
  @spec written_order([term()]) :: [term()]
  def written_order(operations) do
    {written, segment} = Enum.reduce(operations, {[], nil}, &step/2)
    written |> close(segment, :end) |> Enum.reverse()
  end

  # `segment` is nil when no path is open, or the open path's construction
  # and setters, each in call order (reversed), and whether its last
  # construction was a :none shape.
  defp step(op, {written, segment}) do
    case kind(op) do
      :construction ->
        segment = segment || %{construction: [], setters: [], none_last?: false}

        {written,
         %{segment | construction: [op | segment.construction], none_last?: none_shape?(op)}}

      :setter when segment != nil ->
        {written, %{segment | setters: [op | segment.setters]}}

      :paint when segment != nil ->
        {[op | flush(written, segment)], nil}

      _other when segment != nil ->
        {[op | close(written, segment, :other)], nil}

      _no_path ->
        {[op | written], nil}
    end
  end

  # The path is painted: setters first, then the path, then the paint.
  # `written` and the segment's lists are all reversed, so prepending the
  # construction before the setters writes the setters first.
  defp flush(written, segment), do: segment.construction ++ segment.setters ++ written

  # The path is not painted. Ended by a :none shape, it is ended with `n`
  # right after the construction and the setters follow, at the page level,
  # as :none always wrote it. Otherwise the setters go first; at the end of
  # the stream the path is ended with `n`.
  defp close(written, nil, _why), do: written

  defp close(written, %{none_last?: true} = segment, _why),
    do: segment.setters ++ [:end_path | segment.construction] ++ written

  defp close(written, segment, :end), do: [:end_path | flush(written, segment)]
  defp close(written, segment, :other), do: flush(written, segment)

  defp kind({path_op, _x, _y}) when path_op in [:move_to, :line_to], do: :construction
  defp kind({:bezier, _x1, _y1, _x2, _y2, _x3, _y3}), do: :construction
  defp kind({:line, _x1, _y1, _x2, _y2, :none}), do: :construction
  defp kind({:rectangle, _x, _y, _w, _h, :none}), do: :construction
  defp kind({:circle, _cx, _cy, _r, :none}), do: :construction
  defp kind({:line, _x1, _y1, _x2, _y2, _paint}), do: :paint
  defp kind({:rectangle, _x, _y, _w, _h, _paint}), do: :paint
  defp kind({:circle, _cx, _cy, _r, _paint}), do: :paint
  defp kind(op) when op in @paints, do: :paint
  defp kind(op) when is_tuple(op) and elem(op, 0) in @setters, do: :setter
  defp kind(_op), do: :other

  defp none_shape?({:line, _x1, _y1, _x2, _y2, :none}), do: true
  defp none_shape?({:rectangle, _x, _y, _w, _h, :none}), do: true
  defp none_shape?({:circle, _cx, _cy, _r, :none}), do: true
  defp none_shape?(_op), do: false
end

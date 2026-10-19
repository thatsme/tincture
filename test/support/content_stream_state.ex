defmodule Tincture.Test.ContentStreamState do
  @moduledoc """
  Checks the order of operators in content streams against the graphics-object
  state machine of ISO 32000-1 §8.2, Figure 9.

  A content stream is always in one of four states:

    * page description level, where it starts and must end;
    * a text object, from `BT` to `ET`;
    * a path object, from `m` or `re` until a path-painting operator;
    * a clipping path object, after `W` or `W*`, which only a path-painting
      operator may follow.

  Each state admits only the operator categories Figure 9 lists for it.
  Anything else is a violation: a painting operator with no path open, path
  construction inside a text object, `q` inside a text object, marked content
  in the middle of a path. Viewers skip such operators, and veraPDF does not
  check operator order, so without this nothing reports them.

  Marked content is balanced per stream: a sequence begun with `BDC` or `BMC`
  ends with `EMC` in the same stream (§14.6). An `EMC` with nothing open, or a
  stream that ends with a sequence open, is a violation - the shape a tag left
  open across a page break produces.

  Operators outside Figure 9 - the `BX`/`EX` compatibility section, the Type 3
  glyph operators `d0`/`d1`, or a misspelling - are reported as violations
  too. Tincture emits none of them; one appearing means the emitter changed and
  this checker needs to learn about it.

  `check_pdf/1` covers every page `/Contents` stream and every form XObject,
  reached through the cross-reference table. It reads the file as written, and
  refuses rather than skips anything it cannot read faithfully: a filtered
  stream it has to check, an encrypted document, an incremental update,
  object streams or a cross-reference stream.
  """

  alias Tincture.Test.PDFObjects

  @general_graphics_state ~w(w J j M d ri i gs)
  @special_graphics_state ~w(q Q cm)
  @color ~w(CS cs SC SCN sc scn G g RG rg K k)
  @text_state ~w(Tc Tw Tz TL Tf Tr Ts)
  @text_positioning ~w(Td TD Tm T*)
  @text_showing ["Tj", "TJ", "'", "\""]
  @marked_content ~w(MP DP BMC BDC EMC)
  @path_construction ~w(m l c v y h re)
  @path_painting ~w(S s f F f* B B* b b* n)
  @clipping ~w(W W*)

  @page_level @general_graphics_state ++
                @special_graphics_state ++
                @color ++ @text_state ++ @marked_content ++ ~w(Do sh BI)
  @in_text @general_graphics_state ++
             @color ++ @text_state ++ @text_positioning ++ @text_showing ++ @marked_content

  @operand_keywords ~w(true false null)
  @preceding 8

  @type state :: :page | :text | :path | :clip

  @type violation :: %{
          object: non_neg_integer() | nil,
          offset: non_neg_integer(),
          operator: String.t(),
          state: state(),
          preceding: [String.t()]
        }

  @doc """
  Checks every page content stream and form XObject in a PDF file.

  Returns the number of streams checked alongside the violations, so a caller
  can tell a clean document from one where nothing was found to check.
  """
  @spec check_pdf(binary()) :: %{streams: non_neg_integer(), violations: [violation()]}
  def check_pdf(pdf) when is_binary(pdf) do
    %{objects: objects} = PDFObjects.read(pdf)

    targets =
      objects
      |> Enum.flat_map(fn {number, object} -> stream_targets(number, object) end)
      |> Enum.uniq()
      |> Enum.sort()

    violations =
      Enum.flat_map(targets, fn number ->
        object = Map.fetch!(objects, number)
        {start, data} = stream_data!(pdf, number, object, objects)
        check_stream(data, object: number, base_offset: start)
      end)

    %{streams: length(targets), violations: violations}
  end

  @doc """
  Checks one content stream.

  `:object` labels the violations with the object the stream belongs to, and
  `:base_offset` is added to every offset so it points into the whole file.
  """
  @spec check_stream(binary(), keyword()) :: [violation()]
  def check_stream(data, opts \\ []) when is_binary(data) do
    context = %{
      object: Keyword.get(opts, :object),
      base: Keyword.get(opts, :base_offset, 0)
    }

    walk(data, 0, 0, {:page, 0}, [], [], context)
  end

  @doc """
  One line per violation, for an assertion message.
  """
  @spec format_violation(violation()) :: String.t()
  def format_violation(%{} = violation) do
    "object #{violation.object || "?"}, byte #{violation.offset}: `#{violation.operator}` " <>
      "in state #{violation.state} (preceded by: #{Enum.join(violation.preceding, " ")})"
  end

  ## The state machine

  # `marked` counts the marked-content sequences open in this stream. A
  # sequence has to end in the stream it began in (ISO 32000-1 §14.6), so an
  # EMC with none open, or a stream ending with one open, is a violation too.
  defp walk(data, pos, depth, {state, marked}, recent, violations, context) do
    case PDFObjects.next_token(data, pos) do
      :eof ->
        violations
        |> Enum.reverse()
        |> Kernel.++(end_of_stream(state, marked, byte_size(data), recent, context))

      {token, start, next} ->
        {depth, operator} = classify(token, depth)

        case operator do
          nil ->
            walk(data, next, depth, {state, marked}, recent, violations, context)

          "BI" ->
            {state, violations} =
              step(state, "BI", start, recent, violations, context)

            next = skip_inline_image!(data, next, context)
            walk(data, next, depth, {state, marked}, push(recent, "BI"), violations, context)

          operator ->
            {state, violations} = step(state, operator, start, recent, violations, context)

            {marked, violations} =
              balance(operator, marked, {state, start, recent, context}, violations)

            walk(data, next, depth, {state, marked}, push(recent, operator), violations, context)
        end
    end
  end

  defp balance(operator, marked, _at, violations) when operator in ["BDC", "BMC"],
    do: {marked + 1, violations}

  defp balance("EMC", 0, {state, start, recent, context}, violations),
    do:
      {0, [violation(context, start, "EMC (no marked content open)", state, recent) | violations]}

  defp balance("EMC", marked, _at, violations), do: {marked - 1, violations}
  defp balance(_operator, marked, _at, violations), do: {marked, violations}

  defp end_of_stream(state, marked, offset, recent, context) do
    unclosed_object =
      if state == :page,
        do: [],
        else: [violation(context, offset, "<end of stream>", state, recent)]

    unclosed_marked =
      if marked == 0,
        do: [],
        else: [
          violation(
            context,
            offset,
            "<end of stream, #{marked} marked-content sequence(s) open>",
            state,
            recent
          )
        ]

    unclosed_object ++ unclosed_marked
  end

  # Operands are skipped; only a keyword at nesting depth 0 is an operator.
  defp classify(token, depth) when token in [:array_open, :dict_open], do: {depth + 1, nil}

  defp classify(token, depth) when token in [:array_close, :dict_close],
    do: {max(depth - 1, 0), nil}

  defp classify({:keyword, word}, 0) when word not in @operand_keywords, do: {0, word}
  defp classify(_operand, depth), do: {depth, nil}

  defp step(state, operator, start, recent, violations, context) do
    case transition(state, operator) do
      {:ok, next_state} ->
        {next_state, violations}

      :error ->
        {state, [violation(context, start, operator, state, recent) | violations]}
    end
  end

  defp transition(:page, "BT"), do: {:ok, :text}
  defp transition(:page, operator) when operator in ["m", "re"], do: {:ok, :path}
  defp transition(:page, operator) when operator in @page_level, do: {:ok, :page}

  defp transition(:text, "ET"), do: {:ok, :page}
  defp transition(:text, operator) when operator in @in_text, do: {:ok, :text}

  defp transition(:path, operator) when operator in @path_construction, do: {:ok, :path}
  defp transition(:path, operator) when operator in @clipping, do: {:ok, :clip}
  defp transition(:path, operator) when operator in @path_painting, do: {:ok, :page}

  defp transition(:clip, operator) when operator in @path_painting, do: {:ok, :page}

  defp transition(_state, _operator), do: :error

  defp violation(context, offset, operator, state, recent) do
    %{
      object: context.object,
      offset: context.base + offset,
      operator: operator,
      state: state,
      preceding: Enum.reverse(recent)
    }
  end

  defp push(recent, operator), do: Enum.take([operator | recent], @preceding)

  ## Inline images

  # `BI <key value ...> ID <data> EI`. The data is binary and may contain any
  # byte sequence, `EI` included, so its length is computed from the image
  # dictionary whenever that is possible. Only an image too unusual to size
  # (a filtered one) falls back to looking for a whitespace-delimited `EI`.
  defp skip_inline_image!(data, pos, context) do
    {entries, after_id} = inline_image_dictionary!(data, pos, [], context)
    data_start = after_id + 1

    data_end =
      case inline_image_length(entries) do
        nil -> find_inline_image_end!(data, data_start, context)
        length -> data_start + length
      end

    case PDFObjects.next_token(data, data_end) do
      {{:keyword, "EI"}, _start, next} ->
        next

      _other ->
        raise ArgumentError,
              "object #{context.object || "?"}: inline image data is not followed by EI " <>
                "at byte #{context.base + data_end}"
    end
  end

  defp inline_image_dictionary!(data, pos, acc, context) do
    case PDFObjects.next_token(data, pos) do
      {{:keyword, "ID"}, _start, next} ->
        {Map.new(acc), next}

      {{:name, key}, _start, next} ->
        {value, next} = PDFObjects.parse_value(data, next)
        inline_image_dictionary!(data, next, [{key, value} | acc], context)

      _other ->
        raise ArgumentError,
              "object #{context.object || "?"}: malformed inline image dictionary at byte " <>
                "#{context.base + pos}"
    end
  end

  defp inline_image_length(entries) do
    get = fn short, long -> Map.get(entries, short, Map.get(entries, long)) end

    with nil <- get.("F", "Filter"),
         width when is_integer(width) <- get.("W", "Width"),
         height when is_integer(height) <- get.("H", "Height"),
         {bits, components} <- inline_image_format(entries, get) do
      height * div(width * components * bits + 7, 8)
    else
      _unsizable -> nil
    end
  end

  defp inline_image_format(entries, get) do
    if get.("IM", "ImageMask") == true do
      {1, 1}
    else
      with bits when is_integer(bits) <- get.("BPC", "BitsPerComponent"),
           components when is_integer(components) <-
             color_components(Map.get(entries, "CS", Map.get(entries, "ColorSpace"))) do
        {bits, components}
      end
    end
  end

  defp color_components({:name, name}) when name in ["G", "DeviceGray", "I", "Indexed"], do: 1
  defp color_components({:name, name}) when name in ["RGB", "DeviceRGB"], do: 3
  defp color_components({:name, name}) when name in ["CMYK", "DeviceCMYK"], do: 4
  defp color_components([{:name, name} | _rest]) when name in ["I", "Indexed"], do: 1
  defp color_components(_other), do: nil

  defp find_inline_image_end!(data, from, context) do
    case :binary.match(data, "EI", scope: {from, byte_size(data) - from}) do
      {at, 2} ->
        before_ok = at > from and PDFObjects.whitespace?(:binary.at(data, at - 1))

        after_ok =
          at + 2 == byte_size(data) or PDFObjects.delimiter_or_space?(:binary.at(data, at + 2))

        if before_ok and after_ok do
          at
        else
          find_inline_image_end!(data, at + 1, context)
        end

      :nomatch ->
        raise ArgumentError,
              "object #{context.object || "?"}: inline image starting at byte " <>
                "#{context.base + from} has no EI"
    end
  end

  defp stream_targets(number, %{value: %{} = dict, stream_at: stream_at}) do
    cond do
      Map.get(dict, "Type") == {:name, "ObjStm"} ->
        raise ArgumentError,
              "object #{number} is an object stream; objects inside it are not read"

      Map.get(dict, "Type") == {:name, "Page"} ->
        dict |> Map.get("Contents") |> List.wrap() |> Enum.map(&ref_number!(&1, number))

      Map.get(dict, "Subtype") == {:name, "Form"} and stream_at != nil ->
        [number]

      true ->
        []
    end
  end

  defp stream_targets(_number, _object), do: []

  defp ref_number!({:ref, target}, _owner), do: target

  defp ref_number!(other, owner),
    do:
      raise(
        ArgumentError,
        "object #{owner}: /Contents entry #{inspect(other)} is not a reference"
      )

  defp stream_data!(pdf, number, %{value: %{} = dict, stream_at: start}, objects)
       when is_integer(start) do
    if Map.has_key?(dict, "Filter") do
      raise ArgumentError,
            "object #{number} carries /Filter #{inspect(Map.get(dict, "Filter"))}; " <>
              "the checker reads unfiltered content streams only"
    end

    length =
      case Map.get(dict, "Length") do
        length when is_integer(length) -> length
        {:ref, target} -> objects |> Map.fetch!(target) |> Map.fetch!(:value)
      end

    {start, binary_part(pdf, start, length)}
  end

  defp stream_data!(_pdf, number, _object, _objects),
    do: raise(ArgumentError, "object #{number} is referenced as content but is not a stream")
end

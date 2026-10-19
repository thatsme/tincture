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
    {offsets, trailer} = read_xref(pdf)

    if Map.has_key?(trailer, "Encrypt") do
      raise ArgumentError, "the document is encrypted; its streams cannot be read as written"
    end

    objects = Map.new(offsets, fn {number, offset} -> {number, read_object(pdf, offset)} end)

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

    walk(data, 0, 0, :page, [], [], context)
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

  defp walk(data, pos, depth, state, recent, violations, context) do
    case next_token(data, pos) do
      :eof ->
        violations = Enum.reverse(violations)

        if state == :page do
          violations
        else
          violations ++ [violation(context, byte_size(data), "<end of stream>", state, recent)]
        end

      {token, start, next} ->
        {depth, operator} = classify(token, depth)

        case operator do
          nil ->
            walk(data, next, depth, state, recent, violations, context)

          "BI" ->
            {state, violations} =
              step(state, "BI", start, recent, violations, context)

            next = skip_inline_image!(data, next, context)
            walk(data, next, depth, state, push(recent, "BI"), violations, context)

          operator ->
            {state, violations} = step(state, operator, start, recent, violations, context)
            walk(data, next, depth, state, push(recent, operator), violations, context)
        end
    end
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

    case next_token(data, data_end) do
      {{:keyword, "EI"}, _start, next} ->
        next

      _other ->
        raise ArgumentError,
              "object #{context.object || "?"}: inline image data is not followed by EI " <>
                "at byte #{context.base + data_end}"
    end
  end

  defp inline_image_dictionary!(data, pos, acc, context) do
    case next_token(data, pos) do
      {{:keyword, "ID"}, _start, next} ->
        {Map.new(acc), next}

      {{:name, key}, _start, next} ->
        {value, next} = parse_value(data, next)
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
        before_ok = at > from and whitespace?(:binary.at(data, at - 1))
        after_ok = at + 2 == byte_size(data) or delimiter_or_space?(:binary.at(data, at + 2))

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

  ## The file structure

  defp read_xref(pdf) do
    xref_offset =
      case Regex.scan(~r/startxref\s+(\d+)/, pdf, capture: :all_but_first) do
        [] -> raise ArgumentError, "no startxref"
        matches -> matches |> List.last() |> hd() |> String.to_integer()
      end

    unless binary_part(pdf, xref_offset, 4) == "xref" do
      raise ArgumentError,
            "startxref points at byte #{xref_offset}, which is not a cross-reference " <>
              "table; cross-reference streams are not supported"
    end

    trailer_at = find!(pdf, "trailer", xref_offset)
    table = binary_part(pdf, xref_offset + 4, trailer_at - xref_offset - 4)
    {trailer, _next} = parse_value(pdf, trailer_at + byte_size("trailer"))

    if Map.has_key?(trailer, "Prev") do
      raise ArgumentError, "the document has an incremental update; only one xref section is read"
    end

    {parse_xref_table(table), trailer}
  end

  defp parse_xref_table(table) do
    table
    |> String.split(~r/\r\n|\r|\n/, trim: true)
    |> Enum.map(&String.split/1)
    |> Enum.reduce({nil, []}, fn
      [first, _count], {_next, acc} ->
        {String.to_integer(first), acc}

      [offset, _generation, "n"], {number, acc} ->
        {number + 1, [{number, String.to_integer(offset)} | acc]}

      [_offset, _generation, "f"], {number, acc} ->
        {number + 1, acc}
    end)
    |> elem(1)
  end

  defp read_object(pdf, offset) do
    {{:int, _number}, _, pos} = next_token(pdf, offset)
    {{:int, _generation}, _, pos} = next_token(pdf, pos)
    {{:keyword, "obj"}, _, pos} = next_token(pdf, pos)
    {value, pos} = parse_value(pdf, pos)

    case next_token(pdf, pos) do
      {{:keyword, "stream"}, _start, after_keyword} ->
        %{value: value, stream_at: stream_data_start(pdf, after_keyword)}

      _other ->
        %{value: value, stream_at: nil}
    end
  end

  # `stream` is followed by CRLF or LF, never CR alone (ISO 32000-1 §7.3.8.1).
  defp stream_data_start(pdf, pos) do
    case binary_part(pdf, pos, 2) do
      "\r\n" -> pos + 2
      <<"\n", _::binary>> -> pos + 1
      other -> raise ArgumentError, "stream keyword followed by #{inspect(other)}"
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

  defp find!(pdf, pattern, from) do
    case :binary.match(pdf, pattern, scope: {from, byte_size(pdf) - from}) do
      {at, _length} -> at
      :nomatch -> raise ArgumentError, "no #{pattern} after byte #{from}"
    end
  end

  ## Values

  # Enough of the object syntax to read dictionaries: references, arrays,
  # dictionaries, names, numbers, strings and the literal keywords.
  defp parse_value(data, pos) do
    case next_token(data, pos) do
      {:array_open, _start, next} ->
        parse_array(data, next, [])

      {:dict_open, _start, next} ->
        parse_dict(data, next, [])

      {{:int, first}, _start, next} ->
        maybe_reference(data, first, next)

      {{:keyword, "true"}, _start, next} ->
        {true, next}

      {{:keyword, "false"}, _start, next} ->
        {false, next}

      {{:keyword, "null"}, _start, next} ->
        {nil, next}

      {{:real, value}, _start, next} ->
        {value, next}

      {token, _start, next} when elem(token, 0) in [:name, :string, :hex_string] ->
        {token, next}

      other ->
        raise ArgumentError, "unexpected #{inspect(other)} at byte #{pos}"
    end
  end

  defp maybe_reference(data, first, pos) do
    with {{:int, _generation}, _, after_generation} <- next_token(data, pos),
         {{:keyword, "R"}, _, after_r} <- next_token(data, after_generation) do
      {{:ref, first}, after_r}
    else
      _not_a_reference -> {first, pos}
    end
  end

  defp parse_array(data, pos, acc) do
    case next_token(data, pos) do
      {:array_close, _start, next} ->
        {Enum.reverse(acc), next}

      _value ->
        {value, next} = parse_value(data, pos)
        parse_array(data, next, [value | acc])
    end
  end

  defp parse_dict(data, pos, acc) do
    case next_token(data, pos) do
      {:dict_close, _start, next} ->
        {Map.new(acc), next}

      {{:name, key}, _start, next} ->
        {value, next} = parse_value(data, next)
        parse_dict(data, next, [{key, value} | acc])

      other ->
        raise ArgumentError, "expected a dictionary key at byte #{pos}, got #{inspect(other)}"
    end
  end

  ## Tokens

  # Returns `{token, start, next}` or `:eof`. `start` is the token's first
  # byte; `next` is where scanning resumes.
  defp next_token(data, pos) do
    pos = skip_space_and_comments(data, pos)

    if pos >= byte_size(data) do
      :eof
    else
      read_token(data, pos)
    end
  end

  defp read_token(data, pos) do
    case binary_part(data, pos, min(2, byte_size(data) - pos)) do
      "<<" -> {:dict_open, pos, pos + 2}
      ">>" -> {:dict_close, pos, pos + 2}
      <<"<", _::binary>> -> read_hex_string(data, pos)
      <<"(", _::binary>> -> read_literal_string(data, pos)
      <<"[", _::binary>> -> {:array_open, pos, pos + 1}
      <<"]", _::binary>> -> {:array_close, pos, pos + 1}
      <<"{", _::binary>> -> {:array_open, pos, pos + 1}
      <<"}", _::binary>> -> {:array_close, pos, pos + 1}
      <<"/", _::binary>> -> read_name(data, pos)
      _regular -> read_regular(data, pos)
    end
  end

  defp read_hex_string(data, pos) do
    close = find!(data, ">", pos + 1)
    {{:hex_string, binary_part(data, pos + 1, close - pos - 1)}, pos, close + 1}
  end

  # Balanced parentheses nest; a backslash escapes the byte after it, which
  # covers \( \) \\ and the rest. Octal escapes need no special handling: their
  # digits are never parentheses.
  defp read_literal_string(data, pos) do
    close = literal_string_end(data, pos + 1, 1)
    {{:string, binary_part(data, pos + 1, close - pos - 1)}, pos, close + 1}
  end

  defp literal_string_end(data, pos, _depth) when pos >= byte_size(data),
    do: raise(ArgumentError, "unterminated literal string")

  defp literal_string_end(data, pos, depth) do
    case :binary.at(data, pos) do
      ?\\ -> literal_string_end(data, pos + 2, depth)
      ?( -> literal_string_end(data, pos + 1, depth + 1)
      ?) when depth == 1 -> pos
      ?) -> literal_string_end(data, pos + 1, depth - 1)
      _other -> literal_string_end(data, pos + 1, depth)
    end
  end

  defp read_name(data, pos) do
    stop = regular_end(data, pos + 1)
    {{:name, binary_part(data, pos + 1, stop - pos - 1)}, pos, stop}
  end

  defp read_regular(data, pos) do
    stop = regular_end(data, pos)

    if stop == pos do
      raise ArgumentError, "unexpected byte #{inspect(<<:binary.at(data, pos)>>)} at #{pos}"
    end

    word = binary_part(data, pos, stop - pos)

    token =
      cond do
        word =~ ~r/\A[+-]?\d+\z/ -> {:int, String.to_integer(word)}
        word =~ ~r/\A[+-]?(\d+\.\d*|\.\d+)\z/ -> {:real, parse_real(word)}
        true -> {:keyword, word}
      end

    {token, pos, stop}
  end

  defp parse_real(word) do
    {value, ""} = word |> String.replace(~r/\A([+-]?)\./, "\\g{1}0.") |> Float.parse()
    value
  end

  defp regular_end(data, pos) do
    if pos < byte_size(data) and not delimiter_or_space?(:binary.at(data, pos)) do
      regular_end(data, pos + 1)
    else
      pos
    end
  end

  defp skip_space_and_comments(data, pos) do
    cond do
      pos >= byte_size(data) ->
        pos

      whitespace?(:binary.at(data, pos)) ->
        skip_space_and_comments(data, pos + 1)

      :binary.at(data, pos) == ?% ->
        data |> skip_comment(pos) |> then(&skip_space_and_comments(data, &1))

      true ->
        pos
    end
  end

  defp skip_comment(data, pos) do
    if pos < byte_size(data) and :binary.at(data, pos) not in [?\r, ?\n] do
      skip_comment(data, pos + 1)
    else
      pos
    end
  end

  defp whitespace?(byte), do: byte in [0, ?\t, ?\n, ?\f, ?\r, ?\s]

  defp delimiter_or_space?(byte),
    do: whitespace?(byte) or byte in [?(, ?), ?<, ?>, ?[, ?], ?{, ?}, ?/, ?%]
end

defmodule Tincture.Test.PDFObjects do
  @moduledoc """
  Reads the objects of a PDF file as written: the cross-reference table, each
  indirect object's value, and where its stream data starts.

  Enough of the syntax for the files Tincture writes - one classic xref table,
  uncompressed objects - and it refuses the rest rather than misreading it: an
  encrypted document, an incremental update, a cross-reference stream.

  Values are plain terms: a dictionary is a map keyed by name without the
  slash, a name is `{:name, "Page"}`, a reference `{:ref, number}`, an array a
  list, and `true`/`false`/`null` are `true`/`false`/`nil`.
  """

  @type object :: %{value: term(), stream_at: non_neg_integer() | nil}

  @doc """
  Every in-use object, by number, and the trailer dictionary.
  """
  @spec read(binary()) :: %{objects: %{non_neg_integer() => object()}, trailer: map()}
  def read(pdf) when is_binary(pdf) do
    {offsets, trailer} = read_xref(pdf)

    if Map.has_key?(trailer, "Encrypt") do
      raise ArgumentError, "the document is encrypted; its streams cannot be read as written"
    end

    %{
      objects: Map.new(offsets, fn {number, offset} -> {number, read_object(pdf, offset)} end),
      trailer: trailer
    }
  end

  @doc """
  Follows a reference to the value of the object it names; any other value is
  returned as it is.
  """
  @spec resolve(term(), %{non_neg_integer() => object()}) :: term()
  def resolve({:ref, number}, objects), do: objects |> Map.fetch!(number) |> Map.fetch!(:value)
  def resolve(value, _objects), do: value

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

  @doc false
  def find!(pdf, pattern, from) do
    case :binary.match(pdf, pattern, scope: {from, byte_size(pdf) - from}) do
      {at, _length} -> at
      :nomatch -> raise ArgumentError, "no #{pattern} after byte #{from}"
    end
  end

  ## Values

  # Enough of the object syntax to read dictionaries: references, arrays,
  # dictionaries, names, numbers, strings and the literal keywords.
  @doc false
  def parse_value(data, pos) do
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
  @doc false
  def next_token(data, pos) do
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

  @doc false
  def whitespace?(byte), do: byte in [0, ?\t, ?\n, ?\f, ?\r, ?\s]

  @doc false
  def delimiter_or_space?(byte),
    do: whitespace?(byte) or byte in [?(, ?), ?<, ?>, ?[, ?], ?{, ?}, ?/, ?%]
end

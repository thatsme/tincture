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

  ## Stream data, decoded

  @doc """
  A stream's data, decoded: the bytes its filters encode, which is what a
  reader sees.

  The data is located by the stream's `/Length` (resolved if it is a
  reference), never by searching for `endstream`: Flate output can contain
  any byte, `endstream` and end-of-line bytes included. The `/Length` bytes
  must be followed by an end-of-line marker and `endstream`, or it raises.

  - `/FlateDecode` is inflated, and it raises if the data does not inflate to
    the end of a zlib stream, or if bytes are left over after it.
  - `/DCTDecode` is passed through as it is: JPEG data is what is embedded.
  - Any other filter raises, so a test never reads bytes it cannot decode as
    if they were the content.
  - Image data (`/Subtype /Image`) is returned as written unless
    `images: true` is given. Then its Flate is inflated too, but a predictor
    in `/DecodeParms` is not undone: PNG data keeps its per-row filter bytes.
  """
  @spec stream!(binary(), non_neg_integer(), keyword()) :: binary()
  def stream!(pdf, number, opts \\ []) when is_binary(pdf) do
    %{objects: objects} = read(pdf)
    stream!(pdf, objects, number, opts)
  end

  @doc """
  `stream!/3` for a file already read with `read/1`, given its objects, so a
  caller reading many streams parses the file once.
  """
  @spec stream!(binary(), %{non_neg_integer() => object()}, non_neg_integer(), keyword()) ::
          binary()
  def stream!(pdf, objects, number, opts) when is_binary(pdf) and is_map(objects) do
    decoded_stream!(pdf, objects, number, opts)
  end

  @doc """
  Every stream in the file, in object-number order, as
  `{number, dictionary, decoded data}` (`stream!/3`; image data as written
  unless `images: true` is given).
  """
  @spec streams(binary(), keyword()) :: [{non_neg_integer(), map(), binary()}]
  def streams(pdf, opts \\ []) when is_binary(pdf) do
    %{objects: objects} = read(pdf)

    for {number, %{stream_at: at, value: dictionary}} <- Enum.sort(objects), at != nil do
      {number, dictionary, stream!(pdf, objects, number, opts)}
    end
  end

  @doc """
  The decoded content of page `number` (from 1, in `/Kids` order), its
  `/Contents` streams joined in order.
  """
  @spec page_content!(binary(), pos_integer()) :: binary()
  def page_content!(pdf, number \\ 1) when is_binary(pdf) do
    %{objects: objects, trailer: trailer} = read(pdf)
    catalog = trailer |> Map.fetch!("Root") |> resolve(objects)
    pages = catalog |> Map.fetch!("Pages") |> resolve(objects)

    page_ref = pages |> Map.fetch!("Kids") |> resolve(objects) |> Enum.at(number - 1)

    unless page_ref, do: raise(ArgumentError, "the document has no page #{number}")

    page_ref
    |> resolve(objects)
    |> Map.get("Contents", [])
    |> List.wrap()
    |> Enum.map_join(fn {:ref, stream} -> stream!(pdf, objects, stream, []) end)
  end

  @doc """
  The file with every stream's data replaced by its decoded data
  (`stream!/3`), for matching the content of a document as text.

  The result is for matching only. Offsets and `/Length` values are those of
  the file as written, so it is not itself a readable PDF. Image data is kept
  as written unless `images: true` is given.
  """
  @spec decoded(binary(), keyword()) :: binary()
  def decoded(pdf, opts \\ []) when is_binary(pdf) do
    %{objects: objects} = read(pdf)

    streams =
      objects
      |> Enum.filter(fn {_number, object} -> object.stream_at end)
      |> Enum.sort_by(fn {_number, object} -> object.stream_at end)

    {parts, rest_at} =
      Enum.reduce(streams, {[], 0}, fn {number, object}, {parts, from} ->
        data = decoded_stream!(pdf, objects, number, opts)
        length = stream_length(objects, object)
        before = binary_part(pdf, from, object.stream_at - from)
        {[data, before | parts], object.stream_at + length}
      end)

    IO.iodata_to_binary(
      Enum.reverse([binary_part(pdf, rest_at, byte_size(pdf) - rest_at) | parts])
    )
  end

  defp decoded_stream!(pdf, objects, number, opts) do
    object = Map.fetch!(objects, number)

    unless object.stream_at do
      raise ArgumentError, "object #{number} is not a stream"
    end

    length = stream_length(objects, object)
    data = binary_part(pdf, object.stream_at, length)
    check_stream_end!(pdf, object.stream_at + length, number)

    dictionary = object.value

    if Map.get(dictionary, "Subtype") == {:name, "Image"} and
         not Keyword.get(opts, :images, false) do
      data
    else
      dictionary |> Map.get("Filter") |> resolve(objects) |> filters() |> decode(data, number)
    end
  end

  defp stream_length(objects, object) do
    case object.value |> Map.fetch!("Length") |> resolve(objects) do
      length when is_integer(length) and length >= 0 -> length
      other -> raise ArgumentError, "a stream /Length of #{inspect(other)}"
    end
  end

  # ISO 32000-1 §7.3.8.1: an end-of-line marker, not counted in /Length, then
  # endstream.
  defp check_stream_end!(pdf, at, number) do
    tail = binary_part(pdf, at, min(12, byte_size(pdf) - at))

    unless String.starts_with?(tail, ["\r\nendstream", "\nendstream", "\rendstream"]) do
      raise ArgumentError,
            "object #{number}: its /Length bytes are followed by #{inspect(tail)}, " <>
              "not an end-of-line marker and endstream"
    end
  end

  defp filters(nil), do: []
  defp filters({:name, name}), do: [name]
  defp filters(list) when is_list(list), do: Enum.map(list, fn {:name, name} -> name end)

  defp decode([], data, _number), do: data

  defp decode(["FlateDecode" | rest], data, number),
    do: decode(rest, inflate!(data, number), number)

  defp decode(["DCTDecode"], data, _number), do: data

  defp decode([filter | _rest], _data, number),
    do: raise(ArgumentError, "object #{number}: no decoder for the /#{filter} filter")

  # :zlib.inflate/2 neither notices bytes left after the end of the zlib
  # stream nor, by itself, a stream cut short. So the data must end the stream
  # (inflateEnd/1 raises otherwise), and the data less its last byte must not:
  # a stream ends with its 4-byte Adler-32, so if it is still complete without
  # the last byte, that byte was left over.
  @doc """
  Inflates Flate data as `stream!/3` does: it raises if the data does not
  inflate to the end of a zlib stream, or if bytes are left over after it.
  For stream data this module cannot locate itself, such as an encrypted
  stream once decrypted.
  """
  @spec inflate!(binary()) :: binary()
  def inflate!(data) when is_binary(data), do: inflate!(data, "?")

  defp inflate!(data, number) do
    case inflate_whole(data) do
      {:ok, inflated} ->
        if byte_size(data) > 0 and
             match?({:ok, _}, inflate_whole(binary_part(data, 0, byte_size(data) - 1))) do
          raise ArgumentError, "object #{number}: bytes are left over after its Flate data"
        end

        inflated

      :error ->
        raise ArgumentError, "object #{number}: its Flate data does not inflate"
    end
  end

  defp inflate_whole(data) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z)
      inflated = z |> :zlib.inflate(data) |> IO.iodata_to_binary()
      :ok = :zlib.inflateEnd(z)
      {:ok, inflated}
    rescue
      ErlangError -> :error
    after
      :zlib.close(z)
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

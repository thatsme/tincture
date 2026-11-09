defmodule Examples.Checks do
  @moduledoc """
  The checklists the examples print after writing a file.

  Each row names a requirement, where it is satisfied, and whether the written
  bytes carry it. A row that fails prints `MISSING` and, once the whole table
  has been printed, makes the script exit with status 1 - so a check that fails
  fails the run instead of scrolling past in a log.

  A row's status is one of:

    * `true` / `false` — printed as `ok` / `MISSING`;
    * `{found?, ok_text}` — the same, with its own wording for `ok`;
    * `{:note, text}` — information, never a failure.
  """

  @type status :: boolean() | {boolean(), String.t()} | {:note, String.t()}
  @type row :: {String.t(), String.t(), status()}

  @doc """
  The rows as aligned text, one per line, indented by two spaces.
  """
  @spec table([row()]) :: String.t()
  def table(rows) do
    label_width = column_width(rows, 0)
    where_width = column_width(rows, 1)

    Enum.map_join(rows, "\n", fn {label, where, status} ->
      "  " <>
        String.pad_trailing(label, label_width) <>
        "  " <> String.pad_trailing(where, where_width) <> "  " <> text(status)
    end)
  end

  @doc """
  Exits with status 1 if any row failed. Call it after printing.
  """
  @spec halt_if_missing([row()]) :: :ok
  def halt_if_missing(rows) do
    case Enum.filter(rows, &missing?/1) do
      [] ->
        :ok

      missing ->
        IO.puts(:stderr, "\nMISSING: " <> Enum.map_join(missing, ", ", &elem(&1, 0)))
        System.halt(1)
    end
  end

  @doc """
  The rows every tagged form asserts present, read from the written bytes, so
  that no PDF/UA rule for forms passes for having nothing to match.

  `widgets` is the number of widget annotations the form draws (a radio
  group's buttons each count), `fields` the number of fields (a radio group
  counts once), and `headings` the number of headings, each of which has a
  bookmark.
  """
  @spec form_rows(binary(), keyword()) :: [row()]
  def form_rows(binary, counts) do
    widgets = Keyword.fetch!(counts, :widgets)
    fields = Keyword.fetch!(counts, :fields)
    headings = Keyword.fetch!(counts, :headings)

    widget_lines = Regex.scan(~r|<< /Type /Annot /Subtype /Widget[^\n]*|, binary)
    count = fn pattern -> length(Regex.scan(pattern, binary)) end

    [
      {"a Form element per widget (#{widgets})", "7.18.4-1, 7.18.4-2",
       count.(~r|/Type /StructElem /S /Form |) == widgets and length(widget_lines) == widgets},
      {"/StructParent on every widget", "/ParentTree",
       Enum.count(widget_lines, fn [line] -> line =~ ~r|/StructParent \d+| end) == widgets},
      {"/TU on every field (#{fields})", "7.18.1-3", count.(~r|/TU \(|) == fields},
      {"/AP on every widget", "section D",
       Enum.all?(widget_lines, fn [line] -> line =~ "/AP << /N " end)},
      {"/Tabs /S", "7.18.3-1", binary =~ "/Tabs /S"},
      {"no /NeedAppearances", "section D", not (binary =~ "/NeedAppearances")},
      {"a bookmark per heading (#{headings})", "outline",
       count.(~r|<< /Title [^\n]*/Dest \[|) == headings and binary =~ "/Type /Outlines"},
      {"catalog /Lang", "7.2-34, 7.2-25", binary =~ ~r|/Lang \(|},
      {"dc:title in the XMP", "7.1-9", binary =~ "<dc:title>"}
    ]
  end

  defp text(true), do: "ok"
  defp text(false), do: "MISSING"
  defp text({true, ok_text}) when is_binary(ok_text), do: ok_text
  defp text({false, _ok_text}), do: "MISSING"
  defp text({:note, note}), do: note

  defp missing?({_label, _where, false}), do: true
  defp missing?({_label, _where, {false, _ok_text}}), do: true
  defp missing?(_row), do: false

  defp column_width(rows, index),
    do: rows |> Enum.map(&String.length(elem(&1, index))) |> Enum.max()

  @doc """
  The written file with every Flate stream's data replaced by its inflated
  data, so that the checks read content operators and font programs as they
  were before compression. Image data, which carries a PNG predictor, is kept
  as written.

  Each stream's data is located by its `/Length`, never by searching for
  `endstream`, since compressed data can contain any byte. Raises if a
  `/Length` is not followed by an end-of-line and `endstream`, or if Flate
  data does not inflate to exactly the end of its zlib stream. The result is
  for matching only: its offsets are not those of the file.
  """
  @spec inflated(binary()) :: binary()
  def inflated(binary) when is_binary(binary), do: inflate_streams(binary, [])

  @stream_start ">>\nstream\n"

  defp inflate_streams(binary, acc) do
    case :binary.match(binary, @stream_start) do
      :nomatch ->
        IO.iodata_to_binary(Enum.reverse([binary | acc]))

      {at, size} ->
        head = binary_part(binary, 0, at + size)
        rest = binary_part(binary, at + size, byte_size(binary) - at - size)
        dictionary = last_dictionary(head)

        [_, length] =
          Regex.run(~r|/Length (\d+)[ >]|, dictionary) ||
            raise("a stream with no direct /Length: #{inspect(dictionary)}")

        length = String.to_integer(length)
        <<data::binary-size(length), tail::binary>> = rest

        unless String.starts_with?(tail, "\nendstream") do
          raise "a stream's /Length bytes are not followed by EOL and endstream: " <>
                  inspect(dictionary)
        end

        data =
          if dictionary =~ "/FlateDecode" and not (dictionary =~ "/Subtype /Image"),
            do: inflate!(data),
            else: data

        inflate_streams(tail, [data, head | acc])
    end
  end

  # The stream's dictionary: from the last object header before the
  # `stream` keyword.
  defp last_dictionary(head) do
    from =
      case :binary.matches(head, " 0 obj\n") do
        [] -> 0
        matches -> matches |> List.last() |> then(fn {at, size} -> at + size end)
      end

    binary_part(head, from, byte_size(head) - from)
  end

  # :zlib.uncompress/1 raises on data that does not end its zlib stream, but
  # not on bytes left over after it. A zlib stream ends in its 4-byte
  # Adler-32, so if the data less its last byte still uncompresses, that byte
  # was left over.
  defp inflate!(data) do
    inflated = :zlib.uncompress(data)

    leftover? =
      try do
        :zlib.uncompress(binary_part(data, 0, byte_size(data) - 1))
        true
      rescue
        ErlangError -> false
      end

    if leftover?, do: raise("bytes are left over after a stream's Flate data")
    inflated
  end
end

defmodule Tincture.Test.ToUnicodeMap do
  @moduledoc """
  Reads the ToUnicode CMaps of a PDF file as written: each font's `bfrange`
  and `bfchar` lines, and the code-to-Unicode table they define.

  It also builds the documents the ToUnicode tests run on, so that the same
  documents, read by the same code, can be measured against an earlier
  release.

  The table is the mapping the lines intend: code `lo + i` of a `bfrange`
  line `<lo> <hi> <dst>` maps to `dst + i`, the destination read as one
  number. That is how pypdf, PDFium, pdf.js and mutool read a line whose
  destination's last byte passes 255, which ISO 32000-1 9.10.3 leaves
  undefined, and it is the same as the clause's last-byte increment for a
  line that keeps the rule. So a table read from a release that wrote such
  lines can be compared, entry for entry, with one read from a release that
  splits them.
  """

  alias Tincture.Test.PDFObjects

  @type line :: %{lo: binary(), hi: binary(), dst: binary()}

  @doc """
  Every ToUnicode CMap in the file, as `{font object number, CMap data}`,
  one per CMap object, sorted by object number. Raises on a filtered stream:
  these files write ToUnicode uncompressed.
  """
  @spec cmaps(binary()) :: [{non_neg_integer(), binary()}]
  def cmaps(pdf) do
    %{objects: objects} = PDFObjects.read(pdf)

    objects
    |> Enum.flat_map(fn {number, %{value: value}} ->
      case value do
        %{"ToUnicode" => {:ref, cmap_number}} -> [{cmap_number, number}]
        _other -> []
      end
    end)
    |> Enum.uniq_by(fn {cmap_number, _font} -> cmap_number end)
    |> Enum.sort()
    |> Enum.map(fn {cmap_number, font_number} ->
      %{value: dict, stream_at: at} = Map.fetch!(objects, cmap_number)

      if Map.has_key?(dict, "Filter") do
        raise ArgumentError,
              "ToUnicode object #{cmap_number} carries a /Filter; read it decoded"
      end

      length = PDFObjects.resolve(Map.fetch!(dict, "Length"), objects)
      {font_number, binary_part(pdf, at, length)}
    end)
  end

  @doc """
  The `bfrange` lines of a CMap, in order, as hex strings. An array
  destination, which Tincture never writes, raises.
  """
  @spec lines(binary()) :: [line()]
  def lines(cmap) do
    for [_, body] <- Regex.scan(~r/beginbfrange\n(.*?)\nendbfrange/s, cmap),
        line <- String.split(body, "\n") do
      case Regex.run(~r/^<([0-9A-F]+)> <([0-9A-F]+)> <([0-9A-F]+)>$/, line) do
        [_, lo, hi, dst] -> %{lo: lo, hi: hi, dst: dst}
        nil -> raise ArgumentError, "unexpected bfrange line: #{inspect(line)}"
      end
    end
  end

  @doc """
  Whether a `bfrange` line keeps both rules:

    * its source codes share every byte but the last (Adobe TN 5411 1.4.1:
      a line may not cross a first-byte boundary), so it covers at most one
      block of 256;
    * the last byte of its destination, incremented once per code after the
      first, does not pass 255 (ISO 32000-1 9.10.3).
  """
  @spec valid?(line()) :: boolean()
  def valid?(%{lo: lo, hi: hi, dst: dst}) do
    lo_bytes = Base.decode16!(lo)
    hi_bytes = Base.decode16!(hi)
    dst_bytes = Base.decode16!(dst)
    span = :binary.decode_unsigned(hi_bytes) - :binary.decode_unsigned(lo_bytes)
    prefix = byte_size(lo_bytes) - 1

    byte_size(lo_bytes) == byte_size(hi_bytes) and span >= 0 and
      binary_part(lo_bytes, 0, prefix) == binary_part(hi_bytes, 0, prefix) and
      :binary.last(dst_bytes) + span <= 255
  end

  @doc """
  The code-to-Unicode table a CMap defines, as `{source hex, destination
  hex}` pairs sorted by source: every `bfchar` entry, and every code of every
  `bfrange` line, read as the moduledoc says.
  """
  @spec table(binary()) :: [{binary(), binary()}]
  def table(cmap) do
    chars =
      for [_, body] <- Regex.scan(~r/beginbfchar\n(.*?)\nendbfchar/s, cmap),
          line <- String.split(body, "\n"),
          [_, src, dst] <- [Regex.run(~r/^<([0-9A-F]+)> <([0-9A-F]+)>$/, line)],
          do: {src, dst}

    ranges =
      for %{lo: lo, hi: hi, dst: dst} <- lines(cmap),
          lo_int = String.to_integer(lo, 16),
          dst_int = String.to_integer(dst, 16),
          offset <- 0..(String.to_integer(hi, 16) - lo_int),
          do: {hex(lo_int + offset, byte_size(lo)), hex(dst_int + offset, byte_size(dst))}

    Enum.sort(chars ++ ranges)
  end

  @doc """
  A digest of the table: its number of entries and the SHA-256 of its
  entries, one `source:destination` per line, sorted.
  """
  @spec digest([{binary(), binary()}]) :: {non_neg_integer(), binary()}
  def digest(table) do
    text = Enum.map_join(table, "", fn {src, dst} -> src <> ":" <> dst <> "\n" end)
    {length(table), Base.encode16(:crypto.hash(:sha256, text), case: :lower)}
  end

  @sans "examples/fonts/LiberationSans-Regular.ttf"

  # The three ranges of LiberationSans's whole-font map that cross a block
  # of 256 when written as single lines.
  @ranges [{0x00A0, 0x036F}, {0x03D0, 0x0513}, {0x1DFE, 0x1E9B}]

  @doc """
  The documents the ToUnicode tests read, as `{name, binary}`: every
  committed example, a font embedded whole, a field font embedded whole
  with `full_font: true`, a subset whose text straddles U+00FF/U+0100,
  U+03FF/U+0400 and U+1DFF/U+1E00, and the 1,202 codes of the three ranges
  drawn in a font embedded whole.
  """
  @spec documents() :: [{String.t(), binary()}]
  def documents do
    examples =
      "examples/output/**/*.pdf"
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(&{&1, File.read!(&1)})

    examples ++
      [
        {"whole font", whole_font()},
        {"full_font field", full_font_field()},
        {"subset across 256 boundaries", straddling_subset()},
        {"the 1,202 codes", all_codes()}
      ]
  end

  # Text outside WinAnsi, so the font is written as a Type0 font with a
  # ToUnicode map, as the straddling subset below; here the font is whole.
  defp whole_font do
    Tincture.new()
    |> Tincture.register_ttf_font("Sans", @sans, subset: :none)
    |> Tincture.set_font("Sans", 12)
    |> Tincture.text_at(72, 700, straddling_text())
    |> Tincture.export()
  end

  defp full_font_field do
    Tincture.new()
    |> Tincture.register_ttf_font("Sans", @sans)
    |> Tincture.text_field(72, 700, 200, 20, "name", font: "Sans", value: "Ada", full_font: true)
    |> Tincture.export()
  end

  defp straddling_subset do
    Tincture.new()
    |> Tincture.register_ttf_font("Sans", @sans)
    |> Tincture.set_font("Sans", 12)
    |> Tincture.text_at(72, 700, straddling_text())
    |> Tincture.export()
  end

  defp straddling_text do
    [0x00FE..0x0101, 0x03FE..0x0401, 0x1DFE..0x1E01]
    |> Enum.map_join(" ", fn range -> Enum.map_join(range, "", &<<&1::utf8>>) end)
  end

  defp all_codes do
    lines =
      for {lo, hi} <- @ranges, start <- Enum.take_every(lo..hi, 16) do
        start..min(start + 15, hi) |> Enum.map_join(" ", &<<&1::utf8>>)
      end

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("Sans", @sans, subset: :none)

    {pdf, _} =
      Enum.reduce(lines, {pdf, 0}, fn line, {pdf, i} ->
        pdf = if i > 0 and rem(i, 40) == 0, do: Tincture.add_page(pdf), else: pdf

        pdf =
          pdf
          |> Tincture.set_font("Sans", 10)
          |> Tincture.text_at(30, 800 - rem(i, 40) * 19, line)

        {pdf, i + 1}
      end)

    Tincture.export(pdf)
  end

  defp hex(integer, width),
    do: integer |> Integer.to_string(16) |> String.pad_leading(width, "0")
end

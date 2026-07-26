defmodule Tincture.Test.MeasurableFont do
  @moduledoc """
  A minimal but valid TrueType font with advance widths chosen to be recognisable.

  Widths are deliberately not round multiples of each other and nowhere near
  the `0.6 * size` fallback estimate, so a test asserting an exact width is
  really asserting that `hmtx` was read and scaled — not that some plausible
  number came back.

  | character | glyph | advance (units) |
  |-----------|-------|-----------------|
  | `A`       | 1     | 700             |
  | `B`       | 2     | 900             |
  | space     | 3     | 300             |

  Units per em is 1000, so at 10pt an `A` is exactly 7.0pt.
  """

  @units_per_em 1000
  @advance_widths %{?A => 700, ?B => 900, ?\s => 300}

  @doc "Advance width in font design units for a character, or nil."
  @spec advance_units(char()) :: pos_integer() | nil
  def advance_units(codepoint), do: Map.get(@advance_widths, codepoint)

  @doc "The font's units per em."
  @spec units_per_em() :: pos_integer()
  def units_per_em, do: @units_per_em

  @doc """
  The exact width this font gives `text` at `size`, computed independently of
  the library so a test comparing against it is a genuine cross-check.
  """
  @spec expected_width(String.t(), number()) :: float()
  def expected_width(text, size) do
    units =
      text
      |> String.to_charlist()
      |> Enum.map(&Map.fetch!(@advance_widths, &1))
      |> Enum.sum()

    units * size / @units_per_em
  end

  @doc "Write the font to a temporary file and return its path."
  @spec write!() :: Path.t()
  def write! do
    path =
      Path.join(
        System.tmp_dir!(),
        "tincture_measurable_#{System.unique_integer([:positive])}.ttf"
      )

    :ok = File.write(path, binary())
    path
  end

  @doc "The font as a binary."
  @spec binary() :: binary()
  def binary do
    outline = fn x_min, y_min, x_max, y_max ->
      <<1::16-signed-big, x_min::16-signed-big, y_min::16-signed-big, x_max::16-signed-big,
        y_max::16-signed-big>>
    end

    build_ttf([
      {"head", <<0::size(18)-unit(8), @units_per_em::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      # glyph 0 (notdef), then A, B, space - each advance paired with a left
      # side bearing, which measurement ignores.
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 300::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{?A, 1}, {?B, 2}, {?\s, 3}])},
      # Short loca: stored values are byte offsets / 2. Glyph 3 is empty, which
      # is how a space is legitimately encoded.
      {"loca", <<0::16-big, 5::16-big, 10::16-big, 15::16-big, 15::16-big>>},
      {"glyf",
       <<outline.(0, -20, 500, 700)::binary, outline.(0, -10, 700, 750)::binary,
         outline.(0, -30, 900, 820)::binary>>}
    ])
  end

  defp cmap_format0(entries) do
    glyph_ids =
      entries
      |> Enum.reduce(:array.new(256, default: 0), fn {code, glyph_id}, acc ->
        :array.set(code, glyph_id, acc)
      end)
      |> :array.to_list()
      |> :erlang.list_to_binary()

    subtable = <<0::16-big, 262::16-big, 0::16-big, glyph_ids::binary>>
    <<0::16-big, 1::16-big, 3::16-big, 1::16-big, 12::32-big, subtable::binary>>
  end

  defp build_ttf(tables) do
    num_tables = length(tables)
    header = <<0x0001_0000::32-big, num_tables::16-big, 0::16-big, 0::16-big, 0::16-big>>
    base_offset = byte_size(header) + num_tables * 16

    {records, binaries, _next} =
      Enum.reduce(tables, {[], [], base_offset}, fn {tag, data}, {recs, bins, offset} ->
        record = <<tag::binary-size(4), 0::32-big, offset::32-big, byte_size(data)::32-big>>
        {recs ++ [record], bins ++ [data], offset + byte_size(data)}
      end)

    IO.iodata_to_binary([header, records, binaries])
  end
end

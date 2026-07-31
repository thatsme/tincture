defmodule Tincture.PDF.ICC do
  @moduledoc """
  A built-in sRGB ICC profile, for use as a PDF/A output intent.

  PDF/A forbids device-dependent colour without an output intent: `1 0 0 rg` on
  its own says "as red as this device gets", which is not a colour anyone can
  reproduce a decade later. An output intent names the colour space those
  numbers are to be read in, and carries an ICC profile defining it.

  That profile has to come from somewhere. Rather than depend on one being
  installed, or ship someone else's, Tincture builds a v2 matrix/TRC display
  profile describing sRGB (IEC 61966-2.1) from its published constants:

    * the sRGB primaries, chromatically adapted to the D50 profile connection
      space — the same Bradford-adapted values every sRGB profile carries;
    * the real sRGB tone curve, sampled at 1024 points, including its linear
      segment below 0.04045. A plain gamma 2.2 curve is the common shortcut and
      is measurably wrong in the shadows.

  The three channel curves share one tag, which the format allows and which
  keeps the profile around 2.5 kB.

  The AFM parser aside, this is the only place in the library holding
  numeric constants from an external specification, so they are written out in
  full rather than folded into expressions.
  """

  import Bitwise

  # Bradford-adapted sRGB primaries in the D50 profile connection space.
  @red_xyz {0.4360, 0.2225, 0.0139}
  @green_xyz {0.3851, 0.7169, 0.0971}
  @blue_xyz {0.1431, 0.0606, 0.7141}

  # D50, the illuminant every ICC profile connection space uses.
  @white_point {0.9642, 1.0000, 0.8249}

  @trc_samples 1024

  @description "sRGB IEC61966-2.1"
  @copyright "No copyright, generated from published sRGB constants"

  @doc """
  The identifier naming this colour space in an output intent.
  """
  @spec output_condition_identifier() :: String.t()
  def output_condition_identifier, do: @description

  @doc """
  The number of colour components, for the ICC stream's `/N` entry.
  """
  @spec components() :: pos_integer()
  def components, do: 3

  @doc """
  The sRGB profile as an ICC binary.
  """
  @spec srgb() :: binary()
  def srgb do
    curve = curve_tag()

    # rTRC, gTRC and bTRC share one block: identical curves, and the format
    # permits several tags to point at the same data.
    tags = [
      {"desc", text_description_tag(@description)},
      {"wtpt", xyz_tag(@white_point)},
      {"rXYZ", xyz_tag(@red_xyz)},
      {"gXYZ", xyz_tag(@green_xyz)},
      {"bXYZ", xyz_tag(@blue_xyz)},
      {"rTRC", curve},
      {"gTRC", curve},
      {"bTRC", curve},
      {"cprt", text_tag(@copyright)}
    ]

    {table, data, _next_offset} = build_tag_table(tags)

    body = <<length(tags)::32-big, table::binary, data::binary>>
    size = 128 + byte_size(body)

    <<header(size)::binary, body::binary>>
  end

  # Tag data is 4-byte aligned, and shared blocks are written once.
  defp build_tag_table(tags) do
    header_size = 128 + 4 + length(tags) * 12

    {entries, blocks, _offsets, next} =
      Enum.reduce(tags, {[], [], %{}, header_size}, fn {signature, data},
                                                       {acc_entries, acc_blocks, acc_offsets,
                                                        cursor} ->
        case Map.fetch(acc_offsets, data) do
          {:ok, {offset, size}} ->
            entry = <<signature::binary-size(4), offset::32-big, size::32-big>>
            {[entry | acc_entries], acc_blocks, acc_offsets, cursor}

          :error ->
            size = byte_size(data)
            padding = padding_for(size)
            entry = <<signature::binary-size(4), cursor::32-big, size::32-big>>

            {
              [entry | acc_entries],
              [<<data::binary, 0::size(padding)-unit(8)>> | acc_blocks],
              Map.put(acc_offsets, data, {cursor, size}),
              cursor + size + padding
            }
        end
      end)

    {
      entries |> Enum.reverse() |> IO.iodata_to_binary(),
      blocks |> Enum.reverse() |> IO.iodata_to_binary(),
      next
    }
  end

  defp padding_for(size), do: rem(4 - rem(size, 4), 4)

  defp header(size) do
    <<
      size::32-big,
      # No preferred CMM.
      0::32,
      # Version 2.4.0.
      0x02400000::32-big,
      "mntr",
      "RGB ",
      "XYZ ",
      # Creation date and time: zeroed, so building the same document twice
      # produces the same bytes.
      0::size(12)-unit(8),
      "acsp",
      # Platform, flags, manufacturer, model, attributes: all unspecified.
      0::32,
      0::32,
      0::32,
      0::32,
      0::64,
      # Rendering intent: perceptual.
      0::32,
      # The profile connection space illuminant is D50 by definition.
      s15_fixed16(0.9642)::binary,
      s15_fixed16(1.0000)::binary,
      s15_fixed16(0.8249)::binary,
      # Creator, profile id, reserved.
      0::32,
      0::size(16)-unit(8),
      0::size(28)-unit(8)
    >>
  end

  defp xyz_tag({x, y, z}) do
    <<"XYZ ", 0::32, s15_fixed16(x)::binary, s15_fixed16(y)::binary, s15_fixed16(z)::binary>>
  end

  # The sRGB transfer function: linear near black, a 2.4 power curve above.
  defp curve_tag do
    samples =
      for index <- 0..(@trc_samples - 1), into: <<>> do
        value = index / (@trc_samples - 1)

        linear =
          if value <= 0.04045 do
            value / 12.92
          else
            :math.pow((value + 0.055) / 1.055, 2.4)
          end

        <<round(linear * 65_535)::16-big>>
      end

    <<"curv", 0::32, @trc_samples::32-big, samples::binary>>
  end

  # The v2 description type carries ASCII, UTF-16 and Macintosh ScriptCode
  # variants. Only the ASCII one is populated; the rest are required to be
  # present and may be empty.
  defp text_description_tag(text) do
    ascii = text <> <<0>>

    <<
      "desc",
      0::32,
      byte_size(ascii)::32-big,
      ascii::binary,
      # Unicode language code and count.
      0::32,
      0::32,
      # ScriptCode code, count, and its fixed 67-byte buffer.
      0::16,
      0::8,
      0::size(67)-unit(8)
    >>
  end

  defp text_tag(text), do: <<"text", 0::32, text::binary, 0>>

  # ICC's s15Fixed16Number: a signed 16.16 fixed-point value.
  defp s15_fixed16(value) do
    scaled = round(value * 65_536)
    <<scaled &&& 0xFFFFFFFF::32-big>>
  end
end

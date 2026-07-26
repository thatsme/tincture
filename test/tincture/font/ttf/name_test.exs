defmodule Tincture.Font.TTF.NameTest do
  @moduledoc """
  Direct tests for the OpenType `name` table.

  The same logical name appears several times in a real font under different
  platform, encoding and language IDs — a Windows record in UTF-16BE, a
  Macintosh record in Latin-1, sometimes a legacy Unicode one. Reading the
  table is mostly a matter of picking the best-encoded record rather than the
  first, and the encodings are genuinely different, so a font whose only family
  record is a Macintosh one must still be read correctly.
  """
  use ExUnit.Case, async: true

  alias Tincture.Font.TTF.Name

  # name table: format, count, stringOffset, then `count` 12-byte records,
  # then the string storage.
  #
  # A record is {platform_id, encoding_id, language_id, name_id, string}.
  defp name_table(records, opts \\ []) do
    declared_count = Keyword.get(opts, :declared_count, length(records))
    header_size = 6 + length(records) * 12
    string_offset = Keyword.get(opts, :string_offset, header_size)

    {record_bin, storage, _} =
      Enum.reduce(records, {<<>>, <<>>, 0}, fn {plat, enc, lang, name_id, string},
                                               {recs, store, cursor} ->
        encoded =
          case string do
            {:raw, bytes} -> bytes
            text -> encode_for(plat, text)
          end

        rec =
          <<plat::16-big, enc::16-big, lang::16-big, name_id::16-big, byte_size(encoded)::16-big,
            cursor::16-big>>

        {recs <> rec, store <> encoded, cursor + byte_size(encoded)}
      end)

    <<0::16-big, declared_count::16-big, string_offset::16-big, record_bin::binary,
      storage::binary>>
  end

  # Platform 1 is Macintosh, which stores Latin-1. Everything else here is
  # UTF-16BE.
  defp encode_for(1, string), do: :unicode.characters_to_binary(string, :utf8, :latin1)

  defp encode_for(_platform, string),
    do: :unicode.characters_to_binary(string, :utf8, {:utf16, :big})

  # Wraps the name table in a font, since the parser takes {offset, length}.
  defp font_with(name_table), do: {<<0xAA, 0xBB>> <> name_table, byte_size(name_table)}

  defp family(name_table) do
    {data, length} = font_with(name_table)
    {:ok, %{font_family: family}} = Name.parse_name_metadata(data, %{"name" => {2, length}})
    family
  end

  describe "reading the family name" do
    test "reads a Windows UTF-16BE record" do
      # Platform 3, encoding 1, language 0x0409 (US English) is the record a
      # Windows font is expected to carry.
      assert family(name_table([{3, 1, 0x0409, 1, "Inter"}])) == "Inter"
    end

    test "reads a legacy Unicode record (platform 0)" do
      assert family(name_table([{0, 3, 0, 1, "Unicode Sans"}])) == "Unicode Sans"
    end

    test "reads a Macintosh Latin-1 record (platform 1)" do
      assert family(name_table([{1, 0, 0, 1, "Chicago"}])) == "Chicago"
    end

    test "decodes non-ASCII from a Macintosh record as Latin-1, not UTF-16" do
      # If the decoder guessed UTF-16 here it would produce mojibake rather
      # than failing, which is why the platform id has to drive the encoding.
      assert family(name_table([{1, 0, 0, 1, "Futura Ünica"}])) == "Futura Ünica"
    end

    test "decodes non-ASCII from a Windows record as UTF-16BE" do
      assert family(name_table([{3, 1, 0x0409, 1, "Größe"}])) == "Größe"
    end

    test "ignores records for name ids other than the family" do
      # name id 1 is family; 4 is the full name, 6 the PostScript name.
      table = name_table([{3, 1, 0x0409, 4, "Full Name"}, {3, 1, 0x0409, 1, "Family"}])
      assert family(table) == "Family"
    end

    test "trims surrounding whitespace and treats a blank name as absent" do
      assert family(name_table([{3, 1, 0x0409, 1, "  Padded  "}])) == "Padded"
      assert family(name_table([{3, 1, 0x0409, 1, "   "}])) == nil
    end
  end

  describe "record preference" do
    test "prefers the US-English Windows record over any other" do
      table =
        name_table([
          {1, 0, 0, 1, "Mac Name"},
          {0, 3, 0, 1, "Unicode Name"},
          {3, 1, 0x0409, 1, "Windows US Name"}
        ])

      assert family(table) == "Windows US Name"
    end

    test "prefers another Windows record over a Unicode or Macintosh one" do
      table =
        name_table([
          {1, 0, 0, 1, "Mac Name"},
          {0, 3, 0, 1, "Unicode Name"},
          {3, 1, 0x0809, 1, "Windows UK Name"}
        ])

      assert family(table) == "Windows UK Name"
    end

    test "prefers a Unicode record over a Macintosh one" do
      table = name_table([{1, 0, 0, 1, "Mac Name"}, {0, 3, 0, 1, "Unicode Name"}])
      assert family(table) == "Unicode Name"
    end

    test "falls back to a Macintosh record when nothing better exists" do
      assert family(name_table([{1, 0, 0, 1, "Mac Only"}])) == "Mac Only"
    end

    test "skips a preferred record that fails to decode and uses the next" do
      # A platform-3 record is tried first, but three bytes cannot be UTF-16BE.
      # :unicode signals that by returning {:incomplete, ...} rather than
      # raising, so a decoder that only rescues exceptions passes the tuple on
      # and crashes downstream. The malformed record must simply be skipped.
      table =
        name_table([
          {1, 0, 0, 1, "Mac Fallback"},
          {3, 1, 0x0409, 1, {:raw, <<0x00, 0x41, 0x00>>}}
        ])

      assert family(table) == "Mac Fallback"
    end

    test "a lone surrogate in the preferred record does not crash the parse" do
      table =
        name_table([
          {1, 0, 0, 1, "Mac Fallback"},
          {3, 1, 0x0409, 1, {:raw, <<0xD8, 0x00>>}}
        ])

      assert family(table) == "Mac Fallback"
    end

    test "a font whose only family record is undecodable yields no name" do
      table = name_table([{3, 1, 0x0409, 1, {:raw, <<0x00, 0x41, 0x00>>}}])
      assert family(table) == nil
    end
  end

  describe "unreadable tables fall through rather than crashing" do
    test "an unknown platform id yields no name" do
      assert family(name_table([{9, 0, 0, 1, "Unknown Platform"}])) == nil
    end

    test "a table with no records yields no name" do
      assert family(name_table([])) == nil
    end

    test "a record count larger than the table yields no name" do
      assert family(name_table([{3, 1, 0x0409, 1, "Inter"}], declared_count: 500)) == nil
    end

    test "a string offset past the end of the table yields no name" do
      assert family(name_table([{3, 1, 0x0409, 1, "Inter"}], string_offset: 9999)) == nil
    end

    test "a table too short to hold a header yields no name" do
      {data, _} = font_with(<<0::16-big>>)
      assert {:ok, %{font_family: nil}} = Name.parse_name_metadata(data, %{"name" => {2, 2}})
    end

    test "a name record pointing outside the string storage yields no name" do
      # One record claiming 200 bytes when the storage holds a handful.
      table =
        <<0::16-big, 1::16-big, 18::16-big, 3::16-big, 1::16-big, 0x0409::16-big, 1::16-big,
          200::16-big, 0::16-big, "Inter">>

      assert family(table) == nil
    end

    test "a font with no name table yields no name" do
      assert {:ok, %{font_family: nil}} = Name.parse_name_metadata(<<0, 0>>, %{})
    end

    test "a name record pointing outside the font yields no name" do
      assert {:ok, %{font_family: nil}} =
               Name.parse_name_metadata(<<0, 0>>, %{"name" => {900, 40}})
    end

    test "trailing bytes that do not form a whole record are ignored" do
      # 6-byte header, then one and a half records.
      table = <<0::16-big, 1::16-big, 18::16-big, 3::16-big, 1::16-big, 0x0409::16-big>>
      assert family(table) == nil
    end
  end
end

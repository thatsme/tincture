defmodule Tincture.PDF.WinAnsiTest do
  @moduledoc """
  The WinAnsi table against ISO 32000-1:2008 Annex D, stated in a different
  shape from the module's own data, so the two cannot agree by sharing a typo.

  Table D.1 describes WinAnsiEncoding as "Windows Code Page 1252". Table D.2
  gives each character's code, and its notes 5 and 6 add the soft hyphen at
  0xAD and the nonbreaking space at 0xA0. Note 3 maps the unused codes to the
  bullet glyph but assigns only 0x95 to it. So:

    * 0x20-0x7E and 0xA0-0xFF are Latin-1: the code is the code point;
    * 0x80-0x9F holds the 27 characters below, named as D.2 names them;
    * 0x7F, 0x81, 0x8D, 0x8F, 0x90 and 0x9D encode nothing.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF.WinAnsi

  # {code, Unicode code point, Table D.2 character name}
  @high [
    {0x80, 0x20AC, "Euro"},
    {0x82, 0x201A, "quotesinglbase"},
    {0x83, 0x0192, "florin"},
    {0x84, 0x201E, "quotedblbase"},
    {0x85, 0x2026, "ellipsis"},
    {0x86, 0x2020, "dagger"},
    {0x87, 0x2021, "daggerdbl"},
    {0x88, 0x02C6, "circumflex"},
    {0x89, 0x2030, "perthousand"},
    {0x8A, 0x0160, "Scaron"},
    {0x8B, 0x2039, "guilsinglleft"},
    {0x8C, 0x0152, "OE"},
    {0x8E, 0x017D, "Zcaron"},
    {0x91, 0x2018, "quoteleft"},
    {0x92, 0x2019, "quoteright"},
    {0x93, 0x201C, "quotedblleft"},
    {0x94, 0x201D, "quotedblright"},
    {0x95, 0x2022, "bullet"},
    {0x96, 0x2013, "endash"},
    {0x97, 0x2014, "emdash"},
    {0x98, 0x02DC, "tilde"},
    {0x99, 0x2122, "trademark"},
    {0x9A, 0x0161, "scaron"},
    {0x9B, 0x203A, "guilsinglright"},
    {0x9C, 0x0153, "oe"},
    {0x9E, 0x017E, "zcaron"},
    {0x9F, 0x0178, "Ydieresis"}
  ]

  @unused [0x7F, 0x81, 0x8D, 0x8F, 0x90, 0x9D]

  test "0x20-0x7E and 0xA0-0xFF map each code to the same code point" do
    table = WinAnsi.code_to_unicode()

    for code <- Enum.concat(0x20..0x7E, 0xA0..0xFF) do
      assert Map.fetch(table, code) == {:ok, code}, "code 0x#{Integer.to_string(code, 16)}"
    end
  end

  test "0x80-0x9F holds the 27 characters Table D.2 assigns there" do
    table = WinAnsi.code_to_unicode()

    for {code, unicode, name} <- @high do
      assert Map.fetch(table, code) == {:ok, unicode},
             "#{name} at 0x#{Integer.to_string(code, 16)}"
    end
  end

  test "the unused codes encode nothing" do
    table = WinAnsi.code_to_unicode()

    for code <- @unused do
      refute Map.has_key?(table, code), "0x#{Integer.to_string(code, 16)} should be absent"
    end
  end

  test "nothing outside 32-255 is in the table, and 218 codes are" do
    table = WinAnsi.code_to_unicode()

    assert Enum.all?(Map.keys(table), &(&1 in 32..255))
    assert map_size(table) == 95 + 96 + length(@high)
    assert map_size(table) == 218
  end

  test "the soft hyphen and the nonbreaking space are the duplicates D.2's notes add" do
    assert WinAnsi.code(0x00AD) == 0xAD
    assert WinAnsi.code(0x00A0) == 0xA0
    assert WinAnsi.code(?-) == 0x2D
    assert WinAnsi.code(?\s) == 0x20
  end

  test "first_unencodable/1 names the first character WinAnsi cannot encode" do
    assert WinAnsi.first_unencodable("Größe") == nil
    assert WinAnsi.first_unencodable("€ – “quoted” …") == nil
    assert WinAnsi.first_unencodable("Ελλάδα") == 0x0395
    assert WinAnsi.first_unencodable("Größe Ελλάδα") == 0x0395
    assert WinAnsi.first_unencodable("tab\there") == ?\t
  end
end

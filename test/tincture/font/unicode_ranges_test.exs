defmodule Tincture.Font.UnicodeRangesTest do
  use ExUnit.Case, async: true

  alias Tincture.Font.UnicodeRanges

  # A font advertising coverage of exactly `bits`, as the four ulUnicodeRange words.
  defp ranges_with(bits) do
    Enum.reduce(bits, {0, 0, 0, 0}, fn bit, acc ->
      word_index = Bitwise.bsr(bit, 5)
      mask = Bitwise.bsl(1, Bitwise.band(bit, 31))

      acc
      |> Tuple.to_list()
      |> List.update_at(word_index, &Bitwise.bor(&1, mask))
      |> List.to_tuple()
    end)
  end

  describe "bit_for_codepoint/1" do
    test "maps the Latin blocks the original implementation covered" do
      assert UnicodeRanges.bit_for_codepoint(?A) == 0
      assert UnicodeRanges.bit_for_codepoint(0x00E9) == 1
      assert UnicodeRanges.bit_for_codepoint(0x0100) == 2
      assert UnicodeRanges.bit_for_codepoint(0x0180) == 3
    end

    test "maps blocks above bit 31, which the original implementation could not reach" do
      assert UnicodeRanges.bit_for_codepoint(0x20AC) == 33, "Euro sign / Currency Symbols"
      assert UnicodeRanges.bit_for_codepoint(0x2200) == 38, "Mathematical Operators"
      assert UnicodeRanges.bit_for_codepoint(0x3042) == 49, "Hiragana"
      assert UnicodeRanges.bit_for_codepoint(0x30A2) == 50, "Katakana"
      assert UnicodeRanges.bit_for_codepoint(0xAC00) == 56, "Hangul Syllables"
      assert UnicodeRanges.bit_for_codepoint(0x4E2D) == 59, "CJK Unified Ideographs"
      assert UnicodeRanges.bit_for_codepoint(0x1D400) == 89, "Math Alphanumeric Symbols"
    end

    test "maps discontiguous blocks that share a single bit" do
      # Bit 9 is Cyrillic, spread across four separate ranges.
      assert UnicodeRanges.bit_for_codepoint(0x0410) == 9
      assert UnicodeRanges.bit_for_codepoint(0x0500) == 9
      assert UnicodeRanges.bit_for_codepoint(0x2DE0) == 9
      assert UnicodeRanges.bit_for_codepoint(0xA640) == 9
    end

    test "returns nil for codepoints in no assigned block" do
      # 0x0870 sits between Thaana (0780-07BF) and Devanagari (0900-097F) with
      # no ulUnicodeRange bit assigned to it.
      assert UnicodeRanges.bit_for_codepoint(0x0870) == nil
      assert UnicodeRanges.bit_for_codepoint(0x10FFFE) == nil
    end

    test "every assigned bit stays within the 128-bit field" do
      for codepoint <- [?A, 0x20AC, 0x4E2D, 0xAC00, 0x1D400, 0x100000] do
        bit = UnicodeRanges.bit_for_codepoint(codepoint)
        assert bit >= 0 and bit <= 122, "bit #{bit} for U+#{Integer.to_string(codepoint, 16)}"
      end
    end
  end

  describe "supports_codepoint?/2" do
    test "reads coverage out of ulUnicodeRange1 (bits 0-31)" do
      assert UnicodeRanges.supports_codepoint?(ranges_with([0]), ?A)
      refute UnicodeRanges.supports_codepoint?(ranges_with([1]), ?A)
    end

    test "reads coverage out of words 2, 3 and 4" do
      # This is the regression the old implementation could never pass: div(bit, 32)
      # was always 0, so range2/3/4 were read from the font and then ignored.
      assert UnicodeRanges.supports_codepoint?(ranges_with([33]), 0x20AC), "word 2"
      assert UnicodeRanges.supports_codepoint?(ranges_with([59]), 0x4E2D), "word 2, CJK"
      assert UnicodeRanges.supports_codepoint?(ranges_with([75]), 0x1200), "word 3, Ethiopic"
      assert UnicodeRanges.supports_codepoint?(ranges_with([110]), 0x12000), "word 4, Cuneiform"
    end

    test "does not report coverage a font never advertised" do
      # A Latin-only font must not claim to cover CJK.
      latin_only = ranges_with([0, 1, 2, 3])
      assert UnicodeRanges.supports_codepoint?(latin_only, ?A)
      refute UnicodeRanges.supports_codepoint?(latin_only, 0x4E2D)
      refute UnicodeRanges.supports_codepoint?(latin_only, 0xAC00)
    end

    test "a bit set in one word does not leak into another" do
      # Bit 33 lives in word 2. Setting only word 1's bit 1 must not satisfy it.
      refute UnicodeRanges.supports_codepoint?({Bitwise.bsl(1, 1), 0, 0, 0}, 0x20AC)
    end

    test "returns false for unmapped codepoints even when every bit is set" do
      all_set = {0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF}
      refute UnicodeRanges.supports_codepoint?(all_set, 0x0870)
    end

    test "returns false for malformed range tuples" do
      refute UnicodeRanges.supports_codepoint?(nil, ?A)
      refute UnicodeRanges.supports_codepoint?({0, 0}, ?A)
      refute UnicodeRanges.supports_codepoint?({:a, :b, :c, :d}, ?A)
    end

    test "returns false for negative codepoints" do
      refute UnicodeRanges.supports_codepoint?(ranges_with([0]), -1)
    end
  end

  describe "all_zero?/1" do
    test "true only when the font advertises no coverage at all" do
      assert UnicodeRanges.all_zero?({0, 0, 0, 0})
      refute UnicodeRanges.all_zero?({1, 0, 0, 0})
      refute UnicodeRanges.all_zero?({0, 0, 0, 1})
      refute UnicodeRanges.all_zero?(nil)
    end
  end
end

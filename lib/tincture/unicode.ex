defmodule Tincture.Unicode do
  @moduledoc false
  @combining_mark_regex ~r/^\p{M}$/u

  # A default-ignorable code point - a variation selector, a zero-width
  # joiner or non-joiner, a zero-width space, a soft hyphen, a bidi control,
  # a tag character - is a format or control character, not a letter to be
  # drawn: a font that lacks it is not reported as missing a glyph
  # (Tincture.PDF.Ops), and the character is not drawn at all
  # (Tincture.Font.Context.drawn_text/3).
  #
  # The set is Unicode's derived property, which the file derives from
  # Other_Default_Ignorable_Code_Point, the format characters (Cf) and the
  # variation selectors, less white space and a few exceptions.
  #
  # Default_Ignorable_Code_Point, from DerivedCoreProperties-17.0.0.txt
  # (Unicode 17.0.0, dated 2025-07-30; the Unicode version Elixir 1.19 is
  # built on), https://www.unicode.org/Public/17.0.0/ucd/, with adjacent
  # entries merged: 4174 code points, the file's own total.
  @default_ignorable [
    0x00AD..0x00AD,
    0x034F..0x034F,
    0x061C..0x061C,
    0x115F..0x1160,
    0x17B4..0x17B5,
    0x180B..0x180F,
    0x200B..0x200F,
    0x202A..0x202E,
    0x2060..0x206F,
    0x3164..0x3164,
    0xFE00..0xFE0F,
    0xFEFF..0xFEFF,
    0xFFA0..0xFFA0,
    0xFFF0..0xFFF8,
    0x1BCA0..0x1BCA3,
    0x1D173..0x1D17A,
    0xE0000..0xE0FFF
  ]

  @spec default_ignorable?(integer()) :: boolean()
  def default_ignorable?(codepoint), do: Enum.any?(@default_ignorable, &(codepoint in &1))

  @spec zero_advance_codepoint?(integer()) :: boolean()
  def zero_advance_codepoint?(codepoint) when is_integer(codepoint) do
    variation_selector_codepoint?(codepoint) or join_control_codepoint?(codepoint) or
      combining_mark_codepoint?(codepoint)
  end

  def zero_advance_codepoint?(_codepoint), do: false

  @spec variation_selector_codepoint?(integer()) :: boolean()
  def variation_selector_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0xFE00 and codepoint <= 0xFE0F,
      do: true

  def variation_selector_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0xE0100 and codepoint <= 0xE01EF,
      do: true

  def variation_selector_codepoint?(_codepoint), do: false

  @spec join_control_codepoint?(integer()) :: boolean()
  def join_control_codepoint?(0x200C), do: true
  def join_control_codepoint?(0x200D), do: true
  def join_control_codepoint?(0x2060), do: true
  def join_control_codepoint?(_codepoint), do: false

  @spec combining_mark_codepoint?(integer()) :: boolean()
  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0x0300 and codepoint <= 0x036F,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0x1AB0 and codepoint <= 0x1AFF,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0x1DC0 and codepoint <= 0x1DFF,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0x20D0 and codepoint <= 0x20FF,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0xFE20 and codepoint <= 0xFE2F,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0 and codepoint <= 0x10FFFF do
    Regex.match?(@combining_mark_regex, <<codepoint::utf8>>)
  rescue
    _ -> false
  end

  def combining_mark_codepoint?(_codepoint), do: false
end

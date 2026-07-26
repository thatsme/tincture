defmodule Tincture.Typography.LineBreakTest do
  use ExUnit.Case

  alias Tincture.Typography.LineBreak

  test "break_text/4 keeps words on one line when width fits exactly" do
    # Courier at 10pt => each character is 6pt in standard metrics.
    assert LineBreak.break_text("one two", "Courier", 10, 42) == ["one two"]
  end

  test "break_text/4 performs greedy ragged-left wrapping by width" do
    assert LineBreak.break_text("alpha beta gamma", "Courier", 10, 42) == [
             "alpha",
             "beta",
             "gamma"
           ]
  end

  test "break_text/4 uses hyphenation for long words" do
    assert LineBreak.break_text("hyphenation", "Courier", 10, 42) == ["hy-", "phena-", "tion"]
  end

  test "break_text/5 supports hyphen left/right minima controls" do
    assert LineBreak.break_text("hyphenation", "Courier", 10, 42,
             hyphen_left_min: 4,
             hyphen_right_min: 4
           ) == ["hyphena-", "tion"]
  end

  test "break_text/5 supports mixed-locale hyphenation via locale_resolver" do
    resolver = fn
      "anker" -> :da_dk
      _word -> :en_gb
    end

    assert LineBreak.break_text("anker hyphenation", "Courier", 10, 24, locale_resolver: resolver) ==
             ["an-", "ker", "hy-", "phena-", "tion"]
  end

  test "break_text/5 rejects invalid locale_resolver option" do
    assert_raise ArgumentError, "locale_resolver must be a function with arity 1", fn ->
      LineBreak.break_text("anker", "Courier", 10, 24, locale_resolver: :da_dk)
    end
  end
end

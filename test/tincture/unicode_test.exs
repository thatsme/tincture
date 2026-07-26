defmodule Tincture.UnicodeTest do
  use ExUnit.Case

  alias Tincture.Unicode

  test "zero_advance_codepoint?/1 returns true for variation selectors" do
    assert Unicode.zero_advance_codepoint?(0xFE0F)
    assert Unicode.zero_advance_codepoint?(0xE0100)
  end

  test "zero_advance_codepoint?/1 returns true for join controls" do
    assert Unicode.zero_advance_codepoint?(0x200C)
    assert Unicode.zero_advance_codepoint?(0x200D)
    assert Unicode.zero_advance_codepoint?(0x2060)
  end

  test "zero_advance_codepoint?/1 returns true for combining marks" do
    assert Unicode.zero_advance_codepoint?(0x0301)
    assert Unicode.zero_advance_codepoint?(0x1AB2)
    assert Unicode.zero_advance_codepoint?(0x1DC1)
    assert Unicode.zero_advance_codepoint?(0x20D0)
    assert Unicode.zero_advance_codepoint?(0xFE20)
  end

  test "zero_advance_codepoint?/1 returns true for script-specific combining marks" do
    assert Unicode.zero_advance_codepoint?(0x05B0)
    assert Unicode.zero_advance_codepoint?(0x064E)
    assert Unicode.zero_advance_codepoint?(0x093C)
  end

  test "zero_advance_codepoint?/1 returns false for normal spacing codepoints" do
    refute Unicode.zero_advance_codepoint?(?A)
    refute Unicode.zero_advance_codepoint?(0x2603)
    refute Unicode.zero_advance_codepoint?(0x1F600)
  end
end

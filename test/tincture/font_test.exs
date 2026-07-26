defmodule Tincture.FontTest do
  use ExUnit.Case

  # Tincture ships no AFM fonts. The registry reads whatever :afm_path points
  # at, which the test environment aims at a synthetic fixture.
  test "registered_fonts/0 lists fonts found on the configured AFM path" do
    assert "Testface" in Tincture.Font.registered_fonts()
  end

  test "afm/1 returns parsed AFM for a font on the path" do
    assert {:ok, afm} = Tincture.Font.afm("Testface")
    assert afm.font_name == "Testface"
  end

  test "afm/1 returns :error for a font that is not there" do
    assert :error = Tincture.Font.afm("Nope-Font")
  end

  test "standard_font?/1 recognizes base 14 font names" do
    assert Tincture.Font.standard_font?("Helvetica")
    assert Tincture.Font.standard_font?("Times-Roman")
    assert Tincture.Font.standard_font?("Courier-BoldOblique")
    refute Tincture.Font.standard_font?("Not-A-Standard-Font")
  end

  test "font_available?/1 is true for standard and AFM fonts" do
    assert Tincture.Font.font_available?("Helvetica")
    assert Tincture.Font.font_available?("Testface")
    refute Tincture.Font.font_available?("Nope-Font")
  end

  test "text_width/3 applies AFM widths and kerning" do
    # T is 700 and o is 500, with a kerning pair of -200: exactly 10pt at size 10.
    width = Tincture.Font.text_width("Testface", 10, "To")
    assert_in_delta width, 10.0, 0.001
  end

  test "text_width/3 supports standard Helvetica widths" do
    width = Tincture.Font.text_width("Helvetica", 10, "Hello")
    assert_in_delta width, 22.78, 0.001
  end

  test "text_width/3 supports standard Times-Roman kerning" do
    width = Tincture.Font.text_width("Times-Roman", 10, "To")
    assert_in_delta width, 10.31, 0.001
  end

  test "text_width/3 ignores unmapped ZWJ for standard fonts" do
    base = Tincture.Font.text_width("Helvetica", 10, "AB")
    with_zwj = Tincture.Font.text_width("Helvetica", 10, "A‍B")
    assert_in_delta with_zwj, base, 0.001
  end

  test "text_width/3 ignores unmapped combining marks for standard fonts" do
    base = Tincture.Font.text_width("Helvetica", 10, "AB")
    with_combining = Tincture.Font.text_width("Helvetica", 10, "ÁB")
    assert_in_delta with_combining, base, 0.001
  end

  test "text_width/3 ignores unmapped combining marks for AFM fonts" do
    base = Tincture.Font.text_width("Testface", 10, "AB")
    with_combining = Tincture.Font.text_width("Testface", 10, "ÁB")
    assert_in_delta with_combining, base, 0.001
  end

  test "text_width/3 ignores unmapped script-specific combining marks for standard fonts" do
    base = Tincture.Font.text_width("Helvetica", 10, "AB")
    with_combining = Tincture.Font.text_width("Helvetica", 10, "AְB")
    assert_in_delta with_combining, base, 0.001
  end

  test "text_width/3 raises for unknown font" do
    assert_raise ArgumentError, fn ->
      Tincture.Font.text_width("Unknown-Font", 12, "hello")
    end
  end
end

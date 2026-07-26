defmodule Tincture.FontTest do
  use ExUnit.Case

  test "registered_fonts/0 lists available AFM-backed fonts" do
    fonts = Tincture.Font.registered_fonts()

    assert "Victorias-Secret" in fonts
    assert "OCR-A-Digits" in fonts
    assert "OCR-B-Digits" in fonts
  end

  test "afm/1 returns parsed AFM for known font" do
    assert {:ok, afm} = Tincture.Font.afm("Victorias-Secret")
    assert afm.font_name == "Victorias-Secret"
  end

  test "standard_font?/1 recognizes base 14 font names" do
    assert Tincture.Font.standard_font?("Helvetica")
    assert Tincture.Font.standard_font?("Times-Roman")
    assert Tincture.Font.standard_font?("Courier-BoldOblique")
    refute Tincture.Font.standard_font?("Not-A-Standard-Font")
  end

  test "font_available?/1 is true for standard and AFM fonts" do
    assert Tincture.Font.font_available?("Helvetica")
    assert Tincture.Font.font_available?("Victorias-Secret")
    refute Tincture.Font.font_available?("Nope-Font")
  end

  test "text_width/3 applies AFM widths and kerning" do
    width = Tincture.Font.text_width("Victorias-Secret", 10, "To")
    assert_in_delta width, 12.98, 0.001
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
    base = Tincture.Font.text_width("Victorias-Secret", 10, "AB")
    with_combining = Tincture.Font.text_width("Victorias-Secret", 10, "ÁB")
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

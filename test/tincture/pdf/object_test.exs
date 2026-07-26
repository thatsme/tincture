defmodule Tincture.PDF.ObjectTest do
  @moduledoc """
  Direct tests for the PDF syntax primitives.

  These were private to `Tincture.PDF.Serialize`, so string escaping could only
  be tested by generating a whole document and grepping the bytes. They are the
  leaf encoders every other part of the writer depends on, which makes them
  worth pinning precisely — a wrong escape produces a structurally broken PDF
  rather than a visibly wrong one.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF.Object

  describe "num/1" do
    test "integers are written as-is" do
      assert Object.num(0) == "0"
      assert Object.num(-42) == "-42"
      assert Object.num(595) == "595"
    end

    test "floats drop trailing zeros" do
      assert Object.num(1.0) == "1.0"
      assert Object.num(1.5) == "1.5"
      assert Object.num(72.25) == "72.25"
    end

    test "floats do not fall back to scientific notation" do
      # A PDF reader will not accept 1.0e-5 where it expects a number.
      refute Object.num(0.00001) =~ "e"
      refute Object.num(123_456_789.5) =~ "e"
    end

    test "output is stable, so identical documents hash identically" do
      assert Object.num(1.10) == Object.num(1.1)
    end
  end

  describe "format_text/2 with :pdf_text" do
    test "plain ASCII becomes a literal string" do
      assert Object.format_text("Hello") == "(Hello)"
    end

    test "escapes the characters that would terminate or continue the string" do
      assert Object.format_text("a(b") == "(a\\(b)"
      assert Object.format_text("a)b") == "(a\\)b)"
      assert Object.format_text("a\\b") == "(a\\\\b)"
    end

    test "escapes an unbalanced parenthesis, which is the case that breaks parsers" do
      assert Object.format_text("(((") == "(\\(\\(\\()"
    end

    test "control characters become three-digit octal escapes" do
      assert Object.format_text("a\nb") == "(a\\012b)"
      assert Object.format_text("a\tb") == "(a\\011b)"
      assert Object.format_text(<<0>>) == "(\\000)"
    end

    test "non-ASCII switches to a UTF-16BE hex string with a byte order mark" do
      encoded = Object.format_text("é")

      assert String.starts_with?(encoded, "<FEFF")
      assert String.ends_with?(encoded, ">")
      assert encoded == "<FEFF00E9>"
    end

    test "non-BMP characters survive as surrogate pairs" do
      # U+1F600, which needs two UTF-16 code units.
      assert Object.format_text("😀") == "<FEFFD83DDE00>"
    end

    test "an empty string is still a valid literal" do
      assert Object.format_text("") == "()"
    end

    test "defaults to :pdf_text" do
      assert Object.format_text("x") == Object.format_text("x", :pdf_text)
    end
  end

  describe "format_text/2 with :identity_h" do
    test "always produces hex, with no byte order mark" do
      # Identity-H bytes are glyph indices, not characters, so a BOM would be
      # interpreted as a glyph.
      encoded = Object.format_text("AB", :identity_h)

      assert encoded == "<00410042>"
      refute String.starts_with?(encoded, "<FEFF")
    end

    test "plain ASCII is not shortened to a literal" do
      assert Object.format_text("Hello", :identity_h) =~ ~r/^<[0-9A-F]+>$/
    end
  end

  describe "encode_text/2" do
    test "reports which form it chose" do
      assert Object.encode_text("plain", :pdf_text) == {:literal, "plain"}
      assert {:hex, "FEFF00E9"} = Object.encode_text("é", :pdf_text)
      assert {:hex, _} = Object.encode_text("plain", :identity_h)
    end
  end

  describe "unicode_text?/1" do
    test "true only when a codepoint exceeds 7-bit ASCII" do
      refute Object.unicode_text?("plain ascii ~!@#")
      refute Object.unicode_text?("")
      assert Object.unicode_text?("é")
      assert Object.unicode_text?("日本語")
    end

    test "DEL and below are still ASCII" do
      refute Object.unicode_text?(<<127>>)
    end
  end

  describe "escape_byte/1" do
    test "the three reserved characters" do
      assert Object.escape_byte(?() == "\\("
      assert Object.escape_byte(?)) == "\\)"
      assert Object.escape_byte(?\\) == "\\\\"
    end

    test "printable ASCII passes through untouched" do
      assert Object.escape_byte(?A) == "A"
      assert Object.escape_byte(?\s) == " "
      assert Object.escape_byte(?~) == "~"
    end

    test "octal escapes are always three digits" do
      assert Object.escape_byte(0) == "\\000"
      assert Object.escape_byte(7) == "\\007"
      assert Object.escape_byte(255) == "\\377"
    end
  end

  describe "sanitize_name/1" do
    test "keeps characters legal in a PDF name" do
      assert Object.sanitize_name("Helvetica") == "Helvetica"
      assert Object.sanitize_name("ABCDEF+Inter") == "ABCDEF+Inter"
      assert Object.sanitize_name("Font-Bold_2") == "Font-Bold_2"
    end

    test "replaces characters that would break a name object" do
      assert Object.sanitize_name("My Font") == "My_Font"
      assert Object.sanitize_name("a/b") == "a_b"
      assert Object.sanitize_name("a#b") == "a_b"
    end

    test "never returns an empty name" do
      # An empty /BaseFont would make the document structurally invalid.
      assert Object.sanitize_name("") == "EmbeddedTTF"
      assert Object.sanitize_name("///") == "___"
    end
  end
end

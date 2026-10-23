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

  describe "format_text/2 with :win_ansi" do
    test "each character becomes its WinAnsi code, octal-escaped above ASCII" do
      assert Object.format_text("Größe", :win_ansi) == ~S"(Gr\366\337e)"
    end

    test "the codes that differ from Latin-1 use WinAnsi's" do
      # U+20AC EURO SIGN is 0x80 and U+2014 EM DASH 0x97 in WinAnsi.
      assert Object.format_text("€—", :win_ansi) == ~S"(\200\227)"
    end

    test "ASCII is written as :pdf_text writes it" do
      assert Object.format_text("a (b) \\", :win_ansi) == Object.format_text("a (b) \\")
    end

    test "a character WinAnsi does not encode raises" do
      assert_raise ArgumentError, ~r/WinAnsi cannot encode "Ε"/, fn ->
        Object.format_text("Ελλάδα", :win_ansi)
      end
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

  describe "unescape_literal/1, against ISO 32000-1 7.3.4.2" do
    # The section's own examples, as they appear on pages 15 and 16, with the
    # enclosing parentheses removed.

    test "Example 1: newlines and balanced parentheses need no escape" do
      assert Object.unescape_literal("This is a string") == "This is a string"

      assert Object.unescape_literal("Strings may contain newlines\nand such.") ==
               "Strings may contain newlines\nand such."

      assert Object.unescape_literal(
               "Strings may contain balanced parentheses ( ) and\nspecial characters (*!&}^% and so on)."
             ) ==
               "Strings may contain balanced parentheses ( ) and\nspecial characters (*!&}^% and so on)."

      assert Object.unescape_literal("") == ""
      assert Object.unescape_literal("It has zero (0) length.") == "It has zero (0) length."
    end

    test "Example 2: a backslash at the end of a line continues the string" do
      assert Object.unescape_literal("These \\\ntwo strings \\\nare the same.") ==
               "These two strings are the same."

      assert Object.unescape_literal("These \\\r\ntwo strings \\\rare the same.") ==
               "These two strings are the same."
    end

    test "Example 3: an end-of-line marker, written or escaped, is one LINE FEED" do
      assert Object.unescape_literal("This string has an end-of-line at the end of it.\n") ==
               "This string has an end-of-line at the end of it.\n"

      assert Object.unescape_literal("So does this one.\\n") == "So does this one.\n"
      assert Object.unescape_literal("a\rb\r\nc\nd") == "a\nb\nc\nd"
    end

    test "Example 4: octal escapes give bytes outside printable ASCII" do
      assert Object.unescape_literal("This string contains \\245two octal characters\\307.") ==
               "This string contains " <> <<0o245>> <> "two octal characters" <> <<0o307>> <> "."
    end

    test "Example 5: one to three octal digits" do
      assert Object.unescape_literal("\\0053") == <<0o005, ?3>>
      assert Object.unescape_literal("\\053") == "+"
      assert Object.unescape_literal("\\53") == "+"
    end

    test "Table 3, every sequence" do
      assert Object.unescape_literal("\\n\\r\\t\\b\\f\\(\\)\\\\") == "\n\r\t\b\f()\\"
    end

    test "high-order overflow in an octal escape is ignored" do
      assert Object.unescape_literal("\\777") == <<0o777 |> rem(256)>>
    end

    test "a backslash before any other character is ignored" do
      assert Object.unescape_literal("\\q\\8\\ ") == "q8 "
    end
  end

  describe "unescape_literal/1 inverts what the writer escapes" do
    # The writer's literal path: what format_text/1 does for a string it writes
    # as a literal, one escape_byte/1 per byte. The encryptor relies on undoing
    # it exactly; when the two disagreed, encrypted strings were corrupted.
    defp written_literal(bytes),
      do: bytes |> :binary.bin_to_list() |> Enum.map_join(&Object.escape_byte/1)

    defp mismatches(strings) do
      for bytes <- strings, Object.unescape_literal(written_literal(bytes)) != bytes, do: bytes
    end

    test "every single byte" do
      assert mismatches(for(byte <- 0..255, do: <<byte>>)) == []
    end

    test "every pair of bytes" do
      assert mismatches(for(a <- 0..255, b <- 0..255, do: <<a, b>>)) == []
    end

    test "1,000 strings of 0 to 64 random bytes, from a fixed seed" do
      {strings, _state} =
        Enum.map_reduce(1..1000, :rand.seed_s(:exsss, {7, 3, 37}), fn _n, state ->
          {length, state} = :rand.uniform_s(65, state)

          Enum.map_reduce(1..(length - 1)//1, state, fn _i, state ->
            {byte, state} = :rand.uniform_s(256, state)
            {byte - 1, state}
          end)
          |> then(fn {bytes, state} -> {:erlang.list_to_binary(bytes), state} end)
        end)

      assert mismatches(strings) == []
    end

    test "every ASCII string format_text/1 writes as a literal" do
      for byte <- 0..127 do
        assert "(" <> literal = Object.format_text(<<byte>>)
        assert Object.unescape_literal(String.slice(literal, 0..-2//1)) == <<byte>>
      end
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

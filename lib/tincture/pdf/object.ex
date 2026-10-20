defmodule Tincture.PDF.Object do
  @moduledoc """
  Primitives for writing PDF object syntax.

  These are the leaf encoders shared by everything that emits PDF: numbers,
  strings and names. They were previously private to `Tincture.PDF.Serialize`,
  which meant the font-embedding code and the page-structure code could only
  reach them by living in the same 3,500-line module.

  Two string encodings matter here:

    * `:pdf_text` — a document string such as a title, bookmark label or link
      URL. ASCII is written as a literal `(...)` with the reserved bytes
      escaped; anything else becomes a UTF-16BE hex string with a byte order
      mark, which is how the PDF specification carries non-Latin-1 text.
    * `:identity_h` — text drawn with a composite (Type0) font, where the bytes
      are glyph indices rather than characters and must be written as hex with
      no byte order mark.
  """

  @doc """
  Format a number for PDF output.

  Floats are written with up to ten decimals and no trailing zeros, so
  coordinates stay readable and byte-stable across runs.
  """
  @spec num(number()) :: String.t()
  def num(value) when is_integer(value), do: Integer.to_string(value)

  def num(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact, {:decimals, 10}])

  @doc """
  Encode `text` as a PDF string, wrapped in its delimiters.

  See the module documentation for the difference between the two modes.
  """
  @spec format_text(String.t(), :pdf_text | :identity_h) :: String.t()
  def format_text(text, mode \\ :pdf_text) do
    case encode_text(text, mode) do
      {:literal, encoded} -> "(#{encoded})"
      {:hex, encoded} -> "<#{encoded}>"
    end
  end

  @doc """
  Encode `text` without delimiters, reporting which form was produced.
  """
  @spec encode_text(String.t(), :pdf_text | :identity_h) ::
          {:literal, String.t()} | {:hex, String.t()}
  def encode_text(text, :identity_h) do
    encoded =
      text
      |> :unicode.characters_to_binary(:utf8, {:utf16, :big})
      |> Base.encode16(case: :upper)

    {:hex, encoded}
  end

  def encode_text(text, :pdf_text) do
    if unicode_text?(text) do
      utf16 =
        text
        |> :unicode.characters_to_binary(:utf8, {:utf16, :big})
        |> then(fn utf16be -> <<0xFE, 0xFF, utf16be::binary>> end)
        |> Base.encode16(case: :upper)

      {:hex, utf16}
    else
      escaped =
        text
        |> String.to_charlist()
        |> Enum.map_join(&escape_byte/1)

      {:literal, escaped}
    end
  end

  @doc """
  Returns true when `text` contains anything outside 7-bit ASCII, and therefore
  cannot be written as a literal PDF string.
  """
  @spec unicode_text?(String.t()) :: boolean()
  def unicode_text?(text) do
    text
    |> String.to_charlist()
    |> Enum.any?(fn codepoint -> codepoint > 127 end)
  end

  @doc """
  Escape one byte for inclusion in a literal PDF string.

  Parentheses and the backslash are the reserved characters; anything outside
  printable ASCII is written as a three-digit octal escape.
  """
  @spec escape_byte(integer()) :: String.t()
  def escape_byte(?(), do: "\\("
  def escape_byte(?)), do: "\\)"
  def escape_byte(?\\), do: "\\\\"

  def escape_byte(byte) when byte < 32 or byte > 126 do
    "\\" <> String.pad_leading(Integer.to_string(byte, 8), 3, "0")
  end

  def escape_byte(byte), do: <<byte>>

  @doc false
  # The bytes of a literal string, given its contents without the enclosing
  # parentheses: the inverse of `escape_byte/1`, and of every other form ISO
  # 32000-1 7.3.4.2 allows, in one pass. Table 3's escapes; `\ddd` as one to
  # three octal digits, high-order overflow ignored; a backslash before an
  # end-of-line marker continues the string, and both are dropped; a backslash
  # before any other character is ignored; and an end-of-line marker without
  # one, CR, LF or CR LF, is a single LINE FEED.
  @spec unescape_literal(binary()) :: binary()
  def unescape_literal(contents) when is_binary(contents), do: unescape(contents, [])

  defp unescape(<<>>, acc), do: acc |> Enum.reverse() |> :erlang.list_to_binary()
  defp unescape(<<"\\n", rest::binary>>, acc), do: unescape(rest, [?\n | acc])
  defp unescape(<<"\\r", rest::binary>>, acc), do: unescape(rest, [?\r | acc])
  defp unescape(<<"\\t", rest::binary>>, acc), do: unescape(rest, [?\t | acc])
  defp unescape(<<"\\b", rest::binary>>, acc), do: unescape(rest, [?\b | acc])
  defp unescape(<<"\\f", rest::binary>>, acc), do: unescape(rest, [?\f | acc])
  defp unescape(<<"\\(", rest::binary>>, acc), do: unescape(rest, [?( | acc])
  defp unescape(<<"\\)", rest::binary>>, acc), do: unescape(rest, [?) | acc])
  defp unescape(<<"\\\\", rest::binary>>, acc), do: unescape(rest, [?\\ | acc])
  defp unescape(<<"\\\r\n", rest::binary>>, acc), do: unescape(rest, acc)
  defp unescape(<<"\\\r", rest::binary>>, acc), do: unescape(rest, acc)
  defp unescape(<<"\\\n", rest::binary>>, acc), do: unescape(rest, acc)

  defp unescape(<<"\\", digit, rest::binary>>, acc) when digit in ?0..?7,
    do: unescape_octal(rest, digit - ?0, 1, acc)

  defp unescape(<<"\\", rest::binary>>, acc), do: unescape(rest, acc)
  defp unescape(<<"\r\n", rest::binary>>, acc), do: unescape(rest, [?\n | acc])
  defp unescape(<<"\r", rest::binary>>, acc), do: unescape(rest, [?\n | acc])
  defp unescape(<<byte, rest::binary>>, acc), do: unescape(rest, [byte | acc])

  defp unescape_octal(<<digit, rest::binary>>, value, count, acc)
       when count < 3 and digit in ?0..?7,
       do: unescape_octal(rest, value * 8 + digit - ?0, count + 1, acc)

  defp unescape_octal(rest, value, _count, acc), do: unescape(rest, [rem(value, 256) | acc])

  @doc """
  Reduce `name` to characters legal in a PDF name object.

  Falls back to a placeholder rather than emitting an empty name, which would
  produce a structurally invalid document.
  """
  @spec sanitize_name(String.t()) :: String.t()
  def sanitize_name(name) do
    sanitized = String.replace(name, ~r/[^A-Za-z0-9_+\-]/, "_")
    if sanitized == "", do: "EmbeddedTTF", else: sanitized
  end
end

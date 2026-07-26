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

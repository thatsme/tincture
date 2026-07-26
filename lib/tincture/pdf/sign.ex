defmodule Tincture.PDF.Sign do
  @moduledoc """
  Applying a digital signature to a finished PDF.

  Every other part of Tincture is a pure transformation: a document goes in,
  bytes come out, and nothing depends on where those bytes land. A signature
  cannot work that way. It covers the *file*, including the offsets of its own
  objects, so it can only be computed once the file exists — and it then has to
  be written back into the middle of it without moving anything.

  So signing is a three-step dance:

  1. **Reserve.** The document is serialised with a signature dictionary whose
     `/Contents` is a run of zeros of a fixed size, and whose `/ByteRange` is a
     row of placeholders of a fixed width.
  2. **Measure.** The placeholders are replaced with the real offsets, written
     to exactly the same width so nothing shifts.
  3. **Sign.** The file *minus* the `/Contents` string is hashed and signed, and
     the result is written into the space reserved for it.

  Step 2 has to preserve every byte position, which is why the placeholders are
  fixed-width rather than formatted naturally. Writing `[0 1234 5678 90]` where
  `[0 ********** ...]` stood would move every subsequent byte and invalidate the
  offsets being recorded.

  ## What is signed

  `/ByteRange [0 a b c]` covers bytes `0..a` and `b..b+c` — that is, the whole
  file except the `<...>` holding the signature. A verifier repeats exactly that
  and compares. Anything altered afterwards, anywhere in the file, breaks it.

  ## What this does not do

  There is no timestamp authority (RFC 3161), so signatures carry the signing
  machine's own clock and cannot prove *when* they were made to a third party
  — only that the document has not changed since. That is the difference
  between this and a long-term validation signature.
  """

  alias Tincture.PDF.CMS

  # Enough for an RSA-4096 signature with a certificate chain. Reserved in the
  # file whether used or not, so generous rather than tight.
  @default_reserved_bytes 16_384

  # Fixed-width placeholder digits for each /ByteRange entry.
  @byte_range_width 10

  @doc """
  The placeholder signature dictionary written before the file exists.

  `/Contents` and `/ByteRange` are sized here and must not change size later.
  """
  @spec placeholder_dictionary(map()) :: String.t()
  def placeholder_dictionary(signature) do
    reserved = Map.get(signature, :reserved_bytes, @default_reserved_bytes)

    byte_range =
      "[0 #{placeholder_digits()} #{placeholder_digits()} #{placeholder_digits()}]"

    "<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached" <>
      " /ByteRange #{byte_range}" <>
      " /Contents <#{String.duplicate("0", reserved * 2)}>" <>
      optional_text(" /Name ", signature[:name]) <>
      optional_text(" /Reason ", signature[:reason]) <>
      optional_text(" /Location ", signature[:location]) <>
      optional_text(" /ContactInfo ", signature[:contact]) <>
      " /M #{pdf_date(signature.signing_time)} >>"
  end

  defp placeholder_digits, do: String.duplicate("*", @byte_range_width)

  defp optional_text(_key, nil), do: ""

  defp optional_text(key, value) when is_binary(value) do
    key <> Tincture.PDF.Object.format_text(value)
  end

  # PDF's own date format: D:YYYYMMDDHHmmSSZ
  defp pdf_date(%DateTime{} = date_time) do
    utc = date_time |> DateTime.to_unix() |> DateTime.from_unix!()

    parts =
      [utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second]
      |> Enum.map_join("", fn part ->
        part |> Integer.to_string() |> String.pad_leading(2, "0")
      end)

    "(D:#{parts}Z)"
  end

  @doc """
  Fill in the byte range and signature of a serialised document.

  Takes the bytes as written with placeholders, and returns them with the real
  offsets and a signature covering everything outside the `/Contents` string.
  """
  @spec apply_signature(binary(), map()) :: binary()
  def apply_signature(binary, signature) do
    reserved = Map.get(signature, :reserved_bytes, @default_reserved_bytes)
    placeholder = String.duplicate("0", reserved * 2)

    contents_start = contents_offset!(binary, placeholder)

    # The excluded span is the whole <...> string, angle brackets included.
    excluded_start = contents_start - 1
    excluded_length = byte_size(placeholder) + 2
    second_start = excluded_start + excluded_length
    second_length = byte_size(binary) - second_start

    binary =
      patch_byte_range(binary, [0, excluded_start, second_start, second_length])

    signed_bytes =
      binary_part(binary, 0, excluded_start) <>
        binary_part(binary, second_start, second_length)

    blob =
      CMS.sign_detached(
        signed_bytes,
        signature.private_key,
        signature.certificate,
        Map.get(signature, :chain, []),
        Map.get(signature, :digest, :sha256),
        signature.signing_time
      )

    if byte_size(blob) > reserved do
      raise ArgumentError,
            "the signature needs #{byte_size(blob)} bytes but only #{reserved} were reserved. " <>
              "Pass a larger :reserved_bytes to Tincture.sign/3."
    end

    hex = Base.encode16(blob, case: :upper)
    padded = hex <> String.duplicate("0", byte_size(placeholder) - byte_size(hex))

    binary_part(binary, 0, contents_start) <>
      padded <>
      binary_part(
        binary,
        contents_start + byte_size(placeholder),
        byte_size(binary) - contents_start - byte_size(placeholder)
      )
  end

  defp contents_offset!(binary, placeholder) do
    case :binary.match(binary, placeholder) do
      {offset, _length} ->
        offset

      :nomatch ->
        raise ArgumentError,
              "could not find the reserved signature space in the serialised document"
    end
  end

  # Each entry is written into a fixed-width field, so no byte moves and the
  # offsets recorded stay the ones being described.
  defp patch_byte_range(binary, values) do
    placeholder = "[0 #{placeholder_digits()} #{placeholder_digits()} #{placeholder_digits()}]"

    # The first entry is always 0 and is written literally, so only the three
    # measured offsets need padding.
    [0 | measured] = values

    replacement =
      "[0 " <>
        Enum.map_join(measured, " ", fn value ->
          value |> Integer.to_string() |> String.pad_trailing(@byte_range_width, " ")
        end) <> "]"

    case :binary.match(binary, placeholder) do
      {offset, length} ->
        binary_part(binary, 0, offset) <>
          replacement <>
          binary_part(binary, offset + length, byte_size(binary) - offset - length)

      :nomatch ->
        raise ArgumentError, "could not find the /ByteRange placeholder"
    end
  end

  @doc """
  The default number of bytes reserved for the signature.
  """
  @spec default_reserved_bytes() :: pos_integer()
  def default_reserved_bytes, do: @default_reserved_bytes
end

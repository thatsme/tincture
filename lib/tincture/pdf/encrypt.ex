defmodule Tincture.PDF.Encrypt do
  @moduledoc """
  Standard security handler, revision 6 — AES-256.

  Implements `/V 5 /R 6`, the encryption defined by PDF 2.0 (ISO 32000-2) and
  supported by Acrobat X and later, macOS Preview, pdf.js, PDFium, PDFBox,
  Ghostscript, qpdf and Poppler.

  Earlier handlers are deliberately not implemented. Revisions 2 and 3 use RC4,
  which is broken. Revision 4 pairs AES-128 with an MD5-based key derivation.
  Revision 5 was an Adobe extension superseded by revision 6, which adds the
  hardening loop that makes password guessing expensive.

  ## What this does and does not protect

  A **user password** is real encryption. Without it the document cannot be
  read, because the file encryption key is recoverable only from the password.

  An **owner password** on its own is not. The document is encrypted under the
  empty user password, so any reader can open it; the permission flags are
  advisory and enforced only by a viewer that chooses to. `qpdf --decrypt`
  removes them without knowing the password. That is a property of the PDF
  format, not of this implementation, and callers should not be led to believe
  otherwise.

  ## Structure

  A random 32-byte file encryption key is generated per document and never
  derived from a password. Each password instead protects a wrapped copy of
  that key: `/U` and `/UE` for the user password, `/O` and `/OE` for the owner
  password. Opening the document means deriving a key from the supplied
  password, using it to unwrap the file key, and decrypting with that.

  Under revision 6 every string and stream is encrypted with the file key
  directly — unlike revision 4, which derived a distinct key per object.
  """

  import Bitwise

  @typedoc "Everything needed to encrypt a document's strings and streams."
  @type t :: %{
          key: binary(),
          encrypt_dictionary: String.t(),
          id: binary()
        }

  @typedoc """
  A permission a viewer is asked to allow. Everything not listed is denied.

  These are advisory. See the note on owner passwords in the module docs.
  """
  @type permission ::
          :print
          | :modify
          | :copy
          | :annotate
          | :fill_forms
          | :extract_for_accessibility
          | :assemble
          | :print_high_quality

  # Permission bits, PDF specification table 22. Bit numbering there is
  # 1-based, so "bit 3" is 1 <<< 2.
  @permission_bits %{
    print: 1 <<< 2,
    modify: 1 <<< 3,
    copy: 1 <<< 4,
    annotate: 1 <<< 5,
    fill_forms: 1 <<< 8,
    extract_for_accessibility: 1 <<< 9,
    assemble: 1 <<< 10,
    print_high_quality: 1 <<< 11
  }

  # Bits 1-2 are reserved and must be 0; bits 7-8 and 13-32 are reserved and
  # must be 1. Starting from this and OR-ing in the granted permissions yields
  # a conforming /P value.
  @permission_base 0xFFFFF0C0

  @doc """
  Build an encryption context.

  ## Options

    * `:user_password` — required to open the document. Defaults to `""`,
      which means anyone can open it and only the permissions apply.
    * `:owner_password` — grants full rights. Defaults to the user password.
    * `:permissions` — the list of `t:permission/0` values a viewer is asked
      to allow. Defaults to all of them.
    * `:encrypt_metadata` — whether document metadata is encrypted along with
      the content. Defaults to `true`.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    user_password = normalize_password(Keyword.get(opts, :user_password, ""), :user_password)

    owner_password =
      normalize_password(Keyword.get(opts, :owner_password, user_password), :owner_password)

    permissions =
      normalize_permissions(Keyword.get(opts, :permissions, Map.keys(@permission_bits)))

    encrypt_metadata = Keyword.get(opts, :encrypt_metadata, true) == true

    # The file key is random, not derived from any password. Passwords protect
    # wrapped copies of it, which is what lets one document have two.
    file_key = :crypto.strong_rand_bytes(32)

    {u, ue} = user_entries(user_password, file_key)
    {o, oe} = owner_entries(owner_password, file_key, u)
    perms = perms_entry(file_key, permissions, encrypt_metadata)

    %{
      key: file_key,
      id: :crypto.strong_rand_bytes(16),
      encrypt_dictionary: encrypt_dictionary(u, ue, o, oe, perms, permissions, encrypt_metadata)
    }
  end

  @doc """
  Encrypt a string or stream body.

  A fresh initialisation vector is generated per call and prepended to the
  ciphertext, which is what the specification requires and what makes two
  identical strings in one document encrypt differently.
  """
  @spec encrypt(binary(), t()) :: binary()
  def encrypt(data, %{key: key}) when is_binary(data) do
    iv = :crypto.strong_rand_bytes(16)
    iv <> :crypto.crypto_one_time(:aes_256_cbc, key, iv, pad(data), encrypt: true, padding: :none)
  end

  @doc """
  The `/Encrypt` dictionary body, to be written as its own object.
  """
  @spec encrypt_dictionary(t()) :: String.t()
  def encrypt_dictionary(%{encrypt_dictionary: dictionary}), do: dictionary

  @doc """
  The document identifier, written into the trailer's `/ID`.
  """
  @spec id(t()) :: binary()
  def id(%{id: id}), do: id

  @doc """
  The `/P` value for a permission list — exposed for testing and inspection.
  """
  @spec permission_flags([permission()]) :: integer()
  def permission_flags(permissions) do
    granted =
      permissions
      |> normalize_permissions()
      |> Enum.reduce(0, fn permission, acc ->
        bor(acc, Map.fetch!(@permission_bits, permission))
      end)

    # /P is a signed 32-bit integer, so the reserved high bits make it negative.
    signed_32(bor(@permission_base, granted))
  end

  # -- password entries ------------------------------------------------------

  defp user_entries(password, file_key) do
    validation_salt = :crypto.strong_rand_bytes(8)
    key_salt = :crypto.strong_rand_bytes(8)

    u = hash_2b(password, validation_salt, "") <> validation_salt <> key_salt
    intermediate = hash_2b(password, key_salt, "")

    # A zero IV is specified here, not an oversight: the plaintext is a random
    # key, so there is nothing for an IV to protect against.
    ue =
      :crypto.crypto_one_time(:aes_256_cbc, intermediate, <<0::size(16)-unit(8)>>, file_key,
        encrypt: true,
        padding: :none
      )

    {u, ue}
  end

  defp owner_entries(password, file_key, u) do
    validation_salt = :crypto.strong_rand_bytes(8)
    key_salt = :crypto.strong_rand_bytes(8)

    # The owner hashes include /U, which binds the two passwords to one
    # document and stops an owner entry being lifted into another file.
    o = hash_2b(password, validation_salt, u) <> validation_salt <> key_salt
    intermediate = hash_2b(password, key_salt, u)

    oe =
      :crypto.crypto_one_time(:aes_256_cbc, intermediate, <<0::size(16)-unit(8)>>, file_key,
        encrypt: true,
        padding: :none
      )

    {o, oe}
  end

  # Algorithm 2.A's Perms block: the permissions, encrypted with the file key,
  # so a viewer can detect a /P that has been edited in the clear.
  defp perms_entry(file_key, permissions, encrypt_metadata) do
    p = permission_flags(permissions)
    metadata_flag = if encrypt_metadata, do: ?T, else: ?F

    block =
      <<p::32-little-signed, 0xFF, 0xFF, 0xFF, 0xFF, metadata_flag, ?a, ?d, ?b,
        :crypto.strong_rand_bytes(4)::binary>>

    :crypto.crypto_one_time(:aes_256_ecb, file_key, block, encrypt: true, padding: :none)
  end

  # -- Algorithm 2.B ---------------------------------------------------------

  # The revision 6 password hash. The loop is the point: it costs at least 64
  # rounds of AES and SHA per attempt, which is what makes guessing expensive.
  defp hash_2b(password, salt, udata) do
    initial = :crypto.hash(:sha256, password <> salt <> udata)
    hash_2b_round(initial, password, udata, 0)
  end

  defp hash_2b_round(k, password, udata, round) do
    <<aes_key::binary-size(16), iv::binary-size(16), _::binary>> = k

    k1 = :binary.copy(password <> k <> udata, 64)
    e = :crypto.crypto_one_time(:aes_128_cbc, aes_key, iv, k1, encrypt: true, padding: :none)

    <<first_16::binary-size(16), _::binary>> = e

    next_k =
      case rem(Enum.sum(:binary.bin_to_list(first_16)), 3) do
        0 -> :crypto.hash(:sha256, e)
        1 -> :crypto.hash(:sha384, e)
        2 -> :crypto.hash(:sha512, e)
      end

    next_round = round + 1

    # At least 64 rounds, then keep going until the last byte of E is small
    # enough. The termination condition is data-dependent by design.
    if next_round >= 64 and :binary.last(e) <= next_round - 32 do
      <<result::binary-size(32), _::binary>> = next_k
      result
    else
      hash_2b_round(next_k, password, udata, next_round)
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp encrypt_dictionary(u, ue, o, oe, perms, permissions, encrypt_metadata) do
    metadata = if encrypt_metadata, do: "", else: " /EncryptMetadata false"

    "<< /Filter /Standard /V 5 /R 6 /Length 256" <>
      " /CF << /StdCF << /CFM /AESV3 /AuthEvent /DocOpen /Length 32 >> >>" <>
      " /StmF /StdCF /StrF /StdCF" <>
      " /U <#{hex(u)}> /UE <#{hex(ue)}>" <>
      " /O <#{hex(o)}> /OE <#{hex(oe)}>" <>
      " /Perms <#{hex(perms)}>" <>
      " /P #{permission_flags(permissions)}#{metadata} >>"
  end

  defp hex(binary), do: Base.encode16(binary, case: :upper)

  # PKCS#5 padding, always adding a full block when the data is already
  # aligned so the padding length is never ambiguous.
  defp pad(data) do
    pad_length = 16 - rem(byte_size(data), 16)
    data <> :binary.copy(<<pad_length>>, pad_length)
  end

  defp signed_32(value) when value >= 0x80000000, do: value - 0x100000000
  defp signed_32(value), do: value

  # The specification calls for SASLprep. Passwords are truncated to 127 bytes
  # of UTF-8, which is the part that changes the resulting key; full SASLprep
  # normalisation only affects passwords containing unusual Unicode, and
  # getting it wrong there would produce a file the same library cannot open.
  defp normalize_password(password, _field) when is_binary(password) do
    binary_part(password, 0, min(byte_size(password), 127))
  end

  defp normalize_password(other, field),
    do: raise(ArgumentError, "#{field} must be a string, got: #{inspect(other)}")

  defp normalize_permissions(permissions) when is_list(permissions) do
    Enum.map(permissions, fn permission ->
      if Map.has_key?(@permission_bits, permission) do
        permission
      else
        raise ArgumentError,
              "unknown permission: #{inspect(permission)}. " <>
                "Valid: #{inspect(Map.keys(@permission_bits))}"
      end
    end)
  end

  defp normalize_permissions(other),
    do: raise(ArgumentError, "permissions must be a list, got: #{inspect(other)}")

  @doc """
  Encrypt the strings and stream body inside one serialised object.

  Applied to a finished object body rather than at each point a string is
  written, because every string in the document has to be encrypted and
  threading a context through every emitter would touch far more code than it
  would protect.

  Literal `(...)` and hex `<...>` strings are encrypted in place; `<<` and `>>`
  are dictionary delimiters and are left alone. A stream body is encrypted
  whole and its `/Length` corrected, since the ciphertext is longer than the
  plaintext by the initialisation vector plus padding.
  """
  @spec encrypt_object(iodata(), t()) :: iodata()
  def encrypt_object(body, context) when is_list(body) do
    # A stream object: [dictionary, data, "endstream"].
    case body do
      [dictionary, data, trailing] ->
        encrypted = encrypt(IO.iodata_to_binary(data), context)

        [
          dictionary
          |> IO.iodata_to_binary()
          |> replace_stream_length(byte_size(encrypted))
          |> encrypt_strings(context),
          encrypted,
          trailing
        ]

      other ->
        other |> IO.iodata_to_binary() |> encrypt_strings(context)
    end
  end

  def encrypt_object(body, context) when is_binary(body), do: encrypt_strings(body, context)

  defp replace_stream_length(dictionary, length) do
    String.replace(dictionary, ~r|/Length \d+|, "/Length #{length}", global: false)
  end

  @doc false
  # Walks a serialised object and encrypts each PDF string it contains.
  def encrypt_strings(body, context) when is_binary(body) do
    scan_strings(body, context, [])
  end

  defp scan_strings(<<>>, _context, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  # `<<` opens a dictionary, not a hex string. Consume both bytes so the second
  # `<` cannot be mistaken for the start of one.
  defp scan_strings(<<"<<", rest::binary>>, context, acc),
    do: scan_strings(rest, context, ["<<" | acc])

  defp scan_strings(<<">>", rest::binary>>, context, acc),
    do: scan_strings(rest, context, [">>" | acc])

  defp scan_strings(<<"(", rest::binary>>, context, acc) do
    {contents, remainder} = take_literal_string(rest, 0, [])
    encrypted = contents |> unescape_literal() |> encrypt(context) |> escape_literal()
    scan_strings(remainder, context, ["(#{encrypted})" | acc])
  end

  defp scan_strings(<<"<", rest::binary>>, context, acc) do
    case take_hex_string(rest, []) do
      {:ok, contents, remainder} ->
        encrypted =
          contents
          |> Base.decode16!(case: :mixed)
          |> encrypt(context)
          |> Base.encode16(case: :upper)

        scan_strings(remainder, context, ["<#{encrypted}>" | acc])

      :error ->
        scan_strings(rest, context, ["<" | acc])
    end
  end

  defp scan_strings(<<byte::binary-size(1), rest::binary>>, context, acc),
    do: scan_strings(rest, context, [byte | acc])

  # Literal strings nest parentheses, and a backslash escapes the next byte.
  defp take_literal_string(<<"\\", escaped::binary-size(1), rest::binary>>, depth, acc),
    do: take_literal_string(rest, depth, [escaped, "\\" | acc])

  defp take_literal_string(<<"(", rest::binary>>, depth, acc),
    do: take_literal_string(rest, depth + 1, ["(" | acc])

  defp take_literal_string(<<")", rest::binary>>, 0, acc),
    do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp take_literal_string(<<")", rest::binary>>, depth, acc),
    do: take_literal_string(rest, depth - 1, [")" | acc])

  defp take_literal_string(<<byte::binary-size(1), rest::binary>>, depth, acc),
    do: take_literal_string(rest, depth, [byte | acc])

  # An unterminated string cannot happen in output this library generates, but
  # returning what was read keeps the scanner total.
  defp take_literal_string(<<>>, _depth, acc),
    do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), <<>>}

  defp take_hex_string(<<">", rest::binary>>, acc) do
    hex = acc |> Enum.reverse() |> IO.iodata_to_binary()
    # An odd number of digits is legal in PDF (the last is padded with 0), but
    # nothing here emits one; treat it as not-a-string rather than guessing.
    if rem(byte_size(hex), 2) == 0, do: {:ok, hex, rest}, else: :error
  end

  defp take_hex_string(<<byte::binary-size(1), rest::binary>>, acc) do
    if byte =~ ~r/^[0-9A-Fa-f]$/, do: take_hex_string(rest, [byte | acc]), else: :error
  end

  defp take_hex_string(<<>>, _acc), do: :error

  defp unescape_literal(contents) do
    contents
    |> String.replace("\\(", "(")
    |> String.replace("\\)", ")")
    |> String.replace("\\\\", "\\")
  end

  defp escape_literal(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map_join(fn
      ?( ->
        "\\("

      ?) ->
        "\\)"

      ?\\ ->
        "\\\\"

      byte when byte < 32 or byte > 126 ->
        "\\" <> String.pad_leading(Integer.to_string(byte, 8), 3, "0")

      byte ->
        <<byte>>
    end)
  end
end

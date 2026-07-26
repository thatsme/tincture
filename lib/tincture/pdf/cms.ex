defmodule Tincture.PDF.CMS do
  @moduledoc """
  Detached PKCS#7 / CMS signatures, for signing PDFs.

  A PDF signature's `/Contents` holds a CMS `SignedData` blob covering the rest
  of the file. OTP ships no CMS encoder — `:public_key` handles certificates and
  raw signing, not this — so the structure is built here directly in DER.

  **Detached** means the signed content is not carried inside the blob: the
  bytes live in the PDF, and the signature refers to them by digest. That is
  what lets a signature cover the very file it sits in.

  ## What is produced

      ContentInfo
        contentType  id-signedData
        content [0]  SignedData
          version           1
          digestAlgorithms  { sha256 | sha384 | sha512 }
          encapContentInfo  id-data, with no content — detached
          certificates [0]  the signer, plus any chain given
          signerInfos       one SignerInfo
            sid              issuer and serial number
            signedAttrs [0]  contentType, signingTime, messageDigest
            signature        RSA over the DER of signedAttrs

  The signature covers the *signed attributes*, not the content directly, which
  is what CMS requires once `signedAttrs` is present. Those attributes carry the
  content's digest, so the content is still bound to the signature.

  ## Interoperability

  Output is verified against OpenSSL in the test suite rather than only against
  itself, because a signature format that only its author can read is not a
  signature format.
  """

  import Bitwise

  @id_data {1, 2, 840, 113_549, 1, 7, 1}
  @id_signed_data {1, 2, 840, 113_549, 1, 7, 2}
  @id_content_type {1, 2, 840, 113_549, 1, 9, 3}
  @id_message_digest {1, 2, 840, 113_549, 1, 9, 4}
  @id_signing_time {1, 2, 840, 113_549, 1, 9, 5}
  @rsa_encryption {1, 2, 840, 113_549, 1, 1, 1}

  @digest_oids %{
    sha256: {2, 16, 840, 1, 101, 3, 4, 2, 1},
    sha384: {2, 16, 840, 1, 101, 3, 4, 2, 2},
    sha512: {2, 16, 840, 1, 101, 3, 4, 2, 3}
  }

  @type digest :: :sha256 | :sha384 | :sha512

  @doc """
  Build a detached CMS signature over `content`.

  `certificate_der` is the signer's certificate; `chain` is any intermediate
  certificates to include, which a verifier needs when it does not already hold
  them. `signing_time` is a `DateTime` — passed in rather than read from the
  clock so that signing is reproducible and testable.
  """
  @spec sign_detached(binary(), tuple(), binary(), [binary()], digest(), DateTime.t()) ::
          binary()
  def sign_detached(content, private_key, certificate_der, chain, digest, signing_time)
      when is_binary(content) and is_binary(certificate_der) and is_list(chain) and
             is_map_key(@digest_oids, digest) do
    content_digest = :crypto.hash(digest, content)

    signed_attributes = signed_attributes(content_digest, signing_time)

    # The signature covers the attributes as a SET OF, even though they appear
    # in the SignerInfo tagged [0] IMPLICIT. Signing the tagged form is the
    # classic way to produce a blob nothing else will verify.
    signature = :public_key.sign(der_set(signed_attributes), digest, private_key)

    signer_info =
      der_sequence([
        der_integer(1),
        issuer_and_serial_number(certificate_der),
        algorithm_identifier(Map.fetch!(@digest_oids, digest)),
        der_context(0, :constructed, Enum.sort(signed_attributes)),
        algorithm_identifier(@rsa_encryption),
        der_octet_string(signature)
      ])

    signed_data =
      der_sequence([
        der_integer(1),
        der_set([algorithm_identifier(Map.fetch!(@digest_oids, digest))]),
        # No content: that is what makes the signature detached.
        der_sequence([der_oid(@id_data)]),
        der_context(0, :constructed, [certificate_der | chain]),
        der_set([signer_info])
      ])

    der_sequence([
      der_oid(@id_signed_data),
      der_context(0, :constructed, [signed_data])
    ])
  end

  defp signed_attributes(content_digest, signing_time) do
    [
      attribute(@id_content_type, der_oid(@id_data)),
      attribute(@id_signing_time, der_utc_time(signing_time)),
      attribute(@id_message_digest, der_octet_string(content_digest))
    ]
  end

  defp attribute(oid, value), do: der_sequence([der_oid(oid), der_set([value])])

  defp algorithm_identifier(oid), do: der_sequence([der_oid(oid), der_null()])

  # CMS identifies the signer by the certificate's issuer and serial number,
  # which must match the certificate byte for byte — so the issuer is
  # re-encoded from the parsed certificate rather than reconstructed.
  defp issuer_and_serial_number(certificate_der) do
    {:Certificate, tbs_certificate, _algorithm, _signature} =
      :public_key.pkix_decode_cert(certificate_der, :plain)

    serial_number = elem(tbs_certificate, 2)
    issuer = elem(tbs_certificate, 4)

    der_sequence([
      :public_key.pkix_encode(:Name, issuer, :plain),
      der_integer(serial_number)
    ])
  end

  # --- DER ------------------------------------------------------------------
  #
  # Tag, length, value. Only the handful of types CMS needs.

  @doc false
  def der_sequence(elements), do: der_tagged(0x30, IO.iodata_to_binary(elements))

  @doc false
  # DER requires the members of a SET OF to appear in ascending order of their
  # encodings. Verifiers that re-encode to check a signature will disagree
  # otherwise.
  def der_set(elements) do
    sorted = elements |> Enum.map(&IO.iodata_to_binary/1) |> Enum.sort()
    der_tagged(0x31, IO.iodata_to_binary(sorted))
  end

  @doc false
  def der_context(number, :constructed, elements) do
    der_tagged(0xA0 + number, IO.iodata_to_binary(elements))
  end

  @doc false
  def der_octet_string(value), do: der_tagged(0x04, value)

  @doc false
  def der_null, do: <<0x05, 0x00>>

  @doc false
  def der_integer(value) when is_integer(value) and value >= 0 do
    bytes = unsigned_bytes(value)

    # A leading bit of 1 would read as negative, so DER prefixes a zero byte.
    bytes = if :binary.first(bytes) >= 0x80, do: <<0>> <> bytes, else: bytes

    der_tagged(0x02, bytes)
  end

  defp unsigned_bytes(0), do: <<0>>
  defp unsigned_bytes(value) when value > 0, do: :binary.encode_unsigned(value)

  @doc false
  def der_oid(oid) when is_tuple(oid) do
    [first, second | rest] = Tuple.to_list(oid)

    body = IO.iodata_to_binary([<<first * 40 + second>> | Enum.map(rest, &base128/1)])

    der_tagged(0x06, body)
  end

  # Arcs after the first two are base-128 with the high bit set on every byte
  # but the last.
  defp base128(value) when value < 128, do: <<value>>

  defp base128(value), do: base128(bsr(value, 7), [band(value, 0x7F)])

  defp base128(0, [last | leading]) do
    leading
    |> Enum.map(&<<bor(&1, 0x80)>>)
    |> Enum.reverse()
    |> Kernel.++([<<last>>])
    |> IO.iodata_to_binary()
  end

  defp base128(value, acc), do: base128(bsr(value, 7), acc ++ [band(value, 0x7F)])

  @doc false
  def der_utc_time(%DateTime{} = date_time) do
    # Converted through a Unix timestamp so no time zone database is needed.
    utc = date_time |> DateTime.to_unix() |> DateTime.from_unix!()

    text =
      [utc.year |> rem(100), utc.month, utc.day, utc.hour, utc.minute, utc.second]
      |> Enum.map_join("", fn part ->
        part |> Integer.to_string() |> String.pad_leading(2, "0")
      end)

    der_tagged(0x17, text <> "Z")
  end

  defp der_tagged(tag, body) when is_binary(body) do
    <<tag>> <> der_length(byte_size(body)) <> body
  end

  defp der_length(length) when length < 0x80, do: <<length>>

  defp der_length(length) do
    bytes = unsigned_bytes(length)
    <<0x80 + byte_size(bytes)>> <> bytes
  end
end

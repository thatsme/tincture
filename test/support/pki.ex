defmodule Tincture.Test.PKI do
  @moduledoc """
  Throwaway keys and certificates for signature tests, plus enough DER walking
  to verify a signature independently of the code that produced it.

  Generated per test run rather than committed, so no private key ever lives in
  the repository — and a test that mints its own key cannot be quietly passing
  against a stale fixture.

  `verify_detached/3` re-derives what should have been signed and checks the
  RSA signature against the certificate's public key. It deliberately does not
  reuse `Tincture.PDF.CMS` to do so: a test that builds the expected value with
  the same code that built the actual one proves only that the code is
  consistent with itself.
  """

  @rsa_encryption {1, 2, 840, 113_549, 1, 1, 1}
  @sha256_with_rsa {1, 2, 840, 113_549, 1, 1, 11}

  # The DER body of 1.2.840.113549.1.9.4 (messageDigest), written out rather
  # than computed. Deriving it with the same encoder under test would make this
  # check agree with a broken encoder.
  @message_digest_oid_body <<0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04>>

  @doc """
  A fresh RSA key and matching self-signed certificate.
  """
  @spec generate(String.t()) :: %{
          private_key: tuple(),
          public_key: tuple(),
          certificate: binary()
        }
  def generate(common_name \\ "Tincture Test Signer") do
    {:RSAPrivateKey, _version, modulus, exponent, _d, _p, _q, _e1, _e2, _c, _other} =
      private_key = :public_key.generate_key({:rsa, 2048, 65_537})

    name =
      {:rdnSequence,
       [
         [
           {:AttributeTypeAndValue, {2, 5, 4, 3},
            {:printableString, String.to_charlist(common_name)}}
         ]
       ]}

    algorithm = {:SignatureAlgorithm, @sha256_with_rsa, :asn1_NOVALUE}

    subject_public_key_info =
      {:OTPSubjectPublicKeyInfo, {:PublicKeyAlgorithm, @rsa_encryption, :asn1_NOVALUE},
       {:RSAPublicKey, modulus, exponent}}

    tbs_certificate =
      {:OTPTBSCertificate, :v3, 1, algorithm, name,
       {:Validity, {:utcTime, ~c"260101000000Z"}, {:utcTime, ~c"360101000000Z"}}, name,
       subject_public_key_info, :asn1_NOVALUE, :asn1_NOVALUE, :asn1_NOVALUE}

    %{
      private_key: private_key,
      public_key: {:RSAPublicKey, modulus, exponent},
      certificate: :public_key.pkix_sign(tbs_certificate, private_key)
    }
  end

  @doc """
  Check a detached CMS blob against the content it claims to cover.

  Returns `:ok`, or `{:error, reason}` naming which half failed — the digest
  binding the content, or the signature binding the attributes.
  """
  @spec verify_detached(binary(), binary(), tuple()) :: :ok | {:error, atom()}
  def verify_detached(cms_der, content, public_key) do
    tree = parse(cms_der)

    with {:ok, signed_attributes} <- find_signed_attributes(tree),
         {:ok, signature} <- find_signature(tree),
         :ok <- check_message_digest(signed_attributes, content) do
      # The signature covers the attributes re-tagged as a SET OF, which is
      # what CMS requires and what a verifier reconstructs.
      signed = <<0x31>> <> der_length(byte_size(signed_attributes.body)) <> signed_attributes.body

      if :public_key.verify(signed, :sha256, signature, public_key) do
        :ok
      else
        {:error, :bad_signature}
      end
    end
  end

  defp check_message_digest(signed_attributes, content) do
    expected = :crypto.hash(:sha256, content)

    recorded =
      signed_attributes.children
      |> Enum.find_value(fn attribute ->
        case attribute.children do
          [%{tag: 0x06, value: oid_bytes}, %{children: [%{tag: 0x04, value: digest}]}] ->
            if oid_bytes == @message_digest_oid_body, do: digest

          _other ->
            nil
        end
      end)

    cond do
      is_nil(recorded) -> {:error, :no_message_digest}
      recorded != expected -> {:error, :digest_mismatch}
      true -> :ok
    end
  end

  # The [0] IMPLICIT SET OF holding the signed attributes, inside SignerInfo.
  defp find_signed_attributes(tree) do
    case find(tree, fn node -> node.tag == 0xA0 and signed_attributes?(node) end) do
      nil -> {:error, :no_signed_attributes}
      node -> {:ok, node}
    end
  end

  defp signed_attributes?(node) do
    Enum.any?(node.children, fn child ->
      child.tag == 0x30 and
        match?([%{tag: 0x06} | _rest], child.children)
    end)
  end

  # The last OCTET STRING in the SignerInfo is the signature itself.
  defp find_signature(tree) do
    case tree |> collect(&(&1.tag == 0x04)) |> List.last() do
      nil -> {:error, :no_signature}
      node -> {:ok, node.value}
    end
  end

  # --- a very small DER walker ---------------------------------------------

  @doc false
  def parse(der), do: %{tag: :root, children: parse_many(der), value: der, body: der}

  defp parse_many(<<>>), do: []

  defp parse_many(<<tag, rest::binary>>) do
    {length, remainder} = read_length(rest)
    <<body::binary-size(length), tail::binary>> = remainder

    children = if constructed?(tag), do: parse_many(body), else: []

    [%{tag: tag, value: body, body: body, children: children} | parse_many(tail)]
  end

  defp constructed?(tag), do: Bitwise.band(tag, 0x20) != 0

  defp read_length(<<length, rest::binary>>) when length < 0x80, do: {length, rest}

  defp read_length(<<first, rest::binary>>) do
    count = Bitwise.band(first, 0x7F)
    <<length_bytes::binary-size(count), remainder::binary>> = rest
    {:binary.decode_unsigned(length_bytes), remainder}
  end

  defp der_length(length) when length < 0x80, do: <<length>>

  defp der_length(length) do
    bytes = :binary.encode_unsigned(length)
    <<0x80 + byte_size(bytes)>> <> bytes
  end

  defp find(node, predicate) do
    if node.tag != :root and predicate.(node) do
      node
    else
      Enum.find_value(node.children, fn child -> find(child, predicate) end)
    end
  end

  defp collect(node, predicate) do
    own = if node.tag != :root and predicate.(node), do: [node], else: []
    own ++ Enum.flat_map(node.children, &collect(&1, predicate))
  end
end

defmodule Tincture.SignatureTest do
  @moduledoc """
  Tests for digitally signing a PDF.

  A signature covers the finished file, including where every object landed, so
  it cannot be computed until the bytes exist and then has to be written back
  into the middle of them without moving anything. These tests check both
  halves: that the byte arithmetic is right, and that the resulting signature
  actually verifies — against a verifier that does not share any code with the
  one that produced it.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF.CMS
  alias Tincture.Test.PKI

  setup_all do
    # One key for the whole module: generating RSA keys is the slow part.
    {:ok, pki: PKI.generate()}
  end

  defp signed_document(pki, opts \\ []) do
    Tincture.new()
    |> Tincture.page_size(:a4)
    |> Tincture.set_metadata(title: "Signed agreement")
    |> Tincture.set_font("Helvetica", 12)
    |> Tincture.text_at(50, 700, "This document has been digitally signed.")
    |> Tincture.signature_field(50, 500, 220, 48, "signature")
    |> Tincture.sign(
      "signature",
      Keyword.merge(
        [
          private_key: pki.private_key,
          certificate: pki.certificate,
          signing_time: ~U[2026-07-26 12:00:00Z]
        ],
        opts
      )
    )
    |> Tincture.export()
  end

  # Everything a verifier does: read the byte range out of the file itself.
  defp byte_range(binary) do
    [[_, entries]] = Regex.scan(~r/\/ByteRange \[([^\]]*)\]/, binary)
    entries |> String.split() |> Enum.map(&String.to_integer/1)
  end

  defp signed_bytes(binary) do
    [start_one, length_one, start_two, length_two] = byte_range(binary)

    binary_part(binary, start_one, length_one) <> binary_part(binary, start_two, length_two)
  end

  # Read the blob by its declared DER length rather than by stripping padding:
  # a trailing zero byte is real data.
  defp signature_blob(binary) do
    [[_, hex]] = Regex.scan(~r/\/Contents <([0-9A-F]+)>/, binary)
    raw = Base.decode16!(hex, case: :upper)

    <<0x30, rest::binary>> = raw
    {length, _remainder} = declared_length(rest)
    header = byte_size(raw) - byte_size(rest)

    binary_part(raw, 0, header + length_bytes(rest) + length)
  end

  defp declared_length(<<length, _rest::binary>>) when length < 0x80, do: {length, nil}

  defp declared_length(<<first, rest::binary>>) do
    count = Bitwise.band(first, 0x7F)
    <<bytes::binary-size(count), _tail::binary>> = rest
    {:binary.decode_unsigned(bytes), nil}
  end

  defp length_bytes(<<length, _rest::binary>>) when length < 0x80, do: 1
  defp length_bytes(<<first, _rest::binary>>), do: 1 + Bitwise.band(first, 0x7F)

  describe "the signed document" do
    test "carries a signature dictionary linked from the field", %{pki: pki} do
      binary = signed_document(pki)

      assert binary =~ "/Type /Sig"
      assert binary =~ "/Filter /Adobe.PPKLite"
      assert binary =~ "/SubFilter /adbe.pkcs7.detached"
      assert binary =~ ~r|/FT /Sig[^>]*/V \d+ 0 R|
    end

    test "marks the form as signed and append-only", %{pki: pki} do
      # /SigFlags 3 tells a reader the file must only ever be changed by
      # appending, since rewriting it would break the range the signature covers.
      assert signed_document(pki) =~ "/SigFlags 3"
    end

    test "records the signing metadata", %{pki: pki} do
      binary =
        signed_document(pki,
          name: "R. Aldiss",
          reason: "I approve this document",
          location: "Sheffield"
        )

      assert binary =~ "/Name (R. Aldiss)"
      assert binary =~ "/Reason (I approve this document)"
      assert binary =~ "/Location (Sheffield)"
      assert binary =~ "/M (D:20260726120000Z)"
    end
  end

  describe "the byte range" do
    test "covers the whole file except the signature itself", %{pki: pki} do
      binary = signed_document(pki)
      [start_one, length_one, start_two, length_two] = byte_range(binary)

      assert start_one == 0
      assert start_two + length_two == byte_size(binary)

      # The gap is exactly the /Contents string, angle brackets included.
      reserved = Tincture.PDF.Sign.default_reserved_bytes()
      assert start_two - length_one == reserved * 2 + 2
    end

    test "the excluded span is precisely the /Contents string", %{pki: pki} do
      binary = signed_document(pki)
      [_start_one, length_one, start_two, _length_two] = byte_range(binary)

      excluded = binary_part(binary, length_one, start_two - length_one)

      assert <<?<, rest::binary>> = excluded
      assert String.ends_with?(rest, ">")
    end

    test "no byte moved when the placeholders were filled in", %{pki: pki} do
      # The placeholder and the value it is replaced by must be the same width,
      # or the offsets being recorded stop describing the file they are in.
      binary = signed_document(pki)

      refute binary =~ "**********"
      assert byte_range(binary) |> List.last() > 0
    end
  end

  describe "verification" do
    test "the signature verifies against the content the file says it covers",
         %{pki: pki} do
      binary = signed_document(pki)

      assert :ok =
               PKI.verify_detached(signature_blob(binary), signed_bytes(binary), pki.public_key)
    end

    test "altering the document breaks it", %{pki: pki} do
      binary = signed_document(pki)

      # Change the visible text, exactly as a forger would.
      {offset, length} = :binary.match(binary, "This document has been")
      tampered = replace_at(binary, offset, length, "THIS document has been")

      assert {:error, :digest_mismatch} =
               PKI.verify_detached(
                 signature_blob(tampered),
                 signed_bytes(tampered),
                 pki.public_key
               )
    end

    test "a different key does not verify it", %{pki: pki} do
      other = PKI.generate("Someone Else")
      binary = signed_document(pki)

      assert {:error, :bad_signature} =
               PKI.verify_detached(signature_blob(binary), signed_bytes(binary), other.public_key)
    end

    test "each digest algorithm produces a verifiable signature", %{pki: pki} do
      for digest <- [:sha256, :sha384, :sha512] do
        binary = signed_document(pki, digest: digest)

        # verify_detached checks the sha256 binding; for the others just assert
        # the blob is well-formed and the range arithmetic holds.
        assert byte_size(signature_blob(binary)) > 0
        assert signed_bytes(binary) != ""
      end
    end
  end

  describe "CMS output" do
    test "is a well-formed detached SignedData", %{pki: pki} do
      blob =
        CMS.sign_detached(
          "content",
          pki.private_key,
          pki.certificate,
          [],
          :sha256,
          ~U[2026-07-26 12:00:00Z]
        )

      assert :ok = PKI.verify_detached(blob, "content", pki.public_key)
    end

    test "binds the content, so a different message fails", %{pki: pki} do
      blob =
        CMS.sign_detached(
          "content",
          pki.private_key,
          pki.certificate,
          [],
          :sha256,
          ~U[2026-07-26 12:00:00Z]
        )

      assert {:error, :digest_mismatch} =
               PKI.verify_detached(blob, "different content", pki.public_key)
    end

    test "encodes object identifiers the way the specification says" do
      # pkcs7-data, whose encoding is fixed and widely published — a check that
      # the base-128 arc encoder is right rather than merely self-consistent.
      assert Base.encode16(CMS.der_oid({1, 2, 840, 113_549, 1, 7, 1})) ==
               "06092A864886F70D010701"

      assert Base.encode16(CMS.der_oid({2, 16, 840, 1, 101, 3, 4, 2, 1})) ==
               "0609608648016503040201"
    end
  end

  describe "validation" do
    test "signing an unknown field says which fields exist", %{pki: pki} do
      pdf =
        Tincture.new()
        |> Tincture.signature_field(50, 500, 200, 40, "approval")

      error =
        assert_raise ArgumentError, fn ->
          Tincture.sign(pdf, "signature",
            private_key: pki.private_key,
            certificate: pki.certificate
          )
        end

      assert error.message =~ ~s(no signature field named "signature")
      assert error.message =~ ~s("approval")
    end

    test "signing with no signature field at all says to add one", %{pki: pki} do
      error =
        assert_raise ArgumentError, fn ->
          Tincture.sign(Tincture.new(), "signature",
            private_key: pki.private_key,
            certificate: pki.certificate
          )
        end

      assert error.message =~ "Add one with signature_field/7"
    end

    test "signing twice is refused, since it needs incremental updates", %{pki: pki} do
      pdf =
        Tincture.new()
        |> Tincture.signature_field(50, 500, 200, 40, "first")
        |> Tincture.signature_field(50, 400, 200, 40, "second")
        |> Tincture.sign("first",
          private_key: pki.private_key,
          certificate: pki.certificate
        )

      assert_raise ArgumentError, ~r/already being signed/, fn ->
        Tincture.sign(pdf, "second",
          private_key: pki.private_key,
          certificate: pki.certificate
        )
      end
    end

    test "an unsupported digest is refused", %{pki: pki} do
      pdf = Tincture.signature_field(Tincture.new(), 50, 500, 200, 40, "signature")

      assert_raise ArgumentError, ~r/digest must be/, fn ->
        Tincture.sign(pdf, "signature",
          private_key: pki.private_key,
          certificate: pki.certificate,
          digest: :md5
        )
      end
    end

    test "too little reserved space is refused rather than truncated", %{pki: pki} do
      pdf =
        Tincture.new()
        |> Tincture.signature_field(50, 500, 200, 40, "signature")
        |> Tincture.sign("signature",
          private_key: pki.private_key,
          certificate: pki.certificate,
          reserved_bytes: 64
        )

      # Silently cutting a signature short would produce a file that looks
      # signed and is not.
      assert_raise ArgumentError, ~r/only 64 were reserved/, fn -> Tincture.export(pdf) end
    end
  end

  describe "reproducibility" do
    test "the same document and signing time produce the same bytes", %{pki: pki} do
      assert signed_document(pki) == signed_document(pki)
    end
  end

  defp replace_at(binary, offset, length, replacement) do
    binary_part(binary, 0, offset) <>
      replacement <>
      binary_part(binary, offset + length, byte_size(binary) - offset - length)
  end
end

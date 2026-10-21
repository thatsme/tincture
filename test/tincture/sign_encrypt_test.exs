defmodule Tincture.SignEncryptTest do
  @moduledoc """
  A document cannot be both signed and encrypted. Through 0.3.x the
  combination was accepted by both calls and failed at export, with a message
  about the signature's reserved space; it never produced a file. Each call
  that would combine the two now refuses at once, naming itself and the
  combination.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO, only: [with_io: 2]

  alias Tincture.Test.PKI

  @sign_message " was called on a document that is encrypted. Tincture cannot sign an " <>
                  "encrypted document: sign it without encryption, or encrypt it without " <>
                  "a signature."

  @encrypt_message " was called on a document that is signed. Tincture cannot encrypt a " <>
                     "signed document: encrypt it without a signature, or sign it without " <>
                     "encryption."

  setup_all do
    %{pki: PKI.generate()}
  end

  defp with_field, do: Tincture.signature_field(Tincture.new(), 72, 600, 220, 48, "signature")

  defp signing_opts(pki), do: [private_key: pki.private_key, certificate: pki.certificate]

  # The refusal is an exception, and nothing is written to stderr first.
  defp assert_refused(message, fun) do
    {result, stderr} =
      with_io(:stderr, fn ->
        assert_raise ArgumentError, message, fun
      end)

    assert %ArgumentError{} = result
    assert stderr == ""
  end

  describe "signing an encrypted document" do
    test "sign/3 after encrypt/2 raises, naming sign/3", %{pki: pki} do
      pdf = with_field() |> Tincture.encrypt(user_password: "p")

      assert_refused("Tincture.sign/3" <> @sign_message, fn ->
        Tincture.sign(pdf, "signature", signing_opts(pki))
      end)
    end

    test "sign/3 after encrypt/1 raises, naming sign/3", %{pki: pki} do
      pdf = with_field() |> Tincture.encrypt()

      assert_refused("Tincture.sign/3" <> @sign_message, fn ->
        Tincture.sign(pdf, "signature", signing_opts(pki))
      end)
    end

    test "PDF.set_signature/3 after encrypt/2 raises, naming set_signature/3", %{pki: pki} do
      pdf = with_field() |> Tincture.encrypt(user_password: "p")

      assert_refused("Tincture.PDF.set_signature/3" <> @sign_message, fn ->
        Tincture.PDF.set_signature(pdf, "signature", signing_opts(pki))
      end)
    end
  end

  describe "encrypting a signed document" do
    test "encrypt/2 after sign/3 raises, naming encrypt/2", %{pki: pki} do
      pdf = with_field() |> Tincture.sign("signature", signing_opts(pki))

      assert_refused("Tincture.encrypt/2" <> @encrypt_message, fn ->
        Tincture.encrypt(pdf, user_password: "p")
      end)
    end

    test "encrypt/1 after sign/3 raises, naming encrypt/1", %{pki: pki} do
      pdf = with_field() |> Tincture.sign("signature", signing_opts(pki))

      assert_refused("Tincture.encrypt/1" <> @encrypt_message, fn ->
        Tincture.encrypt(pdf)
      end)
    end
  end

  describe "a document given both by setting its fields directly" do
    @export_message " was given a document that is both signed and encrypted. Tincture " <>
                      "cannot sign an encrypted document: sign it without encryption, or " <>
                      "encrypt it without a signature."

    # Neither refusing call is used: the encryption settings are copied into a
    # signed document's struct.
    defp signed_and_encrypted(pki) do
      encrypted = with_field() |> Tincture.encrypt(user_password: "p")
      signed = with_field() |> Tincture.sign("signature", signing_opts(pki))
      %{signed | encryption: encrypted.encryption}
    end

    test "export/2 raises, naming export/2", %{pki: pki} do
      pdf = signed_and_encrypted(pki)

      assert_refused("Tincture.export/2" <> @export_message, fn ->
        Tincture.export(pdf, [])
      end)
    end

    test "export/1 raises, naming export/1", %{pki: pki} do
      pdf = signed_and_encrypted(pki)

      assert_refused("Tincture.export/1" <> @export_message, fn ->
        Tincture.export(pdf)
      end)
    end

    test "export/2 raises with enforce: false too", %{pki: pki} do
      pdf = signed_and_encrypted(pki)

      assert_refused("Tincture.export/2" <> @export_message, fn ->
        Tincture.export(pdf, enforce: false)
      end)
    end
  end

  describe "either one alone" do
    test "a signed document still exports", %{pki: pki} do
      binary =
        with_field()
        |> Tincture.sign("signature", signing_opts(pki))
        |> Tincture.export()

      assert binary =~ "/Type /Sig"
      refute binary =~ "/Encrypt"
    end

    test "an encrypted document with an unsigned signature field still exports" do
      binary = with_field() |> Tincture.encrypt(user_password: "p") |> Tincture.export()

      assert binary =~ ~r|/Encrypt \d+ 0 R|
      refute binary =~ "/Type /Sig"
    end
  end
end

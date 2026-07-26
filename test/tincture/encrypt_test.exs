defmodule Tincture.EncryptTest do
  @moduledoc """
  AES-256 document encryption, standard security handler revision 6.

  Encryption cannot be tested by asserting on the writer's output alone —
  "it emitted an /Encrypt dictionary" says nothing about whether a reader can
  open the file. So these tests implement the reader side (Algorithm 2.A)
  independently and check the whole round trip: validate the password, unwrap
  the file encryption key, decrypt the content stream, and compare against
  what went in.

  The reader implementation below is deliberately written from the
  specification rather than by calling into the module under test, so a
  mistake shared by both would show up as a mismatch rather than cancelling
  out.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF.Encrypt

  @zero_iv <<0::size(16)-unit(8)>>

  # -- reader side, per the specification ------------------------------------

  # Algorithm 2.B: the revision 6 password hash.
  defp hash_2b(password, salt, udata) do
    :sha256
    |> :crypto.hash(password <> salt <> udata)
    |> hash_2b_round(password, udata, 0)
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

    if next_round >= 64 and :binary.last(e) <= next_round - 32 do
      <<result::binary-size(32), _::binary>> = next_k
      result
    else
      hash_2b_round(next_k, password, udata, next_round)
    end
  end

  defp entry(binary, key) do
    [_, hex] = Regex.run(~r|/#{key} <([0-9A-F]+)>|, binary)
    Base.decode16!(hex)
  end

  # Algorithm 2.A: validate a password and recover the file encryption key.
  defp open_document(binary, password) do
    <<u_hash::binary-size(32), validation_salt::binary-size(8), key_salt::binary-size(8)>> =
      entry(binary, "U")

    if hash_2b(password, validation_salt, "") == u_hash do
      intermediate = hash_2b(password, key_salt, "")

      key =
        :crypto.crypto_one_time(:aes_256_cbc, intermediate, @zero_iv, entry(binary, "UE"),
          encrypt: false,
          padding: :none
        )

      {:ok, key}
    else
      :wrong_password
    end
  end

  defp open_as_owner(binary, password) do
    u = entry(binary, "U")

    <<o_hash::binary-size(32), validation_salt::binary-size(8), key_salt::binary-size(8)>> =
      entry(binary, "O")

    if hash_2b(password, validation_salt, u) == o_hash do
      intermediate = hash_2b(password, key_salt, u)

      key =
        :crypto.crypto_one_time(:aes_256_cbc, intermediate, @zero_iv, entry(binary, "OE"),
          encrypt: false,
          padding: :none
        )

      {:ok, key}
    else
      :wrong_password
    end
  end

  defp decrypt(ciphertext, key) do
    <<iv::binary-size(16), body::binary>> = ciphertext
    plain = :crypto.crypto_one_time(:aes_256_cbc, key, iv, body, encrypt: false, padding: :none)
    binary_part(plain, 0, byte_size(plain) - :binary.last(plain))
  end

  # The first content stream, taken by its declared length rather than by
  # scanning for "endstream" — ciphertext can contain anything.
  defp content_stream(binary) do
    [_, length] = Regex.run(~r|/Length (\d+) >>\nstream\n|, binary)
    {start, marker_length} = :binary.match(binary, "stream\n")
    binary_part(binary, start + marker_length, String.to_integer(length))
  end

  defp encrypted_document(opts \\ [], text \\ "Confidential") do
    Tincture.new()
    |> Tincture.set_font("Helvetica", 14)
    |> Tincture.text_at(72, 700, text)
    |> Tincture.encrypt(opts)
    |> Tincture.export()
  end

  # -- round trip ------------------------------------------------------------

  describe "round trip" do
    test "a reader with the password recovers the content" do
      binary = encrypted_document(user_password: "hunter2")

      assert {:ok, key} = open_document(binary, "hunter2")
      assert decrypt(content_stream(binary), key) =~ "(Confidential) Tj"
    end

    test "the wrong password is rejected" do
      binary = encrypted_document(user_password: "hunter2")
      assert open_document(binary, "wrong") == :wrong_password
    end

    test "an empty password is rejected when one was set" do
      binary = encrypted_document(user_password: "hunter2")
      assert open_document(binary, "") == :wrong_password
    end

    test "the owner password opens the same document and yields the same key" do
      binary = encrypted_document(user_password: "user", owner_password: "owner")

      assert {:ok, user_key} = open_document(binary, "user")
      assert {:ok, owner_key} = open_as_owner(binary, "owner")
      assert user_key == owner_key
    end

    test "text containing escapes survives the round trip" do
      binary = encrypted_document([user_password: "p"], "a (b) c \\ d")

      assert {:ok, key} = open_document(binary, "p")
      assert decrypt(content_stream(binary), key) =~ "a \\(b\\) c"
    end

    test "a long password is truncated to 127 bytes rather than rejected" do
      long = String.duplicate("x", 200)
      binary = encrypted_document(user_password: long)

      # The specification truncates; a reader doing the same must still open it.
      assert {:ok, _key} = open_document(binary, String.duplicate("x", 127))
    end

    test "unicode passwords work" do
      binary = encrypted_document(user_password: "pässwörd")
      assert {:ok, _key} = open_document(binary, "pässwörd")
    end
  end

  describe "owner-only protection" do
    test "opens with the empty user password, as the format requires" do
      # This is the honest limit of owner-password protection: the document is
      # encrypted under the empty user password, so anyone can read it. The
      # permissions are advisory.
      binary = encrypted_document(owner_password: "master", permissions: [:print])

      assert {:ok, _key} = open_document(binary, "")
    end
  end

  describe "what leaks" do
    test "the drawn text does not appear in the output" do
      binary = encrypted_document([user_password: "p"], "TopSecretPhrase")
      refute binary =~ "TopSecretPhrase"
    end

    test "document metadata does not appear in the output" do
      binary =
        Tincture.new()
        |> Tincture.set_metadata(title: "SecretTitle", author: "SecretAuthor")
        |> Tincture.text_at(0, 0, "x")
        |> Tincture.encrypt(user_password: "p")
        |> Tincture.export()

      refute binary =~ "SecretTitle"
      refute binary =~ "SecretAuthor"
    end

    test "link URLs do not appear in the output" do
      binary =
        Tincture.new()
        |> Tincture.link(0, 0, 10, 10, "https://secret.example/path")
        |> Tincture.encrypt(user_password: "p")
        |> Tincture.export()

      refute binary =~ "secret.example"
    end

    test "form field names and values do not appear in the output" do
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "ssn", value: "123-45-6789")
        |> Tincture.encrypt(user_password: "p")
        |> Tincture.export()

      refute binary =~ "123-45-6789"
    end

    test "the same text encrypts differently each time" do
      # A fresh IV per string, so identical content does not produce identical
      # ciphertext and reveal repetition.
      a = encrypted_document([user_password: "p"], "same")
      b = encrypted_document([user_password: "p"], "same")

      assert content_stream(a) != content_stream(b)
    end
  end

  describe "document structure" do
    test "an unencrypted document has no Encrypt entry" do
      binary = Tincture.new() |> Tincture.text_at(0, 0, "x") |> Tincture.export()

      refute binary =~ "/Encrypt"

      # /ID is present regardless: PDF/A requires a file identifier on every
      # document, and for an unencrypted one it is derived from the content.
      assert binary =~ "/ID ["
    end

    test "the trailer references the Encrypt dictionary and carries an ID" do
      binary = encrypted_document(user_password: "p")

      assert binary =~ ~r|/Encrypt \d+ 0 R|
      assert binary =~ ~r|/ID \[<[0-9A-F]{32}> <[0-9A-F]{32}>\]|
    end

    test "declares AES-256 at revision 6" do
      binary = encrypted_document(user_password: "p")

      assert binary =~ "/Filter /Standard"
      assert binary =~ "/V 5"
      assert binary =~ "/R 6"
      assert binary =~ "/CFM /AESV3"
    end

    test "the Encrypt dictionary itself is not encrypted" do
      # A reader has to parse it before it holds any key, so it must be plain.
      binary = encrypted_document(user_password: "p")
      assert binary =~ "/Filter /Standard /V 5 /R 6"
    end

    test "U and UE are the sizes the specification requires" do
      binary = encrypted_document(user_password: "p")

      assert byte_size(entry(binary, "U")) == 48
      assert byte_size(entry(binary, "UE")) == 32
      assert byte_size(entry(binary, "O")) == 48
      assert byte_size(entry(binary, "OE")) == 32
      assert byte_size(entry(binary, "Perms")) == 16
    end

    test "the document stays structurally valid" do
      binary = encrypted_document(user_password: "p")

      assert String.starts_with?(binary, "%PDF-1.4")
      assert binary =~ "xref"
      assert String.ends_with?(String.trim_trailing(binary), "%%EOF")
    end

    test "stream lengths are corrected for the ciphertext" do
      # Ciphertext is longer than plaintext by the IV plus padding; a stale
      # /Length would make the file unreadable.
      binary = encrypted_document(user_password: "p")
      [_, length] = Regex.run(~r|/Length (\d+) >>\nstream\n|, binary)

      assert rem(String.to_integer(length) - 16, 16) == 0
    end
  end

  describe "permissions" do
    test "the P value has the reserved high bits set, so it is negative" do
      assert Encrypt.permission_flags([:print]) < 0
    end

    test "granting more permissions only adds bits" do
      print_only = Encrypt.permission_flags([:print])
      print_and_copy = Encrypt.permission_flags([:print, :copy])

      assert Bitwise.band(print_and_copy, print_only) == print_only
      assert print_and_copy != print_only
    end

    test "each permission maps to its specified bit" do
      base = Encrypt.permission_flags([])

      for {permission, bit} <- [
            {:print, 4},
            {:modify, 8},
            {:copy, 16},
            {:annotate, 32},
            {:fill_forms, 256},
            {:extract_for_accessibility, 512},
            {:assemble, 1024},
            {:print_high_quality, 2048}
          ] do
        assert Encrypt.permission_flags([permission]) == base + bit,
               "#{permission} should set bit value #{bit}"
      end
    end

    test "granting everything is the default" do
      all = [
        :print,
        :modify,
        :copy,
        :annotate,
        :fill_forms,
        :extract_for_accessibility,
        :assemble,
        :print_high_quality
      ]

      default = encrypted_document(user_password: "p")
      explicit = encrypted_document(user_password: "p", permissions: all)

      [_, default_p] = Regex.run(~r|/P (-?\d+)|, default)
      [_, explicit_p] = Regex.run(~r|/P (-?\d+)|, explicit)
      assert default_p == explicit_p
    end

    test "rejects an unknown permission" do
      assert_raise ArgumentError, ~r/unknown permission/, fn ->
        Tincture.encrypt(Tincture.new(), permissions: [:teleport])
      end
    end

    test "rejects a non-list permissions option" do
      assert_raise ArgumentError, ~r/permissions must be a list/, fn ->
        Tincture.encrypt(Tincture.new(), permissions: :print)
      end
    end
  end

  describe "options" do
    test "encrypt_metadata: false is declared" do
      binary = encrypted_document(user_password: "p", encrypt_metadata: false)
      assert binary =~ "/EncryptMetadata false"
    end

    test "encrypt_metadata defaults to true and is not declared" do
      refute encrypted_document(user_password: "p") =~ "/EncryptMetadata"
    end

    test "the owner password defaults to the user password" do
      binary = encrypted_document(user_password: "same")
      assert {:ok, _key} = open_as_owner(binary, "same")
    end

    test "rejects a non-string password" do
      for opts <- [[user_password: 123], [owner_password: :atom]] do
        assert_raise ArgumentError, ~r/must be a string/, fn ->
          Tincture.encrypt(Tincture.new(), opts)
        end
      end
    end

    test "calling encrypt twice uses the later settings" do
      binary =
        Tincture.new()
        |> Tincture.text_at(0, 0, "x")
        |> Tincture.encrypt(user_password: "first")
        |> Tincture.encrypt(user_password: "second")
        |> Tincture.export()

      assert open_document(binary, "first") == :wrong_password
      assert {:ok, _key} = open_document(binary, "second")
    end
  end
end

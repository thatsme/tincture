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

  import ExUnit.CaptureIO, only: [with_io: 2]

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

  # -- strings outside content streams ---------------------------------------
  #
  # A content stream is encrypted whole. Every other string is encrypted on its
  # own, after its object has been serialised: the encryptor finds each literal
  # string in the object, recovers the string's bytes from the escapes the
  # writer used, and encrypts those bytes. These tests read each such string
  # back the way ISO 32000-1 says a reader must, without calling the encryptor.

  # Object offsets from the cross-reference table rather than a scan of the
  # file, since ciphertext can contain "obj" or "endobj".
  defp object_offsets(binary) do
    [_, startxref] = Regex.run(~r/startxref\s+(\d+)\s+%%EOF\s*\z/, binary)
    "xref" <> table = drop(binary, String.to_integer(startxref))
    [subsection | entries] = table |> String.trim_leading() |> String.split(~r/\r?\n/)
    [first, count] = subsection |> String.split() |> Enum.map(&String.to_integer/1)

    entries
    |> Enum.take(count)
    |> Enum.with_index(first)
    |> Enum.flat_map(fn {entry, number} ->
      case String.split(entry) do
        [offset, _generation, "n"] -> [{number, String.to_integer(offset)}]
        _free -> []
      end
    end)
  end

  defp drop(binary, count), do: binary_part(binary, count, byte_size(binary) - count)

  # The strings in one object's dictionary, as {key, bytes}. The key is the
  # last name before the string, which for an array of strings is the array's.
  defp dictionary_strings(binary, offset) do
    [_, body] = Regex.run(~r/\A\d+ \d+ obj\s(.*)\z/s, drop(binary, offset))
    lex_strings(body, nil, [])
  end

  defp lex_strings(<<"endobj", _::binary>>, _key, acc), do: Enum.reverse(acc)
  defp lex_strings(<<"stream", _::binary>>, _key, acc), do: Enum.reverse(acc)
  defp lex_strings(<<"<<", rest::binary>>, key, acc), do: lex_strings(rest, key, acc)

  defp lex_strings(<<"/", rest::binary>>, _key, acc) do
    [name] = Regex.run(~r/\A[^\s\/\[\]<>()]*/, rest)
    lex_strings(drop(rest, byte_size(name)), name, acc)
  end

  defp lex_strings(<<"(", rest::binary>>, key, acc) do
    {bytes, rest} = literal_string(rest, 0, [])
    lex_strings(rest, key, [{key, bytes} | acc])
  end

  defp lex_strings(<<"<", rest::binary>>, key, acc) do
    [digits] = Regex.run(~r/\A[0-9A-Fa-f\s]*/, rest)
    ">" <> rest = drop(rest, byte_size(digits))
    bytes = digits |> String.replace(~r/\s/, "") |> Base.decode16!(case: :mixed)
    lex_strings(rest, key, [{key, bytes} | acc])
  end

  defp lex_strings(<<_byte, rest::binary>>, key, acc), do: lex_strings(rest, key, acc)
  defp lex_strings(<<>>, _key, acc), do: Enum.reverse(acc)

  # ISO 32000-1 7.3.4.2 and its Table 3: balanced parentheses need no escape;
  # a backslash before an end-of-line marker continues the string and both are
  # dropped; \ddd is one to three octal digits with high-order overflow
  # ignored; a backslash before any other character is ignored; and an
  # unescaped end-of-line marker, CR, LF or CR LF, is one LINE FEED.
  @table_3 %{
    ?n => ?\n,
    ?r => ?\r,
    ?t => ?\t,
    ?b => ?\b,
    ?f => ?\f,
    ?( => ?(,
    ?) => ?),
    ?\\ => ?\\
  }

  defp literal_string(<<")", rest::binary>>, 0, acc),
    do: {acc |> Enum.reverse() |> :erlang.list_to_binary(), rest}

  defp literal_string(<<")", rest::binary>>, depth, acc),
    do: literal_string(rest, depth - 1, [?) | acc])

  defp literal_string(<<"(", rest::binary>>, depth, acc),
    do: literal_string(rest, depth + 1, [?( | acc])

  defp literal_string(<<"\\\r\n", rest::binary>>, depth, acc),
    do: literal_string(rest, depth, acc)

  defp literal_string(<<"\\", eol, rest::binary>>, depth, acc) when eol in [?\r, ?\n],
    do: literal_string(rest, depth, acc)

  defp literal_string(<<"\\", char, rest::binary>>, depth, acc) when is_map_key(@table_3, char),
    do: literal_string(rest, depth, [Map.fetch!(@table_3, char) | acc])

  defp literal_string(<<"\\", rest::binary>>, depth, acc) do
    case octal(rest, 0, 0) do
      {0, _value, rest} -> literal_string(rest, depth, acc)
      {_digits, value, rest} -> literal_string(rest, depth, [rem(value, 256) | acc])
    end
  end

  defp literal_string(<<"\r\n", rest::binary>>, depth, acc),
    do: literal_string(rest, depth, [?\n | acc])

  defp literal_string(<<"\r", rest::binary>>, depth, acc),
    do: literal_string(rest, depth, [?\n | acc])

  defp literal_string(<<byte, rest::binary>>, depth, acc),
    do: literal_string(rest, depth, [byte | acc])

  defp octal(<<digit, rest::binary>>, count, value) when count < 3 and digit in ?0..?7,
    do: octal(rest, count + 1, value * 8 + digit - ?0)

  defp octal(rest, count, value), do: {count, value, rest}

  # Every string under `key` in the document's objects, decrypted. The
  # /Encrypt dictionary is the one object written in the clear.
  defp decrypted_strings(binary, password, key) do
    {:ok, file_key} = open_document(binary, password)
    [_, encrypt_object] = Regex.run(~r|/Encrypt (\d+) 0 R|, binary)

    for {number, offset} <- object_offsets(binary),
        number != String.to_integer(encrypt_object),
        {^key, ciphertext} <- dictionary_strings(binary, offset),
        do: decrypt(ciphertext, file_key)
  end

  # A text string is UTF-16BE behind a byte order mark, or else single bytes.
  # The single bytes are compared as they are rather than mapped through
  # PDFDocEncoding: what is under test is whether the bytes survive.
  defp text_string(<<0xFE, 0xFF, utf16::binary>>),
    do: :unicode.characters_to_binary(utf16, {:utf16, :big})

  defp text_string(bytes), do: bytes

  # Each string site the public API writes outside a content stream, as
  # {site, the key it is written under}.
  @string_sites [
    title: "Title",
    author: "Author",
    subject: "Subject",
    keywords: "Keywords",
    creator: "Creator",
    bookmark: "Title",
    language: "Lang",
    link_uri: "URI",
    link_contents: "Contents",
    link_to_file: "F",
    field_name: "T",
    field_value: "V",
    tooltip: "TU",
    choice_option: "Opt",
    choice_value: "V",
    button_label: "CA",
    button_url: "URI",
    button_submit: "F",
    figure_alt: "Alt",
    actual_text: "ActualText",
    element_title: "T",
    element_lang: "Lang",
    note_id: "ID",
    note_id_tree: "Names"
  ]

  # Every byte 1-31, then 0, then 127: everything the writer escapes as octal
  # in an ASCII string.
  @control_bytes "a" <> :erlang.list_to_binary(Enum.to_list(1..31) ++ [0, 127]) <> "z"

  @string_inputs [
    control_bytes: @control_bytes,
    balanced_parentheses: "Section 2 (Overview)",
    unbalanced_parentheses: "a) b ( c",
    backslash: "C:\\dir\\file",
    non_ascii: "Ελληνικά (τίτλος)",
    empty: ""
  ]

  # Where the public API refuses an input, for a reason of its own: a blank
  # bookmark, language, link description or figure alternative, and a path to
  # another file that is not ASCII.
  @refused %{
    bookmark: [:empty],
    language: [:empty],
    link_contents: [:empty],
    link_to_file: [:non_ascii],
    figure_alt: [:empty]
  }

  # Where the writer, by design, writes nothing: an empty field value has no
  # /V (Tincture.PDF.Serialize, field_value_entries/1).
  @not_written %{field_value: [:empty], choice_value: [:empty]}

  defp written_value(site, value) when site in [:link_uri, :button_url, :button_submit],
    do: "https://example.com/" <> value

  defp written_value(:link_to_file, value), do: "reports/" <> value <> ".pdf"
  defp written_value(:field_name, value), do: "field " <> value
  defp written_value(site, value) when site in [:note_id, :note_id_tree], do: "note " <> value
  defp written_value(_site, value), do: value

  # A path to another file is written with forward slashes whatever separator
  # it was given (Tincture.PDF, normalize_link_path/1).
  defp expected_value(:link_to_file, written), do: String.replace(written, "\\", "/")
  defp expected_value(_site, written), do: written

  defp document_with(site, value) when site in [:title, :author, :subject, :keywords, :creator],
    do: Tincture.new() |> Tincture.set_metadata([{site, value}]) |> Tincture.text_at(0, 0, "x")

  defp document_with(:bookmark, value),
    do: Tincture.new() |> Tincture.text_at(0, 0, "x") |> Tincture.add_bookmark(value, 1)

  defp document_with(:language, value),
    do: Tincture.new() |> Tincture.set_language(value) |> Tincture.text_at(0, 0, "x")

  defp document_with(site, value) when site in [:link_uri, :link_to_file],
    do: Tincture.new() |> Tincture.link(0, 0, 10, 10, link_target(site, value))

  defp document_with(:link_contents, value),
    do: Tincture.new() |> Tincture.link(0, 0, 10, 10, "https://example.com/", contents: value)

  defp document_with(:field_name, value),
    do: Tincture.new() |> Tincture.text_field(0, 0, 90, 20, value)

  defp document_with(:field_value, value),
    do: Tincture.new() |> Tincture.text_field(0, 0, 90, 40, "f", value: value, multiline: true)

  defp document_with(:tooltip, value),
    do: Tincture.new() |> Tincture.text_field(0, 0, 90, 20, "f", tooltip: value)

  defp document_with(:choice_option, value),
    do: Tincture.new() |> Tincture.choice_field(0, 0, 90, 20, "c", options: ["x", value])

  defp document_with(:choice_value, value),
    do:
      Tincture.new()
      |> Tincture.choice_field(0, 0, 90, 20, "c", options: ["x", value], value: value)

  defp document_with(:button_label, value),
    do: Tincture.new() |> Tincture.push_button(0, 0, 90, 20, "b", label: value, action: :reset)

  defp document_with(:button_url, value),
    do: Tincture.new() |> Tincture.push_button(0, 0, 90, 20, "b", action: {:url, value})

  defp document_with(:button_submit, value),
    do: Tincture.new() |> Tincture.push_button(0, 0, 90, 20, "b", action: {:submit, value})

  defp document_with(:figure_alt, value) do
    Tincture.new()
    |> Tincture.set_language("en")
    |> Tincture.tag(:figure, [alt: value], &Tincture.rectangle(&1, 0, 0, 10, 10, :fill))
  end

  defp document_with(site, value) when site in [:actual_text, :element_title, :element_lang] do
    option = %{actual_text: :actual_text, element_title: :title, element_lang: :lang}[site]

    Tincture.new()
    |> Tincture.set_language("en")
    |> Tincture.tag(:p, [{option, value}], &Tincture.text_at(&1, 0, 0, "x"))
  end

  defp document_with(site, value) when site in [:note_id, :note_id_tree] do
    Tincture.new()
    |> Tincture.set_language("en")
    |> Tincture.tag(:note, [id: value], &Tincture.text_at(&1, 0, 0, "x"))
  end

  defp link_target(:link_uri, value), do: value
  defp link_target(:link_to_file, value), do: {:file, value}

  describe "a string outside a content stream reads back exactly" do
    for {site, key} <- @string_sites do
      test "#{site}, written under /#{key}" do
        site = unquote(site)
        key = unquote(key)

        for {input, value} <- @string_inputs, input not in Map.get(@refused, site, []) do
          written = written_value(site, value)

          # Characters a standard font cannot draw warn; that is not under test.
          {pdf, _warnings} = with_io(:stderr, fn -> document_with(site, written) end)
          binary = pdf |> Tincture.encrypt(user_password: "p") |> Tincture.export()
          read_back = binary |> decrypted_strings("p", key) |> Enum.map(&text_string/1)

          if input in Map.get(@not_written, site, []) do
            assert read_back == [], "#{site}, input #{input}: read back #{inspect(read_back)}"
          else
            expected = expected_value(site, written)

            assert expected in read_back,
                   "#{site}, input #{input}: expected #{inspect(expected)}, " <>
                     "read back #{inspect(read_back)}"
          end
        end
      end
    end
  end
end

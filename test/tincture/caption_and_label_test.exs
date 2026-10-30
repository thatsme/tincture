defmodule Tincture.CaptionAndLabelTest do
  @moduledoc """
  Push-button captions and signature labels.

  A push button's caption and a signature field's `:label` are drawn in the
  field's own appearance, in its `:font`, standard or embedded. The font is
  `/DR`'s object under the field's `/DA` alias, as every widget appearance's
  is, and an embedded font's `/DA` names the size the appearance draws at.
  A visible signature field always carries an appearance, empty without a
  label; an invisible one, `invisible: true`, has a zero rectangle and none.
  The label is drawn before the document is signed, so it lies inside the
  bytes the signature covers.
  """
  use ExUnit.Case, async: true

  alias Tincture.Test.PKI

  @sans "examples/fonts/LiberationSans-Regular.ttf"

  defp with_sans(pdf), do: Tincture.register_ttf_font(pdf, "Sans", @sans)

  # The widget dictionary of the field `name`, which may hold one level of
  # nested dictionary (/AP's, /MK's, /A's), itself holding hex strings.
  defp widget(binary, name) do
    case Regex.run(
           ~r/<< \/Type \/Annot \/Subtype \/Widget[^>]*\/T \(#{name}\)(?:<<(?:<[0-9A-F]*>|[^<>])*>>|<[0-9A-F]*>|[^<>])*>>/,
           binary
         ) do
      [object] -> object
      _ -> flunk("no widget named #{name}")
    end
  end

  # The appearance stream of the widget `name`: {dictionary, content}.
  defp appearance(binary, name) do
    [_, id] = Regex.run(~r/\/AP << \/N (\d+) 0 R >>/, widget(binary, name))

    [_, dictionary, content] =
      Regex.run(
        ~r/\n#{id} 0 obj\n(<< \/Type \/XObject .*? >>)\nstream\n(.*?)\nendstream/s,
        binary
      )

    {dictionary, content}
  end

  # The object number /DR gives the font alias `alias`.
  defp dr_font(binary, alias_name) do
    [_, id] = Regex.run(~r"/DR << /Font << [^>]*/#{alias_name} (\d+) 0 R", binary)
    id
  end

  describe "a push button's caption in an embedded font" do
    setup do
      binary =
        Tincture.new()
        |> with_sans()
        |> Tincture.push_button(72, 700, 120, 26, "latin",
          font: "Sans",
          label: "Send",
          action: :reset
        )
        |> Tincture.push_button(72, 660, 120, 26, "greek",
          font: "Sans",
          label: "Αποστολή",
          action: :reset
        )
        |> Tincture.push_button(72, 620, 120, 26, "helv", label: "Send", action: :reset)
        |> Tincture.export()

      %{binary: binary}
    end

    test "is drawn through /DR's Type0 object, under the /DA alias", %{binary: binary} do
      id = dr_font(binary, "Sans")
      assert binary =~ ~r"\n#{id} 0 obj\n<< /Type /Font /Subtype /Type0 "

      for name <- ["latin", "greek"] do
        {dictionary, content} = appearance(binary, name)
        assert dictionary =~ "/Resources << /Font << /Sans #{id} 0 R >> >>"
        assert content =~ "/Sans 12 Tf"
      end
    end

    test "writes Latin and Greek as Identity-H codes", %{binary: binary} do
      {_dictionary, latin} = appearance(binary, "latin")
      {_dictionary, greek} = appearance(binary, "greek")

      assert latin =~ "<00530065006E0064> Tj"
      assert greek =~ "<039103C003BF03C303C403BF03BB03AE> Tj"
    end

    test "names the size its caption is drawn at in /DA, in any font, never 0", %{binary: binary} do
      assert widget(binary, "greek") =~ "/DA (/Sans 12 Tf 0 g)"
      assert widget(binary, "helv") =~ "/DA (/Helv 12 Tf 0 g)"

      for name <- ["greek", "helv"] do
        [_, size] = Regex.run(~r"/DA \(/\S+ (\S+) Tf", widget(binary, name))
        {_dictionary, content} = appearance(binary, name)
        assert content =~ " #{size} Tf\n"
      end
    end

    test "declares what its appearance draws: /MK /BC and /BG, and /BS /W", %{binary: binary} do
      for name <- ["latin", "greek", "helv"] do
        {_dictionary, content} = appearance(binary, name)

        assert content =~ "0.93 0.93 0.94 rg\n"
        assert content =~ "0.55 0.57 0.6 RG\n0.75 w\n"

        assert widget(binary, name) =~
                 ~r"/MK << /BC \[0\.55 0\.57 0\.6\] /BG \[0\.93 0\.93 0\.94\] /CA [^>]*>* >> /BS << /W 0\.75 >> /AP"
      end
    end

    test "is subset with its glyphs, like page text", %{binary: binary} do
      id = dr_font(binary, "Sans")
      [_, base_font] = Regex.run(~r"\n#{id} 0 obj\n<< [^>]*/BaseFont /(\S+)", binary)
      assert base_font =~ ~r/^[A-Z]{6}\+Sans$/

      [_, to_unicode] = Regex.run(~r"\n#{id} 0 obj\n<< [^>]*/ToUnicode (\d+) 0 R", binary)
      [_, cmap] = Regex.run(~r/\n#{to_unicode} 0 obj\n.*?stream\n(.*?)endstream/s, binary)

      for code <- ["0391", "03C0", "03BF", "03C3", "03C4", "03BB", "03AE", "0053", "006E"] do
        assert cmap =~ "<#{code}>", "the subset's ToUnicode has no #{code}"
      end
    end

    test "J4's advice is followed: a Greek label in an embedded font is accepted" do
      assert %Tincture.PDF{} =
               Tincture.new()
               |> with_sans()
               |> Tincture.push_button(0, 0, 80, 20, "p",
                 font: "Sans",
                 label: "Ελλάδα",
                 action: :reset
               )
    end

    test "/MK /CA carries the caption as a text string", %{binary: binary} do
      assert widget(binary, "greek") =~ "/CA <FEFF039103C003BF03C303C403BF03BB03AE> >>"
    end
  end

  describe "a visible signature field" do
    test "without a label carries an empty appearance" do
      binary =
        Tincture.new() |> Tincture.signature_field(72, 600, 200, 40, "s") |> Tincture.export()

      assert widget(binary, "s") =~ "/AP << /N "
      {dictionary, content} = appearance(binary, "s")
      assert dictionary =~ "/BBox [0 0 200 40] /Resources << >> /Length 0 >>"
      assert content == ""
    end

    test "with a border and no label, strokes its border, as an empty bordered text field does" do
      binary =
        Tincture.new()
        |> Tincture.signature_field(72, 600, 200, 40, "s", border: {0, 0, 2})
        |> Tincture.text_field(72, 500, 200, 40, "t", border: {0, 0, 2})
        |> Tincture.export()

      {dictionary, content} = appearance(binary, "s")
      {_dictionary, text} = appearance(binary, "t")

      assert dictionary =~ "/BBox [0 0 200 40] /Resources << >> /Length 29 >>"
      assert content == "0 0 0 RG\n2 w\n1 1 198 38 re\nS\n"
      # The text field draws the same border, then its empty /Tx marking.
      assert text == content <> "/Tx BMC\nEMC\n"
    end

    test "without a border and without a label, stays empty" do
      binary =
        Tincture.new()
        |> Tincture.signature_field(72, 600, 200, 40, "s", border: :none)
        |> Tincture.export()

      assert {_dictionary, ""} = appearance(binary, "s")
    end

    test "draws its label on the single-line rule a text field uses, left at the padding" do
      label = "Signed by A. Lovelace"

      binary =
        Tincture.new()
        |> Tincture.signature_field(72, 600, 240, 44, "s", label: label)
        |> Tincture.text_field(72, 500, 240, 44, "t", value: label)
        |> Tincture.export()

      {_dictionary, signature} = appearance(binary, "s")
      {_dictionary, text} = appearance(binary, "t")

      [_, size, y] =
        Regex.run(~r"/Helv (\S+) Tf\n0 (\S+) Td\n\(Signed by A\. Lovelace\) Tj", signature)

      assert text =~ "/Helv #{size} Tf\n0 #{y} Td\n(Signed by A. Lovelace) Tj"
      assert signature =~ ~r/\A0 0 0 rg\nBT\n/
    end

    test "has no /Tx marking, and no /MK" do
      binary =
        Tincture.new()
        |> Tincture.signature_field(72, 600, 240, 44, "s", label: "Signed")
        |> Tincture.export()

      {_dictionary, content} = appearance(binary, "s")
      refute content =~ "/Tx BMC"
      refute widget(binary, "s") =~ "/MK"
    end

    test "takes an explicit size, and with a border is padded by twice its width" do
      binary =
        Tincture.new()
        |> Tincture.signature_field(72, 600, 240, 44, "s",
          label: "Signed",
          size: 11,
          border: {0, 0, 2}
        )
        |> Tincture.export()

      {_dictionary, content} = appearance(binary, "s")
      assert content =~ ~r/\A0 0 0 RG\n2 w\n1 1 238 42 re\nS\n0 0 0 rg\nBT\n\/Helv 11 Tf\n4 /
      assert widget(binary, "s") =~ "/DA (/Helv 11 Tf 0 g)"
    end

    test "in an embedded font, draws through /DR's Type0 and names its resolved size in /DA" do
      binary =
        Tincture.new()
        |> with_sans()
        |> Tincture.signature_field(72, 600, 240, 44, "s", font: "Sans", label: "Υπογραφή")
        |> Tincture.export()

      id = dr_font(binary, "Sans")
      {dictionary, content} = appearance(binary, "s")
      [_, size] = Regex.run(~r"/Sans (\S+) Tf", content)

      refute size == "0"
      assert dictionary =~ "/Resources << /Font << /Sans #{id} 0 R >> >>"
      assert widget(binary, "s") =~ "/DA (/Sans #{size} Tf 0 g)"
      assert content =~ "<03A503C003BF03B303C103B103C603AE> Tj"
    end

    test "with a standard font, its label goes through J4" do
      error =
        assert_raise ArgumentError, fn ->
          Tincture.signature_field(Tincture.new(), 72, 600, 240, 44, "s", label: "Υπογραφή")
        end

      assert error.message ==
               ~s{signature field "s" uses the standard font "Helvetica", which cannot draw "Υ" (U+03A5): its encoding is WinAnsi. Register a TrueType or OpenType font that has the character and use it for the field.}

      assert_raise ArgumentError, ~r/cannot draw "\\n" \(U\+000A\)/, fn ->
        Tincture.signature_field(Tincture.new(), 72, 600, 240, 44, "s", label: "Signed\nby")
      end
    end

    test "rejects a label that is not a string" do
      assert_raise ArgumentError, "signature :label must be a string, got: :me", fn ->
        Tincture.signature_field(Tincture.new(), 72, 600, 240, 44, "s", label: :me)
      end
    end
  end

  describe "an invisible signature field" do
    test "has a zero rectangle, /F 4, and no appearance" do
      binary =
        Tincture.new()
        |> Tincture.signature_field(0, 0, 0, 0, "s", invisible: true)
        |> Tincture.export()

      widget = widget(binary, "s")
      assert widget =~ "/Rect [0 0 0 0] /P 3 0 R /F 4 "
      refute widget =~ "/AP"
      refute binary =~ "/Subtype /Form"
    end

    test "is stored as the zero rectangle, with no key of its own" do
      [field] =
        Tincture.signature_field(Tincture.new(), 0, 0, 0, 0, "s", invisible: true).form_fields

      assert field.rect == {0, 0, 0, 0}
      refute Map.has_key?(field, :invisible)
    end

    test "with a label is refused, and nothing is added" do
      pdf = Tincture.new()

      error =
        assert_raise ArgumentError, fn ->
          Tincture.signature_field(pdf, 0, 0, 0, 0, "s", invisible: true, label: "Signed")
        end

      assert error.message ==
               ~s{signature field "s" is invisible: true and has a :label. An invisible signature has no appearance to draw the label in. Remove the :label, or drop invisible: true.}

      assert pdf.form_fields == []
    end

    test "with any non-zero position argument is refused, naming the four" do
      error =
        assert_raise ArgumentError, fn ->
          Tincture.signature_field(Tincture.new(), 72, 600, 200, 40, "s", invisible: true)
        end

      assert error.message ==
               ~s{signature field "s" is invisible: true, but was given the rectangle x 72, y 600, width 200, height 40. An invisible signature's rectangle is [0 0 0 0]: pass 0, 0, 0, 0, or drop invisible: true.}

      for {x, y, w, h} <- [{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}] do
        assert_raise ArgumentError, ~r/is invisible: true, but was given the rectangle/, fn ->
          Tincture.signature_field(Tincture.new(), x, y, w, h, "s", invisible: true)
        end
      end
    end

    test "the label refusal comes first" do
      assert_raise ArgumentError, ~r/has a :label/, fn ->
        Tincture.signature_field(Tincture.new(), 72, 600, 200, 40, "s",
          invisible: true,
          label: "Signed"
        )
      end
    end

    test "invisible: must be a boolean" do
      assert_raise ArgumentError, "invisible must be a boolean, got: \"yes\"", fn ->
        Tincture.signature_field(Tincture.new(), 0, 0, 0, 0, "s", invisible: "yes")
      end
    end
  end

  describe "a signed field with a label" do
    setup do
      pki = PKI.generate()

      binary =
        Tincture.new()
        |> Tincture.signature_field(50, 500, 240, 44, "signature",
          label: "Signed by A. Lovelace",
          size: 11
        )
        |> Tincture.sign("signature",
          private_key: pki.private_key,
          certificate: pki.certificate,
          signing_time: ~U[2026-07-26 12:00:00Z]
        )
        |> Tincture.export()

      %{binary: binary, pki: pki}
    end

    test "has its label inside the bytes the signature covers", %{binary: binary} do
      [start_one, length_one, start_two, length_two] = byte_range(binary)
      {position, _length} = :binary.match(binary, "(Signed by A. Lovelace) Tj")

      covered =
        position + 26 <= start_one + length_one or
          (position >= start_two and position + 26 <= start_two + length_two)

      assert covered
      assert start_one == 0 and start_two + length_two == byte_size(binary)
    end

    test "verifies", %{binary: binary, pki: pki} do
      assert :ok =
               PKI.verify_detached(signature_blob(binary), signed_bytes(binary), pki.public_key)
    end
  end

  defp byte_range(binary) do
    [[_, entries]] = Regex.scan(~r/\/ByteRange \[([^\]]*)\]/, binary)
    entries |> String.split() |> Enum.map(&String.to_integer/1)
  end

  defp signed_bytes(binary) do
    [start_one, length_one, start_two, length_two] = byte_range(binary)
    binary_part(binary, start_one, length_one) <> binary_part(binary, start_two, length_two)
  end

  # The CMS blob, read by its declared DER length.
  defp signature_blob(binary) do
    [[_, hex]] = Regex.scan(~r/\/Contents <([0-9A-F]+)>/, binary)
    <<0x30, rest::binary>> = raw = Base.decode16!(hex, case: :upper)

    {length, length_bytes} =
      case rest do
        <<length, _::binary>> when length < 0x80 ->
          {length, 1}

        <<first, tail::binary>> ->
          count = Bitwise.band(first, 0x7F)
          <<bytes::binary-size(count), _::binary>> = tail
          {:binary.decode_unsigned(bytes), 1 + count}
      end

    binary_part(raw, 0, 1 + length_bytes + length)
  end
end

defmodule Tincture.PDFAFormsTest do
  @moduledoc """
  Form fields in a document that declares PDF/A.

  A field names a font, in `/DA` and through it in `/DR`, only if its
  appearance draws text with it: a text or choice field, or a signature with
  a `:label`. A checkbox, a radio group and an unlabelled signature name
  none, and the AcroForm carries no document-level `/DA`, so the document
  never names a font it does not embed. Outside PDF/A, every field still
  writes `/DA`.

  And a field drawn with an embedded font that has no glyph for one of its
  characters is refused at the call, in any document.
  """
  use ExUnit.Case, async: true

  @sans "examples/fonts/LiberationSans-Regular.ttf"

  defp base(level) do
    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("Sans", @sans)
      |> Tincture.set_metadata(title: "Form")
      |> Tincture.set_font("Sans", 11)
      |> Tincture.text_at(50, 800, "Form")

    if level, do: Tincture.set_pdf_a(pdf, level), else: pdf
  end

  defp every_kind(pdf) do
    pdf
    |> Tincture.text_field(50, 700, 200, 20, "name", value: "Ada", font: "Sans", full_font: true)
    |> Tincture.choice_field(50, 660, 120, 20, "pick",
      options: ["A", "B"],
      value: "A",
      font: "Sans"
    )
    |> Tincture.checkbox(50, 620, 14, "agree", value: true)
    |> Tincture.radio_group("plan", [[value: "a", x: 50, y: 590, size: 12]], selected: "a")
    |> Tincture.signature_field(50, 520, 200, 40, "signed", label: "Signed", font: "Sans")
    |> Tincture.signature_field(50, 460, 200, 40, "blank")
  end

  # Each object's dictionary, by its /T (a field) or, for a radio kid, its
  # parent's /T.
  defp field_dictionaries(binary) do
    for [object] <-
          Regex.scan(~r/\n\d+ 0 obj\n(<<.*?>>)\n(?:endobj|stream)/s, binary,
            capture: :all_but_first
          ),
        [_, name] <- [Regex.run(~r|/T \(([^)]*)\)|, object)],
        into: %{},
        do: {name, object}
  end

  defp acro_form(binary) do
    [acro_form] = Regex.run(~r|/AcroForm << .*? >> >>(?: >>)?|s, binary)
    acro_form
  end

  describe "in a document that declares PDF/A" do
    setup do
      {:ok, binary: base(:a2u) |> every_kind() |> Tincture.export()}
    end

    test "text and choice fields and a labelled signature carry their own /DA, naming the embedded font",
         %{binary: binary} do
      fields = field_dictionaries(binary)

      assert fields["name"] =~ "/DA (/Sans "
      assert fields["pick"] =~ "/DA (/Sans "
      assert fields["signed"] =~ "/DA (/Sans "
    end

    test "a checkbox, a radio group and an unlabelled signature carry no /DA", %{binary: binary} do
      fields = field_dictionaries(binary)

      for name <- ["agree", "plan", "blank"] do
        refute fields[name] =~ "/DA", name
      end
    end

    test "the AcroForm carries no /DA, and /DR lists exactly the embedded font drawn", %{
      binary: binary
    } do
      acro_form = acro_form(binary)

      refute acro_form =~ ~r|/Fields \[[^\]]*\][^/]*/DA|
      refute acro_form =~ "/Helv"

      assert [[font_ref]] =
               Regex.scan(~r|/DR << /Font << /Sans (\d+ 0 R) >> >>|, acro_form,
                 capture: :all_but_first
               )

      # The object /DR names is the one every text-drawing appearance uses.
      appearance_refs =
        Regex.scan(~r|/Resources << /Font << /Sans (\d+ 0 R) >>|, binary, capture: :all_but_first)

      assert appearance_refs != []
      assert Enum.all?(appearance_refs, &(&1 == [font_ref]))
    end

    test "a form whose fields draw no text writes neither /DA nor /DR" do
      binary =
        base(:a2b)
        |> Tincture.checkbox(50, 620, 14, "agree", value: true)
        |> Tincture.radio_group("plan", [[value: "a", x: 50, y: 590, size: 12]], selected: "a")
        |> Tincture.signature_field(50, 460, 200, 40, "blank")
        |> Tincture.export()

      acro_form = acro_form(binary)
      refute acro_form =~ "/DR"
      refute acro_form =~ "/DA"
      refute binary =~ "/DA ("
    end

    test "text, choice and signature widgets carry /AP /N as a stream, buttons as a dictionary",
         %{binary: binary} do
      fields = field_dictionaries(binary)

      for name <- ["name", "pick", "signed", "blank"] do
        assert fields[name] =~ ~r|/AP << /N \d+ 0 R >>|, name
      end

      assert fields["agree"] =~ ~r|/AP << /N << /Yes \d+ 0 R /Off \d+ 0 R >> >>|
    end
  end

  describe "a read-only field in a subset font" do
    # A stream object's decoded content, by object number.
    defp stream_content(binary, number) do
      [_, length, rest] =
        Regex.run(~r|\n#{number} 0 obj\n<<[^\n]*?/Length (\d+)[^\n]*>>\nstream\n(.*)|s, binary)

      data = binary_part(rest, 0, String.to_integer(length))

      if Regex.match?(~r|\n#{number} 0 obj\n<<[^\n]*/FlateDecode|, binary),
        do: :zlib.uncompress(data),
        else: data
    end

    defp ref(binary, pattern) do
      [_, number] = Regex.run(pattern, binary)
      number
    end

    test "carries its glyph in the subset, and the subset leaves out what nothing draws" do
      binary =
        Tincture.new()
        |> Tincture.register_ttf_font("Sans", @sans)
        |> Tincture.register_ttf_font("Body", "examples/fonts/LiberationSerif-Regular.ttf")
        |> Tincture.set_pdf_a(:a2u)
        |> Tincture.set_font("Sans", 11)
        |> Tincture.text_at(50, 800, "Ref")
        |> Tincture.text_field(50, 700, 200, 20, "certificate",
          value: "Ref. № 1843",
          font: "Body",
          read_only: true
        )
        |> Tincture.export()

      assert binary =~ ~r|/FontName /[A-Z]{6}\+Body|

      descriptor =
        ref(binary, ~r|/FontName /[A-Z]{6}\+Body[^\n]*/FontFile2 (\d+) 0 R|)

      map = ref(binary, ~r|/BaseFont /[A-Z]{6}\+Body[^\n]*/CIDToGIDMap (\d+) 0 R|)

      <<_::binary-size(2 * 0x2116), glyph_id::16-big, _::binary>> = stream_content(binary, map)
      assert glyph_id > 0

      {:ok, subset} = Tincture.Font.TTF.parse_basic_tables(stream_content(binary, descriptor))
      counts = subset.glyph_contour_counts_by_id

      # № has an outline in the subset; "Q", which nothing draws, has none.
      assert Map.get(counts, glyph_id, 0) > 0

      {:ok, full} =
        Tincture.Font.TTF.parse_basic_tables(
          File.read!("examples/fonts/LiberationSerif-Regular.ttf")
        )

      assert Map.get(counts, Map.fetch!(full.cmap_by_code, ?Q), 0) == 0
    end
  end

  test "outside PDF/A every field writes /DA, and the AcroForm its default" do
    binary = nil |> base() |> every_kind() |> Tincture.export()
    fields = field_dictionaries(binary)

    for name <- ["name", "pick", "agree", "plan", "signed", "blank"] do
      assert fields[name] =~ "/DA (", name
    end

    assert acro_form(binary) =~ "/DA (/Helv 0 Tf 0 g)"
  end

  describe "a field drawn with an embedded font that lacks a glyph" do
    @one ~s[font "Sans" has no glyph for "✓" (U+2713), which is drawn as a blank. ] <>
           "Register a font that covers it, or remove the character."

    test "is refused at the call, for a text value" do
      assert_raise ArgumentError, @one, fn ->
        Tincture.text_field(base(nil), 50, 700, 200, 20, "t",
          value: "a ✓",
          font: "Sans",
          read_only: true
        )
      end
    end

    test "is refused at the call, for a choice option, listing every character once" do
      assert_raise ArgumentError,
                   ~s[font "Sans" has no glyph for "★" (U+2605), "✓" (U+2713), which are ] <>
                     "drawn as blanks. Register a font that covers them, or remove the characters.",
                   fn ->
                     Tincture.choice_field(base(nil), 50, 700, 120, 20, "c",
                       options: ["ok", "★ ✓ ★"],
                       value: "ok",
                       font: "Sans"
                     )
                   end
    end

    test "is refused at the call, for a push-button caption" do
      assert_raise ArgumentError, @one, fn ->
        Tincture.push_button(base(nil), 50, 700, 90, 24, "b",
          label: "Go ✓",
          font: "Sans",
          action: :reset
        )
      end
    end

    test "is refused at the call, for a signature label" do
      assert_raise ArgumentError, @one, fn ->
        Tincture.signature_field(base(nil), 50, 700, 200, 40, "s", label: "✓", font: "Sans")
      end
    end

    # The fixture font maps only "A", "B" and space, and its format 0 cmap
    # lists every other byte with glyph 0, so it lacks every character below.
    defp probe do
      path = Tincture.Test.MeasurableFont.write!()
      on_exit(fn -> File.rm(path) end)
      Tincture.register_ttf_font(Tincture.new(), "Probe", path)
    end

    test "is refused for a character the cmap maps to glyph 0, as for one it does not list" do
      assert_raise ArgumentError,
                   ~s[font "Probe" has no glyph for "C" (U+0043), which is drawn as a blank. ] <>
                     "Register a font that covers it, or remove the character.",
                   fn ->
                     Tincture.text_field(probe(), 50, 700, 200, 20, "t",
                       value: "AC",
                       font: "Probe",
                       read_only: true
                     )
                   end
    end

    test "is not refused for ZWJ, ZWNJ, ZWSP or a soft hyphen, the font lacking them all" do
      pdf =
        Tincture.text_field(probe(), 50, 700, 200, 20, "t",
          value: "A‍B‌A​B­A",
          font: "Probe",
          read_only: true
        )

      assert [%{name: "t"}] = pdf.form_fields
    end

    test "names only the really missing character beside default-ignorable ones" do
      assert_raise ArgumentError,
                   ~r/^font "Probe" has no glyph for "C" \(U\+0043\), which is drawn/,
                   fn ->
                     Tincture.text_field(probe(), 50, 700, 200, 20, "t",
                       value: "A‍B‌ A​C­B",
                       font: "Probe",
                       read_only: true
                     )
                   end
    end

    test "is not refused when the font covers every character" do
      pdf =
        Tincture.text_field(base(nil), 50, 700, 200, 20, "t",
          value: "Ada № Αθήνα",
          font: "Sans",
          read_only: true
        )

      assert [%{name: "t"}] = pdf.form_fields
    end

    test "is not refused for a variation selector, nor for a multiline value's line breaks" do
      pdf =
        base(nil)
        |> Tincture.text_field(50, 700, 200, 20, "t", value: "a️", font: "Sans", read_only: true)
        |> Tincture.text_field(50, 600, 200, 60, "m",
          value: "one\ntwo",
          font: "Sans",
          multiline: true,
          read_only: true
        )

      assert length(pdf.form_fields) == 2
    end
  end
end

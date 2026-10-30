defmodule Tincture.FieldFontsTest do
  @moduledoc """
  Text and choice fields may use embedded fonts.

  The field's font is written as a `Type0` font with Identity-H, the same
  dictionary any page text in that font uses, over one font program. A field
  someone can type into needs its font embedded whole, covering every
  character of its cmap, and licensed for editable embedding. A form whose
  fields use only the standard 14 writes the same font dictionaries as before;
  since 0.3.11 `/DR` references them as indirect objects.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tincture.Test.ContentStreamState
  alias Tincture.Test.MeasurableFont
  alias Tincture.Test.PatchedFont
  alias Tincture.Test.PDFObjects

  @sans "examples/fonts/LiberationSans-Regular.ttf"

  setup do
    measurable = MeasurableFont.write!()

    on_exit(fn -> File.rm(measurable) end)
    %{measurable: measurable}
  end

  defp with_sans(pdf, opts \\ []), do: Tincture.register_ttf_font(pdf, "Sans", @sans, opts)

  defp patched(version, fs_type) do
    path = PatchedFont.write!(version, fs_type)
    on_exit(fn -> File.rm(path) end)

    capture_log(fn ->
      send(self(), {:pdf, Tincture.register_ttf_font(Tincture.new(), "Sans", path)})
    end)

    assert_received {:pdf, pdf}
    pdf
  end

  ## Reading the written font back

  defp count(binary, pattern), do: length(Regex.scan(pattern, binary))

  defp stream_of(binary, object_id) do
    [_, header, length] =
      Regex.run(~r/\n#{object_id} 0 obj\n(<< \/Length (\d+)[^>]*>>)\nstream\n/, binary)

    {start, _} = :binary.match(binary, "#{header}\nstream\n")
    data = binary_part(binary, start + byte_size(header) + 8, String.to_integer(length))
    if header =~ "FlateDecode", do: :zlib.uncompress(data), else: data
  end

  defp referenced(binary, key) do
    [_, id] = Regex.run(~r/\/#{key} (\d+) 0 R/, binary)
    String.to_integer(id)
  end

  # /W [c [w1 w2 ...] c_first c_last w ...] as a map from CID to width.
  defp widths(binary) do
    {start, length} = :binary.match(binary, "/W [")
    rest = binary_part(binary, start + length, byte_size(binary) - start - length)

    tokens =
      ~r/\[|\]|\d+/
      |> Regex.scan(rest)
      |> List.flatten()
      |> take_until_close(0, [])

    parse_widths(tokens, %{})
  end

  # The tokens inside /W's own brackets, stopping at the one that closes it.
  defp take_until_close(["]" | _rest], 0, acc), do: Enum.reverse(acc)

  defp take_until_close(["[" | rest], depth, acc),
    do: take_until_close(rest, depth + 1, ["[" | acc])

  defp take_until_close(["]" | rest], depth, acc),
    do: take_until_close(rest, depth - 1, ["]" | acc])

  defp take_until_close([token | rest], depth, acc),
    do: take_until_close(rest, depth, [token | acc])

  defp parse_widths([], acc), do: acc

  defp parse_widths([cid, "[" | rest], acc) do
    {list, ["]" | rest]} = Enum.split_while(rest, &(&1 != "]"))

    acc =
      list
      |> Enum.with_index(String.to_integer(cid))
      |> Enum.reduce(acc, fn {w, c}, acc -> Map.put(acc, c, String.to_integer(w)) end)

    parse_widths(rest, acc)
  end

  defp parse_widths([first, last, w | rest], acc) do
    acc =
      Enum.reduce(String.to_integer(first)..String.to_integer(last), acc, fn c, acc ->
        Map.put(acc, c, String.to_integer(w))
      end)

    parse_widths(rest, acc)
  end

  defp cid_to_gid(binary, cid) do
    map = stream_of(binary, referenced(binary, "CIDToGIDMap"))
    <<gid::16>> = binary_part(map, cid * 2, 2)
    gid
  end

  # ToUnicode's bfchar and bfrange entries, as a map from CID to the Unicode
  # value it maps to (single code units only, which is all these tests use).
  defp to_unicode(binary) do
    cmap = stream_of(binary, referenced(binary, "ToUnicode"))
    hex = &String.to_integer(&1, 16)

    chars =
      for [_, cid, uni] <- Regex.scan(~r/^<([0-9A-F]{4})> <([0-9A-F]{4})>$/m, cmap),
          into: %{},
          do: {hex.(cid), hex.(uni)}

    for [_, first, last, uni] <-
          Regex.scan(~r/^<([0-9A-F]{4})> <([0-9A-F]{4})> <([0-9A-F]{4})>$/m, cmap),
        offset <- 0..(hex.(last) - hex.(first)),
        into: chars,
        do: {hex.(first) + offset, hex.(uni) + offset}
  end

  defp assert_clean(binary) do
    %{violations: violations} = ContentStreamState.check_pdf(binary)
    assert violations == []
  end

  describe "F1: standard-14 forms are unchanged" do
    # As 0.3.11 writes it: each /DR font is an object of its own, holding the
    # dictionary earlier releases wrote inline.
    test "the /DR fonts of a Helvetica and Times-Roman form are 0.3.11's Type1 objects" do
      binary =
        Tincture.new()
        |> Tincture.text_field(72, 700, 200, 20, "name")
        |> Tincture.choice_field(72, 650, 200, 20, "day",
          options: ["Mon", "Tue"],
          font: "Times-Roman",
          full_font: true
        )
        |> Tincture.export()

      [_, helv, times] =
        Regex.run(
          ~r|/DA \(/Helv 0 Tf 0 g\) /DR << /Font << /Helv (\d+) 0 R /Times-Roman (\d+) 0 R >> >> >>|,
          binary
        )

      assert binary =~
               "\n#{helv} 0 obj\n" <>
                 "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"

      assert binary =~
               "\n#{times} 0 obj\n" <>
                 "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding >>"

      refute binary =~ "/Type0"
      refute binary =~ "/FontFile"
    end
  end

  describe "F2, F3, F13: one font dictionary and one program for page and field" do
    setup do
      binary =
        Tincture.new()
        |> with_sans()
        |> Tincture.set_font("Sans", 12)
        |> Tincture.text_at(72, 700, "Hello")
        |> Tincture.text_field(72, 600, 200, 20, "name", font: "Sans", full_font: true)
        |> Tincture.export()

      %{binary: binary}
    end

    test "F2: one FontFile2, one Type0 dictionary, no simple font, an untagged whole font",
         %{binary: binary} do
      assert count(binary, ~r/\/FontFile2/) == 1
      assert count(binary, ~r/\/Subtype \/Type0/) == 1
      refute binary =~ "/Subtype /TrueType"
      assert binary =~ "/Subtype /Type0 /BaseFont /Sans /Encoding /Identity-H"
    end

    test "F3: /DR and the page's /Font name the same object", %{binary: binary} do
      [_, page_ref] = Regex.run(~r/\/Font << \/F1 (\d+) 0 R >>/, binary)
      [_, dr_ref] = Regex.run(~r/\/DR << \/Font << \/Sans (\d+) 0 R >> >>/, binary)

      assert page_ref == dr_ref
      assert binary =~ ~r/\n#{page_ref} 0 obj\n<< \/Type \/Font \/Subtype \/Type0/
    end

    test "F13: ASCII page text in a field's font is written through Identity-H", %{binary: binary} do
      [_, content] = Regex.run(~r/<< \/Length \d+ >>\nstream\n(.*?)\nendstream/s, binary)

      assert content =~ ~r/^BT\n\/F1 12 Tf\n72 700 Td\n<[0-9A-F]+> Tj\nET\n$/
      refute content =~ "(Hello)"
    end

    test "F14: the content streams are in order", %{binary: binary} do
      assert_clean(binary)
    end
  end

  describe "F4, F5: the text a non-editable field's subset holds" do
    test "F4: a font used only by a read-only field is embedded, subset to its value", %{
      measurable: path
    } do
      binary =
        Tincture.new()
        |> Tincture.register_ttf_font("M", path)
        |> Tincture.text_field(72, 600, 200, 20, "name", font: "M", value: "B", read_only: true)
        |> Tincture.export()

      assert binary =~ ~r/\/DR << \/Font << \/M \d+ 0 R >> >>/
      assert binary =~ "/Subtype /Type0"
      assert binary =~ ~r/\/BaseFont \/[A-Z]{6}\+M /
      assert widths(binary) == %{?B => 900}
    end

    test "F5: a non-editable choice field's subset holds every option", %{measurable: path} do
      binary =
        Tincture.new()
        |> Tincture.register_ttf_font("M", path)
        |> Tincture.choice_field(72, 600, 200, 20, "letter",
          options: ["A", "B"],
          value: "A",
          font: "M"
        )
        |> Tincture.export()

      assert widths(binary) == %{?A => 700, ?B => 900}
    end
  end

  describe "F6, F7: the full embed" do
    test "F6: an editable text field with a subset font is refused" do
      message =
        ~s(text field "name" uses the embedded font "Sans", which is subset to the glyphs this ) <>
          "document draws. A viewer cannot render characters someone types into the field if " <>
          "they are missing from the subset. Pass full_font: true, or register the font with " <>
          "subset: :none, to embed the whole font; or make the field read_only: true."

      assert_raise ArgumentError, message, fn ->
        Tincture.new() |> with_sans() |> Tincture.text_field(0, 0, 100, 20, "name", font: "Sans")
      end
    end

    test "F6: an editable choice field with a subset font is refused" do
      message =
        ~s(choice field "day" uses the embedded font "Sans", which is subset to the glyphs this ) <>
          "document draws. A viewer cannot render characters someone types into the field if " <>
          "they are missing from the subset. Pass full_font: true, or register the font with " <>
          "subset: :none, to embed the whole font; or make the field read_only: true or not " <>
          "editable."

      assert_raise ArgumentError, message, fn ->
        Tincture.new()
        |> with_sans()
        |> Tincture.choice_field(0, 0, 100, 20, "day",
          options: ["Mon"],
          editable: true,
          font: "Sans"
        )
      end
    end

    test "F6: read_only, a non-editable choice, full_font and subset: :none each pass" do
      pdf = Tincture.new() |> with_sans()

      assert %Tincture.PDF{} =
               Tincture.text_field(pdf, 0, 0, 100, 20, "a", font: "Sans", read_only: true)

      assert %Tincture.PDF{} =
               Tincture.choice_field(pdf, 0, 0, 100, 20, "b", options: ["x"], font: "Sans")

      assert %Tincture.PDF{} =
               Tincture.text_field(pdf, 0, 0, 100, 20, "c", font: "Sans", full_font: true)

      whole = Tincture.new() |> with_sans(subset: :none)
      assert %Tincture.PDF{} = Tincture.text_field(whole, 0, 0, 100, 20, "d", font: "Sans")
    end

    test "F6: full_font must be a boolean" do
      assert_raise ArgumentError, "full_font must be a boolean, got: :yes", fn ->
        Tincture.new() |> Tincture.text_field(0, 0, 100, 20, "a", full_font: :yes)
      end
    end

    test "F7: full_font on a standard-14 field changes no byte" do
      build = fn opts ->
        Tincture.new()
        |> Tincture.text_field(72, 700, 200, 20, "name", opts)
        |> Tincture.export()
      end

      assert build.(full_font: true) == build.([])
    end
  end

  describe "F8, F9: the fsType of an editable field's font" do
    defp editable(pdf),
      do: Tincture.text_field(pdf, 0, 0, 100, 20, "name", font: "Sans", full_font: true)

    defp refusal(fs_type, reason) do
      ~s(text field "name" uses the embedded font "Sans", whose OS/2 fsType \(#{fs_type}\) ) <>
        reason <>
        ". Filling a form field formats new text with the font, which needs Editable or " <>
        "Installable embedding. Use a font licensed for editable embedding, or make the field " <>
        "read_only: true."
    end

    test "F8: OS/2 version 3 - Installable, Editable and no-subsetting pass" do
      for fs_type <- [0, 8, 0x0100, 0x0100 + 8] do
        assert %Tincture.PDF{} = fs_type |> then(&patched(3, &1)) |> editable()
      end
    end

    test "F8: OS/2 version 3 - Restricted, Preview & Print and bitmap-only are refused" do
      cases = [
        {2,
         "is Restricted License: the font must not be embedded without the owner's permission"},
        {4, "allows Preview & Print embedding only"},
        {0x0200, "allows bitmap embedding only, with no outlines to draw typed text"},
        {12,
         "sets more than one embedding permission, which OS/2 version 3 and later forbid; " <>
           "it is read as Preview & Print"}
      ]

      for {fs_type, reason} <- cases do
        pdf = patched(3, fs_type)
        assert_raise ArgumentError, refusal(fs_type, reason), fn -> editable(pdf) end
      end
    end

    test "F8: OS/2 version 2 - combined bits take the least restrictive" do
      assert %Tincture.PDF{} = editable(patched(2, 12))

      pdf = patched(2, 6)

      assert_raise ArgumentError, refusal(6, "allows Preview & Print embedding only"), fn ->
        editable(pdf)
      end
    end

    test "F8: a font with no OS/2 table passes", %{measurable: path} do
      pdf = Tincture.register_ttf_font(Tincture.new(), "M", path)

      assert %Tincture.PDF{} =
               Tincture.text_field(pdf, 0, 0, 100, 20, "n", font: "M", full_font: true)
    end

    test "F8: enforce_embedding_permissions: false does not lift the refusal" do
      path = PatchedFont.write!(3, 4)
      on_exit(fn -> File.rm(path) end)

      pdf =
        Tincture.register_ttf_font(Tincture.new(), "Sans", path,
          enforce_embedding_permissions: false
        )

      assert_raise ArgumentError, refusal(4, "allows Preview & Print embedding only"), fn ->
        editable(pdf)
      end
    end

    test "F9: a read-only field with a Preview & Print font exports" do
      binary =
        3
        |> patched(4)
        |> Tincture.text_field(0, 0, 100, 20, "name", font: "Sans", value: "Hi", read_only: true)
        |> Tincture.export()

      assert binary =~ "/FontFile2"
    end
  end

  describe "F10: an editable field's font covers its whole cmap" do
    test "/W, the CIDToGIDMap and ToUnicode map characters the document never draws" do
      pdf =
        Tincture.new()
        |> with_sans()
        |> Tincture.set_font("Sans", 12)
        |> Tincture.text_at(72, 700, "Hello")
        |> Tincture.text_field(72, 600, 200, 20, "name", font: "Sans", full_font: true)

      binary = Tincture.export(pdf)
      cmap = pdf.embedded_fonts["Sans"].ttf_metrics.cmap_by_code
      widths = widths(binary)
      to_unicode = to_unicode(binary)

      for char <- [?Z, ?q, 0x03A9, 0x20AC] do
        assert Map.has_key?(widths, char), "no /W entry for U+#{Integer.to_string(char, 16)}"
        assert cid_to_gid(binary, char) == Map.fetch!(cmap, char)
        assert Map.fetch!(to_unicode, char) == char
      end

      # None of them is drawn anywhere: the page draws "Hello", and the field
      # has no value.
      drawn =
        for {:text_at, _x, _y, text, _font} <- Tincture.PDF.stream_operations(pdf, {:page, 1}),
            do: text

      assert drawn == ["Hello"]
      assert hd(pdf.form_fields).value == ""
    end
  end

  describe "F11: fields other than text and choice keep the standard 14" do
    test "checkbox, radio group, push button and signature field refuse an embedded font" do
      pdf = Tincture.new() |> with_sans()

      calls = [
        {"checkbox \"c\"", &Tincture.checkbox(&1, 0, 0, 12, "c", font: "Sans")},
        {"radio group \"r\"",
         &Tincture.radio_group(&1, "r", [[value: "a", x: 0, y: 0, size: 12]], font: "Sans")},
        {"push button \"p\"", &Tincture.push_button(&1, 0, 0, 80, 20, "p", font: "Sans")},
        {"signature field \"s\"", &Tincture.signature_field(&1, 0, 0, 200, 40, "s", font: "Sans")}
      ]

      for {label, call} <- calls do
        assert_raise ArgumentError,
                     "#{label} uses the embedded font \"Sans\", but only text and choice fields " <>
                       "can use an embedded font; other fields use one of the standard 14 fonts.",
                     fn -> call.(pdf) end
      end
    end

    test "an unregistered font is named as neither standard nor registered" do
      assert_raise ArgumentError,
                   "form field font \"Body\" is neither one of the standard 14 fonts nor a font " <>
                     "registered with register_ttf_font/4 or register_otf_font/4.",
                   fn ->
                     Tincture.new() |> Tincture.text_field(0, 0, 100, 20, "a", font: "Body")
                   end
    end
  end

  describe "F12: allocation" do
    test "page fonts keep their first-use order; a field-only font comes after them", %{
      measurable: path
    } do
      binary =
        Tincture.new()
        |> Tincture.register_ttf_font("M", path)
        |> with_sans()
        |> Tincture.set_font("M", 12)
        |> Tincture.text_at(72, 700, "AB")
        |> Tincture.text_field(72, 600, 200, 20, "name",
          font: "Sans",
          value: "x",
          read_only: true
        )
        |> Tincture.export()

      [_, page_font] = Regex.run(~r/\/Font << \/F1 (\d+) 0 R >>/, binary)
      [_, field_font] = Regex.run(~r/\/DR << \/Font << \/Sans (\d+) 0 R >> >>/, binary)

      assert String.to_integer(page_font) < String.to_integer(field_font)
      assert_clean(binary)
    end
  end

  # Every /DR font is an object of its own. A standard font gets a new one,
  # allocated after every other object but the info dictionary; an embedded
  # font is the Type0 dictionary its page text uses.
  describe "F14: a /DR mixing embedded and standard fonts" do
    test "references in field order; standard fonts consecutive after the metadata; no ids skipped" do
      binary =
        Tincture.new()
        |> with_sans()
        |> Tincture.set_metadata(title: "Mixed field fonts")
        |> Tincture.set_font("Sans", 12)
        |> Tincture.text_at(72, 750, "Hello")
        |> Tincture.text_field(72, 700, 200, 20, "a")
        |> Tincture.text_field(72, 650, 200, 20, "b", font: "Sans", full_font: true)
        |> Tincture.text_field(72, 600, 200, 20, "c", font: "Courier")
        |> Tincture.export()

      [helv, sans, courier] =
        ~r/\/DR << \/Font << \/Helv (\d+) 0 R \/Sans (\d+) 0 R \/Courier (\d+) 0 R >> >>/
        |> Regex.run(binary, capture: :all_but_first)
        |> Enum.map(&String.to_integer/1)

      %{objects: objects, trailer: trailer} = PDFObjects.read(binary)
      {:ref, metadata} = PDFObjects.resolve(trailer["Root"], objects)["Metadata"]
      {:ref, info} = trailer["Info"]

      assert [helv, courier, info] == [metadata + 1, metadata + 2, metadata + 3]

      for {id, base_font} <- [{helv, "Helvetica"}, {courier, "Courier"}] do
        assert objects[id].value == %{
                 "Type" => {:name, "Font"},
                 "Subtype" => {:name, "Type1"},
                 "BaseFont" => {:name, base_font},
                 "Encoding" => {:name, "WinAnsiEncoding"}
               }
      end

      [_, page_font] = Regex.run(~r/\/Font << \/F1 (\d+) 0 R >>/, binary)
      assert String.to_integer(page_font) == sans
      assert %{"Subtype" => {:name, "Type0"}} = objects[sans].value

      assert objects |> Map.keys() |> Enum.sort() == Enum.to_list(1..(trailer["Size"] - 1))
    end
  end
end

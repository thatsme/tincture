defmodule Tincture.FormTest do
  @moduledoc """
  Interactive form fields.

  A form field is two things at once: a widget annotation on a page, and an
  entry in the document's `/AcroForm /Fields` array. Both refer to the *same*
  dictionary, which is why form widgets have to be indirect objects where link
  annotations can be written inline — an array cannot hold two copies of one
  object and have a viewer treat them as the same field.
  """
  use ExUnit.Case, async: true

  alias Tincture.Test.PDFObjects

  defp export(pdf), do: Tincture.export(pdf)

  defp field_object(pdf_binary, name) do
    # Widgets are indirect objects; find the one carrying this field name.
    ~r/<< \/Type \/Annot \/Subtype \/Widget[^>]*\/T \(#{name}\)[^>]*>>/
    |> Regex.run(pdf_binary)
    |> case do
      [object] -> object
      _ -> flunk("no widget object named #{name} in the document")
    end
  end

  describe "document structure" do
    test "a document with no fields has no AcroForm entry" do
      binary = Tincture.new() |> Tincture.text_at(72, 700, "plain") |> export()

      refute binary =~ "/AcroForm"
      refute binary =~ "/Widget"
    end

    test "adding a field creates the AcroForm and lists it in Fields" do
      binary =
        Tincture.new()
        |> Tincture.text_field(72, 700, 200, 24, "name")
        |> export()

      assert binary =~ "/AcroForm"
      assert binary =~ ~r|/Fields \[\d+ 0 R\]|
    end

    test "the widget appears in the page's Annots as an indirect reference" do
      # Not inline: the AcroForm Fields array has to point at the same object.
      binary =
        Tincture.new()
        |> Tincture.text_field(72, 700, 200, 24, "name")
        |> export()

      assert [annots] = Regex.run(~r|/Annots \[[^\]]*\]|, binary)
      assert annots =~ ~r|\d+ 0 R|
      refute annots =~ "/Subtype /Widget"
    end

    test "the same object id appears in both Fields and Annots" do
      binary =
        Tincture.new()
        |> Tincture.text_field(72, 700, 200, 24, "name")
        |> export()

      [_, fields_id] = Regex.run(~r|/Fields \[(\d+) 0 R\]|, binary)
      [_, annots_id] = Regex.run(~r|/Annots \[(\d+) 0 R\]|, binary)

      assert fields_id == annots_id
    end

    test "NeedAppearances is set so viewers render values from the DA string" do
      binary = Tincture.new() |> Tincture.text_field(0, 0, 10, 10, "f") |> export()
      assert binary =~ "/NeedAppearances true"
    end

    test "the AcroForm carries a resource dictionary for the DA font" do
      # Without /DR a viewer has no font to resolve /Helv against.
      binary = Tincture.new() |> Tincture.text_field(0, 0, 10, 10, "f") |> export()

      assert binary =~ "/DR << /Font <<"
      assert binary =~ "/BaseFont /Helvetica"
    end

    test "each widget names the page it belongs to" do
      binary =
        Tincture.new()
        |> Tincture.add_page()
        |> Tincture.text_field(72, 700, 200, 24, "on_page_two")
        |> export()

      # Page objects are 3, 5, 7...; page 2 is object 5.
      assert field_object(binary, "on_page_two") =~ "/P 5 0 R"
    end

    test "links and form fields coexist on one page" do
      binary =
        Tincture.new()
        |> Tincture.link(72, 750, 100, 14, "https://example.com")
        |> Tincture.text_field(72, 700, 200, 24, "name")
        |> export()

      # Extract the page object rather than the /Annots array: the array holds
      # nested brackets (/Rect, /Border), so a non-greedy match stops early.
      [_, page_object] = Regex.run(~r|3 0 obj\n(.*?)\nendobj|s, binary)

      assert page_object =~ "/Annots ["
      # The link is inline; the widget is an indirect reference. Both in one
      # array, which is why annotations_entry has to handle the two shapes.
      assert page_object =~ "/Subtype /Link"
      assert page_object =~ ~r|/Annots \[.*\d+ 0 R\]|s
    end

    test "the document remains structurally valid" do
      binary =
        Tincture.new()
        |> Tincture.text_field(72, 700, 200, 24, "name")
        |> Tincture.checkbox(72, 660, 14, "agree")
        |> export()

      assert String.starts_with?(binary, "%PDF-1.4")
      assert binary =~ "xref"
      assert String.ends_with?(String.trim_trailing(binary), "%%EOF")
    end
  end

  describe "text_field/7" do
    test "emits a text field with its name and rectangle" do
      binary =
        Tincture.new() |> Tincture.text_field(72, 700, 300, 24, "full_name") |> export()

      object = field_object(binary, "full_name")
      assert object =~ "/FT /Tx"
      assert object =~ "/Rect [72 700 372 724]"
    end

    test "an initial value is set as both value and default" do
      # /DV is what a form reset restores, so both are needed.
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "greeting", value: "hello")
        |> export()

      object = field_object(binary, "greeting")
      assert object =~ "/V (hello)"
      assert object =~ "/DV (hello)"
    end

    test "an empty value emits no V entry" do
      binary = Tincture.new() |> Tincture.text_field(0, 0, 10, 10, "empty") |> export()
      refute field_object(binary, "empty") =~ "/V "
    end

    test "font size defaults to auto" do
      # 0 Tf means "fit the text to the box", which is what you want for a
      # field whose height the caller chose.
      binary = Tincture.new() |> Tincture.text_field(0, 0, 10, 10, "f") |> export()
      assert field_object(binary, "f") =~ "/DA (/Helv 0 Tf 0 g)"
    end

    test "an explicit size is used verbatim" do
      binary = Tincture.new() |> Tincture.text_field(0, 0, 10, 10, "f", size: 11) |> export()
      assert field_object(binary, "f") =~ "/DA (/Helv 11 Tf 0 g)"
    end

    test "multiline sets the multiline flag" do
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "notes", multiline: true)
        |> export()

      assert field_object(binary, "notes") =~ "/Ff 4096"
    end

    test "password sets the password flag" do
      binary =
        Tincture.new() |> Tincture.text_field(0, 0, 10, 10, "pw", password: true) |> export()

      assert field_object(binary, "pw") =~ "/Ff 8192"
    end

    test "flags combine" do
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "f",
          multiline: true,
          read_only: true,
          required: true
        )
        |> export()

      # ReadOnly(1) + Required(2) + Multiline(4096)
      assert field_object(binary, "f") =~ "/Ff 4099"
    end

    test "no flags emits no Ff entry" do
      binary = Tincture.new() |> Tincture.text_field(0, 0, 10, 10, "f") |> export()
      refute field_object(binary, "f") =~ "/Ff"
    end

    test "max_length is carried through" do
      binary =
        Tincture.new() |> Tincture.text_field(0, 0, 10, 10, "f", max_length: 40) |> export()

      assert field_object(binary, "f") =~ "/MaxLen 40"
    end

    test "a tooltip becomes the TU entry" do
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "f", tooltip: "Your full name")
        |> export()

      assert field_object(binary, "f") =~ "/TU (Your full name)"
    end

    test "a negative width or height still yields a valid rectangle" do
      binary = Tincture.new() |> Tincture.text_field(372, 724, -300, -24, "f") |> export()
      assert field_object(binary, "f") =~ "/Rect [72 700 372 724]"
    end

    test "values containing parentheses are escaped" do
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "f", value: "a (b) c")
        |> export()

      assert field_object(binary, "f") =~ "\\(b\\)"
    end
  end

  describe "checkbox/6" do
    test "emits a button field, square from a single size" do
      binary = Tincture.new() |> Tincture.checkbox(72, 700, 14, "agree") |> export()

      object = field_object(binary, "agree")
      assert object =~ "/FT /Btn"
      assert object =~ "/Rect [72 700 86 714]"
    end

    test "an unchecked box is Off in value, default and appearance state" do
      binary = Tincture.new() |> Tincture.checkbox(0, 0, 10, "b") |> export()

      object = field_object(binary, "b")
      assert object =~ "/V /Off"
      assert object =~ "/DV /Off"
      assert object =~ "/AS /Off"
    end

    test "a checked box is Yes throughout" do
      binary = Tincture.new() |> Tincture.checkbox(0, 0, 10, "b", value: true) |> export()

      object = field_object(binary, "b")
      assert object =~ "/V /Yes"
      assert object =~ "/AS /Yes"
    end

    test "rejects a non-boolean value" do
      assert_raise ArgumentError, ~r/checkbox value must be a boolean/, fn ->
        Tincture.checkbox(Tincture.new(), 0, 0, 10, "b", value: "yes")
      end
    end
  end

  describe "choice_field/7" do
    test "emits a choice field with its options" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(72, 700, 200, 24, "country",
          options: ["Italy", "Norway", "Japan"]
        )
        |> export()

      object = field_object(binary, "country")
      assert object =~ "/FT /Ch"
      assert object =~ "/Opt [(Italy) (Norway) (Japan)]"
    end

    test "defaults to a dropdown" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(0, 0, 10, 10, "c", options: ["a"])
        |> export()

      # Combo is bit 18, value 131072.
      assert field_object(binary, "c") =~ "/Ff 131072"
    end

    test "dropdown: false makes it a list box" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(0, 0, 10, 10, "c", options: ["a"], dropdown: false)
        |> export()

      refute field_object(binary, "c") =~ "/Ff"
    end

    test "editable and sort add their flags" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(0, 0, 10, 10, "c",
          options: ["a"],
          editable: true,
          sort: true
        )
        |> export()

      # Combo(131072) + Edit(262144) + Sort(524288)
      assert field_object(binary, "c") =~ "/Ff 917504"
    end

    test "a selected value is carried through" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(0, 0, 10, 10, "c", options: ["a", "b"], value: "b")
        |> export()

      assert field_object(binary, "c") =~ "/V (b)"
    end

    test "requires a non-empty options list" do
      for options <- [nil, []] do
        assert_raise ArgumentError, ~r/needs a non-empty :options list/, fn ->
          Tincture.choice_field(Tincture.new(), 0, 0, 10, 10, "c", options: options)
        end
      end
    end

    test "rejects non-string options" do
      assert_raise ArgumentError, ~r/choice options must be strings/, fn ->
        Tincture.choice_field(Tincture.new(), 0, 0, 10, 10, "c", options: ["a", 42])
      end
    end
  end

  describe "the AcroForm's default appearance" do
    # Its font must be one /DR holds (ISO 32000-1 12.7.3.3), and /DR holds
    # only the fields' own fonts.
    test "is not written when no field uses Helvetica" do
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "f", value: "x", font: "Courier")
        |> export()

      [acro_form] = Regex.run(~r|/AcroForm << .*? >> >> >>|s, binary)
      refute acro_form =~ "/Helv"
      refute acro_form =~ "/DA"
      assert acro_form =~ "/DR << /Font << /Courier"
      # The widget keeps its own.
      assert field_object(binary, "f") =~ "/DA (/Courier 0 Tf 0 g)"
    end

    test "is written, naming /Helv, when a field uses Helvetica" do
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "f", font: "Courier")
        |> Tincture.checkbox(0, 20, 10, "c")
        |> export()

      assert binary =~ ~r|/DA \(/Helv 0 Tf 0 g\) /DR << /Font << /Courier \d+ 0 R /Helv \d+ 0 R|
    end
  end

  describe "the AcroForm's /DR fonts" do
    # ISO 32000-1 7.3.10 allows a font dictionary inline in /DR, but Acrobat
    # Reader draws no value for a field whose /DA font is written that way:
    # the value shows only while the field has focus.
    test "are indirect objects, one per distinct field font, shared by the fields using it" do
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "a")
        |> Tincture.text_field(0, 20, 10, 10, "b", font: "Courier")
        |> Tincture.choice_field(0, 40, 10, 10, "c", options: ["x"])
        |> export()

      %{objects: objects, trailer: trailer} = PDFObjects.read(binary)
      catalog = PDFObjects.resolve(trailer["Root"], objects)
      fonts = catalog["AcroForm"]["DR"]["Font"]

      assert Map.keys(fonts) == ["Courier", "Helv"]
      assert Enum.all?(Map.values(fonts), &match?({:ref, _}, &1))
      assert fonts |> Map.values() |> Enum.uniq() |> length() == 2

      for {alias_name, base_font} <- [{"Helv", "Helvetica"}, {"Courier", "Courier"}] do
        assert PDFObjects.resolve(fonts[alias_name], objects) == %{
                 "Type" => {:name, "Font"},
                 "Subtype" => {:name, "Type1"},
                 "BaseFont" => {:name, base_font},
                 "Encoding" => {:name, "WinAnsiEncoding"}
               }
      end

      assert field_object(binary, "a") =~ "/DA (/Helv 0 Tf 0 g)"
      assert field_object(binary, "b") =~ "/DA (/Courier 0 Tf 0 g)"
      assert field_object(binary, "c") =~ "/DA (/Helv 0 Tf 0 g)"
    end

    # The font objects are allocated after every other object but the info
    # dictionary, and only for a form, so a document without one keeps its
    # 0.3.10 bytes. Metadata, structure and an info dictionary are the objects
    # written next to them. The hash is 0.3.10's output for this document.
    test "leave a document without form fields byte-identical" do
      binary =
        Tincture.new()
        |> Tincture.set_metadata(title: "No fields", author: "Tincture")
        |> Tincture.set_language("en-GB")
        |> Tincture.tag(:document, [], fn doc ->
          Tincture.tag(doc, :p, [], fn p ->
            p
            |> Tincture.set_font("Helvetica", 12)
            |> Tincture.text_at(50, 700, "Hello")
          end)
        end)
        |> Tincture.add_bookmark("Start", 1)
        |> export()

      assert :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower) ==
               "142be673da79531f691691403d538dd1a491ad4bf8220a655ac8d576766a05a8"
    end
  end

  describe "the push-button caption" do
    defp caption(label) do
      binary =
        Tincture.new()
        |> Tincture.push_button(72, 700, 90, 24, "b", label: label, action: :reset)
        |> export()

      [_, shown] = Regex.run(~r|Td\n(.*?) Tj\nET|s, binary)
      {shown, binary}
    end

    test "is written in WinAnsi, the caption font's encoding" do
      {shown, binary} = caption("Größe")

      # Not UTF-16: that belongs in /MK /CA, a text string, not in the stream.
      assert shown == ~S"(Gr\366\337e)"
      assert binary =~ "/MK << /CA <FEFF0047007200F600DF0065> >>"

      assert binary =~
               "/Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
    end

    test "an ASCII label is written as before" do
      assert {"(Send \\(now\\))", _binary} = caption("Send (now)")
    end
  end

  describe "sort: true" do
    defp opt(opts) do
      binary =
        Tincture.new()
        |> Tincture.choice_field(
          0,
          0,
          10,
          10,
          "c",
          [options: ["banana", "Apple", "cherry"]] ++ opts
        )
        |> export()

      [opt] = Regex.run(~r|/Opt \[.*?\]|, binary)
      opt
    end

    test "writes the options sorted, ignoring case" do
      assert opt(sort: true) == "/Opt [(Apple) (banana) (cherry)]"
    end

    test "without it, the order given is kept" do
      assert opt([]) == "/Opt [(banana) (Apple) (cherry)]"
    end

    test "text differing only in case is ordered by the text itself" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(0, 0, 10, 10, "c", options: ["b", "a", "B", "A"], sort: true)
        |> export()

      assert binary =~ "/Opt [(A) (a) (B) (b)]"
    end

    test "the value is unchanged" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(0, 0, 10, 10, "c",
          options: ["b", "a"],
          value: "b",
          sort: true
        )
        |> export()

      assert field_object(binary, "c") =~ "/V (b) /DV (b) /Opt [(a) (b)]"
    end
  end

  describe "validation" do
    test "rejects a duplicate field name" do
      # Names address values in the filled document, so two fields sharing one
      # is a data-loss bug rather than a cosmetic one.
      pdf = Tincture.text_field(Tincture.new(), 0, 0, 10, 10, "name")

      assert_raise ArgumentError, ~r/duplicate form field name/, fn ->
        Tincture.text_field(pdf, 0, 40, 10, 10, "name")
      end
    end

    test "a duplicate across different field types is still a duplicate" do
      pdf = Tincture.text_field(Tincture.new(), 0, 0, 10, 10, "x")

      assert_raise ArgumentError, ~r/duplicate form field name/, fn ->
        Tincture.checkbox(pdf, 0, 40, 10, "x")
      end
    end

    test "rejects an empty field name" do
      assert_raise ArgumentError, ~r/must not be empty/, fn ->
        Tincture.text_field(Tincture.new(), 0, 0, 10, 10, "")
      end
    end

    test "rejects an unknown page" do
      assert_raise ArgumentError, ~r/unknown page: 5/, fn ->
        Tincture.text_field(Tincture.new(), 0, 0, 10, 10, "f", page: 5)
      end
    end

    test "rejects a negative font size" do
      assert_raise ArgumentError, ~r/font size must be >= 0/, fn ->
        Tincture.text_field(Tincture.new(), 0, 0, 10, 10, "f", size: -1)
      end
    end

    test "rejects a non-positive max_length" do
      for value <- [0, -1, 1.5] do
        assert_raise ArgumentError, ~r/max_length must be a positive integer/, fn ->
          Tincture.text_field(Tincture.new(), 0, 0, 10, 10, "f", max_length: value)
        end
      end
    end

    test "rejects options on a non-choice field" do
      assert_raise ArgumentError, ~r/do not take :options/, fn ->
        Tincture.text_field(Tincture.new(), 0, 0, 10, 10, "f", options: ["a"])
      end
    end

    test "rejects a non-boolean flag" do
      assert_raise ArgumentError, ~r/flags must be booleans/, fn ->
        Tincture.text_field(Tincture.new(), 0, 0, 10, 10, "f", read_only: "yes")
      end
    end
  end

  describe "fields across several pages" do
    test "each page carries only its own widgets" do
      binary =
        Tincture.new()
        |> Tincture.text_field(0, 0, 10, 10, "on_one")
        |> Tincture.add_page()
        |> Tincture.text_field(0, 0, 10, 10, "on_two")
        |> export()

      [first_annots, second_annots] = Regex.scan(~r|/Annots \[[^\]]*\]|, binary) |> List.flatten()

      assert first_annots != second_annots
      # Both fields still appear in the single document-level Fields array.
      assert binary =~ ~r|/Fields \[\d+ 0 R \d+ 0 R\]|
    end

    test "the :page option places a widget on an earlier page" do
      binary =
        Tincture.new()
        |> Tincture.add_page()
        |> Tincture.text_field(0, 0, 10, 10, "back_on_one", page: 1)
        |> export()

      assert field_object(binary, "back_on_one") =~ "/P 3 0 R"
    end
  end
end

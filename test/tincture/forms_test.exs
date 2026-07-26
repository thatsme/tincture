defmodule Tincture.FormsTest do
  @moduledoc """
  Tests for the field types that complete the interactive form set: radio
  groups, push buttons and signature fields.

  Radio groups are the only field that is not one object. The specification
  models a group as a parent field holding the value with a kid widget per
  button, and a button's export value *is* the name of its "on" appearance
  state — so a radio group is also the only field that cannot work without
  real appearance streams.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF

  defp form_pdf do
    Tincture.new() |> Tincture.add_page()
  end

  defp export(pdf), do: Tincture.export(pdf)

  # Every `N 0 obj` in the file, so tests can assert the object graph is sound
  # rather than only that some bytes appear somewhere.
  defp object_ids(binary) do
    ~r/^(\d+) 0 obj/m
    |> Regex.scan(binary)
    |> Enum.map(fn [_, id] -> String.to_integer(id) end)
  end

  defp referenced_ids(binary) do
    ~r/(\d+) 0 R/
    |> Regex.scan(binary)
    |> Enum.map(fn [_, id] -> String.to_integer(id) end)
    |> Enum.uniq()
  end

  describe "radio_group/4" do
    setup do
      pdf =
        Tincture.radio_group(
          form_pdf(),
          "delivery",
          [
            [value: "standard", x: 50, y: 700, size: 12],
            [value: "express", x: 50, y: 680, size: 12],
            [value: "collect", x: 50, y: 660, size: 12]
          ],
          selected: "express"
        )

      {:ok, pdf: pdf, binary: export(pdf)}
    end

    test "records one field with a widget per button", %{pdf: pdf} do
      assert [field] = pdf.form_fields
      assert field.type == :radio
      assert length(field.widgets) == 3
      assert Enum.map(field.widgets, & &1.export_value) == ["standard", "express", "collect"]
    end

    test "the parent carries the value as a name object", %{binary: binary} do
      # A name, not a string: it names one of the kids' appearance states.
      assert binary =~ "/V /express"
      assert binary =~ "/DV /express"
      refute binary =~ "/V (express)"
    end

    test "the parent references every kid", %{binary: binary} do
      # Anchored to the field dictionary: the page tree has a /Kids too.
      assert [_, kids] = Regex.run(~r/\/FT \/Btn[^>]*\/Kids \[([^\]]+)\]/, binary)
      assert length(Regex.scan(~r/\d+ 0 R/, kids)) == 3
    end

    test "each kid points back at the parent", %{binary: binary} do
      parents = Regex.scan(~r/\/Subtype \/Widget \/Parent (\d+) 0 R/, binary)

      assert length(parents) == 3
      assert parents |> Enum.map(&Enum.at(&1, 1)) |> Enum.uniq() |> length() == 1
    end

    test "each kid names its export value as an appearance state", %{binary: binary} do
      for value <- ["standard", "express", "collect"] do
        assert binary =~ ~r|/AP << /N << /#{value} \d+ 0 R /Off \d+ 0 R >> >>|
      end
    end

    test "only the selected button is in its on state", %{binary: binary} do
      assert binary =~ "/AS /express"
      refute binary =~ "/AS /standard"
      assert length(Regex.scan(~r|/AS /Off|, binary)) == 2
    end

    test "with nothing selected the value is /Off" do
      binary =
        form_pdf()
        |> Tincture.radio_group("delivery", [[value: "standard", x: 50, y: 700, size: 12]])
        |> export()

      assert binary =~ "/V /Off"
      refute binary =~ "/AS /standard"
    end

    test "sets the radio flag, and no-toggle-to-off by default", %{pdf: pdf} do
      [field] = pdf.form_fields

      assert Bitwise.band(field.flags, 32_768) == 32_768
      assert Bitwise.band(field.flags, 16_384) == 16_384
    end

    test "allow_deselect: true drops no-toggle-to-off" do
      pdf =
        Tincture.radio_group(
          form_pdf(),
          "delivery",
          [[value: "standard", x: 50, y: 700, size: 12]],
          allow_deselect: true
        )

      assert [field] = pdf.form_fields
      assert Bitwise.band(field.flags, 16_384) == 0
    end

    test "emits an appearance stream per state per button", %{binary: binary} do
      # Three buttons, an on and an off appearance each.
      assert length(Regex.scan(~r|/Subtype /Form /BBox|, binary)) == 6
    end

    test "the on appearance draws a dot the off appearance does not", %{binary: binary} do
      # Both stroke a ring; only the on state also fills one.
      assert binary =~ "f\n"
      streams = Regex.scan(~r/stream\n(.*?)endstream/s, binary)
      filled = Enum.count(streams, fn [_, body] -> body =~ "c\nf\n" end)

      assert filled == 3
    end

    test "the object graph has no dangling references", %{binary: binary} do
      assert referenced_ids(binary) -- object_ids(binary) == []
    end

    test "every widget is listed in the page's /Annots", %{binary: binary} do
      assert [_, annots] = Regex.run(~r/\/Annots \[([^\]]+)\]/, binary)
      assert length(Regex.scan(~r/\d+ 0 R/, annots)) == 3
    end

    test "only the parent is listed in /AcroForm /Fields", %{binary: binary} do
      assert [_, fields] = Regex.run(~r/\/Fields \[([^\]]+)\]/, binary)
      assert length(Regex.scan(~r/\d+ 0 R/, fields)) == 1
    end
  end

  describe "radio_group/4 validation" do
    test "rejects an empty button list" do
      assert_raise ArgumentError, ~r/at least one button/, fn ->
        Tincture.radio_group(form_pdf(), "delivery", [])
      end
    end

    test "rejects duplicate button values" do
      assert_raise ArgumentError, ~r/duplicate radio button value/, fn ->
        Tincture.radio_group(form_pdf(), "delivery", [
          [value: "a", x: 0, y: 0, size: 10],
          [value: "a", x: 0, y: 20, size: 10]
        ])
      end
    end

    test ~s(rejects "Off" as a button value, which the specification reserves) do
      assert_raise ArgumentError, ~r/reserves it/, fn ->
        Tincture.radio_group(form_pdf(), "delivery", [[value: "Off", x: 0, y: 0, size: 10]])
      end
    end

    test "rejects a selection that is not one of the buttons" do
      assert_raise ArgumentError, ~r/is not one of/, fn ->
        Tincture.radio_group(
          form_pdf(),
          "delivery",
          [[value: "a", x: 0, y: 0, size: 10]],
          selected: "b"
        )
      end
    end

    test "rejects a duplicate field name" do
      pdf = Tincture.text_field(form_pdf(), 0, 0, 10, 10, "delivery")

      assert_raise ArgumentError, ~r/duplicate form field name/, fn ->
        Tincture.radio_group(pdf, "delivery", [[value: "a", x: 0, y: 0, size: 10]])
      end
    end

    test "rejects a button missing its geometry" do
      assert_raise ArgumentError, ~r/must be a number/, fn ->
        Tincture.radio_group(form_pdf(), "delivery", [[value: "a", x: 0, y: 0]])
      end
    end

    test "rejects a non-positive size" do
      assert_raise ArgumentError, ~r/:size must be positive/, fn ->
        Tincture.radio_group(form_pdf(), "delivery", [[value: "a", x: 0, y: 0, size: 0]])
      end
    end
  end

  describe "push_button/7" do
    test "requires an action, since it holds no value" do
      assert_raise ArgumentError, ~r/needs an :action/, fn ->
        Tincture.push_button(form_pdf(), 0, 0, 80, 20, "go")
      end
    end

    test "rejects an unsupported action" do
      assert_raise ArgumentError, ~r/unsupported button action/, fn ->
        Tincture.push_button(form_pdf(), 0, 0, 80, 20, "go", action: :explode)
      end
    end

    test "rejects a value" do
      assert_raise ArgumentError, ~r/do not take a :value/, fn ->
        Tincture.push_button(form_pdf(), 0, 0, 80, 20, "go", action: :reset, value: "x")
      end
    end

    test "emits a reset action" do
      binary =
        form_pdf()
        |> Tincture.push_button(0, 0, 80, 20, "clear", action: :reset)
        |> export()

      assert binary =~ "/A << /S /ResetForm >>"
      assert binary =~ "/FT /Btn"
    end

    test "emits a URL action" do
      binary =
        form_pdf()
        |> Tincture.push_button(0, 0, 80, 20, "help", action: {:url, "https://example.com"})
        |> export()

      assert binary =~ "/S /URI /URI (https://example.com)"
    end

    test "emits a submit action" do
      binary =
        form_pdf()
        |> Tincture.push_button(0, 0, 80, 20, "send", action: {:submit, "https://example.com/f"})
        |> export()

      assert binary =~ "/S /SubmitForm"
      assert binary =~ "/FS /URL /F (https://example.com/f)"
    end

    test "sets the push button flag" do
      pdf = Tincture.push_button(form_pdf(), 0, 0, 80, 20, "go", action: :reset)

      assert [field] = pdf.form_fields
      assert Bitwise.band(field.flags, 65_536) == 65_536
    end

    test "draws its caption, so it is visible without an interactive viewer" do
      binary =
        form_pdf()
        |> Tincture.push_button(0, 0, 80, 20, "go", action: :reset, label: "Send")
        |> export()

      assert binary =~ "/MK << /CA (Send) >>"
      assert binary =~ "/AP << /N "
      assert binary =~ "/Subtype /Form /BBox [0 0 80 20]"
      assert binary =~ "(Send) Tj"
    end

    test "a button with no label still gets a face" do
      binary =
        form_pdf()
        |> Tincture.push_button(0, 0, 80, 20, "go", action: :reset)
        |> export()

      assert binary =~ "/Subtype /Form /BBox [0 0 80 20]"
      refute binary =~ "Tj"
    end
  end

  describe "signature_field/7" do
    test "emits a signature field" do
      binary =
        form_pdf()
        |> Tincture.signature_field(50, 500, 200, 40, "signature")
        |> export()

      assert binary =~ "/FT /Sig"
      assert binary =~ "/T (signature)"
    end

    test "carries no value, signed or otherwise" do
      binary =
        form_pdf()
        |> Tincture.signature_field(50, 500, 200, 40, "signature")
        |> export()

      refute binary =~ "/V "
    end

    test "rejects a value" do
      assert_raise ArgumentError, ~r/do not take a :value/, fn ->
        Tincture.signature_field(form_pdf(), 0, 0, 80, 20, "sig", value: "signed")
      end
    end
  end

  describe "checkbox appearance" do
    test "is drawn, rather than left to the viewer" do
      # Without an /AP a checkbox is invisible anywhere the renderer is not an
      # interactive viewer: printing, thumbnails, server-side rasterising.
      binary =
        form_pdf()
        |> Tincture.checkbox(50, 700, 14, "terms")
        |> export()

      assert binary =~ "/AP << /N << /Yes "
      assert length(Regex.scan(~r|/Subtype /Form /BBox|, binary)) == 2
    end

    test "both states are always drawn; the value only selects between them" do
      unchecked =
        form_pdf() |> Tincture.checkbox(50, 700, 14, "terms", value: false) |> export()

      checked =
        form_pdf() |> Tincture.checkbox(50, 700, 14, "terms", value: true) |> export()

      # A widget carries an appearance for every state it can be in, so the two
      # documents differ only in which one is current.
      assert checked =~ "/AS /Yes"
      assert unchecked =~ "/AS /Off"
      assert byte_size(checked) == byte_size(unchecked)
    end

    test "exactly one of the two states draws a tick" do
      binary = form_pdf() |> Tincture.checkbox(50, 700, 14, "terms") |> export()

      streams =
        ~r/stream\n(.*?)endstream/s
        |> Regex.scan(binary)
        |> Enum.map(fn [_, body] -> body end)

      # The tick is three points joined by `l` and stroked; the box alone is a
      # rectangle, so counting `l` operators separates them.
      assert Enum.count(streams, &(&1 =~ " l\n")) == 1
    end
  end

  describe "field fonts" do
    test "an embedded font is rejected rather than silently not rendering" do
      # /DA resolves against the AcroForm resource dictionary, which can only
      # carry the standard 14 - an embedded name would emit an unresolvable dict.
      assert_raise ArgumentError, ~r/standard 14 fonts/, fn ->
        Tincture.text_field(form_pdf(), 0, 0, 100, 20, "name", font: "Body")
      end
    end

    test "the standard 14 are accepted" do
      pdf = Tincture.text_field(form_pdf(), 0, 0, 100, 20, "name", font: "Times-Roman")

      assert [%{font: "Times-Roman"}] = pdf.form_fields
    end
  end

  describe "a document with every field type" do
    setup do
      pdf =
        form_pdf()
        |> Tincture.text_field(50, 700, 200, 20, "name")
        |> Tincture.checkbox(50, 670, 14, "terms")
        |> Tincture.choice_field(50, 640, 120, 20, "terms_days", options: ["14", "30"])
        |> Tincture.radio_group("tier", [
          [value: "standard", x: 50, y: 610, size: 12],
          [value: "priority", x: 50, y: 590, size: 12]
        ])
        |> Tincture.signature_field(50, 520, 200, 40, "signature")
        |> Tincture.push_button(50, 470, 80, 24, "send",
          label: "Send",
          action: {:submit, "https://example.com"}
        )

      {:ok, pdf: pdf, binary: export(pdf)}
    end

    test "every field appears in /AcroForm /Fields exactly once", %{binary: binary} do
      assert [_, fields] = Regex.run(~r/\/Fields \[([^\]]+)\]/, binary)
      ids = Regex.scan(~r/(\d+) 0 R/, fields) |> Enum.map(&Enum.at(&1, 1))

      assert length(ids) == 6
      assert length(Enum.uniq(ids)) == 6
    end

    test "the object graph is sound", %{binary: binary} do
      ids = object_ids(binary)

      assert referenced_ids(binary) -- ids == []
      assert ids == Enum.to_list(1..length(ids))
    end

    test "widgets on the page outnumber fields, because a radio group has kids",
         %{binary: binary} do
      assert [_, annots] = Regex.run(~r/\/Annots \[([^\]]+)\]/, binary)

      # Five single-widget fields plus two radio buttons.
      assert length(Regex.scan(~r/\d+ 0 R/, annots)) == 7
    end

    test "records the expected field types", %{pdf: pdf} do
      assert Enum.map(pdf.form_fields, & &1.type) ==
               [:text, :checkbox, :choice, :radio, :signature, :push_button]
    end
  end

  describe "PDF.add_radio_group/4 directly" do
    test "rejects an empty name" do
      assert_raise ArgumentError, ~r/must not be empty/, fn ->
        PDF.add_radio_group(form_pdf(), "", [[value: "a", x: 0, y: 0, size: 10]], [])
      end
    end

    test "rejects an unknown page" do
      assert_raise ArgumentError, ~r/unknown page/, fn ->
        PDF.add_radio_group(
          form_pdf(),
          "r",
          [[value: "a", x: 0, y: 0, size: 10, page: 99]],
          []
        )
      end
    end

    test "rejects a button that is not a keyword list" do
      assert_raise ArgumentError, ~r/must be a keyword list/, fn ->
        PDF.add_radio_group(form_pdf(), "r", ["nope"], [])
      end
    end
  end
end

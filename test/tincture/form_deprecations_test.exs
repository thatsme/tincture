defmodule Tincture.FormDeprecationsTest do
  @moduledoc """
  The form deprecations and the refusals they became:

    * J1, a form field with no tooltip in a tagged document, at export, and
    * J2, a form field created outside every tag/4 scope in a tagged
      document, at export: both still warn, and carry on;
    * J4, a standard-14 field value that WinAnsi cannot encode, and
    * W8, a non-editable choice value that is not one of its options: both
      raise at the field call, as 0.4.0 draws the value into the field's
      appearance.
  """
  # Captures stderr, which is process-global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defp warnings(fun) do
    stderr = capture_io(:stderr, fun)

    stderr
    |> String.split("warning: ", trim: true)
    |> Enum.map(&(&1 |> String.split("\n") |> hd() |> String.trim()))
    |> Enum.filter(&(&1 =~ "0.4.0"))
  end

  defp tagged(fun) do
    Tincture.new()
    |> Tincture.set_language("en-GB")
    |> fun.()
  end

  defp radio(pdf, opts \\ []) do
    Tincture.radio_group(
      pdf,
      "contact",
      [[value: "email", x: 72, y: 650, size: 12], [value: "post", x: 92, y: 650, size: 12]],
      opts
    )
  end

  describe "J1, a field without a tooltip in a tagged document" do
    test "warns once per field at export, a radio group once" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(pdf, :section, fn doc ->
            doc |> Tincture.text_field(72, 700, 200, 20, "full_name") |> radio()
          end)
        end)

      assert warnings(fn -> Tincture.export(pdf) end) == [
               ~s(a text field "full_name" on page 1 has no tooltip. In a tagged document every form field needs one: it is written as /TU, the name a screen reader announces for the field. Pass tooltip: "...". This will raise in 0.4.0.),
               ~s(a radio group "contact" on page 1 has no tooltip. In a tagged document every form field needs one: it is written as /TU, the name a screen reader announces for the field. Pass tooltip: "...". This will raise in 0.4.0.)
             ]
    end

    test "a blank tooltip counts as none" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(pdf, :section, &Tincture.checkbox(&1, 72, 700, 14, "agree", tooltip: "  "))
        end)

      assert [warning] = warnings(fn -> Tincture.export(pdf) end)
      assert warning =~ ~s(a checkbox "agree" on page 1 has no tooltip)
    end

    test "does not warn when every field has a tooltip" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(pdf, :section, fn doc ->
            doc
            |> Tincture.text_field(72, 700, 200, 20, "full_name", tooltip: "Your full name")
            |> radio(tooltip: "Preferred contact")
          end)
        end)

      assert warnings(fn -> Tincture.export(pdf) end) == []
    end

    test "does not warn in an untagged document" do
      pdf =
        Tincture.new()
        |> Tincture.text_field(72, 700, 200, 20, "full_name")
        |> radio()

      assert warnings(fn -> Tincture.export(pdf) end) == []
    end

    test "warns on every export of the document, once per field each time" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(pdf, :section, &Tincture.text_field(&1, 72, 700, 200, 20, "full_name"))
        end)

      assert length(warnings(fn -> Tincture.export(pdf) end)) == 1
      assert length(warnings(fn -> Tincture.export(pdf) end)) == 1
    end
  end

  describe "J2, a field outside the structure tree in a tagged document" do
    test "warns once at export for a field created outside every tag scope" do
      pdf =
        tagged(fn pdf ->
          pdf
          |> Tincture.tag(:p, &Tincture.text_at(&1, 72, 740, "Name"))
          |> Tincture.text_field(72, 700, 200, 20, "full_name", tooltip: "Your full name")
        end)

      assert warnings(fn -> Tincture.export(pdf) end) == [
               ~s{a text field "full_name" on page 1 is not in the structure tree. In a tagged document a form field must be created inside a tag(...) scope so a reader can reach it. This will raise in 0.4.0.}
             ]
    end

    test "a radio group outside every tag scope warns once, not once per button" do
      pdf =
        tagged(fn pdf ->
          pdf
          |> Tincture.tag(:p, &Tincture.text_at(&1, 72, 740, "Contact"))
          |> radio(tooltip: "Preferred contact")
        end)

      assert [warning] = warnings(fn -> Tincture.export(pdf) end)
      assert warning =~ ~s(a radio group "contact" on page 1 is not in the structure tree)
    end

    test "does not warn for a field created inside a :section" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(
            pdf,
            :section,
            &Tincture.text_field(&1, 72, 700, 200, 20, "full_name", tooltip: "Your full name")
          )
        end)

      assert warnings(fn -> Tincture.export(pdf) end) == []
    end

    test "does not warn in an untagged document" do
      pdf = Tincture.text_field(Tincture.new(), 72, 700, 200, 20, "full_name", tooltip: "Name")

      assert warnings(fn -> Tincture.export(pdf) end) == []
    end
  end

  # J4 and W8 warned in 0.3.6 and 0.3.10, and raise in 0.4.0 with the same
  # message less "This will raise in 0.4.0.".
  describe "J4, a standard-14 field value WinAnsi cannot encode, raises" do
    test "a Helvetica text field, naming the first such character" do
      error =
        assert_raise ArgumentError, fn ->
          Tincture.text_field(Tincture.new(), 72, 700, 200, 20, "full_name", value: "Ελλάδα")
        end

      assert error.message ==
               ~s{text field "full_name" uses the standard font "Helvetica", which cannot draw "Ε" (U+0395): its encoding is WinAnsi. Register a TrueType or OpenType font that has the character and use it for the field.}
    end

    test "a WinAnsi value does not raise" do
      assert warnings(fn ->
               Tincture.text_field(Tincture.new(), 72, 700, 200, 20, "full_name", value: "Größe")
             end) == []
    end

    test "line breaks in a multiline text value do not raise" do
      assert warnings(fn ->
               Tincture.text_field(Tincture.new(), 72, 700, 200, 60, "notes",
                 multiline: true,
                 value: "Größe\nzweite Zeile\r\ndritte"
               )
             end) == []
    end

    test "a Greek letter in a multiline text value raises" do
      assert_raise ArgumentError, ~r/text field "notes" .* cannot draw "Ε" \(U\+0395\)/, fn ->
        Tincture.text_field(Tincture.new(), 72, 700, 200, 60, "notes",
          multiline: true,
          value: "eins\nΕλλάδα"
        )
      end
    end

    test "a line break in a single-line text value raises" do
      assert_raise ArgumentError,
                   ~r/text field "full_name" .* cannot draw "\\n" \(U\+000A\)/,
                   fn ->
                     Tincture.text_field(Tincture.new(), 72, 700, 200, 20, "full_name",
                       value: "Ada\nLovelace"
                     )
                   end
    end

    test "a line break in a choice option raises" do
      assert_raise ArgumentError,
                   ~r/choice field "country" .* cannot draw "\\n" \(U\+000A\)/,
                   fn ->
                     Tincture.choice_field(Tincture.new(), 72, 700, 200, 20, "country",
                       options: ["Italy", "Norway\nNorge"]
                     )
                   end
    end

    test "a line break in a push-button label raises" do
      assert_raise ArgumentError, ~r/push button "go" .* cannot draw "\\n" \(U\+000A\)/, fn ->
        Tincture.push_button(Tincture.new(), 72, 700, 80, 20, "go",
          label: "Send\nnow",
          action: :reset
        )
      end
    end

    test "a choice value raises" do
      assert_raise ArgumentError, ~r/choice field "country" uses the standard font/, fn ->
        Tincture.choice_field(Tincture.new(), 72, 700, 200, 20, "country",
          options: ["Italy", "Ελλάδα"],
          value: "Ελλάδα"
        )
      end
    end

    test "a choice field with one Greek option raises" do
      assert_raise ArgumentError, ~r/choice field "country" .* cannot draw "Ε" \(U\+0395\)/, fn ->
        Tincture.choice_field(Tincture.new(), 72, 700, 200, 20, "country",
          options: ["Italy", "Ελλάδα"]
        )
      end
    end

    test "a push button with a Greek label raises" do
      assert_raise ArgumentError, ~r/push button "go" uses the standard font "Helvetica"/, fn ->
        Tincture.push_button(Tincture.new(), 72, 700, 80, 20, "go",
          label: "Εμπρός",
          action: :reset
        )
      end
    end

    test "checkboxes and radio groups draw no text and do not raise" do
      assert warnings(fn ->
               Tincture.new()
               |> Tincture.checkbox(72, 700, 14, "agree")
               |> radio()
             end) == []
    end
  end

  describe "W8, a non-editable choice value that is not one of its options, raises" do
    test "with the full message" do
      error =
        assert_raise ArgumentError, fn ->
          Tincture.choice_field(Tincture.new(), 72, 700, 200, 20, "currency",
            options: ["GBP", "USD"],
            value: "EUR"
          )
        end

      assert error.message ==
               ~s{choice field "currency" has the value "EUR", which is not one of its options. A choice field that is not editable can only hold one of its options: add it to options:, or pass editable: true.}
    end

    test "a list box raises too" do
      assert_raise ArgumentError, ~r/has the value "EUR", which is not one of its options/, fn ->
        Tincture.choice_field(Tincture.new(), 72, 700, 200, 60, "currency",
          options: ["GBP"],
          value: "EUR",
          dropdown: false
        )
      end
    end

    test "not for an editable combo with a free value" do
      assert warnings(fn ->
               Tincture.choice_field(Tincture.new(), 72, 700, 200, 20, "currency",
                 options: ["GBP"],
                 value: "EUR",
                 editable: true
               )
             end) == []
    end

    test "not for a value among the options, or for no value" do
      assert warnings(fn ->
               Tincture.new()
               |> Tincture.choice_field(72, 700, 200, 20, "a", options: ["GBP"], value: "GBP")
               |> Tincture.choice_field(72, 650, 200, 20, "b", options: ["GBP"])
               |> Tincture.choice_field(72, 600, 200, 20, "c", options: ["GBP"], value: "")
             end) == []
    end
  end

  describe "J1 and J2 still warn, and change no byte" do
    # 0.3.11 writes the same document as 4662 bytes, cff2445e…6419. Against
    # that, three structural changes and no others: the text field carries its
    # own /AP, whose /Helv is the /DR font object, and /NeedAppearances is
    # gone. The warnings themselves change no byte.
    @sha256 "e62e1a91b1280db28aa1bf01393221a266408f3b8d0b114960c738fa385c44e4"

    test "a document that triggers both exports, warning three times" do
      {binary, count} =
        with_warnings(fn ->
          Tincture.new()
          |> Tincture.set_language("en-GB")
          |> Tincture.set_metadata(title: "Form deprecations")
          |> Tincture.text_field(72, 700, 200, 20, "full_name", value: "Größe")
          |> Tincture.tag(:section, fn doc ->
            doc
            |> Tincture.tag(:p, &Tincture.text_at(&1, 72, 740, "Contact"))
            |> radio()
          end)
          |> Tincture.export()
        end)

      # J1 for both fields; J2 for the text field.
      assert count == 3
      assert byte_size(binary) == 4895
      assert :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower) == @sha256
      refute binary =~ "created_outside_structure"
    end

    defp with_warnings(fun) do
      parent = self()
      stderr = capture_io(:stderr, fn -> send(parent, {:result, fun.()}) end)
      assert_received {:result, result}
      {result, length(Regex.scan(~r/This will raise in 0\.4\.0\./, stderr))}
    end
  end
end

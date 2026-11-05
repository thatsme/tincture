defmodule Tincture.FormDeprecationsTest do
  @moduledoc """
  The form deprecations and the refusals they became:

    * J1, a form field with no tooltip in a tagged document, and
    * J2, a form field created outside every tag/4 scope in a tagged
      document: both warned at export from 0.3.6, and are refused at export
      in 0.4.0, as `:field_without_description` and `:field_outside_structure`,
      following `:enforce`; nothing warns first;
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
    |> Tincture.set_metadata(title: "Test document")
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

  @no_tooltip "In a tagged document every form field needs one: it is written as /TU, " <>
                "the name a screen reader announces for the field. Pass tooltip: \"...\""

  @outside "In a tagged document a form field must be created inside a tag(...) scope " <>
             "so a reader can reach it"

  defp field_violations(pdf) do
    pdf
    |> Tincture.pdf_ua_violations()
    |> Enum.filter(&(&1.rule in [:field_without_description, :field_outside_structure]))
  end

  # Export refuses, naming each violation, and nothing is written to stderr
  # first: no 0.3.6 warning is left.
  defp assert_refused(pdf, messages) do
    stderr =
      capture_io(:stderr, fn ->
        error = assert_raise ArgumentError, fn -> Tincture.export(pdf) end

        assert error.message =~
                 "this document is tagged, which claims PDF/UA structure, but does not meet it:"

        for message <- messages, do: assert(error.message =~ message)
      end)

    assert stderr == ""
  end

  describe "J1, a field without a tooltip in a tagged document, is refused at export" do
    test "once per field, a radio group once" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(pdf, :section, fn doc ->
            doc |> Tincture.text_field(72, 700, 200, 20, "full_name") |> radio()
          end)
        end)

      assert field_violations(pdf) == [
               %{
                 rule: :field_without_description,
                 clause: "7.18.1",
                 message: ~s(a text field "full_name" on page 1 has no tooltip. ) <> @no_tooltip
               },
               %{
                 rule: :field_without_description,
                 clause: "7.18.1",
                 message: ~s(a radio group "contact" on page 1 has no tooltip. ) <> @no_tooltip
               }
             ]

      assert_refused(pdf, [
        ~s(a text field "full_name" on page 1 has no tooltip. ) <>
          @no_tooltip <> " (ISO 14289-1 clause 7.18.1)",
        ~s(a radio group "contact" on page 1 has no tooltip.)
      ])
    end

    test "a blank tooltip counts as none" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(pdf, :section, &Tincture.checkbox(&1, 72, 700, 14, "agree", tooltip: "  "))
        end)

      assert [%{message: message}] = field_violations(pdf)
      assert message == ~s(a checkbox "agree" on page 1 has no tooltip. ) <> @no_tooltip
    end

    test "a push button and a labelled signature field need a tooltip too: a label is not one" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(pdf, :section, fn doc ->
            doc
            |> Tincture.push_button(72, 700, 120, 24, "open",
              action: {:url, "https://example.org"},
              label: "Open"
            )
            |> Tincture.signature_field(72, 600, 200, 50, "sign", label: "Sign here")
          end)
        end)

      assert Enum.map(field_violations(pdf), & &1.message) == [
               ~s(a push button "open" on page 1 has no tooltip. ) <> @no_tooltip,
               ~s(a signature field "sign" on page 1 has no tooltip. ) <> @no_tooltip
             ]
    end

    test "no violation when every field has a tooltip" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(pdf, :section, fn doc ->
            doc
            |> Tincture.text_field(72, 700, 200, 20, "full_name", tooltip: "Your full name")
            |> radio(tooltip: "Preferred contact")
          end)
        end)

      assert field_violations(pdf) == []
      assert capture_io(:stderr, fn -> Tincture.export(pdf) end) == ""
    end

    test "not checked in an untagged document" do
      pdf =
        Tincture.new()
        |> Tincture.text_field(72, 700, 200, 20, "full_name")
        |> radio()

      assert field_violations(pdf) == []
      assert capture_io(:stderr, fn -> Tincture.export(pdf) end) == ""
    end

    test "refused on every export of the document" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(pdf, :section, &Tincture.text_field(&1, 72, 700, 200, 20, "full_name"))
        end)

      assert_raise ArgumentError, fn -> Tincture.export(pdf) end
      assert_raise ArgumentError, fn -> Tincture.export(pdf) end
    end
  end

  describe "J2, a field outside the structure tree in a tagged document, is refused at export" do
    test "for a field created outside every tag scope" do
      pdf =
        tagged(fn pdf ->
          pdf
          |> Tincture.tag(:p, &Tincture.text_at(&1, 72, 740, "Name"))
          |> Tincture.text_field(72, 700, 200, 20, "full_name", tooltip: "Your full name")
        end)

      message = ~s{a text field "full_name" on page 1 is not in the structure tree. } <> @outside

      assert field_violations(pdf) == [
               %{rule: :field_outside_structure, clause: "7.18.4", message: message}
             ]

      assert_refused(pdf, [message <> " (ISO 14289-1 clause 7.18.4)"])
    end

    test "a radio group outside every tag scope is refused once, not once per button" do
      pdf =
        tagged(fn pdf ->
          pdf
          |> Tincture.tag(:p, &Tincture.text_at(&1, 72, 740, "Contact"))
          |> radio(tooltip: "Preferred contact")
        end)

      assert [%{message: message}] = field_violations(pdf)

      assert message ==
               ~s{a radio group "contact" on page 1 is not in the structure tree. } <> @outside
    end

    test "no violation for a field created inside a :section" do
      pdf =
        tagged(fn pdf ->
          Tincture.tag(
            pdf,
            :section,
            &Tincture.text_field(&1, 72, 700, 200, 20, "full_name", tooltip: "Your full name")
          )
        end)

      assert field_violations(pdf) == []
    end

    test "not checked in an untagged document" do
      pdf = Tincture.text_field(Tincture.new(), 72, 700, 200, 20, "full_name", tooltip: "Name")

      assert field_violations(pdf) == []
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

  describe "J1 and J2 refuse, and enforce: false changes no byte" do
    # 0.3.11 writes the same document as 4662 bytes, cff2445e…6419. Against
    # that, three structural changes and no others: the text field carries its
    # own /AP, whose /Helv is the /DR font object, and /NeedAppearances is
    # gone. Since stage 8a, two more: each radio button, created inside the
    # :section, is owned by a Form element of its own, and carries the
    # /StructParent key the parent tree maps to it; the text field, created
    # outside every tag scope, has neither. The refusal itself changes no byte:
    # with enforce: false the document is written exactly as it would be.
    @sha256 "cff0586354d3ebef26a339c35f8c9999ae606d97770095ad000582d51c508ce5"

    defp both do
      Tincture.new()
      |> Tincture.set_language("en-GB")
      |> Tincture.set_metadata(title: "Form deprecations")
      |> Tincture.text_field(72, 700, 200, 20, "full_name", value: "Größe")
      |> Tincture.tag(:section, fn doc ->
        doc
        |> Tincture.tag(:p, &Tincture.text_at(&1, 72, 740, "Contact"))
        |> radio()
      end)
    end

    test "a document that triggers both is refused, naming all three violations" do
      # J1 for both fields; J2 for the text field.
      assert Enum.map(field_violations(both()), &{&1.rule, &1.message =~ ~s("full_name")}) == [
               {:field_without_description, true},
               {:field_without_description, false},
               {:field_outside_structure, true}
             ]

      assert_refused(both(), [~s("full_name"), ~s("contact")])
    end

    test "exported with enforce: false, it writes the bytes it always did, and warns nothing on stderr" do
      parent = self()

      stderr =
        capture_io(:stderr, fn ->
          ExUnit.CaptureLog.capture_log(fn ->
            send(parent, {:binary, Tincture.export(both(), enforce: false)})
          end)
        end)

      assert_received {:binary, binary}
      assert stderr == ""
      assert byte_size(binary) == 5282
      assert :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower) == @sha256
      refute binary =~ "created_outside_structure"
    end
  end
end

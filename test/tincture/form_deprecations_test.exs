defmodule Tincture.FormDeprecationsTest do
  @moduledoc """
  The 0.3.6 warnings for what 0.4.0 refuses in forms:

    * J1, a form field with no tooltip in a tagged document, at export;
    * J2, a form field created outside every tag/4 scope in a tagged
      document, at export;
    * J4, a standard-14 field value that WinAnsi cannot encode, at the field
      call.

  Each warns and carries on: the exported bytes are those 0.3.5 writes.
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

  describe "J4, a standard-14 field value WinAnsi cannot encode" do
    test "a Helvetica text field warns once at the call, naming the first such character" do
      assert warnings(fn ->
               Tincture.text_field(Tincture.new(), 72, 700, 200, 20, "full_name", value: "Ελλάδα")
             end) == [
               ~s{text field "full_name" uses the standard font "Helvetica", which cannot draw "Ε" (U+0395): its encoding is WinAnsi. Register a TrueType or OpenType font that has the character and use it for the field. This will raise in 0.4.0.}
             ]
    end

    test "a WinAnsi value does not warn" do
      assert warnings(fn ->
               Tincture.text_field(Tincture.new(), 72, 700, 200, 20, "full_name", value: "Größe")
             end) == []
    end

    test "line breaks in a multiline text value do not warn" do
      assert warnings(fn ->
               Tincture.text_field(Tincture.new(), 72, 700, 200, 60, "notes",
                 multiline: true,
                 value: "Größe\nzweite Zeile\r\ndritte"
               )
             end) == []
    end

    test "a line break in a single-line text value warns" do
      assert [warning] =
               warnings(fn ->
                 Tincture.text_field(Tincture.new(), 72, 700, 200, 20, "full_name",
                   value: "Ada\nLovelace"
                 )
               end)

      assert warning =~ ~s{text field "full_name" uses the standard font "Helvetica"}
      assert warning =~ ~s{cannot draw "\\n" (U+000A)}
    end

    test "a line break in a choice option warns" do
      assert [warning] =
               warnings(fn ->
                 Tincture.choice_field(Tincture.new(), 72, 700, 200, 20, "country",
                   options: ["Italy", "Norway\nNorge"]
                 )
               end)

      assert warning =~ ~s{choice field "country"}
      assert warning =~ ~s{cannot draw "\\n" (U+000A)}
    end

    test "a line break in a push-button label warns" do
      assert [warning] =
               warnings(fn ->
                 Tincture.push_button(Tincture.new(), 72, 700, 80, 20, "go",
                   label: "Send\nnow",
                   action: :reset
                 )
               end)

      assert warning =~ ~s{push button "go"}
      assert warning =~ ~s{cannot draw "\\n" (U+000A)}
    end

    test "a choice field with one Greek option warns" do
      assert [warning] =
               warnings(fn ->
                 Tincture.choice_field(Tincture.new(), 72, 700, 200, 20, "country",
                   options: ["Italy", "Ελλάδα"]
                 )
               end)

      assert warning =~ ~s(choice field "country" uses the standard font "Helvetica")
      assert warning =~ ~s{"Ε" (U+0395)}
    end

    test "a push button with a Greek label warns" do
      assert [warning] =
               warnings(fn ->
                 Tincture.push_button(Tincture.new(), 72, 700, 80, 20, "go",
                   label: "Εμπρός",
                   action: :reset
                 )
               end)

      assert warning =~ ~s(push button "go" uses the standard font "Helvetica")
    end

    test "checkboxes and radio groups draw no text and do not warn" do
      assert warnings(fn ->
               Tincture.new()
               |> Tincture.checkbox(72, 700, 14, "agree")
               |> radio()
             end) == []
    end
  end

  describe "no output changes" do
    # Built and hashed at v0.3.5 (f3a9914), from a scratch worktree of the tag:
    # 4627 bytes. The same document under this release must be byte-identical.
    @v035_sha256 "c9261f1e7eacaa57df53f99d769df4416db8571b6c2b8144bc2c68e4a238f949"

    test "a document that triggers J1, J2 and J4 exports the bytes 0.3.5 wrote" do
      {binary, count} =
        with_warnings(fn ->
          Tincture.new()
          |> Tincture.set_language("en-GB")
          |> Tincture.set_metadata(title: "Form deprecations")
          |> Tincture.text_field(72, 700, 200, 20, "full_name", value: "Ελλάδα")
          |> Tincture.tag(:section, fn doc ->
            doc
            |> Tincture.tag(:p, &Tincture.text_at(&1, 72, 740, "Contact"))
            |> radio()
          end)
          |> Tincture.export()
        end)

      # J4 for the value; J1 for both fields; J2 for the text field.
      assert count == 4
      assert byte_size(binary) == 4627
      assert :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower) == @v035_sha256
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

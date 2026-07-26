defmodule Tincture.PDFAEnforcementTest do
  @moduledoc """
  Tests for refusing to export a false PDF/A claim.

  `set_pdf_a/2` writes `pdfaid:conformance` into the file. That is an assertion
  rather than a request, so a document that declares a level and breaks it
  produces a file that lies about itself — and nothing discovers that until
  someone tries to rely on it.

  Every rule enforced here was confirmed against veraPDF rather than read off a
  specification, and the cases that are *allowed* matter as much as the ones
  refused: rejecting a document a validator accepts is its own kind of wrong.
  """
  use ExUnit.Case, async: true

  alias Tincture.Test.MeasurableFont

  setup do
    path = MeasurableFont.write!()
    on_exit(fn -> File.rm(path) end)
    {:ok, font: path}
  end

  # A document with an embedded font and nothing else wrong.
  defp archival(font, level \\ :a2b) do
    Tincture.new()
    |> Tincture.page_size(:a4)
    |> Tincture.register_ttf_font("Body", font)
    |> Tincture.set_metadata(title: "Retained")
    |> Tincture.set_language("en-GB")
    |> Tincture.set_pdf_a(level)
    |> Tincture.set_font("Body", 12)
    |> Tincture.text_at(50, 700, "AB BA")
  end

  defp rules(pdf), do: pdf |> Tincture.pdf_a_violations() |> Enum.map(& &1.rule)

  describe "a conforming document" do
    test "exports without complaint", %{font: font} do
      assert Tincture.pdf_a_violations(archival(font)) == []
      assert Tincture.export(archival(font)) =~ "%PDF"
    end
  end

  describe "unembedded fonts" do
    test "are refused, because the reader would have to supply them", %{font: font} do
      pdf = archival(font) |> Tincture.set_font("Helvetica", 12) |> Tincture.text_at(50, 600, "x")

      assert :unembedded_font in rules(pdf)

      error = assert_raise ArgumentError, fn -> Tincture.export(pdf) end
      assert error.message =~ "not embedded"
      assert error.message =~ "Helvetica"
      assert error.message =~ "6.2.11.4.1"
    end

    test "a font registered but never drawn with is not reported", %{font: font} do
      pdf =
        archival(font)
        |> Tincture.register_ttf_font("Unused", font)

      assert rules(pdf) == []
    end
  end

  describe "encryption" do
    test "is refused, because an archived file has to stay readable", %{font: font} do
      pdf = Tincture.encrypt(archival(font), user_password: "secret")

      assert :encrypted in rules(pdf)
      assert_raise ArgumentError, ~r/forbids encryption/, fn -> Tincture.export(pdf) end
    end
  end

  describe "form fields" do
    test "text fields are refused: their value is drawn by the viewer", %{font: font} do
      pdf = Tincture.text_field(archival(font), 50, 600, 200, 20, "name")

      assert :value_rendered_field in rules(pdf)
      assert_raise ArgumentError, ~r/NeedAppearances/, fn -> Tincture.export(pdf) end
    end

    test "choice fields are refused for the same reason", %{font: font} do
      pdf = Tincture.choice_field(archival(font), 50, 600, 120, 20, "pick", options: ["a", "b"])

      assert :value_rendered_field in rules(pdf)
    end

    test "signature fields are refused: nothing to draw until signed", %{font: font} do
      pdf = Tincture.signature_field(archival(font), 50, 600, 200, 40, "sig")

      assert :signature_field in rules(pdf)
      assert_raise ArgumentError, ~r/signature field/, fn -> Tincture.export(pdf) end
    end

    test "push buttons are refused: a widget may not carry an action", %{font: font} do
      pdf = Tincture.push_button(archival(font), 50, 600, 80, 24, "b", label: "B", action: :reset)

      assert :push_button in rules(pdf)
      assert_raise ArgumentError, ~r|/A action|, fn -> Tincture.export(pdf) end
    end

    test "checkboxes are allowed, carrying their own appearances", %{font: font} do
      # Confirmed against veraPDF: this document is compliant. Refusing it
      # would be as wrong as accepting a broken one.
      pdf = Tincture.checkbox(archival(font), 50, 600, 14, "agree")

      assert rules(pdf) == []
      assert Tincture.export(pdf) =~ "%PDF"
    end

    test "radio groups are allowed for the same reason", %{font: font} do
      pdf =
        Tincture.radio_group(archival(font), "pick", [
          [value: "a", x: 50, y: 600, size: 12],
          [value: "b", x: 50, y: 580, size: 12]
        ])

      assert rules(pdf) == []
      assert Tincture.export(pdf) =~ "%PDF"
    end
  end

  describe "links" do
    test "are allowed, now that annotations carry the flags they need", %{font: font} do
      pdf = Tincture.link(archival(font), 50, 600, 100, 14, "https://example.com")

      assert rules(pdf) == []
      assert Tincture.export(pdf) =~ "%PDF"
    end

    test "every annotation carries /F, which PDF/A requires", %{font: font} do
      binary =
        archival(font)
        |> Tincture.link(50, 600, 100, 14, "https://example.com")
        |> Tincture.export()

      assert binary =~ "/Subtype /Link"
      assert binary =~ ~r|/Subtype /Link /Rect \[[^\]]+\] /F 4|
    end
  end

  describe "conformance levels" do
    test "level A requires tagging", %{font: font} do
      pdf = archival(font, :a2a)

      assert :untagged in rules(pdf)

      error = assert_raise ArgumentError, fn -> Tincture.export(pdf) end
      assert error.message =~ "2A requires a tagged document"
    end

    test "level A is satisfied by a tagged document", %{font: font} do
      pdf =
        Tincture.new()
        |> Tincture.register_ttf_font("Body", font)
        |> Tincture.set_metadata(title: "Retained")
        |> Tincture.set_language("en-GB")
        |> Tincture.set_pdf_a(:a2a)
        |> Tincture.set_font("Body", 12)
        |> Tincture.tag(:p, &Tincture.text_at(&1, 50, 700, "AB"))

      assert rules(pdf) == []
    end

    test "level B does not require tagging", %{font: font} do
      assert rules(archival(font, :a2b)) == []
    end
  end

  describe "documents claiming nothing" do
    test "are never checked, however they are built" do
      pdf =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_at(50, 700, "not embedded, and that is fine")
        |> Tincture.text_field(50, 600, 100, 20, "name")

      assert Tincture.pdf_a_violations(pdf) == []
      assert Tincture.export(pdf) =~ "%PDF"
    end
  end

  describe "enforce: false" do
    test "exports anyway, claim and all", %{font: font} do
      pdf = archival(font) |> Tincture.set_font("Helvetica", 12) |> Tincture.text_at(50, 600, "x")

      binary = Tincture.export(pdf, enforce: false)

      assert binary =~ "%PDF"
      # The claim is still in the file, which is exactly why the default refuses.
      assert binary =~ "pdfaid:conformance"
    end

    test "warns about what it let through", %{font: font} do
      pdf = archival(font) |> Tincture.set_font("Helvetica", 12) |> Tincture.text_at(50, 600, "x")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          Tincture.export(pdf, enforce: false)
        end)

      assert log =~ "does not conform"
      assert log =~ "Helvetica"
    end

    test "makes no difference to a document with nothing wrong", %{font: font} do
      assert Tincture.export(archival(font)) == Tincture.export(archival(font), enforce: false)
    end
  end

  describe "save/3" do
    test "refuses the same documents export/2 does", %{font: font} do
      path =
        Path.join(System.tmp_dir!(), "tincture_pdfa_#{System.unique_integer([:positive])}.pdf")

      on_exit(fn -> File.rm(path) end)

      pdf = archival(font) |> Tincture.set_font("Helvetica", 12) |> Tincture.text_at(50, 600, "x")

      assert_raise ArgumentError, fn -> Tincture.save(pdf, path) end
      refute File.exists?(path)

      assert :ok = Tincture.save(archival(font), path)
      assert File.exists?(path)
    end
  end

  describe "the error message" do
    test "names every violation, not just the first", %{font: font} do
      pdf =
        archival(font, :a2a)
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_at(50, 600, "x")
        |> Tincture.text_field(50, 500, 100, 20, "name")

      error = assert_raise ArgumentError, fn -> Tincture.export(pdf) end

      assert error.message =~ "not embedded"
      assert error.message =~ "text or choice field"
      assert error.message =~ "requires a tagged document"
    end

    test "says how to proceed", %{font: font} do
      pdf = archival(font) |> Tincture.set_font("Helvetica", 12) |> Tincture.text_at(50, 600, "x")

      error = assert_raise ArgumentError, fn -> Tincture.export(pdf) end

      assert error.message =~ "enforce: false"
      assert error.message =~ "set_pdf_a"
    end
  end
end

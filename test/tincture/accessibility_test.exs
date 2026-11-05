defmodule Tincture.AccessibilityTest do
  use ExUnit.Case, async: true

  alias Tincture.Layout.Box
  alias Tincture.Layout.Template
  alias Tincture.Typography.RichText

  defp rich(text \\ "One two three four five six seven eight nine ten") do
    RichText.from_plain(text, font: "Helvetica", size: 10)
  end

  describe "/Tabs /S" do
    test "a tagged page declares structure-ordered tab navigation" do
      binary =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.set_metadata(title: "Test document")
        |> Tincture.tag(:document, [], fn doc ->
          Tincture.tag(doc, :p, [], fn p ->
            p
            |> Tincture.set_font("Helvetica", 12)
            |> Tincture.text_at(50, 700, "Hello")
          end)
        end)
        |> Tincture.export()

      assert binary =~ "/Tabs /S"
    end

    # Without structure there is no order to follow, and emitting it anyway
    # would rewrite every untagged document for nothing.
    test "an untagged page does not" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_at(50, 700, "Hello")
        |> Tincture.export()

      refute binary =~ "/Tabs"
    end
  end

  describe "Layout.Box tagging" do
    test "flowed text is tagged inside a tagged document" do
      binary =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.set_metadata(title: "Test document")
        |> Tincture.tag(:document, [], fn doc ->
          {flowed, _result} = Box.flow_text(doc, 50, 700, 200, 100, rich())
          flowed
        end)
        |> Tincture.export()

      assert binary =~ "/P <</MCID"
    end

    test "flowed text is not tagged in an untagged document" do
      {pdf, _result} = Box.flow_text(Tincture.new(), 50, 700, 200, 100, rich())
      binary = Tincture.export(pdf)

      refute binary =~ "BDC"
    end

    test "tag: true tags even when the document is not otherwise tagged" do
      {pdf, _result} =
        Box.flow_text(
          Tincture.new()
          |> Tincture.set_language("en-GB")
          |> Tincture.set_metadata(title: "Test document"),
          50,
          700,
          200,
          100,
          rich(),
          tag: true
        )

      assert Tincture.export(pdf) =~ "/P <</MCID"
    end

    test "tag: false suppresses tagging inside a tagged document" do
      binary =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.set_metadata(title: "Test document")
        |> Tincture.tag(:document, [], fn doc ->
          {flowed, _result} = Box.flow_text(doc, 50, 700, 200, 100, rich(), tag: false)
          flowed
        end)
        |> Tincture.export()

      refute binary =~ "/P <</MCID"
    end

    test "tag_as picks the structure element" do
      {pdf, _result} =
        Box.flow_text(
          Tincture.new()
          |> Tincture.set_language("en-GB")
          |> Tincture.set_metadata(title: "Test document"),
          50,
          700,
          200,
          100,
          rich(),
          tag: true,
          tag_as: :h2
        )

      assert Tincture.export(pdf) =~ "/H2 <</MCID"
    end

    # Decorative text announced as content is the failure PAC catches and
    # veraPDF does not: veraPDF checks the structure is well-formed, not that
    # it describes the page correctly.
    test "tag_as: :artifact marks flowed text as decoration, not content" do
      {pdf, _result} =
        Box.flow_text(Tincture.new(), 50, 700, 200, 100, rich("CONFIDENTIAL DRAFT"),
          tag: true,
          tag_as: :artifact
        )

      binary = Tincture.export(pdf)

      assert binary =~ "/Artifact BMC"
      refute binary =~ "/P <</MCID"
    end

    test "an invalid :tag is refused" do
      assert_raise ArgumentError, ~r/:tag must be true, false or :auto/, fn ->
        Box.flow_text(Tincture.new(), 50, 700, 200, 100, rich(), tag: :yes)
      end
    end
  end

  describe "Layout.Template tagging" do
    test "header and footer become artifacts in a tagged document" do
      template =
        Template.new(page_size: :a4)
        |> Template.with_header("Quarterly Report")
        |> Template.with_footer("Page {page} of {total}")

      binary =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.set_metadata(title: "Test document")
        |> Tincture.tag(:document, [], fn doc ->
          {rendered, _result} = Template.render(doc, template, rich(), page_number: 1)
          rendered
        end)
        |> Tincture.export()

      # Running furniture repeats on every page and says nothing about the
      # content: marked as an artifact, a reader skips it.
      assert binary =~ "/Artifact BMC"
    end

    test "no artifact marking in an untagged document" do
      template =
        Template.new(page_size: :a4)
        |> Template.with_header("Quarterly Report")

      {pdf, _result} = Template.render(Tincture.new(), template, rich(), page_number: 1)

      refute Tincture.export(pdf) =~ "/Artifact"
    end
  end

  describe "pdf_ua_violations/1" do
    defp figure_document(figure_opts) do
      Tincture.new()
      |> Tincture.set_language("en-GB")
      |> Tincture.set_metadata(title: "Test document")
      |> Tincture.tag(:document, [], fn doc ->
        Tincture.tag(doc, :figure, figure_opts, fn fig ->
          Tincture.rectangle(fig, 50, 600, 100, 80, :fill)
        end)
      end)
    end

    test "a figure without alternative text is a violation" do
      assert [violation] = Tincture.pdf_ua_violations(figure_document([]))
      assert violation.rule == :figure_without_alt
      assert violation.clause == "7.3"
      assert violation.message =~ "no alternative text"
    end

    test "a figure with alternative text is not" do
      assert Tincture.pdf_ua_violations(figure_document(alt: "A gauge at 40%")) == []
    end

    test "whitespace does not count as alternative text" do
      assert [_violation] = Tincture.pdf_ua_violations(figure_document(alt: "   "))
    end

    test "an untagged document claims nothing and so violates nothing" do
      pdf =
        Tincture.new()
        |> Tincture.rectangle(50, 600, 100, 80, :fill)

      assert Tincture.pdf_ua_violations(pdf) == []
    end

    test "export refuses a tagged document with an undescribed figure" do
      assert_raise ArgumentError, ~r/no alternative text/, fn ->
        Tincture.export(figure_document([]))
      end
    end

    test "enforce: false exports it anyway" do
      assert is_binary(Tincture.export(figure_document([]), enforce: false))
    end
  end

  # A tagged document declares PDF/UA-1 in its XMP (pdfuaid:part), and veraPDF
  # fails one with no catalog /Lang on rule 7.2-34 as soon as it draws text,
  # on 7.2-25 for a field's /TU, and on 7.2-33 for a metadata title.
  describe "a tagged document with no language" do
    @language_message "the document has no language. A tagged document claims PDF/UA, " <>
                        "which needs the natural language of its text, its form fields' " <>
                        "tooltips and its metadata title to be known (veraPDF rules 7.2-34, " <>
                        "7.2-25 and 7.2-33), so a screen reader does not have to guess how " <>
                        "to pronounce them. Call set_language/2, for example " <>
                        ~s{set_language(pdf, "en-GB")}

    # Titled, so that the language is the only thing missing.
    defp text_document(pdf) do
      pdf
      |> Tincture.set_metadata(title: "Test document")
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.tag(:document, fn doc ->
        Tincture.tag(doc, :p, &Tincture.text_at(&1, 50, 700, "Text"))
      end)
    end

    test "is a violation, once for the document" do
      assert Tincture.pdf_ua_violations(text_document(Tincture.new())) == [
               %{rule: :language_missing, clause: "7.2", message: @language_message}
             ]
    end

    test "is refused at export, with the full message" do
      error =
        assert_raise ArgumentError, fn -> Tincture.export(text_document(Tincture.new())) end

      assert error.message =~ @language_message <> " (ISO 14289-1 clause 7.2)"
    end

    test "is refused even when it has a title and form fields: one violation, not one per rule" do
      pdf =
        Tincture.new()
        |> Tincture.set_metadata(title: "Untitled language")
        |> Tincture.tag(:document, fn doc ->
          Tincture.tag(doc, :section, fn section ->
            Tincture.text_field(section, 72, 700, 200, 20, "name", tooltip: "Name")
          end)
        end)

      assert [%{rule: :language_missing}] = Tincture.pdf_ua_violations(pdf)
    end

    test "element-level :lang does not stand in for set_language/2" do
      pdf =
        Tincture.new()
        |> Tincture.set_metadata(title: "Test document")
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:document, [lang: "en-GB"], fn doc ->
          Tincture.tag(doc, :p, [lang: "en-GB"], &Tincture.text_at(&1, 50, 700, "Text"))
        end)

      assert [%{rule: :language_missing, message: message}] = Tincture.pdf_ua_violations(pdf)
      assert message =~ "Call set_language/2"
    end

    test "set_language/2 clears it" do
      pdf = Tincture.new() |> Tincture.set_language("en-GB") |> text_document()
      assert Tincture.pdf_ua_violations(pdf) == []
    end

    test "an untagged document needs no language: it claims nothing" do
      pdf = Tincture.new() |> Tincture.set_font("Helvetica", 12) |> Tincture.text_at(50, 700, "x")
      assert Tincture.pdf_ua_violations(pdf) == []
      assert is_binary(Tincture.export(pdf))
    end

    test "enforce: false exports it anyway" do
      assert is_binary(Tincture.export(text_document(Tincture.new()), enforce: false))
    end
  end

  # A tagged document declares PDF/UA-1, and veraPDF fails one whose XMP has
  # no dc:title on rule 7.1-9, and on nothing else once it has a language.
  describe "a tagged document with no title" do
    @title_message "the document has no title. A tagged document claims PDF/UA, which " <>
                     "needs its metadata to carry a title that identifies the document " <>
                     "(veraPDF rule 7.1-9, dc:title), so a reader can announce what it is. " <>
                     "Call set_metadata/2 with title:, for example " <>
                     ~s{set_metadata(pdf, title: "Annual report")}

    # In a language, so that the title is the only thing missing.
    defp untitled(pdf \\ Tincture.new()) do
      pdf
      |> Tincture.set_language("en-GB")
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.tag(:document, fn doc ->
        Tincture.tag(doc, :p, &Tincture.text_at(&1, 50, 700, "Text"))
      end)
    end

    test "is a violation, once for the document" do
      assert Tincture.pdf_ua_violations(untitled()) == [
               %{rule: :title_missing, clause: "7.1", message: @title_message}
             ]
    end

    test "is refused at export, with the full message" do
      error = assert_raise ArgumentError, fn -> Tincture.export(untitled()) end
      assert error.message =~ @title_message <> " (ISO 14289-1 clause 7.1)"
    end

    test "a blank title counts as none" do
      pdf = untitled(Tincture.set_metadata(Tincture.new(), title: "   "))
      assert [%{rule: :title_missing}] = Tincture.pdf_ua_violations(pdf)
    end

    test "metadata without a title counts as none" do
      pdf = untitled(Tincture.set_metadata(Tincture.new(), author: "A. Lovelace"))
      assert [%{rule: :title_missing}] = Tincture.pdf_ua_violations(pdf)
    end

    test "set_metadata/2 with a title clears it" do
      pdf = untitled(Tincture.set_metadata(Tincture.new(), title: "Annual report"))
      assert Tincture.pdf_ua_violations(pdf) == []
    end

    test "with neither a language nor a title, both are reported" do
      pdf =
        Tincture.new()
        |> Tincture.tag(:document, fn doc -> Tincture.tag(doc, :section, & &1) end)

      assert pdf |> Tincture.pdf_ua_violations() |> Enum.map(& &1.rule) ==
               [:language_missing, :title_missing]
    end

    test "an untagged document needs no title: it claims nothing" do
      pdf = Tincture.new() |> Tincture.set_font("Helvetica", 12) |> Tincture.text_at(50, 700, "x")
      assert Tincture.pdf_ua_violations(pdf) == []
    end

    test "enforce: false exports it anyway" do
      assert is_binary(Tincture.export(untitled(), enforce: false))
    end
  end

  # A satellite package renders by *calling* Tincture, not by being called by
  # it, so there is no behaviour to implement and nothing to dispatch. What has
  # to hold is that the public API is sufficient on its own.
  describe "rendering through the public API alone" do
    defmodule Stamp do
      def place(pdf, text, opts) do
        pdf
        |> Tincture.set_font("Helvetica", Keyword.get(opts, :size, 12))
        |> Tincture.text_at(Keyword.get(opts, :x, 50), Keyword.get(opts, :y, 700), text)
      end
    end

    test "an external module can take a document, draw, and return it" do
      binary =
        Tincture.new()
        |> Stamp.place("Rendered", x: 60, y: 690)
        |> Tincture.export()

      assert binary =~ "Rendered"
    end
  end
end

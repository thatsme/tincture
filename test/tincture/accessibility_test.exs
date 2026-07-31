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
      {pdf, _result} = Box.flow_text(Tincture.new(), 50, 700, 200, 100, rich(), tag: true)

      assert Tincture.export(pdf) =~ "/P <</MCID"
    end

    test "tag: false suppresses tagging inside a tagged document" do
      binary =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.tag(:document, [], fn doc ->
          {flowed, _result} = Box.flow_text(doc, 50, 700, 200, 100, rich(), tag: false)
          flowed
        end)
        |> Tincture.export()

      refute binary =~ "/P <</MCID"
    end

    test "tag_as picks the structure element" do
      {pdf, _result} =
        Box.flow_text(Tincture.new(), 50, 700, 200, 100, rich(), tag: true, tag_as: :h2)

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

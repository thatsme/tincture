defmodule Tincture.EmbeddedFontLayoutTest do
  @moduledoc """
  Regression tests for laying out text in an embedded font.

  Font embedding and the typography engine are the library's two headline
  features, and they did not compose: every layout entry point measured through
  `Tincture.Font.text_width/3`, which resolves only the standard 14 fonts and
  AFM files. Passing an embedded font to `Tincture.text_paragraph/6`,
  `Tincture.Layout.Box.flow_text/7`, `Tincture.Layout.Table.render/6` with
  `:auto` columns, or `Tincture.text_link/6` raised `unknown font`.

  The fixture's advance widths are known exactly, so these assert real
  arithmetic rather than the absence of a crash.
  """
  use ExUnit.Case, async: true

  alias Tincture.Font.Context
  alias Tincture.Layout.Box
  alias Tincture.Layout.Table
  alias Tincture.Test.MeasurableFont
  alias Tincture.Typography
  alias Tincture.Typography.RichText

  setup do
    path = MeasurableFont.write!()
    on_exit(fn -> File.rm(path) end)

    pdf =
      Tincture.new()
      |> Tincture.page_size(:a4)
      |> Tincture.register_ttf_font("Probe", path)
      |> Tincture.add_page()

    {:ok, path: path, pdf: pdf}
  end

  describe "text_paragraph/6" do
    test "lays out an embedded font instead of raising", %{pdf: pdf} do
      rich = RichText.from_plain("AB BA AB BA", font: "Probe", size: 10)

      result = Tincture.text_paragraph(pdf, 50, 700, rich, 200)

      assert %Tincture.PDF{} = result
    end

    test "breaks lines on the font's real metrics", %{pdf: pdf} do
      # "AB" is 16.0pt, a space 3.0pt, "A" 7.0pt. At a 20pt limit "AB" fits and
      # "AB A" (26.0pt) does not, so this must break into two lines. Under the
      # old 0.6em estimate "AB" alone would have measured 12.0pt and "AB A"
      # 24.0pt, which breaks in the same place - so also assert a case where
      # the estimate and the truth disagree.
      lines = layout(pdf, "AB A", font: "Probe", size: 10, max_width: 20)
      assert length(lines) == 2

      # A case where the truth and the old estimate disagree. "AB AB" measures
      # 35.0pt with real metrics but 30.0pt under the 0.6em estimate, so at a
      # 32pt limit real metrics must break it and the estimate must not.
      assert length(layout(pdf, "AB AB", font: "Probe", size: 10, max_width: 32)) == 2
    end

    test "every laid-out line fits the requested width", %{pdf: pdf} do
      max_width = 40

      for line <- layout(pdf, "AB BA AB BA AB BA", font: "Probe", size: 10, max_width: max_width) do
        assert line_width(line) <= max_width
      end
    end

    test "still raises for a genuinely unknown font", %{pdf: pdf} do
      rich = RichText.from_plain("AB", font: "Probee", size: 10)

      assert_raise ArgumentError, ~r/unknown font: Probee/, fn ->
        Tincture.text_paragraph(pdf, 50, 700, rich, 200)
      end
    end
  end

  describe "Box.flow_text/7" do
    test "flows an embedded font instead of raising", %{pdf: pdf} do
      rich = RichText.from_plain("AB BA AB BA", font: "Probe", size: 10)

      {_pdf, result} = Box.flow_text(pdf, 50, 400, 40, 100, rich)

      assert length(result.lines) > 1
      assert Enum.all?(result.lines, &(line_width(&1) <= 40))
    end
  end

  describe "Table.render/6 with :auto columns" do
    test "sizes columns from the embedded font's metrics", %{pdf: pdf} do
      padding = 4

      {_pdf, result} =
        Table.render(pdf, 50, 700, :auto, [["AB"], ["BB"]],
          font: "Probe",
          font_size: 10,
          padding: padding
        )

      # The widest cell is "BB" at 18.0pt, plus padding either side.
      assert [width] = result.widths
      assert width == 18.0 + padding * 2
    end
  end

  describe "text_link/6" do
    test "measures the clickable rectangle with the embedded font", %{pdf: pdf} do
      linked =
        pdf
        |> Tincture.set_font("Probe", 10)
        |> Tincture.text_link(50, 500, "AB", "https://example.com")

      [%{rect: {x0, _y0, x1, _y1}}] = Tincture.PDF.page_annotations(linked, linked.current_page)

      assert x1 - x0 == 16.0
    end
  end

  describe "RichText measurement state" do
    test "an unresolvable font is recorded rather than guessed at" do
      rich = RichText.from_plain("AB", font: "Probe", size: 10)

      assert RichText.unmeasured_fonts(rich) == ["Probe"]
      refute Enum.all?(rich.tokens, & &1.measured?)
    end

    test "a resolvable font is measured at construction" do
      rich = RichText.from_plain("Hi", font: "Helvetica", size: 10)

      assert RichText.unmeasured_fonts(rich) == []
      assert Enum.all?(rich.tokens, & &1.measured?)
    end

    test "a context supplied up front measures embedded fonts immediately", %{pdf: pdf} do
      rich =
        RichText.from_plain("AB", font: "Probe", size: 10, context: Context.from_pdf(pdf))

      assert RichText.unmeasured_fonts(rich) == []
      assert [%{width: 16.0}] = rich.tokens
    end

    test "remeasure/2 resolves what construction could not", %{pdf: pdf} do
      rich = RichText.from_plain("AB", font: "Probe", size: 10)
      assert [%{measured?: false}] = rich.tokens

      remeasured = RichText.remeasure(rich, Context.from_pdf(pdf))

      assert RichText.unmeasured_fonts(remeasured) == []
      assert [%{width: 16.0, measured?: true}] = remeasured.tokens
    end

    test "remeasure/2 preserves token structure and only changes widths", %{pdf: pdf} do
      rich = RichText.from_plain("AB BA\nAB", font: "Probe", size: 10)
      remeasured = RichText.remeasure(rich, Context.from_pdf(pdf))

      assert length(rich.tokens) == length(remeasured.tokens)

      assert Enum.map(rich.tokens, &token_shape/1) ==
               Enum.map(remeasured.tokens, &token_shape/1)
    end

    test "remeasure/2 leaves a font it still cannot resolve unmeasured" do
      rich = RichText.from_plain("AB", font: "Probe", size: 10)

      remeasured = RichText.remeasure(rich, Context.from_pdf(Tincture.new()))

      assert RichText.unmeasured_fonts(remeasured) == ["Probe"]
    end
  end

  describe "Typography.layout_paragraph/3" do
    test "refuses to lay out estimated widths" do
      # Laying these out would produce a plausible-looking but wrong paragraph.
      rich = RichText.from_plain("AB", font: "Probe", size: 10)

      assert_raise ArgumentError, ~r/unknown font: Probe/, fn ->
        Typography.layout_paragraph(rich, 200)
      end
    end

    test "the error points at the document-aware entry points" do
      rich = RichText.from_plain("AB", font: "Probe", size: 10)

      error =
        assert_raise ArgumentError, fn -> Typography.layout_paragraph(rich, 200) end

      assert error.message =~ "text_paragraph"
      assert error.message =~ "remeasure"
    end

    test "accepts text remeasured against a document", %{pdf: pdf} do
      rich =
        "AB"
        |> RichText.from_plain(font: "Probe", size: 10)
        |> RichText.remeasure(Context.from_pdf(pdf))

      assert [_line] = Typography.layout_paragraph(rich, 200)
    end
  end

  describe "the drawn document" do
    test "an embedded font laid out as a paragraph still exports and subsets", %{pdf: pdf} do
      rich = RichText.from_plain("AB BA AB BA", font: "Probe", size: 10)

      binary =
        pdf
        |> Tincture.text_paragraph(50, 700, rich, 60)
        |> Tincture.export()

      assert binary =~ "%PDF"
      # A subset tag is six capitals and a plus sign before the base name.
      assert binary =~ ~r|/BaseFont /[A-Z]{6}\+|
    end
  end

  defp layout(pdf, text, opts) do
    max_width = Keyword.fetch!(opts, :max_width)

    text
    |> RichText.from_plain(Keyword.take(opts, [:font, :size]))
    |> RichText.remeasure(Context.from_pdf(pdf))
    |> Typography.layout_paragraph(max_width)
  end

  defp line_width(line), do: line.width

  defp token_shape(%RichText.Break{}), do: :break
  defp token_shape(%RichText.Space{} = token), do: {:space, token.text, token.font, token.size}
  defp token_shape(%RichText.Word{} = token), do: {:word, token.text, token.font, token.size}
end

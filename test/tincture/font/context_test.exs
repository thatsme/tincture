defmodule Tincture.Font.ContextTest do
  @moduledoc """
  Tests for the measurement context.

  The gap this closes: `Tincture.Font.text_width/3` is pure, so it can only see
  the standard 14 fonts and AFM files on disk. An embedded TrueType font has no
  AFM — its metrics are parsed at registration and live on the document — so a
  pure function could never measure one, and the whole layout and typography
  layer raised `unknown font` for every embedded font. Two headline features,
  font embedding and typography, did not compose.
  """
  use ExUnit.Case, async: true

  alias Tincture.Font
  alias Tincture.Font.Context
  alias Tincture.Test.MeasurableFont

  setup do
    path = MeasurableFont.write!()
    on_exit(fn -> File.rm(path) end)

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("Probe", path)

    {:ok, path: path, pdf: pdf, context: Context.from_pdf(pdf)}
  end

  describe "measuring embedded fonts" do
    test "reads the advance width out of hmtx and scales by units per em", %{context: context} do
      # 'A' is glyph 1, whose hmtx advance is 700 units against 1000 per em.
      assert Context.text_width(context, "Probe", 10, "A") == 7.0
      assert Context.text_width(context, "Probe", 10, "B") == 9.0
      assert Context.text_width(context, "Probe", 10, "AB") == 16.0
    end

    test "matches an independently computed width for a mixed string", %{context: context} do
      text = "AB BA A"

      assert Context.text_width(context, "Probe", 12, text) ==
               MeasurableFont.expected_width(text, 12)
    end

    test "scales linearly with point size", %{context: context} do
      at_11 = Context.text_width(context, "Probe", 11, "ABBA")
      at_22 = Context.text_width(context, "Probe", 22, "ABBA")

      assert at_22 == at_11 * 2
    end

    test "counts the space glyph rather than skipping it", %{context: context} do
      # Space is a real glyph with a 300-unit advance and no outline. Dropping
      # zero-outline glyphs would make every measured line too short.
      assert Context.text_width(context, "Probe", 10, "A B") ==
               Context.text_width(context, "Probe", 10, "AB") + 3.0
    end

    test "is not the fallback estimate in disguise", %{context: context} do
      # The estimate for an unmeasurable font is 0.6 * size per character. If
      # that were being returned here the earlier exact assertions would be
      # coincidences; this pins that the two paths genuinely differ.
      text = "ABBA"
      estimate = String.length(text) * 10 * 0.6

      measured = Context.text_width(context, "Probe", 10, text)

      assert measured == 32.0
      refute measured == estimate
    end
  end

  describe "measuring standard fonts" do
    test "an empty context agrees with Font.text_width/3" do
      context = Context.new()

      for font <- ["Helvetica", "Times-Roman", "Courier"], size <- [9, 12.5] do
        assert Context.text_width(context, font, size, "Hamburgefonstiv") ==
                 Font.text_width(font, size, "Hamburgefonstiv")
      end
    end

    test "a document context still resolves standard fonts", %{context: context} do
      assert Context.text_width(context, "Helvetica", 12, "Hello") ==
               Font.text_width("Helvetica", 12, "Hello")
    end

    test "a standard name wins over an embedded font registered under it", %{path: path} do
      # Documented precedence, and what the pre-existing drawing path did.
      context =
        Tincture.new()
        |> Tincture.register_ttf_font("Helvetica", path)
        |> Context.from_pdf()

      assert Context.text_width(context, "Helvetica", 10, "AB") ==
               Font.text_width("Helvetica", 10, "AB")

      refute Context.text_width(context, "Helvetica", 10, "AB") == 16.0
    end
  end

  describe "unknown fonts" do
    test "raise by default, so a mistyped name is caught", %{context: context} do
      assert_raise ArgumentError, ~r/unknown font: Nope/, fn ->
        Context.text_width(context, "Nope", 10, "A")
      end
    end

    test "estimate when asked to, which is what the drawing path needs", %{context: context} do
      # set_font/3 does not validate, so a document can already be drawing with
      # an unknown font. Raising at measurement would turn a cosmetic problem
      # into a crash at export.
      assert Context.text_width(context, "Nope", 10, "ABCD", on_unknown: :estimate) == 24.0
    end
  end

  describe "measure/4" do
    test "reports a real width as :ok", %{context: context} do
      assert {:ok, 7.0} = Context.measure(context, "Probe", 10, "A")
      assert {:ok, _width} = Context.measure(context, "Helvetica", 10, "A")
    end

    test "reports an unresolvable font as :unresolved, with an estimate", %{context: context} do
      assert {:unresolved, 24.0} = Context.measure(context, "Nope", 10, "ABCD")
    end
  end

  describe "from_pdf/1" do
    test "an empty document resolves nothing embedded" do
      context = Context.from_pdf(Tincture.new())

      assert {:unresolved, _estimate} = Context.measure(context, "Probe", 10, "A")
    end

    test "carries every registered font", %{path: path} do
      context =
        Tincture.new()
        |> Tincture.register_ttf_font("One", path)
        |> Tincture.register_ttf_font("Two", path)
        |> Context.from_pdf()

      assert Context.measurable?(context, "One")
      assert Context.measurable?(context, "Two")
      refute Context.measurable?(context, "Three")
    end
  end

  describe "measurable?/2" do
    test "is true for standard and embedded fonts, false otherwise", %{context: context} do
      assert Context.measurable?(context, "Helvetica")
      assert Context.measurable?(context, "Probe")
      refute Context.measurable?(context, "Nope")
    end
  end
end

defmodule Tincture.LayoutAttributesTest do
  # Not async: several tests capture stderr, which the whole VM shares.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # Layout attributes on structure elements (ISO 32000-1 §14.8.5.4): the
  # /BBox a figure computes from what it draws, and the /Placement /Block an
  # inline element declares when it sits directly in a grouping element.

  defp tagged(fun) do
    Tincture.new()
    |> Tincture.set_language("en-GB")
    |> Tincture.tag(:document, fun)
  end

  defp figure(pdf, opts \\ [], fun),
    do: Tincture.tag(pdf, :figure, [alt: "a figure"] ++ opts, fun)

  defp figure_element(pdf) do
    pdf.structure_tree
    |> Tincture.PDF.Structure.flatten()
    |> Enum.find(&(&1.tag == :figure))
  end

  defp bbox(fun), do: tagged(&figure(&1, fun)) |> figure_element() |> Map.get(:bbox)

  describe "a figure's computed bounding box" do
    test "a filled rectangle is its own box" do
      assert bbox(&Tincture.rectangle(&1, 100, 200, 50, 30, :fill)) == {100, 200, 150, 230}
    end

    test "a stroked line is inflated by half the line width" do
      box =
        bbox(fn pdf ->
          pdf |> Tincture.set_line_width(4) |> Tincture.line(100, 200, 300, 200)
        end)

      assert box == {98.0, 198.0, 302.0, 202.0}
    end

    test "the default line width is 1" do
      assert bbox(&Tincture.line(&1, 100, 200, 300, 200)) == {99.5, 199.5, 300.5, 200.5}
    end

    test "a Bezier contributes the hull of its control points" do
      box =
        bbox(fn pdf ->
          pdf
          |> Tincture.move_to(100, 100)
          |> Tincture.bezier(120, 300, 180, -50, 200, 100)
          |> Tincture.fill()
        end)

      assert box == {100, -50, 200, 300}
    end

    test "an image is its placement rectangle" do
      path = write_test_png!()

      try do
        assert bbox(&Tincture.image_png(&1, 72, 500, 144, 96, path)) == {72, 500, 216, 596}
      after
        File.rm(path)
      end
    end

    # Tincture has no operation that changes the transformation matrix; the
    # one `cm` it writes is an image's placement, covered above. What q/Q do
    # carry is the line width, which decides how far a stroke is inflated.
    test "q/Q restore the line width a later stroke is inflated by" do
      box =
        bbox(fn pdf ->
          pdf
          |> Tincture.set_line_width(2)
          |> Tincture.save_state()
          |> Tincture.set_line_width(10)
          |> Tincture.save_state()
          |> Tincture.set_line_width(20)
          |> Tincture.restore_state()
          |> Tincture.line(100, 100, 200, 100)
          |> Tincture.restore_state()
          |> Tincture.line(100, 300, 200, 300)
        end)

      assert box == {95.0, 95.0, 205.0, 301.0}
    end

    test "a stroked circle is its square, inflated" do
      box = bbox(fn pdf -> pdf |> Tincture.set_line_width(2) |> Tincture.circle(100, 100, 10) end)
      assert box == {89.0, 89.0, 111.0, 111.0}
    end

    test "a gradient is the rectangle it fills" do
      box =
        bbox(fn pdf ->
          Tincture.linear_gradient(pdf, 20, 30, 100, 50, [{0, {1, 0, 0}}, {1, {0, 0, 1}}])
        end)

      assert box == {20, 30, 120, 80}
    end

    test "a clip draws nothing, and an even-odd fill is not inflated" do
      box =
        bbox(fn pdf ->
          pdf
          |> Tincture.set_line_width(8)
          |> Tincture.rectangle(0, 0, 500, 500, :none)
          |> Tincture.clip()
          |> Tincture.move_to(10, 10)
          |> Tincture.line_to(40, 10)
          |> Tincture.line_to(25, 40)
          |> Tincture.fill_even_odd()
        end)

      assert box == {10, 10, 40, 40}
    end

    test "content nested in the figure counts, and the figure ends at its own EMC" do
      pdf =
        tagged(fn pdf ->
          pdf
          |> figure(fn pdf ->
            pdf
            |> Tincture.artifact(&Tincture.rectangle(&1, 10, 10, 10, 10, :fill))
            |> Tincture.tag(:span, &Tincture.rectangle(&1, 50, 50, 10, 10, :fill))
          end)
          |> Tincture.rectangle(200, 200, 10, 10, :fill)
        end)

      assert figure_element(pdf).bbox == {10, 10, 60, 60}
    end

    test "only what is drawn inside the figure counts" do
      pdf =
        tagged(fn pdf ->
          pdf
          |> Tincture.artifact(&Tincture.rectangle(&1, 0, 0, 500, 500, :fill))
          |> figure(&Tincture.rectangle(&1, 10, 10, 20, 20, :fill))
          |> Tincture.artifact(&Tincture.rectangle(&1, 0, 0, 500, 500, :fill))
        end)

      assert figure_element(pdf).bbox == {10, 10, 30, 30}
    end

    test "is written as a Layout attribute" do
      binary =
        tagged(&figure(&1, fn pdf -> Tincture.rectangle(pdf, 100, 200, 50, 30, :fill) end))
        |> Tincture.export()

      assert binary =~ "/S /Figure "
      assert binary =~ "/A << /O /Layout /Placement /Block /BBox [100 200 150 230] >>"
    end
  end

  describe "text in a figure" do
    defp text_figure_bbox(fun) do
      pdf =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.set_font("Helvetica", 10)
        |> Tincture.tag(:document, &figure(&1, fun))

      {pdf, figure_element(pdf).bbox}
    end

    # The same estimate text_link/6 uses for its clickable area: the metric
    # width, three quarters of the size above the baseline and a quarter below.
    test "is bounded by its metric width and 0.75/0.25 of its size" do
      {pdf, box} = text_figure_bbox(&Tincture.text_at(&1, 100, 200, "Label"))
      width = Tincture.PDF.TextExtent.extent(pdf, "Helvetica", 10, "Label") |> elem(0)

      assert box == {100, 197.5, 100 + width, 207.5}
      assert width > 0
    end

    test "unions with the geometry around it" do
      {_pdf, box} =
        text_figure_bbox(fn pdf ->
          pdf
          |> Tincture.rectangle(50, 50, 300, 300, :fill)
          |> Tincture.text_at(60, 60, "label")
        end)

      assert box == {50, 50, 350, 350}
    end

    test "rotated text is bounded by its rotated corners" do
      {pdf, {left, bottom, right, top}} =
        text_figure_bbox(&Tincture.text_at_rotated(&1, 100, 200, 90, "Label"))

      width = Tincture.PDF.TextExtent.extent(pdf, "Helvetica", 10, "Label") |> elem(0)

      # Turned 90 degrees anticlockwise about the start of the baseline: the
      # run goes up the page, and the ascent extends to the left.
      assert {left, bottom, right, top} == {92.5, 200.0, 102.5, 200 + width}
    end

    test "uses the same extent as a text link's clickable area" do
      pdf =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_link(72, 700, "Read more", "https://example.com")

      [annotation] = Tincture.PDF.page_annotations(pdf, 1)
      {width, ascent, descent} = Tincture.PDF.TextExtent.extent(pdf, "Helvetica", 12, "Read more")

      bottom = 700 - descent
      assert annotation.rect == {72, bottom, 72 + width, bottom + (ascent + descent)}
    end

    test "is no longer a violation, and the document exports with its /BBox" do
      {pdf, _box} = text_figure_bbox(&Tincture.text_at(&1, 100, 200, "Label"))

      assert Tincture.pdf_ua_violations(pdf) == []
      assert Tincture.export(pdf) =~ "/BBox [100 197.5 "
    end
  end

  describe "a figure that draws nothing" do
    test "warns, gets no /BBox, and still exports" do
      {pdf, warning} = with_io(:stderr, fn -> tagged(&figure(&1, fn pdf -> pdf end)) end)

      assert warning =~
               ~s|Tincture.tag(:figure, ...) with alt text "a figure" on page 1 draws nothing|

      assert warning =~ "This will raise in 0.4.0."
      assert figure_element(pdf).bbox_unknown == :no_content
      assert Tincture.pdf_ua_violations(pdf) == []
      refute Tincture.export(pdf) =~ "/BBox"
    end

    test "is named as having no alt text when it has none" do
      {_pdf, warning} =
        with_io(:stderr, fn -> tagged(&Tincture.tag(&1, :figure, fn pdf -> pdf end)) end)

      assert warning =~ "Tincture.tag(:figure, ...) with no alt text on page 1 draws nothing"
    end

    test "an explicit :bbox is used instead, silently" do
      {pdf, warning} =
        with_io(:stderr, fn ->
          tagged(&figure(&1, [bbox: {10, 20, 30, 40}], fn pdf -> pdf end))
        end)

      assert warning == ""
      assert Tincture.export(pdf) =~ "/BBox [10 20 30 40]"
    end
  end

  describe "an explicit :bbox" do
    test "is used as is, even where one could be computed" do
      pdf =
        tagged(fn pdf ->
          figure(pdf, [bbox: {0, 0, 300, 300}], &Tincture.rectangle(&1, 10, 10, 20, 20, :fill))
        end)

      assert figure_element(pdf).bbox == {0, 0, 300, 300}
    end

    test "accepts four numbers inside the MediaBox" do
      assert figure_element(with_bbox({0, 0, 595, 842})).bbox == {0, 0, 595, 842}
      assert figure_element(with_bbox({10.5, 20, 30, 40.25})).bbox == {10.5, 20, 30, 40.25}
    end

    # tag/4 has always ignored options it does not know, :bbox among them, so a
    # :bbox it cannot use is ignored with a warning, and the box is computed.
    for {name, bbox, message} <- [
          {"a list", [0, 0, 10, 10], "four numbers"},
          {"three numbers", {0, 0, 10}, "four numbers"},
          {"a non-number", {0, 0, "10", 10}, "four numbers"},
          {"left == right", {10, 0, 10, 10}, "left < right and bottom < top"},
          {"left > right", {20, 0, 10, 10}, "left < right and bottom < top"},
          {"bottom == top", {0, 10, 10, 10}, "left < right and bottom < top"},
          {"left outside the page", {-1, 0, 10, 10}, "outside the page's MediaBox [0 0 595 842]"},
          {"right outside the page", {0, 0, 596, 10}, "outside the page's MediaBox"},
          {"top outside the page", {0, 0, 10, 843}, "outside the page's MediaBox"}
        ] do
      test "#{name} is ignored with a warning, and the box computed" do
        {pdf, warning} = with_io(:stderr, fn -> with_bbox(unquote(Macro.escape(bbox))) end)

        assert warning =~ unquote(message)
        assert warning =~ "It is ignored"
        assert warning =~ "This will raise in 0.4.0."
        assert figure_element(pdf).bbox == {1, 1, 2, 2}
      end
    end

    test "on another tag is ignored with a warning" do
      {pdf, warning} = with_io(:stderr, fn -> with_bbox({0, 0, 10, 10}, :p) end)

      assert warning =~ ":bbox is only used on :figure, and was given on :p"
      assert warning =~ "This will raise in 0.4.0."
      refute Tincture.export(pdf) =~ "/BBox"
    end
  end

  describe "a figure across pages" do
    # ISO 32000-1 Table 344 requires BBox only of a figure "appearing in its
    # entirety on a single page".
    test "gets no box and is not a violation" do
      {pdf, _warning} =
        with_io(:stderr, fn ->
          tagged(fn pdf ->
            figure(pdf, fn pdf ->
              pdf
              |> Tincture.rectangle(50, 50, 100, 100, :fill)
              |> Tincture.add_page()
              |> Tincture.rectangle(60, 60, 100, 100, :fill)
            end)
          end)
        end)

      assert figure_element(pdf).bbox_unknown == :spans_pages
      assert Tincture.pdf_ua_violations(pdf) == []
    end
  end

  defp with_bbox(bbox, tag \\ :figure) do
    tagged(fn pdf ->
      Tincture.tag(pdf, tag, [alt: "x", bbox: bbox], &Tincture.rectangle(&1, 1, 1, 1, 1, :fill))
    end)
  end

  describe "/Placement /Block" do
    defp structure_element(binary, type) do
      [element] = Regex.scan(~r/<< \/Type \/StructElem \/S \/#{type} [^\n]*/, binary)
      hd(element)
    end

    defp link(pdf),
      do: Tincture.text_link(pdf, 50, 700, "Example", "https://example.com", contents: "Example")

    test "is written on an inline element directly in a grouping element" do
      for container <- [:document, :part, :article, :section, :div] do
        binary =
          Tincture.new()
          |> Tincture.set_language("en-GB")
          |> Tincture.tag(container, &Tincture.tag(&1, :link, fn pdf -> link(pdf) end))
          |> Tincture.export()

        assert structure_element(binary, "Link") =~ "/A << /O /Layout /Placement /Block >>",
               "a :link in #{inspect(container)}"
      end
    end

    test "is not written on an inline element inside a block element" do
      binary =
        tagged(fn pdf ->
          Tincture.tag(pdf, :p, fn pdf ->
            pdf
            |> Tincture.text_at(50, 750, "See ")
            |> Tincture.tag(:link, fn pdf -> link(pdf) end)
            |> Tincture.tag(:figure, [alt: "icon"], &Tincture.rectangle(&1, 10, 10, 5, 5, :fill))
          end)
        end)
        |> Tincture.export()

      refute structure_element(binary, "Link") =~ "/A "
      refute binary =~ "/Placement"
      assert structure_element(binary, "Figure") =~ "/A << /O /Layout /BBox [10 10 15 15] >>"
    end

    test "is not written on a block element in a grouping element" do
      binary =
        tagged(&Tincture.tag(&1, :p, fn pdf -> Tincture.text_at(pdf, 50, 750, "x") end))
        |> Tincture.export()

      refute binary =~ "/A "
    end

    test "leaves table header scope as it was" do
      binary =
        tagged(fn pdf ->
          Tincture.tag(pdf, :table, fn pdf ->
            Tincture.tag(pdf, :tr, fn pdf ->
              Tincture.tag(pdf, :th, [scope: :column], &Tincture.text_at(&1, 50, 700, "Region"))
            end)
          end)
        end)
        |> Tincture.export()

      assert structure_element(binary, "TH") =~ "/A << /O /Table /Scope /Column >> >>"
    end
  end

  defp write_test_png! do
    path = Path.join(System.tmp_dir!(), "tincture_bbox_#{System.unique_integer([:positive])}.png")
    ihdr = <<1::32-big, 1::32-big, 8, 6, 0, 0, 0>>
    idat = :zlib.compress(<<0, 255, 0, 0, 128>>)

    png =
      <<137, 80, 78, 71, 13, 10, 26, 10>> <>
        png_chunk("IHDR", ihdr) <> png_chunk("IDAT", idat) <> png_chunk("IEND", "")

    :ok = File.write(path, png)
    path
  end

  defp png_chunk(type, data) do
    <<byte_size(data)::32-big, type::binary-size(4), data::binary,
      :erlang.crc32([type, data])::32-big>>
  end
end

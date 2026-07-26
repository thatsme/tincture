defmodule Tincture.Layout.TemplateValidationTest do
  @moduledoc """
  Option validation, slot sizing and spill handling for page templates.

  The existing template tests cover the happy paths — building a template,
  flowing text through it, paginating. These cover what happens when a caller
  gets an option wrong, which for a layout API is most of what users hit first:
  a template that silently accepts `columns: 0` produces a division by zero
  somewhere far away from the mistake.
  """
  use ExUnit.Case, async: true

  alias Tincture.Layout.Template
  alias Tincture.Typography.RichText

  defp rich(text), do: RichText.from_plain(text, font: "Helvetica", size: 12)

  describe "new/1 margin validation" do
    test "accepts a four-tuple of non-negative numbers" do
      template = Template.new(margins: {10, 20, 30, 40})
      assert template.margins == %{left: 10.0, right: 20.0, top: 30.0, bottom: 40.0}
    end

    test "normalises integers to floats so later arithmetic is consistent" do
      assert Template.new(margins: {0, 0, 0, 0}).margins.left === 0.0
    end

    test "rejects a negative margin" do
      assert_raise ArgumentError, ~r/invalid margins/, fn ->
        Template.new(margins: {-1, 0, 0, 0})
      end
    end

    test "rejects a tuple of the wrong size" do
      assert_raise ArgumentError, ~r/invalid margins/, fn ->
        Template.new(margins: {10, 20})
      end
    end

    test "rejects a non-tuple" do
      for value <- [nil, 10, [10, 20, 30, 40], %{left: 1}] do
        assert_raise ArgumentError, ~r/invalid margins/, fn ->
          Template.new(margins: value)
        end
      end
    end
  end

  describe "new/1 column validation" do
    test "accepts a positive integer" do
      assert Template.new(columns: 3).columns == 3
    end

    test "produces one body box per column" do
      assert length(Template.new(columns: 3).body_boxes) == 3
    end

    test "rejects zero or negative columns" do
      for value <- [0, -1] do
        assert_raise ArgumentError, ~r/columns must be a positive integer/, fn ->
          Template.new(columns: value)
        end
      end
    end

    test "rejects a non-integer column count" do
      for value <- [1.5, nil, "2"] do
        assert_raise ArgumentError, ~r/columns must be a positive integer/, fn ->
          Template.new(columns: value)
        end
      end
    end
  end

  describe "new/1 measurement validation" do
    test "accepts zero for the non-negative measurements" do
      template = Template.new(gutter: 0, header_height: 0, footer_height: 0)
      assert template.gutter === 0.0
      assert template.header_height === 0.0
      assert template.footer_height === 0.0
    end

    test "rejects a negative gutter, header height or footer height" do
      for {key, label} <- [
            {:gutter, "gutter"},
            {:header_height, "header_height"},
            {:footer_height, "footer_height"}
          ] do
        assert_raise ArgumentError, ~r/#{label} must be >= 0/, fn ->
          Template.new([{key, -1}])
        end
      end
    end

    test "rejects a non-numeric measurement" do
      assert_raise ArgumentError, ~r/gutter must be >= 0/, fn ->
        Template.new(gutter: "wide")
      end
    end
  end

  describe "with_header/3 and with_footer/3" do
    test "store the slot text" do
      template = Template.new() |> Template.with_header("Title")
      assert template.header.text == "Title"
    end

    test "default to sensible sizes for each slot" do
      template = Template.new() |> Template.with_header("H") |> Template.with_footer("F")
      # Footers are conventionally set smaller than headers.
      assert template.header.size == 12.0
      assert template.footer.size == 10.0
    end

    test "accept an explicit size" do
      template = Template.new() |> Template.with_header("Title", size: 18)
      assert template.header.size == 18.0
    end

    test "accept an explicit height, which resizes the slot and the body" do
      base = Template.new()
      taller = Template.with_header(base, "Title", height: 100)

      assert taller.header_height == 100.0

      # Body boxes are {x, y, width, height}; a taller header eats into the
      # height by exactly the difference.
      [{_x, _y, _w, base_height}] = base.body_boxes
      [{_x2, _y2, _w2, taller_height}] = taller.body_boxes
      assert taller_height == base_height - (100.0 - base.header_height)
    end

    test "an omitted height leaves the template's own height in place" do
      template = Template.new(header_height: 45) |> Template.with_header("Title")
      assert template.header_height == 45.0
    end

    test "a footer height also resizes the body" do
      base = Template.new()
      taller = Template.with_footer(base, "Page", height: 90)

      assert taller.footer_height == 90.0

      [{_x, _y, _w, base_height}] = base.body_boxes
      [{_x2, _y2, _w2, taller_height}] = taller.body_boxes
      assert taller_height == base_height - (90.0 - base.footer_height)
    end

    test "reject a non-positive size" do
      assert_raise ArgumentError, ~r/size must be > 0/, fn ->
        Template.with_header(Template.new(), "T", size: 0)
      end
    end

    test "reject a negative height" do
      assert_raise ArgumentError, ~r/height must be >= 0/, fn ->
        Template.with_footer(Template.new(), "F", height: -1)
      end
    end
  end

  describe "render/4 page number validation" do
    setup do
      {:ok, template: Template.new() |> Template.with_footer("Page {page} of {total}")}
    end

    test "render/3 works without an options list" do
      {pdf, result} = Template.render(Tincture.new(), Template.new(), rich("body"))

      assert %Tincture.Layout.Template.RenderResult{} = result
      assert Tincture.export(pdf) =~ "(body) Tj"
    end

    test "defaults the total to the current page number", %{template: template} do
      {pdf, _result} = Template.render(Tincture.new(), template, rich("body"), page_number: 3)
      assert Tincture.export(pdf) =~ "Page 3 of 3"
    end

    test "accepts an explicit total", %{template: template} do
      {pdf, _result} =
        Template.render(Tincture.new(), template, rich("body"), page_number: 2, page_total: 9)

      assert Tincture.export(pdf) =~ "Page 2 of 9"
    end

    test "rejects a page number that is not a positive integer", %{template: template} do
      for value <- [0, -1, 1.5, nil] do
        assert_raise ArgumentError, ~r/page_number must be > 0/, fn ->
          Template.render(Tincture.new(), template, rich("body"), page_number: value)
        end
      end
    end

    test "rejects a page total that is not a positive integer", %{template: template} do
      assert_raise ArgumentError, ~r/page_total must be > 0/, fn ->
        Template.render(Tincture.new(), template, rich("body"), page_total: 0)
      end
    end
  end

  describe "render_document/4 validation" do
    setup do
      # Tall header and footer leave a short body, which is what forces
      # pagination - a letter page fits a lot of 12pt text otherwise.
      template =
        Template.new(header_height: 330, footer_height: 330)
        |> Template.with_footer("{page}/{total}")

      {:ok, template: template}
    end

    test "rejects a non-positive starting page", %{template: template} do
      assert_raise ArgumentError, ~r/page_number_start must be > 0/, fn ->
        Template.render_document(Tincture.new(), template, rich("body"), page_number_start: 0)
      end
    end

    test "rejects a non-positive max_pages", %{template: template} do
      assert_raise ArgumentError, ~r/max_pages must be > 0/, fn ->
        Template.render_document(Tincture.new(), template, rich("body"), max_pages: 0)
      end
    end

    test "rejects an explicit page_total that is not a positive integer", %{template: template} do
      assert_raise ArgumentError, ~r/page_total must be > 0/, fn ->
        Template.render_document(Tincture.new(), template, rich("body"), page_total: -2)
      end
    end

    test "an omitted page_total resolves per page", %{template: template} do
      # With no total supplied each page reports its own number, because the
      # real total is not known until pagination finishes.
      {pdf, _result} = Template.render_document(Tincture.new(), template, rich("short"))
      assert Tincture.export(pdf) =~ "1/1"
    end

    test "an explicit page_total is used on every page", %{template: template} do
      long = rich(Enum.map_join(1..60, " ", &"word#{&1}"))
      {pdf, result} = Template.render_document(Tincture.new(), template, long, page_total: 7)

      binary = Tincture.export(pdf)
      assert result.pages_used > 1
      assert binary =~ "1/7"
      assert binary =~ "2/7"
    end

    test "stops at max_pages and reports the spill", %{template: template} do
      long = rich(Enum.map_join(1..2000, " ", &"word#{&1}"))
      {_pdf, result} = Template.render_document(Tincture.new(), template, long, max_pages: 2)

      assert result.pages_used == 2
      assert result.overflow?
      assert result.spill_text != ""
    end

    test "content that fits reports no overflow", %{template: template} do
      {_pdf, result} = Template.render_document(Tincture.new(), template, rich("short"))

      assert result.pages_used == 1
      refute result.overflow?
      assert result.spill_text == ""
    end
  end

  describe "spill carries styling forward" do
    test "continuation pages keep the font of the original text" do
      template = Template.new(header_height: 330, footer_height: 330)
      long = RichText.from_plain(Enum.map_join(1..60, " ", &"w#{&1}"), font: "Courier", size: 9)
      {pdf, result} = Template.render_document(Tincture.new(), template, long)

      assert result.pages_used > 1
      assert Tincture.export(pdf) =~ "/Courier"
    end

    test "an empty document renders one page with no overflow" do
      {_pdf, result} = Template.render_document(Tincture.new(), Template.new(), rich(""))

      assert result.pages_used == 1
      refute result.overflow?
    end
  end

  describe "XML attribute validation" do
    defp xml(attrs) do
      ~s(<document #{attrs}><body font="Courier" size="10">Hi</body></document>)
    end

    test "omitted attributes fall back to defaults" do
      assert {:ok, template, _rich} = Template.parse_xml(xml(""))
      assert template.page_size == :letter
      assert template.columns == 1
      assert template.gutter == 20.0
      assert template.margins == %{left: 50.0, right: 50.0, top: 50.0, bottom: 50.0}
    end

    test "reads each supported attribute" do
      assert {:ok, template, _rich} =
               Template.parse_xml(xml(~s(page_size="a4" columns="2" gutter="15")))

      assert template.page_size == :a4
      assert template.columns == 2
      assert template.gutter == 15.0
    end

    test "reads a four-value margins attribute" do
      assert {:ok, template, _rich} = Template.parse_xml(xml(~s(margins="1,2,3,4")))
      assert template.margins == %{left: 1.0, right: 2.0, top: 3.0, bottom: 4.0}
    end

    test "rejects an unknown page size" do
      assert {:error, _} = Template.parse_xml(xml(~s(page_size="tabloid")))
    end

    test "rejects a malformed margins attribute" do
      for value <- ["1,2,3", "1,2,3,4,5", "a,b,c,d", "-1,0,0,0"] do
        assert {:error, _} = Template.parse_xml(xml(~s(margins="#{value}"))),
               "margins=#{inspect(value)} should be rejected"
      end
    end

    test "rejects a non-positive column count" do
      for value <- ["0", "-1", "two"] do
        assert {:error, _} = Template.parse_xml(xml(~s(columns="#{value}")))
      end
    end

    test "rejects a negative gutter" do
      assert {:error, _} = Template.parse_xml(xml(~s(gutter="-5")))
    end
  end

  describe "XML document structure" do
    test "rejects input that is not XML at all" do
      assert Template.parse_xml("not xml") == {:error, :invalid_xml}
    end

    test "rejects an empty string" do
      assert Template.parse_xml("") == {:error, :invalid_xml}
    end

    test "rejects XML with an unclosed tag" do
      assert Template.parse_xml("<document><body><p>x</body></document>") ==
               {:error, :invalid_xml}
    end
  end

  describe "XML page sizes" do
    test "accepts each named page size, case-insensitively" do
      for {value, expected} <- [
            {"a4", :a4},
            {"letter", :letter},
            {"legal", :legal},
            {"A4", :a4},
            {" Legal ", :legal}
          ] do
        assert {:ok, template, _rich} = Template.parse_xml(xml(~s(page_size="#{value}")))
        assert template.page_size == expected, "page_size=#{inspect(value)}"
      end
    end

    test "accepts a custom width,height page size" do
      assert {:ok, template, _rich} = Template.parse_xml(xml(~s(page_size="200,400")))
      assert template.page_size == {200.0, 400.0}
    end

    test "rejects a custom page size with a non-positive dimension" do
      for value <- ["0,400", "200,0", "-1,400"] do
        assert {:error, _} = Template.parse_xml(xml(~s(page_size="#{value}")))
      end
    end
  end

  describe "XML slot attributes" do
    defp doc_with(slot) do
      ~s(<document>#{slot}<body font="Courier" size="10">Hi</body></document>)
    end

    test "a header carries font, size and height" do
      xml = doc_with(~s(<header font="Helvetica" size="14" height="60">Top</header>))

      assert {:ok, template, _rich} = Template.parse_xml(xml)
      assert template.header.text == "Top"
      assert template.header.font == "Helvetica"
      assert template.header.size == 14.0
      assert template.header_height == 60.0
    end

    test "a footer carries font, size and height" do
      xml = doc_with(~s(<footer font="Courier" size="8" height="40">Bottom</footer>))

      assert {:ok, template, _rich} = Template.parse_xml(xml)
      assert template.footer.size == 8.0
      assert template.footer_height == 40.0
    end

    test "omitted slot attributes fall back to defaults" do
      assert {:ok, template, _rich} = Template.parse_xml(doc_with("<header>Top</header>"))
      assert template.header.font == "Helvetica-Bold"
      assert template.header.size == 12.0
      # No height attribute means the template's own height survives.
      assert template.header_height == 30.0
    end

    test "rejects a non-positive slot size" do
      for value <- ["0", "-3", "big"] do
        assert {:error, _} =
                 Template.parse_xml(doc_with(~s(<header size="#{value}">T</header>))),
               "size=#{inspect(value)} should be rejected"
      end
    end

    test "rejects a negative slot height" do
      for value <- ["-1", "tall"] do
        assert {:error, _} =
                 Template.parse_xml(doc_with(~s(<footer height="#{value}">F</footer>)))
      end
    end

    test "a zero slot height is legal and collapses the slot" do
      assert {:ok, template, _rich} =
               Template.parse_xml(doc_with(~s(<header height="0">T</header>)))

      assert template.header_height == 0.0
    end
  end

  describe "XML body attributes" do
    test "an omitted body size falls back to the default" do
      xml = ~s(<document><body font="Courier">Hi</body></document>)
      assert {:ok, _template, rich} = Template.parse_xml(xml)
      assert [%{size: 12.0}] = rich.runs
    end

    test "rejects a non-positive body size" do
      xml = ~s(<document><body size="0">Hi</body></document>)
      assert {:error, _} = Template.parse_xml(xml)
    end
  end
end

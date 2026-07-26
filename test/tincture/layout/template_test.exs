defmodule Tincture.Layout.TemplateTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Tincture.Layout.Box.FlowResult
  alias Tincture.Layout.Template
  alias Tincture.Layout.Template.DocumentResult
  alias Tincture.Layout.Template.RenderResult
  alias Tincture.Typography.RichText

  test "new/1 computes body boxes from page size, margins, columns, and slots" do
    template =
      Template.new(
        page_size: :letter,
        margins: {50, 50, 50, 50},
        columns: 2,
        gutter: 20,
        header_height: 30,
        footer_height: 20
      )

    assert template.page_size == :letter
    assert template.columns == 2

    # Letter width 612, margins 50/50, gutter 20 => each column width 246
    assert template.body_boxes == [
             {50.0, 712.0, 246.0, 642.0},
             {316.0, 712.0, 246.0, 642.0}
           ]
  end

  test "render/4 places header/footer and flows body content across template boxes" do
    rich = RichText.from_plain("one two three four five six", font: "Courier", size: 10)

    template =
      Template.new(page_size: :letter, margins: {50, 50, 50, 50}, columns: 2, gutter: 20)
      |> Template.with_header("Quarterly Report", font: "Helvetica-Bold", size: 14)
      |> Template.with_footer("Page 1", font: "Helvetica", size: 10)

    {pdf, result} =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Template.render(template, rich, line_height: 14)

    assert %RenderResult{body_flow: %FlowResult{overflow?: false}} = result

    assert Enum.any?(
             pdf.operations,
             &match?({:text_at, 50.0, 742.0, "Quarterly Report", {"Helvetica-Bold", 14.0}}, &1)
           )

    assert Enum.any?(
             pdf.operations,
             &match?({:text_at, 50.0, 60.0, "Page 1", {"Helvetica", 10.0}}, &1)
           )

    assert Enum.any?(pdf.operations, &match?({:text_at, 50.0, 712.0, "one", {"Courier", 10}}, &1))
  end

  test "render/4 expands page placeholders in header and footer slots" do
    rich = RichText.from_plain("body", font: "Courier", size: 10)

    template =
      Template.new(page_size: :letter, margins: {50, 50, 50, 50}, columns: 1)
      |> Template.with_header("Report {page}/{total}", font: "Helvetica-Bold", size: 12)
      |> Template.with_footer("Page {page}", font: "Helvetica", size: 10)

    {pdf, _result} =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Template.render(template, rich, page_number: 3, page_total: 12, line_height: 14)

    assert Enum.any?(
             pdf.operations,
             &match?({:text_at, 50.0, 742.0, "Report 3/12", {"Helvetica-Bold", 12.0}}, &1)
           )

    assert Enum.any?(
             pdf.operations,
             &match?({:text_at, 50.0, 60.0, "Page 3", {"Helvetica", 10.0}}, &1)
           )
  end

  test "render_document/4 paginates overflow text across pages with page placeholders" do
    text = Enum.map_join(1..30, " ", fn idx -> "word#{idx}" end)
    rich = RichText.from_plain(text, font: "Courier", size: 10)

    template =
      Template.new(
        page_size: :letter,
        margins: {50, 50, 50, 50},
        columns: 1,
        header_height: 330,
        footer_height: 330
      )
      |> Template.with_header("Report {page}/{total}", font: "Helvetica-Bold", size: 12)
      |> Template.with_footer("Page {page}", font: "Helvetica", size: 10)

    {pdf, result} =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Template.render_document(template, rich,
        page_number_start: 1,
        page_total: 2,
        line_height: 14
      )

    assert %DocumentResult{pages_used: 2, overflow?: false, spill_text: ""} = result
    assert pdf.current_page == 2

    pdf_binary = Tincture.export(pdf)
    assert pdf_binary =~ "/Count 2"
    assert pdf_binary =~ "(Report 1/2) Tj"
    assert pdf_binary =~ "(Report 2/2) Tj"
    assert pdf_binary =~ "(Page 1) Tj"
    assert pdf_binary =~ "(Page 2) Tj"
  end

  test "parse_xml/1 builds template layout and body rich text from XML" do
    xml = """
    <document page_size="letter" margins="40,45,50,55" columns="2" gutter="18">
      <header font="Helvetica-Bold" size="13">Invoice {page}/{total}</header>
      <footer font="Helvetica" size="9">Page {page}</footer>
      <body font="Courier" size="11">Line one line two</body>
    </document>
    """

    assert {:ok, template, rich} = Template.parse_xml(xml)
    assert template.page_size == :letter
    assert template.columns == 2
    assert template.gutter == 18.0
    assert template.margins == %{left: 40.0, right: 45.0, top: 50.0, bottom: 55.0}
    assert template.header.text == "Invoice {page}/{total}"
    assert template.footer.text == "Page {page}"
    assert [%{text: "Line one line two", font: "Courier", size: 11.0}] = rich.runs
  end

  test "render_xml_document/3 composes XML template into a rendered document" do
    xml = """
    <document page_size="letter" margins="50,50,50,50" columns="1" gutter="20">
      <header font="Helvetica-Bold" size="12">Report {page}/{total}</header>
      <footer font="Helvetica" size="10">p.{page}</footer>
      <body font="Courier" size="10">one two three four five six seven eight</body>
    </document>
    """

    assert {:ok, pdf, %DocumentResult{} = result} =
             Tincture.new()
             |> Tincture.page_size(:letter)
             |> Template.render_xml_document(xml,
               page_number_start: 1,
               page_total: 1,
               line_height: 14
             )

    assert result.pages_used == 1
    assert result.overflow? == false

    pdf_binary = Tincture.export(pdf)
    assert pdf_binary =~ "(Report 1/1) Tj"
    assert pdf_binary =~ "(p.1) Tj"
    assert pdf_binary =~ "(one) Tj"
  end

  test "parse_xml/1 returns :invalid_xml for malformed XML" do
    xml = "<document><body>broken"

    capture_log(fn ->
      assert {:error, :invalid_xml} = Template.parse_xml(xml)
    end)
  end

  test "parse_xml/1 returns :missing_body when body node is absent" do
    xml = """
    <document page_size="letter" margins="50,50,50,50" columns="1" gutter="20">
      <header font="Helvetica-Bold" size="12">Report</header>
    </document>
    """

    assert {:error, :missing_body} = Template.parse_xml(xml)
  end

  test "render_xml_document/3 propagates XML attribute validation errors" do
    xml = """
    <document page_size="letter" margins="50,50,50,50" columns="1" gutter="20">
      <body font="Courier" size="-1">one two</body>
    </document>
    """

    assert {:error, {:invalid_body_size, "-1"}} =
             Tincture.new()
             |> Tincture.page_size(:letter)
             |> Template.render_xml_document(xml)
  end
end

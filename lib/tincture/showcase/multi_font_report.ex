defmodule Tincture.Showcase.MultiFontReport do
  @moduledoc false

  alias Tincture.Layout.Table
  alias Tincture.Typography.RichText
  alias Tincture.Typography.RichText.Run

  @type build_result :: %{
          pdf: Tincture.PDF.t(),
          pages: pos_integer(),
          metrics_result: Table.RenderResult.t()
        }

  @spec build_document() :: build_result()
  def build_document do
    pdf =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Tincture.set_metadata(
        title: "Multi-Font Report Showcase Demo",
        author: "Tincture",
        subject: "Typography and multi-font report demo",
        keywords: "showcase,typography,report,pdf"
      )
      |> Tincture.add_page()
      |> Tincture.add_bookmark("Executive Summary", 1)
      |> Tincture.add_bookmark("Implementation Appendix", 2)
      |> Tincture.set_page(1)
      |> draw_page_chrome(1, 2)
      |> Tincture.set_font("Helvetica-Bold", 24)
      |> Tincture.text_at(48, 730, "Q1 Product Rollout Report")
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_at(48, 700, "Helvetica headline drives hierarchy.")
      |> Tincture.set_font("Times-Roman", 12)
      |> Tincture.text_at(48, 682, "Times body copy demonstrates readable long-form text.")
      |> Tincture.set_font("Courier", 11)
      |> Tincture.text_at(48, 664, "Courier code block preserves alignment.")

    rich =
      RichText.from_runs([
        %Run{text: "Tincture can mix ", font: "Times-Roman", size: 11},
        %Run{text: "headline", font: "Helvetica-Bold", size: 11},
        %Run{text: ", ", font: "Times-Roman", size: 11},
        %Run{text: "body", font: "Times-Italic", size: 11},
        %Run{text: ", and ", font: "Times-Roman", size: 11},
        %Run{text: "code-like", font: "Courier-Bold", size: 11},
        %Run{text: " treatment in one document.", font: "Times-Roman", size: 11}
      ])

    pdf =
      Tincture.text_paragraph(pdf, 48, 636, rich, 516,
        align: :justified,
        line_break: :optimal,
        line_height: 14
      )

    {pdf, metrics_result} =
      Table.render(pdf, 48, 560, [170, 110, 110, 126], rollout_metrics_rows(),
        header_rows: 1,
        font: "Helvetica",
        header_font: "Helvetica-Bold",
        font_size: 9,
        padding: 4,
        valign: :middle
      )

    pdf =
      pdf
      |> Tincture.set_page(2)
      |> draw_page_chrome(2, 2)
      |> Tincture.set_font("Helvetica-Bold", 14)
      |> Tincture.text_at(48, 730, "Implementation Appendix")
      |> Tincture.set_font("Helvetica", 11)
      |> Tincture.text_at(48, 708, "Kerning and line-break modes can be tuned per block.")
      |> draw_code_block(48, 680)
      |> Tincture.set_fill_color({0.0, 0.0, 0.0})
      |> Tincture.set_font("Times-Roman", 11)
      |> Tincture.text_at(48, 614, "Post-code commentary remains readable and properly colored.")
      |> Tincture.text_at(
        48,
        598,
        "This section intentionally verifies contrast and vertical rhythm."
      )

    %{pdf: pdf, pages: 2, metrics_result: metrics_result}
  end

  @spec pdf_binary() :: binary()
  def pdf_binary do
    %{pdf: pdf} = build_document()
    Tincture.export(pdf)
  end

  @spec write_pdf(Path.t()) :: Path.t()
  def write_pdf(path \\ "tmp/multi_font_report_showcase.pdf") when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, pdf_binary())
    path
  end

  defp draw_code_block(pdf, x, top_y) do
    lines = [
      "defmodule Rollout do",
      "  def step(id, status), do: %{id: id, status: status}",
      "end"
    ]

    line_height = 12
    box_height = line_height * length(lines) + 10
    box_bottom = top_y - box_height + 4

    pdf =
      pdf
      |> Tincture.set_fill_color({0.94, 0.95, 0.97})
      |> Tincture.rectangle(x, box_bottom, 516, box_height)
      |> Tincture.fill()
      |> Tincture.set_stroke_color({0.78, 0.81, 0.87})
      |> Tincture.set_line_width(0.8)
      |> Tincture.rectangle(x, box_bottom, 516, box_height)
      |> Tincture.stroke()
      |> Tincture.set_fill_color({0.0, 0.0, 0.0})

    {pdf, _next_y} =
      Enum.reduce(lines, {pdf, top_y - 12}, fn line, {acc_pdf, y} ->
        next_pdf =
          acc_pdf
          |> Tincture.set_font("Courier", 10)
          |> Tincture.text_at(x + 8, y, line)

        {next_pdf, y - line_height}
      end)

    pdf
  end

  defp draw_page_chrome(pdf, page, total) do
    pdf
    |> Tincture.set_font("Helvetica-Bold", 11)
    |> Tincture.text_at(48, 758, "Northstar Analytics - Multi-Font Report #{page}/#{total}")
    |> Tincture.set_font("Helvetica", 9)
    |> Tincture.text_at(48, 30, "Internal Review Copy - Page #{page} of #{total}")
  end

  defp rollout_metrics_rows do
    [
      ["Track", "Goal", "Actual", "Status"],
      ["Adoption", "32%", "35%", "Ahead"],
      ["Latency P95", "<200ms", "184ms", "Healthy"],
      ["Error Rate", "<0.30%", "0.21%", "Healthy"],
      ["Migration", "85%", "81%", "Watch"]
    ]
  end
end

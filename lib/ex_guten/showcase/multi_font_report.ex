defmodule ExGuten.Showcase.MultiFontReport do
  @moduledoc false

  alias ExGuten.Layout.Table
  alias ExGuten.Typography.RichText
  alias ExGuten.Typography.RichText.Run

  @type build_result :: %{
          pdf: ExGuten.PDF.t(),
          pages: pos_integer(),
          metrics_result: Table.RenderResult.t()
        }

  @spec build_document() :: build_result()
  def build_document do
    pdf =
      ExGuten.new()
      |> ExGuten.page_size(:letter)
      |> ExGuten.set_metadata(
        title: "Multi-Font Report Showcase Demo",
        author: "ExGuten",
        subject: "Typography and multi-font report demo",
        keywords: "showcase,typography,report,pdf"
      )
      |> ExGuten.add_page()
      |> ExGuten.add_bookmark("Executive Summary", 1)
      |> ExGuten.add_bookmark("Implementation Appendix", 2)
      |> ExGuten.set_page(1)
      |> draw_page_chrome(1, 2)
      |> ExGuten.set_font("Helvetica-Bold", 24)
      |> ExGuten.text_at(48, 730, "Q1 Product Rollout Report")
      |> ExGuten.set_font("Helvetica", 12)
      |> ExGuten.text_at(48, 700, "Helvetica headline drives hierarchy.")
      |> ExGuten.set_font("Times-Roman", 12)
      |> ExGuten.text_at(48, 682, "Times body copy demonstrates readable long-form text.")
      |> ExGuten.set_font("Courier", 11)
      |> ExGuten.text_at(48, 664, "Courier code block preserves alignment.")

    rich =
      RichText.from_runs([
        %Run{text: "ExGuten can mix ", font: "Times-Roman", size: 11},
        %Run{text: "headline", font: "Helvetica-Bold", size: 11},
        %Run{text: ", ", font: "Times-Roman", size: 11},
        %Run{text: "body", font: "Times-Italic", size: 11},
        %Run{text: ", and ", font: "Times-Roman", size: 11},
        %Run{text: "code-like", font: "Courier-Bold", size: 11},
        %Run{text: " treatment in one document.", font: "Times-Roman", size: 11}
      ])

    pdf =
      ExGuten.text_paragraph(pdf, 48, 636, rich, 516,
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
      |> ExGuten.set_page(2)
      |> draw_page_chrome(2, 2)
      |> ExGuten.set_font("Helvetica-Bold", 14)
      |> ExGuten.text_at(48, 730, "Implementation Appendix")
      |> ExGuten.set_font("Helvetica", 11)
      |> ExGuten.text_at(48, 708, "Kerning and line-break modes can be tuned per block.")
      |> draw_code_block(48, 680)
      |> ExGuten.set_fill_color({0.0, 0.0, 0.0})
      |> ExGuten.set_font("Times-Roman", 11)
      |> ExGuten.text_at(48, 614, "Post-code commentary remains readable and properly colored.")
      |> ExGuten.text_at(
        48,
        598,
        "This section intentionally verifies contrast and vertical rhythm."
      )

    %{pdf: pdf, pages: 2, metrics_result: metrics_result}
  end

  @spec pdf_binary() :: binary()
  def pdf_binary do
    %{pdf: pdf} = build_document()
    ExGuten.export(pdf)
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
      |> ExGuten.set_fill_color({0.94, 0.95, 0.97})
      |> ExGuten.rectangle(x, box_bottom, 516, box_height)
      |> ExGuten.fill()
      |> ExGuten.set_stroke_color({0.78, 0.81, 0.87})
      |> ExGuten.set_line_width(0.8)
      |> ExGuten.rectangle(x, box_bottom, 516, box_height)
      |> ExGuten.stroke()
      |> ExGuten.set_fill_color({0.0, 0.0, 0.0})

    {pdf, _next_y} =
      Enum.reduce(lines, {pdf, top_y - 12}, fn line, {acc_pdf, y} ->
        next_pdf =
          acc_pdf
          |> ExGuten.set_font("Courier", 10)
          |> ExGuten.text_at(x + 8, y, line)

        {next_pdf, y - line_height}
      end)

    pdf
  end

  defp draw_page_chrome(pdf, page, total) do
    pdf
    |> ExGuten.set_font("Helvetica-Bold", 11)
    |> ExGuten.text_at(48, 758, "Northstar Analytics - Multi-Font Report #{page}/#{total}")
    |> ExGuten.set_font("Helvetica", 9)
    |> ExGuten.text_at(48, 30, "Internal Review Copy - Page #{page} of #{total}")
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

defmodule Tincture.Showcase.MarketingPoster do
  @moduledoc false

  alias Tincture.Typography.RichText

  @type build_result :: %{
          pdf: Tincture.PDF.t(),
          pages: pos_integer()
        }

  @spec build_document() :: build_result()
  def build_document do
    qr_path = write_test_qr_png!()

    try do
      pdf =
        Tincture.new()
        |> Tincture.page_size({792, 612})
        |> Tincture.set_metadata(
          title: "Marketing Poster Showcase Demo",
          author: "Tincture",
          subject: "Graphics-heavy poster demo",
          keywords: "showcase,graphics,poster,pdf"
        )
        |> Tincture.add_bookmark("Launch Week", 1)
        |> draw_background()
        |> draw_vector_art()
        |> Tincture.image_png(622, 70, 110, 110, qr_path)
        |> Tincture.set_font("Helvetica-Bold", 46)
        |> Tincture.set_fill_color({1.0, 1.0, 1.0})
        |> Tincture.text_at(60, 500, "Launch Week 2026")
        |> Tincture.set_font("Helvetica-Bold", 16)
        |> Tincture.text_at(60, 466, "VECTOR GRAPHICS + IMAGES + TYPE")
        |> Tincture.set_font("Helvetica", 14)
        |> Tincture.text_at_rotated(690, 188, 90, "SCAN FOR DEMO")
        |> Tincture.set_fill_color({0.0, 0.0, 0.0})

      rich =
        RichText.from_plain(
          "A single page can combine layered vector art, bold typography, and image placement " <>
            "while keeping text crisp and predictable for print output.",
          font: "Times-Roman",
          size: 14
        )

      pdf =
        Tincture.text_paragraph(pdf, 60, 420, rich, 450,
          align: :left,
          line_break: :optimal,
          line_height: 18
        )

      %{pdf: pdf, pages: 1}
    after
      File.rm(qr_path)
    end
  end

  @spec pdf_binary() :: binary()
  def pdf_binary do
    %{pdf: pdf} = build_document()
    Tincture.export(pdf)
  end

  @spec write_pdf(Path.t()) :: Path.t()
  def write_pdf(path \\ "tmp/marketing_poster_showcase.pdf") when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, pdf_binary())
    path
  end

  defp draw_background(pdf) do
    pdf
    |> Tincture.set_fill_color({0.08, 0.12, 0.24})
    |> Tincture.rectangle(0, 0, 792, 612)
    |> Tincture.fill()
    |> Tincture.set_fill_color({0.93, 0.32, 0.27})
    |> Tincture.rectangle(0, 360, 792, 252)
    |> Tincture.fill()
    |> Tincture.set_fill_color({0.96, 0.74, 0.16})
    |> Tincture.rectangle(0, 300, 792, 40)
    |> Tincture.fill()
  end

  defp draw_vector_art(pdf) do
    pdf
    |> Tincture.save_state()
    |> Tincture.set_stroke_color({1.0, 1.0, 1.0})
    |> Tincture.set_line_width(2.5)
    |> Tincture.circle(610, 430, 64)
    |> Tincture.stroke()
    |> Tincture.circle(610, 430, 44)
    |> Tincture.stroke()
    |> Tincture.set_fill_color({0.25, 0.8, 0.82})
    |> Tincture.move_to(610, 486)
    |> Tincture.line_to(632, 430)
    |> Tincture.line_to(610, 374)
    |> Tincture.line_to(588, 430)
    |> Tincture.fill()
    |> Tincture.set_stroke_color({0.96, 0.74, 0.16})
    |> Tincture.set_line_width(3)
    |> Tincture.line(56, 286, 736, 286)
    |> Tincture.restore_state()
  end

  defp write_test_qr_png! do
    path =
      Path.join(
        System.tmp_dir!(),
        "tincture_marketing_qr_#{System.unique_integer([:positive])}.png"
      )

    :ok = File.write(path, test_qr_png_binary())
    path
  end

  defp test_qr_png_binary do
    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = <<2::32-big, 2::32-big, 8, 2, 0, 0, 0>>
    # Scanline filter bytes + pixel RGB bytes for a 2x2 checkerboard.
    idat = :zlib.compress(<<0, 0, 0, 0, 255, 255, 255, 0, 255, 255, 255, 255, 0, 0>>)

    signature <>
      png_chunk("IHDR", ihdr) <>
      png_chunk("IDAT", idat) <>
      png_chunk("IEND", "")
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32([type, data])
    <<byte_size(data)::32-big, type::binary-size(4), data::binary, crc::32-big>>
  end
end

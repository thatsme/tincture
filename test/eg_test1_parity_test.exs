defmodule Tincture.EgTest1ParityTest do
  use ExUnit.Case

  test "eg1-style comprehensive feature fixture exports structurally consistent pdf" do
    jpg_path = write_test_jpeg!()
    png_path = write_test_png!()

    pdf =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Tincture.set_metadata(
        title: "EG Test 1",
        author: "Tincture",
        subject: "Comprehensive parity fixture",
        keywords: "eg_test1,parity"
      )
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_at(50, 740, "EG Test 1")
      |> Tincture.text_at_rotated(300, 700, 30, "Rotated")
      |> Tincture.set_stroke_color({0.1, 0.2, 0.8})
      |> Tincture.set_fill_color({0.9, 0.2, 0.2})
      |> Tincture.set_line_width(2)
      |> Tincture.set_line_cap(1)
      |> Tincture.set_line_join(2)
      |> Tincture.set_dash([6, 3], 0)
      |> Tincture.set_miter_limit(7.5)
      |> Tincture.line(50, 720, 260, 720)
      |> Tincture.rectangle(50, 640, 120, 60)
      |> Tincture.circle(240, 670, 24)
      |> Tincture.move_to(320, 680)
      |> Tincture.line_to(380, 680)
      |> Tincture.line_to(350, 630)
      |> Tincture.fill_even_odd()
      |> Tincture.move_to(410, 680)
      |> Tincture.line_to(470, 680)
      |> Tincture.line_to(440, 630)
      |> Tincture.clip_even_odd()
      |> Tincture.image_jpeg(50, 560, 64, 48, jpg_path)
      |> Tincture.image_png(130, 560, 48, 48, png_path)
      |> Tincture.add_page()
      |> Tincture.set_font("Times-Roman", 11)
      |> Tincture.text_at(50, 740, "Page 2 body")
      |> Tincture.add_bookmark("EG1 Start", 1)
      |> Tincture.add_bookmark("EG1 Page 2", 2)
      |> Tincture.set_page(1)
      |> Tincture.text_at(50, 520, "Back on page 1")

    pdf_binary = Tincture.export(pdf)

    assert String.starts_with?(pdf_binary, "%PDF-1.4")
    assert pdf_binary =~ "/Type /Catalog"
    assert pdf_binary =~ "/Type /Pages"
    assert pdf_binary =~ "/Count 2"
    assert pdf_binary =~ "/Type /Outlines"
    assert pdf_binary =~ "/Info "
    assert pdf_binary =~ "/Title (EG Test 1)"
    assert pdf_binary =~ "/Author (Tincture)"
    assert pdf_binary =~ "/Dest [3 0 R /Fit]"
    assert pdf_binary =~ "/Dest [5 0 R /Fit]"
    assert pdf_binary =~ "/BaseFont /Helvetica"
    assert pdf_binary =~ "/BaseFont /Times-Roman"
    assert pdf_binary =~ "f*\n"
    assert pdf_binary =~ "W*\nn\n"
    assert pdf_binary =~ "7.5 M\n"
    assert pdf_binary =~ "/Filter /DCTDecode"
    assert pdf_binary =~ "/Filter /FlateDecode"

    assert_structural_pdf_consistency(pdf_binary)

    File.rm(jpg_path)
    File.rm(png_path)
  end

  defp assert_structural_pdf_consistency(pdf_binary) do
    assert [_, xref_size_raw] = Regex.run(~r/xref\n0 (\d+)\n/, pdf_binary)
    assert [_, trailer_size_raw] = Regex.run(~r/trailer\n<< \/Size (\d+)/, pdf_binary)
    assert [_, startxref_raw] = Regex.run(~r/startxref\n(\d+)\n%%EOF\n$/, pdf_binary)

    xref_size = String.to_integer(xref_size_raw)
    trailer_size = String.to_integer(trailer_size_raw)
    startxref = String.to_integer(startxref_raw)
    object_count = length(Regex.scan(~r/\n\d+ 0 obj\n/, pdf_binary))

    assert xref_size == trailer_size
    assert object_count == xref_size - 1

    assert binary_part(pdf_binary, startxref, 5) == "xref\n"
  end

  defp write_test_jpeg! do
    path = Path.join(System.tmp_dir!(), "tincture_eg1_#{System.unique_integer([:positive])}.jpg")
    :ok = File.write(path, test_jpeg_binary())
    path
  end

  defp test_jpeg_binary do
    <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00,
      0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01, 0x00, 0x01, 0x03,
      0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01,
      0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00, 0x00, 0xFF, 0xD9>>
  end

  defp write_test_png! do
    path = Path.join(System.tmp_dir!(), "tincture_eg1_#{System.unique_integer([:positive])}.png")
    :ok = File.write(path, test_png_binary())
    path
  end

  defp test_png_binary do
    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = <<1::32-big, 1::32-big, 8, 6, 0, 0, 0>>
    idat = :zlib.compress(<<0, 255, 0, 0, 128>>)

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

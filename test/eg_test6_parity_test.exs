defmodule Tincture.EgTest6ParityTest do
  use ExUnit.Case

  test "eg_test6-style pipeline exports expected minimal PDF primitives" do
    pdf_binary =
      Tincture.new()
      |> Tincture.page_size(:a4)
      |> Tincture.set_font("Helvetica", 14)
      |> Tincture.text_at(50, 700, "Hello Joe from Gutenberg")
      |> Tincture.export()

    assert String.starts_with?(pdf_binary, "%PDF-1.4")
    assert pdf_binary =~ "/MediaBox [0 0 595 842]"
    assert pdf_binary =~ "/BaseFont /Helvetica"
    assert pdf_binary =~ "/F1 14 Tf\n50 700 Td\n(Hello Joe from Gutenberg) Tj\n"
    assert pdf_binary =~ "xref\n0 5\n"
    assert String.ends_with?(pdf_binary, "%%EOF\n")
  end

  test "save/2 writes exported PDF to disk" do
    pdf =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Tincture.set_font("Times-Roman", 12)
      |> Tincture.text_at(50, 720, "saved from Tincture")

    path = Path.join(System.tmp_dir!(), "tincture_eg_test6_parity.pdf")

    assert :ok = Tincture.save(pdf, path)
    assert File.exists?(path)
    assert File.stat!(path).size > 0
  end
end

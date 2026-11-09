defmodule Tincture.PDFObjectsDecodingTest do
  @moduledoc """
  The decoding helper in `Tincture.Test.PDFObjects`: tests read a document's
  streams through it, so that they read what a viewer reads whether or not the
  streams are compressed.

  Its guarantees, each tested here:

  1. stream data is located by `/Length`, never by searching for `endstream`;
  2. a Flate stream that does not inflate, or leaves bytes over, raises, and so
     does any filter it has no decoder for, except `DCTDecode`, which passes
     through;
  3. image data is decoded only when asked.

  A fourth, the complement - in a compressed export every stream but the XMP
  metadata carries a `/Filter`, and the unfiltered streams are exactly the XMP -
  cannot pass before Tincture compresses its streams. It lands with the
  compression itself.
  """
  use ExUnit.Case, async: true

  alias Tincture.Test.PDFObjects

  # A file of the given objects, numbered from 1, with a correct xref table.
  # Each object is its body as written, after "N 0 obj\n".
  defp pdf(bodies) do
    header = "%PDF-1.4\n"

    {objects, xref_at} =
      bodies
      |> Enum.with_index(1)
      |> Enum.map_reduce(byte_size(header), fn {body, number}, at ->
        object = "#{number} 0 obj\n#{body}\nendobj\n"
        {{object, at}, at + byte_size(object)}
      end)

    entries =
      Enum.map(objects, fn {_object, at} ->
        String.pad_leading("#{at}", 10, "0") <> " 00000 n \n"
      end)

    IO.iodata_to_binary([
      header,
      Enum.map(objects, &elem(&1, 0)),
      "xref\n0 #{length(bodies) + 1}\n0000000000 65535 f \n",
      entries,
      "trailer\n<< /Size #{length(bodies) + 1} /Root 1 0 R >>\nstartxref\n#{xref_at}\n%%EOF\n"
    ])
  end

  defp stream(dictionary, data),
    do: "<< #{dictionary} /Length #{byte_size(data)} >>\nstream\n" <> data <> "\nendstream"

  # Flate data whose last byte is a line feed: deflate output is arbitrary
  # bytes, and its Adler-32 checksum is its last four.
  defp flate_ending_in_lf do
    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(&:zlib.compress("BT /F1 12 Tf (#{&1}) Tj ET"))
    |> Enum.find(&String.ends_with?(&1, "\n"))
  end

  test "a Flate stream decodes to its data" do
    file =
      pdf([
        "<< /Type /Catalog >>",
        stream("/Filter /FlateDecode", :zlib.compress("0 0 m 10 10 l S"))
      ])

    assert PDFObjects.stream!(file, 2) == "0 0 m 10 10 l S"
    assert PDFObjects.decoded(file) =~ "stream\n0 0 m 10 10 l S\nendstream"
  end

  test "an unfiltered stream is its bytes, and /Length may be a reference" do
    file =
      pdf([
        "<< /Type /Catalog >>",
        "<< /Length 3 0 R >>\nstream\nq Q\nendstream",
        "3"
      ])

    assert PDFObjects.stream!(file, 2) == "q Q"
  end

  test "a stream is located by /Length, so data ending in LF or holding endstream reads whole" do
    data = flate_ending_in_lf()
    assert String.ends_with?(data, "\n")

    file = pdf(["<< /Type /Catalog >>", stream("/Filter /FlateDecode", data)])
    assert :zlib.uncompress(data) == PDFObjects.stream!(file, 2)

    trap = "a\nendstream\nb"
    file = pdf(["<< /Type /Catalog >>", stream("", trap)])
    assert PDFObjects.stream!(file, 2) == trap
  end

  test "a /Length that does not end at an end-of-line and endstream raises" do
    file = pdf(["<< /Type /Catalog >>", "<< /Length 2 >>\nstream\nq Q\nendstream"])

    assert_raise ArgumentError, ~r/not an end-of-line marker and endstream/, fn ->
      PDFObjects.stream!(file, 2)
    end
  end

  test "a corrupt Flate stream raises" do
    good = :zlib.compress("0 0 m 10 10 l S")

    for {label, data} <- [
          garbage: "not zlib data",
          truncated: binary_part(good, 0, byte_size(good) - 2),
          bytes_left_over: good <> "x"
        ] do
      file = pdf(["<< /Type /Catalog >>", stream("/Filter /FlateDecode", data)])

      error = assert_raise ArgumentError, fn -> PDFObjects.stream!(file, 2) end
      assert error.message =~ ~r/does not inflate|left over/, "#{label}: #{error.message}"

      assert_raise ArgumentError, fn -> PDFObjects.decoded(file) end
    end
  end

  test "a filter with no decoder raises, alone or after Flate" do
    for filter <- ["/LZWDecode", "/ASCIIHexDecode", "[/FlateDecode /RunLengthDecode]"] do
      data = if filter =~ "Flate", do: :zlib.compress("x"), else: "78>"
      file = pdf(["<< /Type /Catalog >>", stream("/Filter #{filter}", data)])

      assert_raise ArgumentError, ~r/no decoder/, fn -> PDFObjects.stream!(file, 2) end
    end
  end

  test "DCTDecode passes through as written" do
    jpeg = <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16, "JFIF", 0, 0xFF, 0xD9>>
    file = pdf(["<< /Type /Catalog >>", stream("/Filter /DCTDecode", jpeg)])

    assert PDFObjects.stream!(file, 2) == jpeg
  end

  test "image data is decoded only when asked" do
    rows = <<0, 1, 2, 3, 0, 4, 5, 6>>
    data = :zlib.compress(rows)

    file =
      pdf([
        "<< /Type /Catalog >>",
        stream(
          "/Type /XObject /Subtype /Image /Width 1 /Height 2 /BitsPerComponent 8 " <>
            "/ColorSpace /DeviceRGB /Filter /FlateDecode " <>
            "/DecodeParms << /Predictor 15 /Colors 3 /Columns 1 >>",
          data
        )
      ])

    assert PDFObjects.stream!(file, 2) == data
    assert PDFObjects.stream!(file, 2, images: true) == rows
    assert PDFObjects.decoded(file) =~ data
  end

  test "an export's Flate CIDToGIDMap decodes, through the document's own xref" do
    path = Path.join([__DIR__, "..", "..", "examples", "fonts", "LiberationSans-Regular.ttf"])

    file =
      Tincture.new()
      |> Tincture.register_ttf_font("Sans", path)
      |> Tincture.set_font("Sans", 12)
      |> Tincture.text_at(72, 700, "Hi Ωμέγα")
      |> Tincture.export()

    [_, number] = Regex.run(~r|/CIDToGIDMap (\d+) 0 R|, file)
    number = String.to_integer(number)
    %{objects: objects} = PDFObjects.read(file)
    assert %{"Filter" => {:name, "FlateDecode"}} = objects[number].value

    map = PDFObjects.stream!(file, number)
    assert rem(byte_size(map), 2) == 0
    assert PDFObjects.decoded(file) =~ map
  end
end

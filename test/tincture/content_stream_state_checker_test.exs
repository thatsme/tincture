defmodule Tincture.ContentStreamStateCheckerTest do
  use ExUnit.Case, async: true

  alias Tincture.Test.ContentStreamState

  # The checker is only as good as these cases: each negative one is a defect
  # it exists to catch, each positive one a construct it must not mistake for
  # one.

  defp operators(stream) do
    stream |> ContentStreamState.check_stream() |> Enum.map(&{&1.operator, &1.state})
  end

  describe "flags" do
    test "a painting operator with no path open" do
      assert operators("56 716 m 539 716 l S\nS\n") == [{"S", :page}]
    end

    test "path construction inside a text object" do
      assert operators("BT /F1 12 Tf 10 10 m ET") == [{"m", :text}]
    end

    test "q inside a text object" do
      assert operators("BT /F1 12 Tf q ET") == [{"q", :text}]
    end

    test "marked content between path construction and painting" do
      assert operators("10 10 m /Span << /MCID 0 >> BDC 20 20 l S EMC") == [{"BDC", :path}]
    end

    test "a clip followed by anything but a painting operator" do
      assert operators("0 0 10 10 re W 1 0 0 1 0 0 cm n") == [{"cm", :clip}]
    end

    test "a stream that ends inside a text object" do
      assert operators("BT /F1 12 Tf (open) Tj") == [{"<end of stream>", :text}]
    end

    test "an EMC with no marked content open" do
      assert operators("/P <</MCID 0>> BDC EMC EMC") == [{"EMC (no marked content open)", :page}]
    end

    test "a stream that ends with marked content open" do
      assert operators("/P <</MCID 0>> BDC /Artifact BMC EMC") ==
               [{"<end of stream, 1 marked-content sequence(s) open>", :page}]
    end

    test "both halves of a sequence split across two streams" do
      assert operators("/Figure <</MCID 0>> BDC 0 0 10 10 re f") ==
               [{"<end of stream, 1 marked-content sequence(s) open>", :page}]

      assert operators("0 0 10 10 re f EMC") == [{"EMC (no marked content open)", :page}]
    end

    test "an operator outside Figure 9" do
      assert operators("BX 0 0 d0 EX") == [{"BX", :page}, {"d0", :page}, {"EX", :page}]
    end
  end

  describe "accepts" do
    test "a rectangle clip ended by n" do
      assert operators("q 0 0 100 100 re W n 0 0 50 50 re f Q") == []
    end

    test "an inline image whose data contains S and EI" do
      # Four bytes of 8-bit grey: `S`, a space, `E`, `I`. A scan for the first
      # whitespace-delimited EI would end the image one byte early and read a
      # stray `I`; the dictionary gives the exact length.
      stream = "q 4 0 0 1 0 0 cm BI /W 4 /H 1 /CS /G /BPC 8 ID S EI EI Q"
      assert operators(stream) == []
    end

    test "an inline image is placed only at page level" do
      assert operators("BT BI /W 1 /H 1 /CS /G /BPC 8 ID x EI ET") == [{"BI", :text}]
    end

    test "marked content with an inline dictionary operand" do
      stream = "/P << /MCID 0 /Lang (en-GB) >> BDC BT /F1 12 Tf 10 10 Td (Hi) Tj ET EMC"
      assert operators(stream) == []
    end

    test "strings that contain operator names, escapes and nested parentheses" do
      stream = ~S"BT /F1 12 Tf (a \) S (nested S) ET) Tj <53> Tj [(S) -20 (ET)] TJ ET"
      assert operators(stream) == []
    end

    test "nested and sequential marked content that closes in the stream" do
      stream =
        "/Document <</MCID 0>> BDC /Span <</MCID 1>> BDC EMC /Artifact BMC EMC EMC " <>
          "/P <</MCID 2>> BDC BT /F1 12 Tf (x) Tj ET EMC"

      assert operators(stream) == []
    end

    test "comments" do
      assert operators("% S\n0 0 m 1 1 l S % trailing S\n") == []
    end
  end

  describe "reports" do
    test "object, byte offset, operator, state and the eight preceding operators" do
      stream = "q Q q Q 1 w 0 J 0 j 4 M 0 g 0 G S"

      assert [violation] = ContentStreamState.check_stream(stream, object: 7, base_offset: 100)

      assert violation == %{
               object: 7,
               offset: 100 + byte_size(stream) - 1,
               operator: "S",
               state: :page,
               preceding: ~w(q Q w J j M g G)
             }

      assert ContentStreamState.format_violation(violation) ==
               "object 7, byte #{100 + byte_size(stream) - 1}: `S` in state page " <>
                 "(preceded by: q Q w J j M g G)"
    end
  end

  describe "check_pdf/1" do
    # Tincture no longer writes a painting operator with no path open, so the
    # double S is written by hand here.
    test "finds a double S at its place in the file" do
      pdf =
        hand_written_pdf([
          "<< /Type /Catalog /Pages 2 0 R >>",
          "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R >>",
          stream_object("", "56 716 m\n539 716 l\nS\nS\n")
        ])

      assert %{streams: 1, violations: [violation]} = ContentStreamState.check_pdf(pdf)
      assert violation.operator == "S"
      assert violation.object == 4
      assert binary_part(pdf, violation.offset - 2, 3) == "S\nS"
    end

    test "a document with a single painting operator per path is clean" do
      pdf = Tincture.new() |> Tincture.line(56, 716, 539, 716) |> Tincture.export()
      assert %{streams: 1, violations: []} = ContentStreamState.check_pdf(pdf)
    end

    test "checks form XObjects as well as page contents" do
      pdf =
        hand_written_pdf([
          "<< /Type /Catalog /Pages 2 0 R >>",
          "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Contents 4 0 R >>",
          stream_object("", "0 0 m 1 1 l S"),
          stream_object(" /Type /XObject /Subtype /Form /BBox [0 0 1 1]", "S")
        ])

      assert %{streams: 2, violations: [%{object: 5, operator: "S"}]} =
               ContentStreamState.check_pdf(pdf)
    end

    test "refuses a filtered stream it has to read, naming the object" do
      pdf =
        hand_written_pdf([
          "<< /Type /Catalog /Pages 2 0 R >>",
          "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Contents [4 0 R] >>",
          stream_object(" /Filter /FlateDecode", "x")
        ])

      assert_raise ArgumentError, ~r/object 4 carries \/Filter/, fn ->
        ContentStreamState.check_pdf(pdf)
      end
    end

    test "refuses an encrypted document" do
      pdf =
        Tincture.new() |> Tincture.text_at(10, 10, "x") |> Tincture.encrypt() |> Tincture.export()

      assert_raise ArgumentError, ~r/encrypted/, fn -> ContentStreamState.check_pdf(pdf) end
    end
  end

  defp stream_object(entries, data),
    do: "<<#{entries} /Length #{byte_size(data)} >>\nstream\n#{data}\nendstream"

  defp hand_written_pdf(bodies) do
    header = "%PDF-1.7\n"

    {objects, xref_offset} =
      bodies
      |> Enum.with_index(1)
      |> Enum.map_reduce(byte_size(header), fn {body, number}, offset ->
        object = "#{number} 0 obj\n#{body}\nendobj\n"
        {{object, offset}, offset + byte_size(object)}
      end)

    entries =
      Enum.map(objects, fn {_object, start} ->
        String.pad_leading(Integer.to_string(start), 10, "0") <> " 00000 n \n"
      end)

    IO.iodata_to_binary([
      header,
      Enum.map(objects, &elem(&1, 0)),
      "xref\n0 #{length(bodies) + 1}\n0000000000 65535 f \n",
      entries,
      "trailer\n<< /Size #{length(bodies) + 1} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"
    ])
  end
end

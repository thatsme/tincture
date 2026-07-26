defmodule Tincture.PDFATest do
  @moduledoc """
  Tests for PDF/A support — what a document needs to outlive its software.

  PDF/A is mostly constraints rather than capability: everything required to
  render the file has to be inside the file. The three things a document cannot
  be valid without are an output intent giving device colour a defined meaning,
  XMP carrying the conformance claim, and a file identifier.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF.ICC
  alias Tincture.Test.MeasurableFont

  defp export(pdf), do: Tincture.export(pdf)

  defp archival_pdf(level \\ :a2b) do
    Tincture.new()
    |> Tincture.set_metadata(title: "Retained record")
    |> Tincture.set_pdf_a(level)
    |> Tincture.set_font("Helvetica", 12)
    |> Tincture.text_at(50, 700, "Kept for a long time.")
  end

  describe "set_pdf_a/2" do
    test "records the part and conformance level" do
      assert Tincture.new() |> Tincture.set_pdf_a(:a2b) |> Map.fetch!(:pdf_a) == {2, :b}
      assert Tincture.new() |> Tincture.set_pdf_a(:a2u) |> Map.fetch!(:pdf_a) == {2, :u}
      assert Tincture.new() |> Tincture.set_pdf_a(:a2a) |> Map.fetch!(:pdf_a) == {2, :a}
      assert Tincture.new() |> Tincture.set_pdf_a(:a3b) |> Map.fetch!(:pdf_a) == {3, :b}
    end

    test "rejects an unknown level, listing the ones it knows" do
      error = assert_raise ArgumentError, fn -> Tincture.set_pdf_a(Tincture.new(), :a4z) end

      assert error.message =~ "unknown PDF/A level: :a4z"
      assert error.message =~ ":a2b"
    end
  end

  describe "the output intent" do
    test "names sRGB and references an embedded profile" do
      binary = export(archival_pdf())

      assert binary =~ "/OutputIntents [<< /Type /OutputIntent /S /GTS_PDFA1"
      assert binary =~ "/OutputConditionIdentifier (sRGB IEC61966-2.1)"
      assert binary =~ ~r|/DestOutputProfile \d+ 0 R|
    end

    test "embeds the ICC profile itself, with its component count" do
      binary = export(archival_pdf())

      assert binary =~ "/N 3 /Length #{byte_size(ICC.srgb())}"
      assert String.contains?(binary, ICC.srgb())
    end

    test "is absent from a document not claiming PDF/A" do
      binary = Tincture.new() |> Tincture.text_at(10, 10, "ordinary") |> export()

      refute binary =~ "/OutputIntents"
      refute binary =~ "/DestOutputProfile"
    end
  end

  describe "the XMP identification" do
    test "states the part and conformance" do
      binary = export(archival_pdf(:a2u))

      assert binary =~ "<pdfaid:part>2</pdfaid:part>"
      assert binary =~ "<pdfaid:conformance>U</pdfaid:conformance>"
    end

    test "reports part 3 as part 3" do
      assert export(archival_pdf(:a3b)) =~ "<pdfaid:part>3</pdfaid:part>"
    end

    test "is absent unless PDF/A is claimed" do
      binary = Tincture.new() |> Tincture.set_metadata(title: "x") |> export()

      assert binary =~ "/Type /Metadata"
      refute binary =~ "pdfaid"
    end

    test "a document claiming both PDF/A and PDF/UA describes the pdfuaid schema" do
      # PDF/A allows only predefined XMP schemas unless the file describes the
      # rest itself, and pdfuaid is not predefined — so without this the very
      # property asserting accessibility would invalidate the archival claim.
      binary =
        Tincture.new()
        |> Tincture.set_pdf_a(:a2a)
        |> Tincture.set_language("en-GB")
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:p, &Tincture.text_at(&1, 10, 10, "tagged"))
        |> export()

      assert binary =~ "pdfaExtension:schemas"
      assert binary =~ "<pdfaSchema:prefix>pdfuaid</pdfaSchema:prefix>"
      assert binary =~ "<pdfaProperty:name>part</pdfaProperty:name>"
    end

    test "a tagged document not claiming PDF/A needs no extension schema" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:p, &Tincture.text_at(&1, 10, 10, "tagged"))
        |> export()

      assert binary =~ "pdfuaid:part"
      refute binary =~ "pdfaExtension"
    end
  end

  describe "the file identifier" do
    test "is present on every document, not only encrypted ones" do
      assert export(archival_pdf()) =~ ~r|/ID \[<[0-9A-F]{32}> <[0-9A-F]{32}>\]|
      assert Tincture.new() |> Tincture.text_at(10, 10, "x") |> export() =~ "/ID [<"
    end

    test "is derived from the content, so a rebuild produces the same file" do
      # An archived document has to be checkable against a rebuild, which a
      # clock-derived identifier would make impossible.
      first = export(archival_pdf())
      second = export(archival_pdf())

      assert first == second
    end

    test "differs when the content differs" do
      other =
        Tincture.new()
        |> Tincture.set_metadata(title: "Retained record")
        |> Tincture.set_pdf_a(:a2b)
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_at(50, 700, "Different text.")
        |> export()

      assert extract_id(export(archival_pdf())) != extract_id(other)
    end

    defp extract_id(binary) do
      [_, id] = Regex.run(~r|/ID \[<([0-9A-F]+)>|, binary)
      id
    end
  end

  describe "stream lengths" do
    test "declared length matches the bytes actually written" do
      # The EOL before `endstream` is a delimiter rather than data. A stream
      # whose own last byte is a newline needs one of each, or /Length
      # overstates the content by one and ISO 19005-2 clause 6.1.7.1 fails.
      path = MeasurableFont.write!()
      on_exit(fn -> File.rm(path) end)

      binary =
        Tincture.new()
        |> Tincture.register_ttf_font("Probe", path)
        |> Tincture.set_font("Probe", 10)
        |> Tincture.text_at(50, 700, "AB BA")
        |> export()

      for [_, declared, data] <-
            Regex.scan(~r/<< [^>]*\/Length (\d+)[^>]*>>\nstream\n(.*?)\nendstream/s, binary) do
        assert byte_size(data) == String.to_integer(declared)
      end
    end

    test "at least one stream is checked, so the test above cannot pass vacuously" do
      binary = export(archival_pdf())

      matches = Regex.scan(~r/<< [^>]*\/Length (\d+)[^>]*>>\nstream\n(.*?)\nendstream/s, binary)

      refute matches == []
    end
  end

  describe "the built-in sRGB profile" do
    test "declares its own size correctly" do
      profile = ICC.srgb()
      <<size::32-big, _rest::binary>> = profile

      assert size == byte_size(profile)
    end

    test "is an RGB display profile in the XYZ connection space" do
      <<_size::32-big, _cmm::32, _version::32, class::binary-size(4), space::binary-size(4),
        pcs::binary-size(4), _rest::binary>> = ICC.srgb()

      assert class == "mntr"
      assert space == "RGB "
      assert pcs == "XYZ "
    end

    test "carries the required signature" do
      <<_::binary-size(36), signature::binary-size(4), _rest::binary>> = ICC.srgb()

      assert signature == "acsp"
    end

    test "every tag lies within the profile" do
      profile = ICC.srgb()
      <<_::binary-size(128), count::32-big, table::binary>> = profile

      assert count == 9

      for index <- 0..(count - 1) do
        skip = index * 12

        <<_::binary-size(skip), signature::binary-size(4), offset::32-big, size::32-big,
          _rest::binary>> = table

        assert offset + size <= byte_size(profile),
               "tag #{signature} runs past the end of the profile"
      end
    end

    test "the tone curve is the real sRGB transfer function, not gamma 2.2" do
      profile = ICC.srgb()

      # Locate the shared curve tag and read its samples back.
      <<_::binary-size(128), _count::32-big, table::binary>> = profile
      {offset, size} = tag_location(table, "rTRC")

      <<_::binary-size(offset), "curv", _reserved::32, samples::32-big, data::binary>> = profile
      # signature, reserved and count are 12 bytes, then one uint16 per sample.
      assert size == 12 + samples * 2

      value_at = fn index ->
        <<_::binary-size(index)-unit(16), value::16-big, _rest::binary>> = data
        value / 65_535
      end

      # Endpoints are exact.
      assert value_at.(0) == 0.0
      assert_in_delta value_at.(samples - 1), 1.0, 0.0001

      # sRGB is linear below 0.04045, where a 2.2 gamma curve is markedly
      # darker. At input 0.02 the true curve gives ~0.00155 and gamma 2.2
      # gives ~0.00019 - an order of magnitude apart.
      index = round(0.02 * (samples - 1))
      assert_in_delta value_at.(index), 0.02 / 12.92, 0.0002
      refute_in_delta value_at.(index), :math.pow(0.02, 2.2), 0.0002
    end

    defp tag_location(table, wanted) do
      Enum.find_value(0..8, fn index ->
        skip = index * 12

        <<_::binary-size(skip), signature::binary-size(4), offset::32-big, size::32-big,
          _rest::binary>> = table

        if signature == wanted, do: {offset, size}
      end)
    end

    test "is deterministic, carrying no creation date" do
      assert ICC.srgb() == ICC.srgb()
    end
  end
end

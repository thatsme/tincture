defmodule Tincture.CompressionTest do
  @moduledoc """
  Which streams are compressed, read from the file as written.

  Every stream Tincture writes is Flate-compressed, except the XMP metadata,
  which stays plain text so that tools that are not PDF-aware can read it (ISO
  32000-1 14.3.2, NOTE 2). Image data and the CIDToGIDMap carry their own
  filters, compressed or not.

  The tests assert the complement: they list the streams that carry no filter,
  and require that list to be exactly the XMP. A writer that escapes
  compression is then a failure, where a test that looked for `/FlateDecode`
  on the streams it knows about could not see it.
  """
  use ExUnit.Case, async: true

  alias Tincture.Test.PDFObjects

  @moduletag :tmp_dir

  @sans "examples/fonts/LiberationSans-Regular.ttf"
  @serif "examples/fonts/LiberationSerif-Regular.ttf"

  # Every kind of stream section A of the design lists, in one document or
  # the other.
  @kinds [
    :page_content,
    :form_xobject,
    :appearance,
    :font_file2,
    :font_file3,
    :to_unicode,
    :cid_to_gid_map,
    :icc_profile,
    :jpeg,
    :png,
    :soft_mask,
    :xmp
  ]

  describe "the default export" do
    test "every stream but the XMP has a filter, and the unfiltered list is exactly [XMP]",
         %{tmp_dir: dir} do
      streams = all_streams(dir, [])

      assert streams |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort() == Enum.sort(@kinds)
      assert streams |> Enum.reject(& &1.filter) |> Enum.map(& &1.kind) == [:xmp]
    end

    test "the streams compression adds a filter to are Flate, with no parameters",
         %{tmp_dir: dir} do
      for stream <- all_streams(dir, []), stream.kind in compressed_kinds() do
        assert stream.filter == {:name, "FlateDecode"},
               "#{stream.kind}: #{inspect(stream.filter)}"

        refute Map.has_key?(stream.dictionary, "DecodeParms"), "#{stream.kind} has /DecodeParms"
      end
    end

    test "the XMP is readable as plain text in the file as written" do
      binary =
        Tincture.new()
        |> Tincture.set_metadata(title: "Plain metadata")
        |> Tincture.text_at(72, 700, "x")
        |> Tincture.export()

      assert binary =~ "<x:xmpmeta"
      assert binary =~ "Plain metadata"
      refute binary =~ "BT\n"
    end
  end

  describe "compress: false" do
    test "only the CIDToGIDMap and the images carry a filter, as before compression",
         %{tmp_dir: dir} do
      filtered =
        dir
        |> all_streams(compress: false)
        |> Enum.filter(& &1.filter)
        |> Enum.map(& &1.kind)
        |> Enum.uniq()
        |> Enum.sort()

      assert filtered == Enum.sort([:cid_to_gid_map, :jpeg, :png, :soft_mask])
    end

    test "decodes to the same stream data as the default export", %{tmp_dir: dir} do
      for {pdf, otf?} <- documents(dir) do
        compressed = export(pdf, [])
        plain = export(pdf, compress: false)

        assert decoded_streams(compressed) == decoded_streams(plain),
               "the #{if otf?, do: "OpenType", else: "main"} document"
      end
    end

    test "compress: true is the default" do
      pdf = Tincture.text_at(Tincture.new(), 72, 700, "x")
      assert Tincture.export(pdf, compress: true) == Tincture.export(pdf)
    end

    test "any other value raises" do
      pdf = Tincture.text_at(Tincture.new(), 72, 700, "x")

      error = assert_raise ArgumentError, fn -> Tincture.export(pdf, compress: :yes) end
      assert error.message =~ "expects :compress to be true or false, got: :yes"
    end
  end

  describe "/Length1" do
    # ISO 32000-1 Table 127: the program's size after decoding. No veraPDF
    # rule checks it, so nothing else would notice it wrong.
    test "is the decoded size of every font program, subset or whole", %{tmp_dir: dir} do
      for {pdf, _otf?} <- documents(dir), opts <- [[], [compress: false]] do
        binary = export(pdf, opts)

        programs =
          for stream <- streams(binary), stream.kind in [:font_file2, :font_file3] do
            decoded = PDFObjects.stream!(binary, stream.number)
            assert stream.dictionary["Length1"] == byte_size(decoded)
            stream
          end

        assert programs != []
      end
    end
  end

  describe "telemetry" do
    test "a page's :byte_size is its content stream's /Length, compressed or not" do
      pdf = Tincture.text_at(Tincture.new(), 72, 700, "Measured")
      handler = "compression-test-#{inspect(self())}"
      :telemetry.attach(handler, [:tincture, :page, :stop], &__MODULE__.page_stop/4, self())

      try do
        for opts <- [[], [compress: false]] do
          binary = Tincture.export(pdf, opts)
          assert_received {:page, byte_size}

          [content] = for stream <- streams(binary), stream.kind == :page_content, do: stream
          assert content.dictionary["Length"] == byte_size
        end
      after
        :telemetry.detach(handler)
      end
    end
  end

  # A handler runs in the process that exports, and handlers are global, so
  # a page another test exports concurrently is ignored.
  @doc false
  def page_stop(_event, measurements, _metadata, test) do
    if self() == test, do: send(test, {:page, measurements.byte_size})
  end

  defp compressed_kinds,
    do: @kinds -- [:xmp, :cid_to_gid_map, :jpeg, :png, :soft_mask]

  # The main document has every kind but FontFile3: a page with text in an
  # embedded font, drawn as a Type0 font (Greek) and as a simple one (Latin),
  # a placed form XObject, a widget of each kind with an appearance, a JPEG,
  # a PNG with transparency, PDF/A's ICC profile and the XMP. No OpenType
  # (CFF) font is available to the suite, so the second document relabels an
  # embedded TrueType font as OpenType: what reaches the FontFile3 writer is
  # a TrueType program, which is enough to read the stream it writes.
  defp documents(dir) do
    main =
      Tincture.new()
      |> Tincture.set_metadata(title: "Every stream")
      |> Tincture.set_pdf_a(:a2b)
      |> Tincture.register_ttf_font("Sans", @sans)
      |> Tincture.register_ttf_font("Serif", @serif)
      |> Tincture.set_font("Sans", 14)
      |> Tincture.text_at(72, 760, "Ελλάδα")
      |> Tincture.set_font("Serif", 12)
      |> Tincture.text_at(72, 740, "Latin")
      |> Tincture.form_xobject("stamp", 120, 40, fn pdf ->
        pdf |> Tincture.set_font("Helvetica", 10) |> Tincture.text_at(6, 15, "Approved")
      end)
      |> Tincture.place_form_xobject("stamp", 72, 690)
      |> Tincture.image_jpeg(72, 600, 40, 40, jpeg!(dir))
      |> Tincture.image_png(130, 600, 40, 40, png!(dir))
      |> Tincture.text_field(72, 540, 200, 20, "name", value: "Ada")
      |> Tincture.choice_field(72, 510, 200, 20, "currency", options: ["GBP", "EUR"])
      |> Tincture.checkbox(72, 480, 12, "agree", value: true)
      |> Tincture.radio_group("contact", [
        [value: "email", x: 72, y: 450, size: 12],
        [value: "post", x: 92, y: 450, size: 12]
      ])
      |> Tincture.push_button(72, 410, 90, 24, "reset", label: "Reset", action: :reset)

    otf =
      Tincture.new()
      |> Tincture.register_ttf_font("Open", @sans)
      |> then(&update_in(&1.embedded_fonts["Open"], fn font -> Map.put(font, :format, :otf) end))
      |> Tincture.set_font("Open", 12)
      |> Tincture.text_at(72, 700, "OpenType")

    [{main, false}, {otf, true}]
  end

  defp all_streams(dir, opts),
    do: Enum.flat_map(documents(dir), fn {pdf, _otf?} -> pdf |> export(opts) |> streams() end)

  # enforce: false, since the documents claim PDF/A for its ICC profile
  # without the structure the claim needs; the streams are what is read.
  defp export(pdf, opts) do
    ExUnit.CaptureLog.capture_log(fn ->
      send(self(), Tincture.export(pdf, [enforce: false] ++ opts))
    end)

    receive do
      binary when is_binary(binary) -> binary
    end
  end

  defp decoded_streams(binary) do
    for stream <- streams(binary), into: %{} do
      {stream.number, PDFObjects.stream!(binary, stream.number, images: false)}
    end
  end

  # Every stream in the file: its object number, its dictionary, its /Filter
  # (nil when it has none), and its kind, from what refers to it.
  defp streams(binary) do
    %{objects: objects} = PDFObjects.read(binary)
    referrers = referrers(objects)

    for {number, %{stream_at: at, value: dictionary}} <- objects, at != nil do
      %{
        number: number,
        dictionary: dictionary,
        filter: Map.get(dictionary, "Filter"),
        kind: kind(dictionary, Map.get(referrers, number, []))
      }
    end
  end

  defp kind(%{"Type" => {:name, "Metadata"}}, _keys), do: :xmp

  defp kind(dictionary, keys) do
    cond do
      "Contents" in keys -> :page_content
      "FontFile2" in keys -> :font_file2
      "FontFile3" in keys -> :font_file3
      "ToUnicode" in keys -> :to_unicode
      "CIDToGIDMap" in keys -> :cid_to_gid_map
      "DestOutputProfile" in keys -> :icc_profile
      "SMask" in keys -> :soft_mask
      dictionary["Filter"] == {:name, "DCTDecode"} -> :jpeg
      dictionary["Subtype"] == {:name, "Image"} -> :png
      Enum.any?(keys, &(&1 =~ ~r/^Fm\d+$/)) -> :form_xobject
      dictionary["Subtype"] == {:name, "Form"} -> :appearance
      true -> {:unknown, keys}
    end
  end

  # For each object number, every dictionary key a reference to it is found
  # under, anywhere in the file.
  defp referrers(objects) do
    objects
    |> Enum.flat_map(fn {_number, %{value: value}} -> references(value, nil) end)
    |> Enum.group_by(fn {number, _key} -> number end, fn {_number, key} -> key end)
  end

  defp references({:ref, number}, key), do: [{number, key}]

  defp references(map, _key) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> references(value, key) end)

  defp references(list, key) when is_list(list), do: Enum.flat_map(list, &references(&1, key))
  defp references(_value, _key), do: []

  # 2 x 2 RGBA, one pixel half transparent, so the image has a soft mask.
  defp png!(dir) do
    chunk = fn type, data ->
      <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
    end

    rows = <<0, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 0, 128, 255, 255, 255, 255>>
    path = Path.join(dir, "image.png")

    File.write!(
      path,
      <<137, 80, 78, 71, 13, 10, 26, 10>> <>
        chunk.("IHDR", <<2::32, 2::32, 8, 6, 0, 0, 0>>) <>
        chunk.("IDAT", :zlib.compress(rows)) <> chunk.("IEND", "")
    )

    path
  end

  # A 1 x 1 baseline JPEG header, enough for Tincture to embed it as written.
  defp jpeg!(dir) do
    path = Path.join(dir, "image.jpg")

    File.write!(
      path,
      <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01, 0x00, 0x01, 0x03,
        0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01,
        0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00, 0x00, 0xFF, 0xD9>>
    )

    path
  end
end

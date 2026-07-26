defmodule Tincture.PDF.ImageTest do
  @moduledoc """
  Direct tests for JPEG and PNG loading.

  This module is a full PNG decoder — four colour types, all five row filters,
  and alpha-channel splitting into a separate soft mask — plus a JPEG segment
  scanner. Until now it was only ever reached through `Tincture.image_png/6`
  with a couple of fixture files, so most of the filters and every malformed
  path went unexercised.

  Both entry points take a file path, so these tests write to a temp file and
  clean up. Images are built byte by byte rather than checked in, which keeps
  the failure cases (a truncated IDAT, a bad colour type, a corrupt zlib
  stream) expressible.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF.Image

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  # -- builders --------------------------------------------------------------

  defp chunk(type, data) do
    <<byte_size(data)::32-big, type::binary-size(4), data::binary,
      :erlang.crc32(type <> data)::32-big>>
  end

  defp ihdr(width, height, bit_depth, color_type, opts \\ []) do
    compression = Keyword.get(opts, :compression, 0)
    filter = Keyword.get(opts, :filter, 0)
    interlace = Keyword.get(opts, :interlace, 0)

    chunk(
      "IHDR",
      <<width::32-big, height::32-big, bit_depth, color_type, compression, filter, interlace>>
    )
  end

  # `rows` is a list of {filter_type, row_bytes}. Everything is deflated into a
  # single IDAT, which is how a small PNG is written in practice.
  defp png(width, height, color_type, rows, opts \\ []) do
    bit_depth = Keyword.get(opts, :bit_depth, 8)
    extra_chunks = Keyword.get(opts, :extra_chunks, [])
    include_iend = Keyword.get(opts, :include_iend, true)
    include_idat = Keyword.get(opts, :include_idat, true)

    raw =
      Enum.reduce(rows, <<>>, fn {filter, bytes}, acc ->
        acc <> <<filter>> <> bytes
      end)

    idat = if include_idat, do: chunk("IDAT", :zlib.compress(raw)), else: <<>>
    iend = if include_iend, do: chunk("IEND", <<>>), else: <<>>

    @png_signature <>
      ihdr(width, height, bit_depth, color_type, opts) <>
      IO.iodata_to_binary(extra_chunks) <> idat <> iend
  end

  defp with_temp(binary, fun) do
    path = Path.join(System.tmp_dir!(), "tincture_img_#{System.unique_integer([:positive])}")
    File.write!(path, binary)

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  defp load_png(binary), do: with_temp(binary, &Image.load_png!/1)
  defp load_jpeg(binary), do: with_temp(binary, &Image.load_jpeg!/1)

  # Inflate what the loader produced, so tests can assert on pixels rather than
  # on a compressed blob.
  defp inflate(data), do: :zlib.uncompress(data)

  # -- PNG: colour types -----------------------------------------------------

  describe "PNG colour types" do
    test "greyscale (type 0) yields one channel" do
      image = load_png(png(2, 1, 0, [{0, <<10, 20>>}]))

      assert image.format == :png
      assert image.width == 2 and image.height == 1
      assert image.color_space == :device_gray
      assert image.bits_per_component == 8
      assert inflate(image.data) == <<0, 10, 20>>
      refute Map.has_key?(image, :alpha_data)
    end

    test "truecolour (type 2) yields three channels" do
      image = load_png(png(1, 1, 2, [{0, <<255, 128, 0>>}]))

      assert image.color_space == :device_rgb
      assert inflate(image.data) == <<0, 255, 128, 0>>
      refute Map.has_key?(image, :alpha_data)
    end

    test "greyscale with alpha (type 4) splits into image and soft mask" do
      # Two pixels: (grey 10, alpha 255) and (grey 20, alpha 0).
      image = load_png(png(2, 1, 4, [{0, <<10, 255, 20, 0>>}]))

      assert image.color_space == :device_gray
      assert inflate(image.data) == <<0, 10, 20>>
      assert inflate(image.alpha_data) == <<0, 255, 0>>
    end

    test "truecolour with alpha (type 6) splits into image and soft mask" do
      image = load_png(png(1, 1, 6, [{0, <<255, 128, 0, 64>>}]))

      assert image.color_space == :device_rgb
      assert inflate(image.data) == <<0, 255, 128, 0>>
      assert inflate(image.alpha_data) == <<0, 64>>
    end

    test "the soft mask declares one channel regardless of the image's" do
      image = load_png(png(1, 1, 6, [{0, <<1, 2, 3, 4>>}]))

      assert image.decode_parms[:colors] == 3
      assert image.alpha_decode_parms[:colors] == 1
    end

    test "rejects an unsupported colour type" do
      # Type 3 is palettised, which this decoder does not handle.
      assert_raise ArgumentError, ~r/invalid PNG/, fn ->
        load_png(png(1, 1, 3, [{0, <<0>>}]))
      end
    end
  end

  # -- PNG: row filters ------------------------------------------------------

  describe "PNG row filters" do
    # One row, three greyscale pixels, so left-neighbour arithmetic is visible.
    test "filter 0 (None) passes bytes through" do
      image = load_png(png(3, 1, 0, [{0, <<10, 20, 30>>}]))
      assert inflate(image.data) == <<0, 10, 20, 30>>
    end

    test "filter 1 (Sub) adds the left neighbour" do
      # 10, then 20+10=30, then 30+30=60
      image = load_png(png(3, 1, 0, [{1, <<10, 20, 30>>}]))
      assert inflate(image.data) == <<0, 10, 30, 60>>
    end

    test "filter 2 (Up) adds the pixel above" do
      # Row 1 unfiltered [10,20,30]; row 2 adds [1,2,3] to it.
      image = load_png(png(3, 2, 0, [{0, <<10, 20, 30>>}, {2, <<1, 2, 3>>}]))
      assert inflate(image.data) == <<0, 10, 20, 30, 0, 11, 22, 33>>
    end

    test "filter 3 (Average) adds the mean of left and above" do
      # Row 2, byte 1: 0 + floor((0 + 10)/2) = 5
      #         byte 2: 0 + floor((5 + 20)/2) = 12
      #         byte 3: 0 + floor((12 + 30)/2) = 21
      image = load_png(png(3, 2, 0, [{0, <<10, 20, 30>>}, {3, <<0, 0, 0>>}]))
      assert inflate(image.data) == <<0, 10, 20, 30, 0, 5, 12, 21>>
    end

    test "filter 4 (Paeth) adds the Paeth predictor" do
      # With a zero delta row the predictor reproduces the row above.
      image = load_png(png(3, 2, 0, [{0, <<10, 20, 30>>}, {4, <<0, 0, 0>>}]))
      assert inflate(image.data) == <<0, 10, 20, 30, 0, 10, 20, 30>>
    end

    test "filter arithmetic wraps at 256" do
      # 200 + 100 = 300, which must wrap to 44 rather than overflow the byte.
      image = load_png(png(2, 1, 0, [{1, <<200, 100>>}]))
      assert inflate(image.data) == <<0, 200, 44>>
    end

    test "Paeth selects the upper-left neighbour when it predicts best" do
      # The predictor picks whichever of left / up / upper-left is closest to
      # a + b - c. Reaching the upper-left branch needs c to sit between a and
      # b: with left=0, up=200, upper-left=100 the estimate is exactly 100.
      #
      # Row 1 decodes to [100, 200]. Row 2 byte 1: no left or upper-left, so
      # the predictor returns up (100) and 156 + 100 wraps to 0 - which then
      # serves as the left neighbour for byte 2.
      image = load_png(png(2, 2, 0, [{0, <<100, 200>>}, {4, <<156, 0>>}]))
      assert inflate(image.data) == <<0, 100, 200, 0, 0, 100>>
    end

    test "rejects an unknown filter type" do
      assert_raise ArgumentError, ~r/invalid PNG/, fn ->
        load_png(png(2, 1, 0, [{9, <<1, 2>>}]))
      end
    end
  end

  # -- PNG: structure --------------------------------------------------------

  describe "PNG structure" do
    test "ignores ancillary chunks it does not understand" do
      text = chunk("tEXt", "Comment\0hello")
      image = load_png(png(1, 1, 0, [{0, <<42>>}], extra_chunks: [text]))
      assert inflate(image.data) == <<0, 42>>
    end

    test "joins several IDAT chunks in order" do
      # A real encoder splits large images across IDATs; the decoder must
      # concatenate before inflating, not inflate each one.
      raw = <<0, 1, 2, 0, 3, 4>>
      compressed = :zlib.compress(raw)
      half = div(byte_size(compressed), 2)
      <<first::binary-size(half), second::binary>> = compressed

      binary =
        @png_signature <>
          ihdr(2, 2, 8, 0) <>
          chunk("IDAT", first) <> chunk("IDAT", second) <> chunk("IEND", <<>>)

      assert load_png(binary).width == 2
    end

    test "rejects a file without the PNG signature" do
      assert_raise ArgumentError, ~r/invalid PNG/, fn ->
        load_png(<<"not a png at all">>)
      end
    end

    test "rejects a file with no IHDR" do
      binary = @png_signature <> chunk("IDAT", :zlib.compress(<<0, 1>>)) <> chunk("IEND", <<>>)

      assert_raise ArgumentError, ~r/invalid PNG/, fn -> load_png(binary) end
    end

    test "rejects a file with no IDAT" do
      assert_raise ArgumentError, ~r/invalid PNG/, fn ->
        load_png(png(1, 1, 0, [{0, <<1>>}], include_idat: false))
      end
    end

    test "rejects a file with no IEND" do
      assert_raise ArgumentError, ~r/invalid PNG/, fn ->
        load_png(png(1, 1, 0, [{0, <<1>>}], include_iend: false))
      end
    end

    test "rejects a chunk whose declared length exceeds the file" do
      binary = @png_signature <> <<9999::32-big, "IDAT", 1, 2, 3>>
      assert_raise ArgumentError, ~r/invalid PNG/, fn -> load_png(binary) end
    end

    test "rejects a corrupt compressed stream" do
      binary =
        @png_signature <>
          ihdr(1, 1, 8, 0) <> chunk("IDAT", <<0xDE, 0xAD, 0xBE, 0xEF>>) <> chunk("IEND", <<>>)

      assert_raise ArgumentError, ~r/invalid PNG/, fn -> load_png(binary) end
    end

    test "rejects pixel data that does not match the declared dimensions" do
      # IHDR says 4x4, the IDAT holds one row of two.
      binary =
        @png_signature <>
          ihdr(4, 4, 8, 0) <>
          chunk("IDAT", :zlib.compress(<<0, 1, 2>>)) <> chunk("IEND", <<>>)

      assert_raise ArgumentError, ~r/invalid PNG/, fn -> load_png(binary) end
    end
  end

  describe "PNG IHDR validation" do
    test "rejects a bit depth other than 8" do
      for depth <- [1, 2, 4, 16] do
        assert_raise ArgumentError, ~r/invalid PNG/, fn ->
          load_png(png(1, 1, 0, [{0, <<1>>}], bit_depth: depth))
        end
      end
    end

    test "rejects zero width or height" do
      for {w, h} <- [{0, 1}, {1, 0}] do
        binary =
          @png_signature <>
            ihdr(w, h, 8, 0) <>
            chunk("IDAT", :zlib.compress(<<0>>)) <> chunk("IEND", <<>>)

        assert_raise ArgumentError, ~r/invalid PNG/, fn -> load_png(binary) end
      end
    end

    test "rejects an interlaced image" do
      # Adam7 interlacing changes the row layout entirely.
      assert_raise ArgumentError, ~r/invalid PNG/, fn ->
        load_png(png(1, 1, 0, [{0, <<1>>}], interlace: 1))
      end
    end

    test "rejects an unknown compression or filter method" do
      for opt <- [[compression: 1], [filter: 1]] do
        assert_raise ArgumentError, ~r/invalid PNG/, fn ->
          load_png(png(1, 1, 0, [{0, <<1>>}], opt))
        end
      end
    end
  end

  # -- JPEG ------------------------------------------------------------------

  describe "JPEG" do
    # SOI, then a SOF segment. `marker` selects which SOF flavour.
    defp jpeg(opts \\ []) do
      marker = Keyword.get(opts, :marker, 0xC0)
      width = Keyword.get(opts, :width, 640)
      height = Keyword.get(opts, :height, 480)
      components = Keyword.get(opts, :components, 3)
      precision = Keyword.get(opts, :precision, 8)
      leading = Keyword.get(opts, :leading, <<>>)

      sof = <<precision, height::16-big, width::16-big, components>>
      <<0xFF, 0xD8>> <> leading <> <<0xFF, marker, byte_size(sof) + 2::16-big, sof::binary>>
    end

    test "reads dimensions and precision from a baseline SOF0" do
      image = load_jpeg(jpeg())

      assert image.format == :jpeg
      assert image.width == 640
      assert image.height == 480
      assert image.bits_per_component == 8
      assert image.color_space == :device_rgb
    end

    test "keeps the original bytes so they can be embedded unchanged" do
      binary = jpeg()
      assert load_jpeg(binary).data == binary
    end

    test "maps component count to a colour space" do
      assert load_jpeg(jpeg(components: 1)).color_space == :device_gray
      assert load_jpeg(jpeg(components: 3)).color_space == :device_rgb
      assert load_jpeg(jpeg(components: 4)).color_space == :device_cmyk
    end

    test "rejects a component count with no colour space" do
      for components <- [0, 2, 5] do
        assert_raise ArgumentError, ~r/invalid JPEG/, fn ->
          load_jpeg(jpeg(components: components))
        end
      end
    end

    test "accepts every SOF marker the format defines" do
      # Progressive, arithmetic-coded and lossless variants all carry the same
      # dimension fields, so the scanner must accept them all.
      for marker <- [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF] do
        assert load_jpeg(jpeg(marker: marker)).width == 640,
               "SOF marker 0x#{Integer.to_string(marker, 16)} should be recognised"
      end
    end

    test "skips segments before the SOF" do
      # A JFIF APP0 header, which every camera JPEG starts with.
      app0 = <<0xFF, 0xE0, 16::16-big, "JFIF", 0, 1, 2, 0, 0, 1, 0, 1, 0, 0>>
      assert load_jpeg(jpeg(leading: app0)).width == 640
    end

    test "skips standalone markers, which carry no length" do
      restart = <<0xFF, 0xD0, 0xFF, 0xD1>>
      assert load_jpeg(jpeg(leading: restart)).width == 640
    end

    test "rejects a file that does not start with SOI" do
      assert_raise ArgumentError, ~r/invalid JPEG/, fn ->
        load_jpeg(<<0xFF, 0xC0, 0, 11, 8, 0, 1, 0, 1, 3>>)
      end
    end

    test "rejects a file that ends before any SOF" do
      assert_raise ArgumentError, ~r/invalid JPEG/, fn -> load_jpeg(<<0xFF, 0xD8>>) end
    end

    test "rejects a file whose scan starts before any SOF" do
      # SOS with no preceding SOF: the entropy data begins and dimensions are
      # unknowable.
      assert_raise ArgumentError, ~r/invalid JPEG/, fn ->
        load_jpeg(<<0xFF, 0xD8, 0xFF, 0xDA, 0, 12>>)
      end
    end

    test "rejects a file that reaches EOI before any SOF" do
      assert_raise ArgumentError, ~r/invalid JPEG/, fn ->
        load_jpeg(<<0xFF, 0xD8, 0xFF, 0xD9>>)
      end
    end

    test "skips stray bytes between segments" do
      # Padding before a marker is legal; the scanner must resynchronise on the
      # next 0xFF rather than give up.
      assert load_jpeg(jpeg(leading: <<0x00, 0x00, 0x12>>)).width == 640
    end

    test "rejects a segment whose declared length is impossibly small" do
      # A segment length counts its own two bytes, so anything under 2 is
      # malformed.
      assert_raise ArgumentError, ~r/invalid JPEG/, fn ->
        load_jpeg(<<0xFF, 0xD8, 0xFF, 0xC0, 1::16-big>>)
      end
    end

    test "rejects a segment truncated before its length field" do
      assert_raise ArgumentError, ~r/invalid JPEG/, fn ->
        load_jpeg(<<0xFF, 0xD8, 0xFF, 0xC0, 5>>)
      end
    end

    test "rejects a segment whose declared length exceeds the file" do
      assert_raise ArgumentError, ~r/invalid JPEG/, fn ->
        load_jpeg(<<0xFF, 0xD8, 0xFF, 0xC0, 9999::16-big, 1, 2>>)
      end
    end

    test "rejects a zero-dimension image" do
      for opt <- [[width: 0], [height: 0], [precision: 0]] do
        assert_raise ArgumentError, ~r/invalid JPEG/, fn -> load_jpeg(jpeg(opt)) end
      end
    end
  end

  describe "unreadable files" do
    test "load_png! reports the path it could not read" do
      assert_raise ArgumentError, ~r/unable to read PNG file/, fn ->
        Image.load_png!("/nonexistent/tincture/nope.png")
      end
    end

    test "load_jpeg! reports the path it could not read" do
      assert_raise ArgumentError, ~r/unable to read JPEG file/, fn ->
        Image.load_jpeg!("/nonexistent/tincture/nope.jpg")
      end
    end
  end
end

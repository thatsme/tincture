defmodule Tincture.Fuzz.MalformedInputFuzzTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Tincture.Layout.Template

  test "embedded font registration rejects deterministic malformed byte corpus" do
    Enum.each(1..20, fn idx ->
      ttf_path =
        write_tmp_payload!(
          "tincture_fuzz_bad_#{idx}.ttf",
          <<"BAD!", deterministic_bytes("ttf", idx, 96)::binary>>
        )

      otf_path =
        write_tmp_payload!(
          "tincture_fuzz_bad_#{idx}.otf",
          <<"NOPE", deterministic_bytes("otf", idx, 96)::binary>>
        )

      assert_raise ArgumentError, "invalid TTF file: #{ttf_path}", fn ->
        Tincture.new()
        |> Tincture.register_ttf_font("FuzzBadTTF#{idx}", ttf_path)
      end

      assert_raise ArgumentError, "invalid OTF file: #{otf_path}", fn ->
        Tincture.new()
        |> Tincture.register_otf_font("FuzzBadOTF#{idx}", otf_path)
      end
    end)
  end

  test "image embedding rejects deterministic malformed byte corpus" do
    Enum.each(1..20, fn idx ->
      jpg_path =
        write_tmp_payload!(
          "tincture_fuzz_bad_#{idx}.jpg",
          <<"NOTJ", deterministic_bytes("jpg", idx, 96)::binary>>
        )

      png_path =
        write_tmp_payload!(
          "tincture_fuzz_bad_#{idx}.png",
          <<"NOTPNG", deterministic_bytes("png", idx, 96)::binary>>
        )

      assert_raise ArgumentError, "invalid JPEG file: #{jpg_path}", fn ->
        Tincture.new()
        |> Tincture.image_jpeg(0, 0, 10, 10, jpg_path)
      end

      assert_raise ArgumentError, "invalid PNG file: #{png_path}", fn ->
        Tincture.new()
        |> Tincture.image_png(0, 0, 10, 10, png_path)
      end
    end)
  end

  test "XML parser and renderer return errors across malformed XML corpus" do
    Enum.each(1..24, fn idx ->
      body_fragment = Base.encode16(deterministic_bytes("xml", idx, 12), case: :lower)

      malformed_xml =
        ~s(<document><layout page_size="letter" columns="2" />) <>
          ~s(<body width="#{100 + idx}" size="10"><p>#{body_fragment}</body>)

      capture_log(fn ->
        assert {:error, :invalid_xml} = Template.parse_xml(malformed_xml)

        assert {:error, :invalid_xml} =
                 Template.render_xml_document(Tincture.new(), malformed_xml)
      end)
    end)
  end

  defp deterministic_bytes(tag, idx, len) do
    chunks = div(len + 31, 32)

    1..chunks
    |> Enum.map(fn chunk -> :crypto.hash(:sha256, "#{tag}:#{idx}:#{chunk}") end)
    |> IO.iodata_to_binary()
    |> binary_part(0, len)
  end

  defp write_tmp_payload!(filename, payload) do
    path = Path.join(System.tmp_dir!(), filename)
    File.write!(path, payload)
    path
  end
end

Code.require_file("support/fonts.exs", __DIR__)

# Attaching to Tincture's telemetry events while building a document.
#
# Tincture emits three spans: one per document, one per page, and one per
# embedded font. The font event is the interesting one — subsetting is usually
# the most expensive single step, and comparing :source_size with :byte_size
# tells you whether it actually helped.
#
# :telemetry is an optional dependency. With it absent every event call
# compiles away and this script reports that nothing was emitted.

defmodule Report do
  @moduledoc false

  # A named function rather than a closure: :telemetry logs a warning for
  # anonymous handlers, because they carry a performance penalty.
  def handle([:tincture, :export, :stop], measurements, metadata, _config) do
    IO.puts("""

    document  #{ms(measurements.duration)}  #{kb(measurements.byte_size)}
      pages #{metadata.page_count} · fields #{metadata.form_field_count} · \
    fonts #{metadata.embedded_font_count} · images #{metadata.image_count}\
    #{if metadata.encrypted?, do: " · encrypted", else: ""}\
    """)
  end

  def handle([:tincture, :page, :stop], measurements, metadata, _config) do
    IO.puts(
      "  page #{metadata.page_number}   #{ms(measurements.duration)}  " <>
        "#{kb(measurements.byte_size)} of content, #{metadata.operation_count} ops"
    )
  end

  def handle([:tincture, :font, :embed, :stop], measurements, metadata, _config) do
    saved = 100 - measurements.byte_size / measurements.source_size * 100

    IO.puts(
      "  font #{metadata.font_name}   #{ms(measurements.duration)}  " <>
        "#{kb(measurements.source_size)} -> #{kb(measurements.byte_size)} " <>
        "(#{:erlang.float_to_binary(saved, decimals: 1)}% smaller, subset: #{metadata.subset})"
    )
  end

  defp ms(native) do
    native
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
    |> :erlang.float_to_binary(decimals: 2)
    |> String.pad_leading(7)
    |> Kernel.<>("ms")
  end

  defp kb(bytes) do
    (bytes / 1024) |> :erlang.float_to_binary(decimals: 1) |> Kernel.<>("kB")
  end
end

unless Tincture.Telemetry.enabled?() do
  IO.puts("""
  :telemetry is not available, so Tincture compiled its event calls away and
  nothing will be reported. Add {:telemetry, "~> 1.0"} to pick these up.
  """)
end

:ok =
  :telemetry.attach_many(
    "example-report",
    [
      [:tincture, :export, :stop],
      [:tincture, :page, :stop],
      [:tincture, :font, :embed, :stop]
    ],
    &Report.handle/4,
    nil
  )

body = fn embedded? -> Examples.Fonts.resolve("Body", embedded?) end

{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Examples.Fonts.register("Body", "Sans")

lorem =
  "The quick brown fox jumps over the lazy dog, and keeps doing so for long " <>
    "enough that the line breaker has something to think about. "

# Three pages, so the per-page events have something to say.
pdf =
  Enum.reduce(1..3, pdf, fn page, acc ->
    acc = if page == 1, do: acc, else: Tincture.add_page(acc)

    acc
    |> Tincture.set_font(body.(embedded?), 11)
    |> Tincture.text_paragraph(
      50,
      760,
      Tincture.Typography.RichText.from_plain(String.duplicate(lorem, page * 3),
        font: body.(embedded?),
        size: 11
      ),
      495,
      align: :justified,
      line_break: :optimal
    )
  end)

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("telemetry.pdf")
File.write!(path, binary)

IO.puts("\nwrote #{Path.relative_to_cwd(path)}")

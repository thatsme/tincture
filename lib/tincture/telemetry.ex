defmodule Tincture.Telemetry do
  @moduledoc """
  Telemetry events emitted while building a document.

  Tincture has no required runtime dependencies, and telemetry does not change
  that: `:telemetry` is an *optional* dependency. If your application does not
  depend on it, every call in this module compiles to a no-op and nothing is
  emitted. Add it to pick the events up:

      {:telemetry, "~> 1.0"}

  Attach as usual:

      :telemetry.attach_many(
        "tincture",
        [
          [:tincture, :export, :stop],
          [:tincture, :page, :stop],
          [:tincture, :font, :embed, :stop]
        ],
        &MyApp.Metrics.handle/4,
        nil
      )

  ## Events

  Each span emits `:start`, `:stop` and `:exception` in the usual
  `:telemetry.span/3` shape. Durations are in native units — pass them through
  `System.convert_time_unit/3`.

  ### `[:tincture, :export, :start | :stop | :exception]`

  One document being serialised to bytes. This is the event to watch for
  "how long does a document take".

    * measurements — `:system_time` on start; `:duration` and `:byte_size` on
      stop.
    * metadata — `:page_count`, `:form_field_count`, `:embedded_font_count`,
      `:image_count`, and `:encrypted?`.

  ### `[:tincture, :page, :start | :stop | :exception]`

  One page's content stream being built and compressed. Emitted per page, so a
  slow page in a long document is visible rather than averaged away.

    * measurements — `:duration` and `:byte_size` (the compressed content
      stream) on stop.
    * metadata — `:page_number` and `:operation_count`.

  ### `[:tincture, :font, :embed, :start | :stop | :exception]`

  One font being embedded, including subsetting. Subsetting is usually the most
  expensive single step in producing a document, and the size measurements say
  whether it actually worked.

    * measurements — `:duration`, `:byte_size` (the bytes this font contributed
      to the document) and `:source_size` (the original font file) on stop.
      Comparing the two is how you tell whether subsetting actually helped.
    * metadata — `:font_name`, `:format` and `:subset` (the configured mode,
      which is what was asked for rather than what was achieved: subsetting
      falls back to the whole font on malformed input, and logs when it does).

  ## Overhead

  With `:telemetry` absent the calls vanish at compile time. With it present but
  nothing attached, dispatch is an ETS lookup per event, and events are emitted
  per document, per page and per font — never per drawing operation.
  """

  # Resolved when Tincture itself is compiled, which happens inside the
  # consuming project - so this correctly reflects whether that project depends
  # on :telemetry, rather than whether Tincture's own build had it.
  @enabled Code.ensure_loaded?(:telemetry)

  @doc """
  Whether telemetry events are being emitted at all.

  False when `:telemetry` was not available when Tincture was compiled, in
  which case every event call in this module compiled away to nothing.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: @enabled

  if @enabled do
    @doc """
    Run `fun` as a telemetry span, emitting start/stop/exception events.

    `fun` returns `{result, extra_measurements}`; the extra measurements are
    merged into the stop event alongside `:duration`.
    """
    @spec span([atom()], map(), (-> {result, map()})) :: result when result: var
    def span(event, metadata, fun) do
      :telemetry.span(event, metadata, fn ->
        {result, measurements} = fun.()
        {result, measurements, metadata}
      end)
    end

    @doc """
    Emit a single event.
    """
    @spec execute([atom()], map(), map()) :: :ok
    def execute(event, measurements, metadata) do
      :telemetry.execute(event, measurements, metadata)
    end
  else
    @spec span([atom()], map(), (-> {result, map()})) :: result when result: var
    def span(_event, _metadata, fun) do
      {result, _measurements} = fun.()
      result
    end

    @spec execute([atom()], map(), map()) :: :ok
    def execute(_event, _measurements, _metadata), do: :ok
  end
end

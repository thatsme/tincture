defmodule Tincture.TelemetryTest do
  @moduledoc """
  Tests for the telemetry events emitted while building a document.

  Not async: telemetry handlers are global, so two tests attaching handlers for
  the same event would see each other's documents.
  """
  use ExUnit.Case, async: false

  alias Tincture.Telemetry
  alias Tincture.Test.MeasurableFont

  @export_events [
    [:tincture, :export, :start],
    [:tincture, :export, :stop],
    [:tincture, :export, :exception]
  ]

  @page_events [[:tincture, :page, :start], [:tincture, :page, :stop]]
  @font_events [[:tincture, :font, :embed, :stop]]

  @doc false
  # A named function rather than a closure: telemetry logs a warning for every
  # anonymous handler, which would be one line per test in CI output.
  def forward(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  # Forwards every named event to the test process, so assertions read as
  # assert_received rather than poking at shared state.
  defp attach(events) do
    handler_id = "test-#{System.unique_integer([:positive])}"

    :ok = :telemetry.attach_many(handler_id, events, &__MODULE__.forward/4, self())

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  defp collect(acc \\ []) do
    receive do
      {:telemetry, event, measurements, metadata} ->
        collect([{event, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp events_named(collected, name) do
    Enum.filter(collected, fn {event, _measurements, _metadata} -> event == name end)
  end

  describe "enabled?/0" do
    test "is true here, because the test environment has :telemetry" do
      # :telemetry is an optional dependency. If this ever reports false the
      # tests below would pass vacuously, so assert it directly.
      assert Telemetry.enabled?()
    end
  end

  describe "the export span" do
    setup do
      attach(@export_events)
      :ok
    end

    test "emits start then stop for one document" do
      Tincture.new() |> Tincture.text_at(10, 10, "hi") |> Tincture.export()

      collected = collect()

      assert [{_event, start_measurements, _}] =
               events_named(collected, [:tincture, :export, :start])

      assert [{_event, stop_measurements, _}] =
               events_named(collected, [:tincture, :export, :stop])

      assert is_integer(start_measurements.system_time)
      assert is_integer(stop_measurements.duration)
      assert stop_measurements.duration >= 0
    end

    test "reports the size of the document actually produced" do
      pdf = Tincture.new() |> Tincture.text_at(10, 10, "hi")
      binary = Tincture.export(pdf)

      assert [{_event, measurements, _metadata}] =
               collect() |> events_named([:tincture, :export, :stop])

      assert measurements.byte_size == byte_size(binary)
    end

    test "describes the document in its metadata" do
      Tincture.new()
      |> Tincture.add_page()
      |> Tincture.text_field(10, 10, 100, 20, "name")
      |> Tincture.export()

      assert [{_event, _measurements, metadata}] =
               collect() |> events_named([:tincture, :export, :stop])

      assert metadata.page_count == 2
      assert metadata.form_field_count == 1
      assert metadata.embedded_font_count == 0
      assert metadata.image_count == 0
      refute metadata.encrypted?
    end

    test "reports an encrypted document as encrypted" do
      Tincture.new()
      |> Tincture.text_at(10, 10, "hi")
      |> Tincture.encrypt(user_password: "secret")
      |> Tincture.export()

      assert [{_event, _measurements, metadata}] =
               collect() |> events_named([:tincture, :export, :stop])

      assert metadata.encrypted?
    end

    test "counts embedded fonts" do
      path = MeasurableFont.write!()
      on_exit(fn -> File.rm(path) end)

      Tincture.new()
      |> Tincture.register_ttf_font("Probe", path)
      |> Tincture.set_font("Probe", 10)
      |> Tincture.text_at(10, 10, "AB")
      |> Tincture.export()

      assert [{_event, _measurements, metadata}] =
               collect() |> events_named([:tincture, :export, :stop])

      assert metadata.embedded_font_count == 1
    end
  end

  describe "the page span" do
    setup do
      attach(@page_events)
      :ok
    end

    test "emits once per page, identifying each" do
      Tincture.new()
      |> Tincture.text_at(10, 10, "one")
      |> Tincture.add_page()
      |> Tincture.text_at(10, 10, "two")
      |> Tincture.add_page()
      |> Tincture.text_at(10, 10, "three")
      |> Tincture.export()

      stops = collect() |> events_named([:tincture, :page, :stop])

      assert length(stops) == 3

      assert Enum.map(stops, fn {_event, _measurements, metadata} -> metadata.page_number end) ==
               [1, 2, 3]
    end

    test "reports the operation count and the compressed stream size" do
      Tincture.new()
      |> Tincture.text_at(10, 10, "one")
      |> Tincture.text_at(10, 30, "two")
      |> Tincture.export()

      assert [{_event, measurements, metadata}] =
               collect() |> events_named([:tincture, :page, :stop])

      # Two text operations, plus whatever set_font emitted (none here).
      assert metadata.operation_count == 2
      assert measurements.byte_size > 0
    end
  end

  describe "the font embed span" do
    setup do
      attach(@font_events)
      :ok
    end

    test "emits once per embedded font, with sizes that show subsetting" do
      path = MeasurableFont.write!()
      on_exit(fn -> File.rm(path) end)

      Tincture.new()
      |> Tincture.register_ttf_font("Probe", path)
      |> Tincture.set_font("Probe", 10)
      |> Tincture.text_at(10, 10, "AB")
      |> Tincture.export()

      assert [{_event, measurements, metadata}] =
               collect() |> events_named([:tincture, :font, :embed, :stop])

      assert metadata.font_name == "Probe"
      assert metadata.subset == :used_text
      assert measurements.source_size == byte_size(File.read!(path))
      assert measurements.byte_size > 0
    end

    test "emits nothing when no font is embedded" do
      Tincture.new() |> Tincture.text_at(10, 10, "hi") |> Tincture.export()

      assert collect() == []
    end

    test "emits per font, not per use" do
      path = MeasurableFont.write!()
      on_exit(fn -> File.rm(path) end)

      Tincture.new()
      |> Tincture.register_ttf_font("One", path)
      |> Tincture.register_ttf_font("Two", path)
      |> Tincture.set_font("One", 10)
      |> Tincture.text_at(10, 10, "A")
      |> Tincture.text_at(10, 30, "B")
      |> Tincture.set_font("Two", 10)
      |> Tincture.text_at(10, 50, "A")
      |> Tincture.export()

      stops = collect() |> events_named([:tincture, :font, :embed, :stop])

      assert length(stops) == 2

      assert stops
             |> Enum.map(fn {_event, _measurements, metadata} -> metadata.font_name end)
             |> Enum.sort() == ["One", "Two"]
    end
  end

  describe "span/3" do
    test "returns the wrapped value, dropping the extra measurements" do
      assert Telemetry.span([:tincture, :test, :unattached], %{}, fn ->
               {:the_result, %{byte_size: 1}}
             end) == :the_result
    end

    test "emits an exception event and re-raises" do
      attach(@export_events)

      assert_raise RuntimeError, "boom", fn ->
        Telemetry.span([:tincture, :export], %{}, fn -> raise "boom" end)
      end

      assert [{_event, measurements, metadata}] =
               collect() |> events_named([:tincture, :export, :exception])

      assert is_integer(measurements.duration)
      assert metadata.kind == :error
      assert %RuntimeError{} = metadata.reason
    end
  end
end

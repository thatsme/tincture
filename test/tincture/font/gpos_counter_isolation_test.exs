defmodule Tincture.Font.GPOSCounterIsolationTest do
  @moduledoc """
  The GPOS guardrail counter lives in the process dictionary. These tests pin
  the properties that make that tolerable, so a future change cannot quietly
  break them.

  The counter is incremented from seven places deep inside the GPOS pair and
  class parsers and read once at the top of `parse_basic_tables/1`. Threading it
  back through those `with` chains would reshape the control flow of the code
  that produces kerning pairs, so it stays where it is — but it must not leak
  between parses or clobber an enclosing one.
  """
  use ExUnit.Case, async: true

  alias Tincture.Font.OpenType.GPOS
  alias Tincture.Font.TTF

  # Asked for rather than hardcoded: a literal {SomeModule, :key} silently stops
  # matching when the counter moves, and every assertion below then passes
  # against a key nothing writes.
  @key GPOS.guardrail_scope_key()

  # Minimal but structurally valid TTF: enough tables for parse_basic_tables/1
  # to succeed. No GPOS table, so the counter stays at zero — these tests are
  # about the counter's lifecycle, not its value.
  defp minimal_ttf do
    tables = [
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 1::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 1::16-big>>},
      {"hmtx", <<500::16-big, 0::16-signed-big>>}
    ]

    num_tables = length(tables)
    header = <<0x0001_0000::32-big, num_tables::16-big, 0::16-big, 0::16-big, 0::16-big>>
    base = byte_size(header) + num_tables * 16

    {records, binaries, _} =
      Enum.reduce(tables, {[], [], base}, fn {tag, data}, {recs, bins, offset} ->
        record = <<tag::binary-size(4), 0::32-big, offset::32-big, byte_size(data)::32-big>>
        {recs ++ [record], bins ++ [data], offset + byte_size(data)}
      end)

    IO.iodata_to_binary([header, records, binaries])
  end

  test "a successful parse leaves no counter behind in a clean process" do
    refute Process.get(@key)

    assert {:ok, _metrics} = TTF.parse_basic_tables(minimal_ttf())

    refute Process.get(@key),
           "parse_basic_tables/1 left its counter in the process dictionary, " <>
             "so every process that parses a font grows a permanent key"
  end

  test "a failed parse leaves no counter behind either" do
    refute Process.get(@key)

    assert TTF.parse_basic_tables(<<"not a font">>) == :error

    refute Process.get(@key), "the counter survived a failed parse"
  end

  test "a parse restores an enclosing parse's counter rather than zeroing it" do
    # Simulates being called from inside another parse that had already
    # accumulated skips. Without the save/restore, the inner parse's reset
    # would zero this and the outer parse would silently under-report.
    Process.put(@key, 7)

    assert {:ok, _metrics} = TTF.parse_basic_tables(minimal_ttf())

    assert Process.get(@key) == 7,
           "a nested parse clobbered the enclosing parse's skip count"
  end

  test "an enclosing count survives even when the inner parse fails" do
    Process.put(@key, 3)

    assert TTF.parse_basic_tables(<<"not a font">>) == :error

    assert Process.get(@key) == 3
  end

  test "the counter does not leak between processes" do
    Process.put(@key, 99)

    task =
      Task.async(fn ->
        before = Process.get(@key)
        {:ok, _metrics} = TTF.parse_basic_tables(minimal_ttf())
        {before, Process.get(@key)}
      end)

    assert {nil, nil} = Task.await(task)
    assert Process.get(@key) == 99
  end
end

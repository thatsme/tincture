defmodule Tincture.Font.OpenType.GPOSTest do
  @moduledoc """
  Direct tests for the `GPOS` parser.

  Two things are worth testing here that a real font cannot easily provide.

  The first is the guardrails. A class-based pair subtable declares
  `class1_count` and `class2_count` and the parser is expected to expand their
  product; a font declaring 60,000 × 60,000 would ask for 3.6 billion entries.
  No legitimate font does that, so the only way to exercise the caps is to
  build a table that lies.

  The second is the value-record format. `GPOS` value records are variable
  width — the format is a bitmask and each set bit adds two bytes — so the
  parser has to compute the stride before it can read anything. Getting that
  wrong misreads every subsequent pair rather than failing outright.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tincture.Font.OpenType.GPOS

  # Only x-advance on the first glyph: one set bit, so a 2-byte value record.
  @x_advance 0x0004

  # -- table builders --------------------------------------------------------

  # Wraps a pair-positioning subtable in the script/feature/lookup chain needed
  # to reach it, with a "kern" feature under "latn".
  defp gpos_table(subtable, trailing \\ <<>>) do
    script_list_off = 10
    script_off = 20
    lang_sys_off = 26
    feature_list_off = 36
    feature_off = 46
    lookup_list_off = 52
    lookup_off = 56
    subtable_off = 64

    header =
      <<1::16-big, 0::16-big, script_list_off::16-big, feature_list_off::16-big,
        lookup_list_off::16-big>>

    parts = [
      {script_list_off, <<1::16-big, "latn"::binary, script_off - script_list_off::16-big>>},
      {script_off, <<lang_sys_off - script_off::16-big, 0::16-big>>},
      {lang_sys_off, <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>},
      {feature_list_off, <<1::16-big, "kern"::binary, feature_off - feature_list_off::16-big>>},
      {feature_off, <<0::16-big, 1::16-big, 0::16-big>>},
      {lookup_list_off, <<1::16-big, lookup_off - lookup_list_off::16-big>>},
      # Lookup type 2 is pair positioning.
      {lookup_off, <<2::16-big, 0::16-big, 1::16-big, subtable_off - lookup_off::16-big>>},
      {subtable_off, subtable <> trailing}
    ]

    Enum.reduce(parts, header, fn {offset, bin}, acc ->
      acc <> String.duplicate(<<0>>, max(offset - byte_size(acc), 0)) <> bin
    end)
  end

  # PairPos format 1: explicit {left, right} pairs with an x-advance each.
  defp pair_pos_format_1(pair_sets, opts \\ []) do
    declared_count = Keyword.get(opts, :declared_pair_set_count, length(pair_sets))
    coverage_glyphs = Keyword.get(opts, :coverage_glyphs, Enum.map(pair_sets, &elem(&1, 0)))

    header_size = 10 + length(pair_sets) * 2
    coverage_size = 4 + length(coverage_glyphs) * 2

    {offsets, bodies, _} =
      Enum.reduce(pair_sets, {[], [], header_size + coverage_size}, fn {_left, pairs},
                                                                       {offs, bods, cursor} ->
        declared = Keyword.get(opts, :declared_pair_value_count, length(pairs))

        body =
          Enum.reduce(pairs, <<declared::16-big>>, fn {right, adv}, acc ->
            acc <> <<right::16-big, adv::16-signed-big>>
          end)

        {offs ++ [cursor], bods ++ [body], cursor + byte_size(body)}
      end)

    offset_bin = for o <- offsets, into: <<>>, do: <<o::16-big>>
    coverage_bin = for g <- coverage_glyphs, into: <<>>, do: <<g::16-big>>

    <<1::16-big, header_size::16-big, @x_advance::16-big, 0::16-big, declared_count::16-big,
      offset_bin::binary, 1::16-big, length(coverage_glyphs)::16-big, coverage_bin::binary,
      IO.iodata_to_binary(bodies)::binary>>
  end

  # PairPos format 2: class-based. `matrix` is a list of rows of x-advances.
  defp pair_pos_format_2(matrix, opts \\ []) do
    class_1_count = Keyword.get(opts, :class_1_count, length(matrix))
    class_2_count = Keyword.get(opts, :class_2_count, length(hd(matrix ++ [[]])))
    coverage_glyphs = Keyword.get(opts, :coverage_glyphs, [1, 2])
    class_1_defs = Keyword.get(opts, :class_1_defs, [{1, 1}])
    class_def_1_opts = Keyword.take(opts, [:declared_glyph_count])
    class_2_defs = Keyword.get(opts, :class_2_defs, [{2, 1}])

    matrix_bin =
      Enum.reduce(matrix, <<>>, fn row, acc ->
        Enum.reduce(row, acc, fn adv, acc2 -> acc2 <> <<adv::16-signed-big>> end)
      end)

    header_size = 16
    matrix_off = header_size
    coverage_off = matrix_off + byte_size(matrix_bin)
    coverage_bin = for g <- coverage_glyphs, into: <<>>, do: <<g::16-big>>
    coverage = <<1::16-big, length(coverage_glyphs)::16-big, coverage_bin::binary>>

    class_def_1_off = coverage_off + byte_size(coverage)
    class_def_1 = class_def_format_1(class_1_defs, class_def_1_opts)
    class_def_2_off = class_def_1_off + byte_size(class_def_1)
    class_def_2 = class_def_format_1(class_2_defs)

    <<2::16-big, coverage_off::16-big, @x_advance::16-big, 0::16-big, class_def_1_off::16-big,
      class_def_2_off::16-big, class_1_count::16-big, class_2_count::16-big, matrix_bin::binary,
      coverage::binary, class_def_1::binary, class_def_2::binary>>
  end

  # ClassDef format 1: a start glyph and one class value per consecutive glyph.
  defp class_def_format_1(defs, opts \\ []) do
    {start_glyph, _} = hd(defs)
    values = Enum.map(defs, &elem(&1, 1))
    declared = Keyword.get(opts, :declared_glyph_count, length(values))
    body = for v <- values, into: <<>>, do: <<v::16-big>>

    # When the declared count exceeds the real entries, supply the bytes anyway.
    # Otherwise the parser rejects the table as truncated before it ever reaches
    # the entry-count cap, and the guardrail under test never fires.
    padding = String.duplicate(<<0, 0>>, max(declared - length(values), 0))

    <<1::16-big, start_glyph::16-big, declared::16-big, body::binary, padding::binary>>
  end

  defp records(table), do: %{"GPOS" => {0, byte_size(table)}}

  # "a" -> glyph 1, "b" -> glyph 2. Note GPOS keys its result by codepoint
  # pair, not by string pair - unlike GSUB, which returns text.
  @cmap %{?a => 1, ?b => 2}

  defp kerns(table, cmap \\ @cmap) do
    GPOS.parse_gpos_pair_kerns(table, records(table), cmap)
  end

  setup do
    scope = GPOS.begin_guardrail_scope()
    on_exit(fn -> GPOS.end_guardrail_scope(scope) end)
    :ok
  end

  describe "pair positioning, format 1" do
    test "reads an explicit kerning pair" do
      table = gpos_table(pair_pos_format_1([{1, [{2, -40}]}]))
      assert kerns(table) == %{{?a, ?b} => -40}
    end

    test "reads several pairs from one pair set" do
      table = gpos_table(pair_pos_format_1([{1, [{2, -40}, {1, -15}]}]))
      assert kerns(table) == %{{?a, ?b} => -40, {?a, ?a} => -15}
    end

    test "reads pairs from several pair sets" do
      table = gpos_table(pair_pos_format_1([{1, [{2, -40}]}, {2, [{1, -20}]}]))
      assert kerns(table) == %{{?a, ?b} => -40, {?b, ?a} => -20}
    end

    test "a positive adjustment is kept as-is" do
      table = gpos_table(pair_pos_format_1([{1, [{2, 25}]}]))
      assert kerns(table) == %{{?a, ?b} => 25}
    end

    test "drops a pair whose glyphs are not in the cmap" do
      table = gpos_table(pair_pos_format_1([{1, [{2, -40}]}]))
      assert kerns(table, %{?a => 1}) == %{}
    end

    test "returns an empty map when the font has no GPOS table" do
      assert GPOS.parse_gpos_pair_kerns(<<0, 0>>, %{}, @cmap) == %{}
    end

    test "returns an empty map when the GPOS record points outside the font" do
      assert GPOS.parse_gpos_pair_kerns(<<0, 0>>, %{"GPOS" => {900, 20}}, @cmap) == %{}
    end
  end

  describe "pair positioning, format 2 (class based)" do
    test "expands a class matrix into concrete pairs" do
      # class1: glyph 1 -> class 1. class2: glyph 2 -> class 1.
      # A 2x2 matrix, so entry [1][1] applies to the pair (1, 2).
      table = gpos_table(pair_pos_format_2([[0, 0], [0, -55]]))
      assert kerns(table) == %{{?a, ?b} => -55}
    end

    test "a zero adjustment produces no pair" do
      table = gpos_table(pair_pos_format_2([[0, 0], [0, 0]]))
      assert kerns(table) == %{}
    end
  end

  describe "guardrails" do
    test "skips a pair subtable whose coverage disagrees with its pair set count" do
      # Coverage lists one glyph, the subtable claims two pair sets.
      subtable = pair_pos_format_1([{1, [{2, -40}]}], declared_pair_set_count: 2)

      log = capture_log(fn -> assert kerns(gpos_table(subtable)) == %{} end)
      assert log =~ "coverage_glyph_count=1 pair_set_count=2 mismatch"
      assert GPOS.guardrail_skips() >= 1
    end

    test "skips a pair set declaring more records than the cap allows" do
      # 10_001 exceeds @max_gpos_pair_set_records without supplying the data.
      subtable = pair_pos_format_1([{1, [{2, -40}]}], declared_pair_value_count: 10_001)

      log = capture_log(fn -> assert kerns(gpos_table(subtable)) == %{} end)
      assert log =~ "pair_value_count=10001 exceeds limit=10000"
      assert GPOS.guardrail_skips() >= 1
    end

    test "skips a class matrix whose declared size exceeds the cap" do
      # 128 x 128 = 16_384 entries, over the 10_000 cap, without the data.
      subtable = pair_pos_format_2([[0, 0], [0, -55]], class_1_count: 128, class_2_count: 128)

      log = capture_log(fn -> assert kerns(gpos_table(subtable)) == %{} end)
      assert log =~ "class1_count=128 class2_count=128 records=16384 exceeds limit=10000"
      assert GPOS.guardrail_skips() >= 1
    end

    test "skips a class definition declaring more entries than the cap" do
      subtable =
        pair_pos_format_2([[0, 0], [0, -55]], declared_glyph_count: 10_001)

      log = capture_log(fn -> assert kerns(gpos_table(subtable)) == %{} end)
      assert log =~ "class definition skipped"
      assert log =~ "entries=10001 exceeds limit=10000"
      assert GPOS.guardrail_skips() >= 1
    end

    test "rejects a class count of zero" do
      subtable = pair_pos_format_2([[0, 0], [0, -55]], class_1_count: 0)
      assert kerns(gpos_table(subtable)) == %{}
    end

    test "guardrail skips start at zero in a fresh scope" do
      assert GPOS.guardrail_skips() == 0
    end
  end

  describe "value record sizing" do
    test "a wider value format shifts every subsequent field" do
      # Two set bits (x-placement + x-advance) means a 4-byte value record.
      # If the parser assumed 2 bytes it would misread the pair entirely.
      pair_set = <<1::16-big, 2::16-big, 0::16-signed-big, -30::16-signed-big>>
      header_size = 12
      coverage = <<1::16-big, 1::16-big, 1::16-big>>

      subtable =
        <<1::16-big, header_size::16-big, 0x0005::16-big, 0::16-big, 1::16-big,
          header_size + byte_size(coverage)::16-big, coverage::binary, pair_set::binary>>

      assert kerns(gpos_table(subtable)) == %{{?a, ?b} => -30}
    end

    test "a value format of zero means no value record at all" do
      # Nothing to read, so no adjustment can be recovered.
      coverage = <<1::16-big, 1::16-big, 1::16-big>>
      pair_set = <<1::16-big, 2::16-big>>

      subtable =
        <<1::16-big, 12::16-big, 0::16-big, 0::16-big, 1::16-big,
          12 + byte_size(coverage)::16-big, coverage::binary, pair_set::binary>>

      assert kerns(gpos_table(subtable)) == %{}
    end
  end

  describe "malformed tables degrade rather than crash" do
    test "a truncated table yields no kerns" do
      full = gpos_table(pair_pos_format_1([{1, [{2, -40}]}]))

      for cut <- [12, 25, 40, 55, 70, 80] do
        truncated = binary_part(full, 0, min(cut, byte_size(full)))

        capture_log(fn ->
          assert kerns(truncated) == %{},
                 "truncating to #{cut} bytes should degrade, not crash"
        end)
      end
    end

    test "random bytes yield no kerns" do
      junk = for i <- 1..300, into: <<>>, do: <<rem(i * 53, 256)>>
      capture_log(fn -> assert kerns(junk) == %{} end)
    end

    test "an unknown subtable format yields no kerns" do
      subtable = <<9::16-big, 0::16-big, 0::16-big, 0::16-big, 0::16-big>>
      assert kerns(gpos_table(subtable)) == %{}
    end

    test "an empty cmap yields no kerns" do
      table = gpos_table(pair_pos_format_1([{1, [{2, -40}]}]))
      assert kerns(table, %{}) == %{}
    end
  end

  describe "guardrail scope" do
    test "a scope reports the skips accumulated inside it" do
      subtable = pair_pos_format_1([{1, [{2, -40}]}], declared_pair_set_count: 2)
      table = gpos_table(subtable)

      outer = GPOS.begin_guardrail_scope()
      capture_log(fn -> kerns(table) end)
      skips = GPOS.guardrail_skips()
      GPOS.end_guardrail_scope(outer)

      assert skips >= 1
    end
  end
end

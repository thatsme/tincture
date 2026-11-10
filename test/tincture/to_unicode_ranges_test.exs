defmodule Tincture.ToUnicodeRangesTest do
  @moduledoc """
  The ToUnicode CMap's `bfrange` lines, which Acrobat Reader reads only when
  every line keeps two rules: its source codes stay within one block of 256,
  sharing every byte but the last (Adobe TN 5411 1.4.1), and its
  destination's last byte is not incremented past 255 (ISO 32000-1 9.10.3).
  One line that breaks either makes Acrobat discard the whole map, so text in
  that font cannot be copied, searched or read aloud. Through 0.4.1 a font
  embedded whole, and a subset whose text used consecutive characters across
  a multiple of 256, wrote such lines.

  The documents are `Tincture.Test.ToUnicodeMap.documents/0`: every committed
  example, a font embedded whole, a field font embedded with
  `full_font: true`, a subset straddling U+00FF/U+0100, U+03FF/U+0400 and
  U+1DFF/U+1E00, and the 1,202 codes of the three ranges LiberationSans's
  whole map used to write as single lines.
  """
  use ExUnit.Case, async: true

  alias Tincture.Test.ToUnicodeMap

  # Each CMap's table, read from 0.4.1's output of the same documents: the
  # document, its font object, the number of entries and their SHA-256. The
  # fix splits lines; it must not change what any code maps to.
  @tables_at_0_4_1 [
    {"examples/output/accessible.pdf", 13, 43,
     "0fec9779e1854041333abfab909d87f10e48472bf91f7dd66004b94150c4d7a1"},
    {"examples/output/archival.pdf", 10, 50,
     "f13a9ff5892730b9974530181c0d068c58943ef6cdd4509694944c51c20273eb"},
    {"examples/output/archival.pdf", 16, 52,
     "e0048fe03441d207d49a0b4ca50a5ca95c80e4bde46e51c2473c6dee9b86a5ac"},
    {"examples/output/archival_form.pdf", 10, 2326,
     "9e1e2b30c605e201211705aaff2acf684a494b7c09fddd0f201212536f769dae"},
    {"examples/output/archival_form.pdf", 16, 14,
     "f6a5f359cc54b56dc18cb447163a00b3119568c68d86ceabda071e1666506483"},
    {"examples/output/compliant.pdf", 10, 44,
     "fcbe677ba8054f28312115857202fd74f1a1f1506050bb8d9fec6afb2d7bcf8b"},
    {"examples/output/compliant.pdf", 16, 55,
     "1871c2c2377eb05add0011788b03fc7d929ebfa248f1607b2be44efdcfe34ee2"},
    {"examples/output/form.pdf", 10, 29,
     "1abceded2a3019c8eb212fb603ee33cc0fe500149a9e2bd3bd0028411c1944c0"},
    {"examples/output/form.pdf", 16, 53,
     "43011cc14b5b1793601e7214b2bf6d3aa2187e276948ff2222d0f9788a332dfb"},
    {"examples/output/gradient.pdf", 10, 34,
     "bf67cbe504e4f88b4d0c9b9a93d3e17cc454c20ad02924701a018055cd412fd7"},
    {"examples/output/gradient.pdf", 16, 28,
     "7ace86d9c2de68c948c4f98da862729d3d685e5d5cad4be908b0e67f0d696193"},
    {"examples/output/invoice.pdf", 10, 67,
     "299627598435098305437e44e7412ab2199cfb2bdc31dc6d6142c321f087b71c"},
    {"examples/output/invoice.pdf", 16, 57,
     "8b28e321f072fc7e15a8b033c226c5e226922a73c28a487ead0a479ba3d96d8f"},
    {"examples/output/linked/Attached documents/Appendix-A.pdf", 32, 35,
     "189b1e1a393d5f63f43be23830911c544ad5434f8038e1b525bcfd2f49544b0b"},
    {"examples/output/linked/Main-report.pdf", 10, 31,
     "2d188f015803f73815707f2aaa7c079ba1623149743839156afecfe511dc75d1"},
    {"examples/output/signed.pdf", 13, 41,
     "8f3b56f8a7ad0d72d0f8aefade0151ad54f7dbd0ea98a312e29d54ba7d09d2fe"},
    {"examples/output/signed_archival.pdf", 10, 37,
     "480c3435204e18a8f12ffe531e071bba6dfed5ad9733a21978780cf803c53172"},
    {"examples/output/tagged_form.pdf", 13, 2326,
     "9e1e2b30c605e201211705aaff2acf684a494b7c09fddd0f201212536f769dae"},
    {"whole font", 10, 13, "d5642aa0a841f43ee9e0fc248c7d621ff4c23c5b90c50164192824bfea4a8017"},
    {"full_font field", 10, 2326,
     "9e1e2b30c605e201211705aaff2acf684a494b7c09fddd0f201212536f769dae"},
    {"subset across 256 boundaries", 10, 13,
     "d5642aa0a841f43ee9e0fc248c7d621ff4c23c5b90c50164192824bfea4a8017"},
    {"the 1,202 codes", 12, 1203,
     "c18987ea8e567e202d6fdb73053a8ab39225241df6130a79969f5c92865dd0b0"}
  ]

  setup_all do
    {:ok, documents: ToUnicodeMap.documents()}
  end

  test "every bfrange line keeps both rules", %{documents: documents} do
    broken =
      for {name, pdf} <- documents,
          {font, cmap} <- ToUnicodeMap.cmaps(pdf),
          line <- ToUnicodeMap.lines(cmap),
          not ToUnicodeMap.valid?(line),
          do: "#{name}, font object #{font}: <#{line.lo}> <#{line.hi}> <#{line.dst}>"

    assert broken == []
  end

  # A rule with nothing to match counts as passed, so each document built to
  # reach the boundaries must write bfrange lines that meet one.
  test "the documents built to straddle a block of 256 write lines that reach its last code",
       %{documents: documents} do
    for name <- [
          "whole font",
          "full_font field",
          "subset across 256 boundaries",
          "the 1,202 codes"
        ] do
      {^name, pdf} = List.keyfind(documents, name, 0)

      reaching =
        for {_font, cmap} <- ToUnicodeMap.cmaps(pdf),
            %{lo: lo, hi: hi} <- ToUnicodeMap.lines(cmap),
            Enum.any?(
              String.to_integer(lo, 16)..String.to_integer(hi, 16),
              &(rem(&1, 256) == 255)
            ),
            do: lo

      assert reaching != [], "#{name} has no bfrange line reaching the last code of a block"
    end
  end

  test "every code maps to what it mapped to in 0.4.1", %{documents: documents} do
    now =
      for {name, pdf} <- documents,
          {font, cmap} <- ToUnicodeMap.cmaps(pdf) do
        {count, sha} = ToUnicodeMap.digest(ToUnicodeMap.table(cmap))
        {name, font, count, sha}
      end

    assert now == @tables_at_0_4_1
  end
end

defmodule Tincture.PDFFixtureLockTest do
  @moduledoc """
  Locks the bytes of the fixture documents, twice.

  Exported with `compress: false`, each document must still be the bytes
  0.4.x wrote for it: `<name>.sha256` was pinned before streams were
  compressed and is unchanged, so this proves compression changed nothing
  else. Exported with the defaults, it is pinned by `<name>.compressed.sha256`.
  Both depend on the reference zlib; see `Tincture.ZlibCanaryTest`.
  """
  use ExUnit.Case

  alias Tincture.Test.FixtureDocuments

  for name <- FixtureDocuments.names() do
    test "#{name} fixture hash stays stable" do
      pdf_binary = FixtureDocuments.build(unquote(name))

      assert sha256_hex(pdf_binary) ==
               read_fixture_hash!("test/fixtures/pdf/#{unquote(name)}.compressed.sha256")
    end

    test "#{name} exported with compress: false keeps its 0.4.x hash" do
      pdf_binary = FixtureDocuments.build(unquote(name), compress: false)

      assert sha256_hex(pdf_binary) ==
               read_fixture_hash!("test/fixtures/pdf/#{unquote(name)}.sha256")
    end
  end

  defp read_fixture_hash!(path) do
    path
    |> File.read!()
    |> String.trim()
  end

  defp sha256_hex(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end
end

defmodule Tincture.PDFFixtureLockTest do
  use ExUnit.Case

  alias Tincture.Test.FixtureDocuments

  for name <- FixtureDocuments.names() do
    test "#{name} fixture hash stays stable" do
      pdf_binary = FixtureDocuments.build(unquote(name))

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

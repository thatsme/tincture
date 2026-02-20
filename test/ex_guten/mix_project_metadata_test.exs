defmodule ExGuten.MixProjectMetadataTest do
  use ExUnit.Case, async: true

  test "hex metadata is configured for publishing" do
    config = Mix.Project.config()

    assert is_binary(config[:description])
    assert String.trim(config[:description]) != ""

    package = config[:package]
    assert is_list(package)

    assert Keyword.get(package, :licenses) == ["MIT"]

    links = Keyword.get(package, :links, %{})
    assert is_map(links)
    assert is_binary(links["GitHub"])
  end

  test "docs config includes readme extras" do
    docs = Mix.Project.config()[:docs]
    assert is_list(docs)
    assert "README.MD" in Keyword.get(docs, :extras, [])
  end
end

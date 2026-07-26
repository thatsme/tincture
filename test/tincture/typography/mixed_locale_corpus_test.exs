defmodule Tincture.Typography.MixedLocaleCorpusTest do
  use ExUnit.Case

  alias Tincture.Typography.LineBreak

  test "mixed-locale corpus fixtures remain stable" do
    corpus = load_corpus!("test/fixtures/hyphen/mixed_locale_corpus.exs")

    Enum.each(corpus, fn %{
                           text: text,
                           width: width,
                           opts: opts,
                           locale_by_word: locales,
                           expected: expected
                         } ->
      resolver = fn word -> Map.get(locales, word, :en_gb) end

      actual =
        LineBreak.break_text(
          text,
          "Courier",
          10,
          width,
          Keyword.merge([locale_resolver: resolver], opts)
        )

      assert actual == expected
    end)
  end

  defp load_corpus!(path) do
    {corpus, _binding} = Code.eval_file(path)

    unless is_list(corpus) do
      raise "mixed-locale corpus fixture must evaluate to a list"
    end

    corpus
  end
end

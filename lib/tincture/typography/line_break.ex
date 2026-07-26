defmodule Tincture.Typography.LineBreak do
  @moduledoc false

  alias Tincture.Font
  alias Tincture.Typography.Hyphen

  @type option ::
          {:hyphenate, boolean()}
          | {:locale, atom()}
          | {:locale_resolver, (String.t() -> atom())}
          | {:hyphen_left_min, pos_integer()}
          | {:hyphen_right_min, pos_integer()}

  @spec break_text(String.t(), String.t(), number(), number(), [option()]) :: [String.t()]
  def break_text(text, font_name, font_size, max_width, opts \\ [])
      when is_binary(text) and is_binary(font_name) and is_number(font_size) and font_size > 0 and
             is_number(max_width) and max_width > 0 and is_list(opts) do
    words = String.split(text, ~r/\s+/, trim: true)

    {lines, current} =
      Enum.reduce(words, {[], ""}, fn word, {acc_lines, acc_current} ->
        add_word(word, acc_lines, acc_current, font_name, font_size, max_width, opts)
      end)

    case current do
      "" -> lines
      _ -> lines ++ [current]
    end
  end

  defp add_word(word, lines, "", font_name, font_size, max_width, opts) do
    case split_word(word, font_name, font_size, max_width, opts) do
      [] ->
        {lines, ""}

      [single] ->
        {lines, single}

      many ->
        {lines ++ Enum.slice(many, 0, length(many) - 1), List.last(many)}
    end
  end

  defp add_word(word, lines, current, font_name, font_size, max_width, opts) do
    candidate = current <> " " <> word

    if fits?(candidate, font_name, font_size, max_width) do
      {lines, candidate}
    else
      add_word(word, lines ++ [current], "", font_name, font_size, max_width, opts)
    end
  end

  defp split_word(word, font_name, font_size, max_width, opts) do
    if fits?(word, font_name, font_size, max_width) do
      [word]
    else
      if Keyword.get(opts, :hyphenate, true) do
        locale = resolve_locale(word, opts)
        hyphen_opts = hyphen_options(opts)
        split_by_hyphenation(word, font_name, font_size, max_width, locale, hyphen_opts)
      else
        hard_split(word, font_name, font_size, max_width)
      end
    end
  end

  defp split_by_hyphenation(word, font_name, font_size, max_width, locale, hyphen_opts) do
    parts = Hyphen.hyphenate(word, locale, hyphen_opts)

    if length(parts) > 1 do
      fragments =
        parts
        |> Enum.with_index()
        |> Enum.map(fn {part, idx} ->
          if idx < length(parts) - 1, do: part <> "-", else: part
        end)

      pack_fragments(fragments, font_name, font_size, max_width, [])
    else
      hard_split(word, font_name, font_size, max_width)
    end
  end

  defp pack_fragments([], _font_name, _font_size, _max_width, acc), do: Enum.reverse(acc)

  defp pack_fragments([fragment | rest], font_name, font_size, max_width, acc) do
    case acc do
      [current | tail] ->
        candidate = current <> fragment

        if fits?(candidate, font_name, font_size, max_width) do
          pack_fragments(rest, font_name, font_size, max_width, [candidate | tail])
        else
          pack_fragments(rest, font_name, font_size, max_width, [fragment | acc])
        end

      [] ->
        pack_fragments(rest, font_name, font_size, max_width, [fragment])
    end
  end

  defp hard_split(word, font_name, font_size, max_width) do
    word
    |> String.graphemes()
    |> Enum.reduce({[], ""}, fn grapheme, {parts, current} ->
      candidate = current <> grapheme

      if current == "" or fits?(candidate, font_name, font_size, max_width) do
        {parts, candidate}
      else
        {parts ++ [current], grapheme}
      end
    end)
    |> then(fn {parts, current} ->
      case current do
        "" -> parts
        _ -> parts ++ [current]
      end
    end)
  end

  defp fits?(string, font_name, font_size, max_width) do
    Font.text_width(font_name, font_size, string) <= max_width
  end

  defp hyphen_options(opts) do
    []
    |> maybe_put(:left_min, Keyword.get(opts, :hyphen_left_min))
    |> maybe_put(:right_min, Keyword.get(opts, :hyphen_right_min))
  end

  defp resolve_locale(word, opts) do
    case Keyword.get(opts, :locale_resolver) do
      nil ->
        Keyword.get(opts, :locale, :en_gb)

      resolver when is_function(resolver, 1) ->
        resolver.(word)

      _other ->
        raise ArgumentError, "locale_resolver must be a function with arity 1"
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end

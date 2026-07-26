defmodule Tincture.Typography.Hyphen do
  @moduledoc false

  @type locale :: :en_gb | :da_dk | :fi_fi | :nb_no | :sv_se
  @type option :: {:left_min, pos_integer()} | {:right_min, pos_integer()}

  @spec hyphenate(String.t(), locale(), [option()]) :: [String.t()]
  def hyphenate(word, locale \\ :en_gb, opts \\ [])

  def hyphenate(word, _locale, _opts) when not is_binary(word), do: [word]
  def hyphenate(word, _locale, _opts) when byte_size(word) <= 4, do: [word]

  def hyphenate(_word, _locale, opts) when not is_list(opts),
    do: raise(ArgumentError, "hyphen options must be a keyword list")

  def hyphenate(word, locale, opts) do
    left_min =
      normalize_hyphen_min(Keyword.get(opts, :left_min, default_left_min(locale)), :left_min)

    right_min =
      normalize_hyphen_min(Keyword.get(opts, :right_min, default_right_min(locale)), :right_min)

    if String.match?(word, ~r/^[[:ascii:]]+$/) do
      lowercase = String.downcase(word)
      rules = rules(locale)

      hyphenated =
        case Map.get(rules.exceptions, lowercase) do
          nil -> hyphenate_with_rules(word, lowercase, rules)
          exception -> exception
        end

      hyphenated
      |> String.split("-")
      |> apply_hyphen_minima(left_min, right_min)
    else
      [word]
    end
  end

  defp normalize_hyphen_min(value, _field) when is_integer(value) and value > 0, do: value

  defp normalize_hyphen_min(_value, field),
    do: raise(ArgumentError, "#{field} must be a positive integer")

  defp default_left_min(:en_gb), do: 2
  defp default_left_min(:da_dk), do: 2
  defp default_left_min(:fi_fi), do: 2
  defp default_left_min(:nb_no), do: 2
  defp default_left_min(:sv_se), do: 2

  defp default_right_min(:en_gb), do: 2
  defp default_right_min(:da_dk), do: 2
  defp default_right_min(:fi_fi), do: 2
  defp default_right_min(:nb_no), do: 2
  defp default_right_min(:sv_se), do: 2

  defp apply_hyphen_minima(parts, _left_min, _right_min) when length(parts) <= 1, do: parts

  defp apply_hyphen_minima(parts, left_min, right_min) do
    lengths = Enum.map(parts, &byte_size/1)
    total_len = Enum.sum(lengths)

    valid_breakpoints =
      lengths
      |> Enum.drop(-1)
      |> Enum.with_index(1)
      |> Enum.reduce({MapSet.new(), 0}, fn {len, idx}, {set, prefix} ->
        prefix_len = prefix + len
        suffix_len = total_len - prefix_len

        updated =
          if prefix_len >= left_min and suffix_len >= right_min,
            do: MapSet.put(set, idx),
            else: set

        {updated, prefix_len}
      end)
      |> elem(0)

    parts
    |> Enum.with_index()
    |> Enum.reduce([], fn
      {part, 0}, [] ->
        [part]

      {part, idx}, [current | tail] ->
        if MapSet.member?(valid_breakpoints, idx) do
          [part, current | tail]
        else
          [current <> part | tail]
        end
    end)
    |> Enum.reverse()
  end

  defp hyphenate_with_rules(original, lowercase, rules) do
    marks =
      ("." <> lowercase <> ".")
      |> collect_marks(0, %{}, rules)
      |> Enum.filter(fn {_pos, count} -> rem(count, 2) == 1 end)
      |> Enum.sort_by(fn {pos, _count} -> pos end)
      |> Enum.map(fn {pos, _count} -> pos end)

    original
    |> insert_marks(marks)
    |> remove_singleton()
    |> List.to_string()
  end

  defp collect_marks("", _n, marks, _rules), do: marks

  defp collect_marks(suffix, n, marks, rules) do
    marks =
      suffix
      |> hyphens_for_suffix(rules)
      |> Enum.reduce(marks, fn {pos, val}, acc ->
        abs_pos = pos + n
        current = Map.get(acc, abs_pos, -1)

        if val > current do
          Map.put(acc, abs_pos, val)
        else
          acc
        end
      end)

    collect_marks(binary_part(suffix, 1, byte_size(suffix) - 1), n + 1, marks, rules)
  end

  defp hyphens_for_suffix("", _rules), do: []

  defp hyphens_for_suffix(suffix, rules) do
    first_char = binary_part(suffix, 0, 1)

    rules.hyphens_by_first
    |> Map.get(first_char, [])
    |> Enum.find_value([], fn {prefix, pairs} ->
      if binary_starts_with?(suffix, prefix), do: pairs
    end)
  end

  defp insert_marks(word, marks) do
    mark_set = MapSet.new(marks)

    word
    |> String.to_charlist()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {char, index} ->
      if MapSet.member?(mark_set, index) do
        [?-, char]
      else
        [char]
      end
    end)
  end

  defp remove_singleton([head, ?- | tail]), do: [head | remove_singleton1(tail)]
  defp remove_singleton([?- | tail]), do: remove_singleton1(tail)
  defp remove_singleton(chars), do: remove_singleton1(chars)

  defp remove_singleton1([?-]), do: []
  defp remove_singleton1([?-, head]), do: [head]
  defp remove_singleton1([head | tail]), do: [head | remove_singleton1(tail)]
  defp remove_singleton1([]), do: []

  defp rules(locale) do
    key = {__MODULE__, locale}

    case :persistent_term.get(key, :missing) do
      :missing ->
        loaded = load_rules(locale)
        :persistent_term.put(key, loaded)
        loaded

      loaded ->
        loaded
    end
  end

  defp load_rules(:en_gb) do
    rules_path = Application.app_dir(:tincture, "priv/hyphen_rules/eg_hyphen_rules_en_GB.erl")
    parse_rule_file(rules_path)
  end

  defp load_rules(:da_dk) do
    rules_path = Application.app_dir(:tincture, "priv/hyphen/hyph_da_DK.dic")
    parse_dic_file(rules_path)
  end

  defp load_rules(:fi_fi) do
    rules_path = Application.app_dir(:tincture, "priv/hyphen/hyph_fi_FI.dic")
    parse_dic_file(rules_path)
  end

  defp load_rules(:nb_no) do
    rules_path = Application.app_dir(:tincture, "priv/hyphen/hyph_nb_NO.dic")
    parse_dic_file(rules_path)
  end

  defp load_rules(:sv_se) do
    rules_path = Application.app_dir(:tincture, "priv/hyphen/hyph_sv_SE.dic")
    parse_dic_file(rules_path)
  end

  defp load_rules(locale) do
    raise ArgumentError, "unsupported hyphen locale: #{inspect(locale)}"
  end

  defp parse_rule_file(path) do
    {exceptions, hyphens_by_first_rev} =
      path
      |> File.stream!([], :line)
      |> Enum.reduce({%{}, %{}}, fn raw_line, {exceptions_acc, hyphens_acc} ->
        line = String.trim(raw_line)

        case Regex.run(~r/^exception\("([^"]+)"\)\s*->\s*"([^"]+)";$/, line,
               capture: :all_but_first
             ) do
          [word, hyphenated] ->
            {Map.put(exceptions_acc, word, hyphenated), hyphens_acc}

          _ ->
            case Regex.run(~r/^hyphens\("([^"]+)"\s*\+\+\s*_\)->\[(.*)\];$/, line,
                   capture: :all_but_first
                 ) do
              [prefix, tuple_body] ->
                pairs = parse_pairs(tuple_body)
                first_char = binary_part(prefix, 0, 1)

                updated =
                  Map.update(hyphens_acc, first_char, [{prefix, pairs}], &[{prefix, pairs} | &1])

                {exceptions_acc, updated}

              _ ->
                {exceptions_acc, hyphens_acc}
            end
        end
      end)

    hyphens_by_first =
      hyphens_by_first_rev
      |> Enum.into(%{}, fn {first_char, clauses} ->
        {first_char, Enum.reverse(clauses)}
      end)

    %{exceptions: exceptions, hyphens_by_first: hyphens_by_first}
  end

  defp parse_pairs(tuple_body) do
    Regex.scan(~r/\{(\d+),(\d+)\}/, tuple_body, capture: :all_but_first)
    |> Enum.map(fn [pos, val] ->
      {String.to_integer(pos), String.to_integer(val)}
    end)
  end

  defp parse_dic_file(path) do
    {:ok, content} = File.read(path)

    {exceptions, hyphens_by_first_rev} =
      content
      |> :binary.split("\n", [:global])
      |> Enum.reduce({%{}, %{}}, fn raw_line, {exceptions_acc, hyphens_acc} ->
        line = trim_ascii_whitespace(raw_line)

        cond do
          line == "" ->
            {exceptions_acc, hyphens_acc}

          line == "ISO8859-1" ->
            {exceptions_acc, hyphens_acc}

          binary_starts_with?(line, "%") ->
            {exceptions_acc, hyphens_acc}

          has_digit?(line) ->
            case parse_dic_pattern(line) do
              {:ok, prefix, pairs} ->
                first_char = binary_part(prefix, 0, 1)

                updated =
                  Map.update(hyphens_acc, first_char, [{prefix, pairs}], &[{prefix, pairs} | &1])

                {exceptions_acc, updated}

              :error ->
                {exceptions_acc, hyphens_acc}
            end

          binary_contains?(line, "-") ->
            key = line |> :binary.replace("-", "", [:global]) |> lowercase_ascii()
            {Map.put(exceptions_acc, key, line), hyphens_acc}

          true ->
            {exceptions_acc, hyphens_acc}
        end
      end)

    hyphens_by_first =
      hyphens_by_first_rev
      |> Enum.into(%{}, fn {first_char, entries} ->
        {first_char, Enum.sort_by(entries, fn {prefix, _pairs} -> -byte_size(prefix) end)}
      end)

    %{exceptions: exceptions, hyphens_by_first: hyphens_by_first}
  end

  defp parse_dic_pattern(line) when is_binary(line) and byte_size(line) > 0 do
    {prefix_rev, pairs_rev, _index} =
      line
      |> :binary.bin_to_list()
      |> Enum.reduce({[], [], 0}, fn byte, {prefix_acc, pairs_acc, index} ->
        cond do
          byte >= ?0 and byte <= ?9 ->
            {prefix_acc, [{index, byte - ?0} | pairs_acc], index}

          true ->
            {[byte | prefix_acc], pairs_acc, index + 1}
        end
      end)

    prefix = prefix_rev |> Enum.reverse() |> :erlang.list_to_binary()
    pairs = pairs_rev |> Enum.reverse() |> merge_same_position_pairs()

    if byte_size(prefix) > 0 and pairs != [] do
      {:ok, prefix, pairs}
    else
      :error
    end
  end

  defp parse_dic_pattern(_), do: :error

  defp merge_same_position_pairs(pairs) do
    pairs
    |> Enum.reduce(%{}, fn {pos, val}, acc ->
      current = Map.get(acc, pos, -1)
      if val > current, do: Map.put(acc, pos, val), else: acc
    end)
    |> Enum.sort_by(fn {pos, _} -> pos end)
  end

  defp trim_ascii_whitespace(binary) when is_binary(binary) do
    binary
    |> trim_left_ascii_whitespace()
    |> trim_right_ascii_whitespace()
  end

  defp trim_left_ascii_whitespace(<<" ", rest::binary>>), do: trim_left_ascii_whitespace(rest)
  defp trim_left_ascii_whitespace(<<"\t", rest::binary>>), do: trim_left_ascii_whitespace(rest)
  defp trim_left_ascii_whitespace(<<"\r", rest::binary>>), do: trim_left_ascii_whitespace(rest)
  defp trim_left_ascii_whitespace(binary), do: binary

  defp trim_right_ascii_whitespace(binary),
    do: do_trim_right_ascii_whitespace(binary, byte_size(binary))

  defp do_trim_right_ascii_whitespace(_binary, 0), do: ""

  defp do_trim_right_ascii_whitespace(binary, len) do
    last = binary_part(binary, len - 1, 1)

    if last in [" ", "\t", "\r"] do
      do_trim_right_ascii_whitespace(binary, len - 1)
    else
      binary_part(binary, 0, len)
    end
  end

  defp has_digit?(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.any?(fn byte -> byte >= ?0 and byte <= ?9 end)
  end

  defp lowercase_ascii(binary) do
    for <<byte <- binary>>, into: <<>> do
      if byte >= ?A and byte <= ?Z, do: <<byte + 32>>, else: <<byte>>
    end
  end

  defp binary_starts_with?(binary, prefix)
       when is_binary(binary) and is_binary(prefix) and byte_size(prefix) <= byte_size(binary) do
    binary_part(binary, 0, byte_size(prefix)) == prefix
  end

  defp binary_starts_with?(_binary, _prefix), do: false

  defp binary_contains?(binary, needle) when is_binary(binary) and is_binary(needle) do
    :binary.match(binary, needle) != :nomatch
  end
end

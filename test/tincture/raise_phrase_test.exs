defmodule Tincture.RaisePhraseTest do
  @moduledoc """
  "This will raise in 0.4.0" marks a warning that 0.4.0 turns into an error.
  Stage 1 converted W1-W4, so the phrase is left only in the three 0.3.6
  form warnings, J1, J2 and J4. Later stages convert those, and lower the
  count here, until it is zero.

  The phrase can be split across a `<>` (J2's is), so the source is not
  grepped line by line. Each file in lib/ is parsed, every chain of literal
  strings joined with `<>` is folded into one string, interpolations become a
  placeholder, and the phrase is counted in the folded strings.
  """
  use ExUnit.Case, async: true

  @phrase "This will raise in 0.4.0"

  # The leading text that identifies each remaining warning's message.
  @remaining %{
    j1: "has no tooltip",
    j2: "is not in the structure tree",
    j4: "uses the standard font"
  }

  test "the phrase is left only in J1, J2 and J4, once each" do
    found =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn path -> path |> File.read!() |> folded_strings() end)
      |> Enum.filter(&String.contains?(&1, @phrase))

    owners =
      Enum.map(found, fn string ->
        Enum.find_value(@remaining, :unknown, fn {name, lead} ->
          if String.contains?(string, lead), do: name
        end)
      end)

    assert length(found) == 3
    assert Enum.sort(owners) == [:j1, :j2, :j4]
  end

  test "self-check: a literal split across <> is found, and so is one with interpolation" do
    source = ~S'''
    defmodule Fixture do
      def a, do: IO.warn("split here. This will raise " <> "in 0.4.0.")
      def b(x), do: IO.warn("named #{x} and " <> "then This will raise in 0.4.0.")
      def c, do: IO.warn("unrelated")
    end
    '''

    found = source |> folded_strings() |> Enum.filter(&String.contains?(&1, @phrase))

    assert length(found) == 2
    assert Enum.any?(found, &String.starts_with?(&1, "split here."))
    assert Enum.any?(found, &String.starts_with?(&1, "named "))
  end

  # Every maximal string expression in the source, folded: a literal binary,
  # an interpolated string, or a <> chain of those.
  defp folded_strings(source) do
    {:ok, ast} = Code.string_to_quoted(source)

    {_ast, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        case fold(node) do
          {:ok, string} when is_tuple(node) -> {:folded, [string | acc]}
          {:ok, string} -> {node, [string | acc]}
          :error -> {node, acc}
        end
      end)

    acc
  end

  defp fold(string) when is_binary(string), do: {:ok, string}

  defp fold({:<>, _meta, [left, right]}) do
    with {:ok, l} <- fold(left), {:ok, r} <- fold(right), do: {:ok, l <> r}
  end

  defp fold({:<<>>, _meta, parts}) do
    {:ok, Enum.map_join(parts, fn part -> if is_binary(part), do: part, else: "￼" end)}
  end

  defp fold(_other), do: :error
end

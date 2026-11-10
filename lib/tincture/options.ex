defmodule Tincture.Options do
  @moduledoc false

  # The one check of a public function's keyword options against the keys it
  # reads. An unknown key, such as a misspelt `tooltp:`, was ignored without a
  # word: the call went ahead as if it had not been given. Each function names
  # itself and its known keys; a call warns once, naming every unknown key.
  # 0.5.0 warns, and 0.6.0 will raise.
  #
  # A function that forwards its options to another public function passes on
  # only the keys that function reads, so a call warns once, under the name of
  # the function the caller called.

  @doc false
  # Warns once, with IO.warn/1, if `opts` carries a key not in `known`.
  # Entries that are not `{key, value}` pairs are left to the function.
  @spec warn_unknown(term(), String.t(), [atom()]) :: :ok
  def warn_unknown(opts, function, known), do: warn_unknown(function, [{"option", opts, known}])

  @doc false
  # The same for a function with more than one keyword list, such as a radio
  # group's options and each button's: `groups` is `{noun, opts, known}` per
  # list, and the one warning names the unknown keys of every list.
  @spec warn_unknown(String.t(), [{String.t(), term(), [atom()]}]) :: :ok
  def warn_unknown(function, groups) do
    found = Enum.map(groups, fn {noun, opts, known} -> {noun, unknown(opts, known), known} end)

    if Enum.any?(found, fn {_noun, unknown, _known} -> unknown != [] end) do
      IO.warn(
        message(function, found) <> " Unknown options are ignored now; this will raise in 0.6.0."
      )
    end

    :ok
  end

  @doc false
  # `opts` with only the keys in `known`, in order: what a function passes on
  # to another that reads those keys, so the other does not warn again about
  # a key the caller was already told of, or about one the first function
  # reads itself. Entries that are not `{key, value}` pairs are kept, as they
  # were passed on before.
  @spec known(list(), [atom()]) :: list()
  def known(opts, known) when is_list(opts) do
    Enum.filter(opts, fn
      {key, _value} -> key in known
      _other -> true
    end)
  end

  @doc false
  # The keys of `opts` not in `known`, each once, in the order given.
  @spec unknown(term(), [atom()]) :: [term()]
  def unknown(opts, known) when is_list(opts) do
    opts
    |> Enum.flat_map(fn
      {key, _value} -> if key in known, do: [], else: [key]
      _other -> []
    end)
    |> Enum.uniq()
  end

  def unknown(_opts, _known), do: []

  @doc false
  # "<function> got the unknown option :a. Known options: :b, :c." With more
  # than one list, every list's unknown keys, then every list's known keys.
  @spec message(String.t(), [{String.t(), [term()], [atom()]}]) :: String.t()
  def message(function, found) do
    unknown =
      found
      |> Enum.reject(fn {_noun, unknown, _known} -> unknown == [] end)
      |> Enum.map_join(" and ", fn {noun, unknown, _known} ->
        "the unknown #{key_list(noun, unknown)}"
      end)

    known =
      Enum.map_join(found, " ", fn {noun, _unknown, known} ->
        "Known #{noun}s: #{Enum.map_join(known, ", ", &inspect/1)}."
      end)

    "#{function} got #{unknown}. #{known}"
  end

  defp key_list(noun, [key]), do: "#{noun} #{inspect(key)}"

  defp key_list(noun, keys) do
    {init, [last]} = Enum.split(keys, -1)
    "#{noun}s #{Enum.map_join(init, ", ", &inspect/1)} and #{inspect(last)}"
  end
end

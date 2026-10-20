defmodule Tincture.Test.ApiSnapshot do
  @moduledoc """
  The types and specs of Tincture's documented API, as text that compares
  equal across the Elixir versions CI runs (1.16 to 1.19).

  Recorded:

    * every `@type` and `@opaque` of every module of the `:tincture`
      application that is built from `lib/` and whose documentation is shown,
      meaning `Code.fetch_docs/1` gives a moduledoc that is not `:hidden`.
      `@typep` is not recorded;
    * the `@spec` of every function in a given list, the documented API.

  Each definition is rendered with `Code.Typespec.type_to_quoted/1` or
  `Code.Typespec.spec_to_quoted/2`, stripped of AST metadata, and turned into
  a string with `Macro.to_string/1`. The string is then normalised:

    * every run of whitespace, line breaks included, becomes one space;
    * the space after `(`, `[` or `{` and before `)`, `]` or `}` is removed.

  `Macro.to_string/1` formats through the code formatter, which may break a
  long definition across lines differently from one version to another. The
  normalisation makes that wrapping irrelevant.
  """

  @doc """
  The documented modules, sorted.
  """
  @spec documented_modules() :: [module()]
  def documented_modules do
    (Application.spec(:tincture, :modules) || [])
    |> Enum.filter(&(Code.ensure_loaded?(&1) and in_lib?(&1) and shown?(&1)))
    |> Enum.sort()
  end

  @doc """
  Whether `module` was compiled from a source file under `lib/`. In the test
  environment, test/support is compiled into the :tincture application too,
  and only modules built from lib/ are published.
  """
  @spec in_lib?(module()) :: boolean()
  def in_lib?(module) do
    source = module.module_info(:compile) |> Keyword.get(:source, ~c"") |> to_string()
    source |> Path.relative_to_cwd() |> String.starts_with?("lib/")
  end

  defp shown?(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _anno, _language, _format, moduledoc, _metadata, _docs} ->
        moduledoc != :hidden

      _no_docs ->
        false
    end
  end

  @doc """
  Every recorded entry, as `{key, definition}`, sorted by key. A key reads
  `"type Mod.name/arity"`, `"opaque Mod.name/arity"` or
  `"spec Mod.name/arity"`. A function in `functions` with no `@spec` has no
  entry.
  """
  @spec entries([{module(), atom(), arity()}]) :: [{String.t(), String.t()}]
  def entries(functions) do
    (types() ++ specs(functions)) |> Enum.sort()
  end

  defp types do
    for module <- documented_modules(),
        {:ok, types} <- [Code.Typespec.fetch_types(module)],
        {kind, typedef} <- types,
        kind in [:type, :opaque] do
      {:"::", _meta, [{name, _name_meta, args}, _body]} =
        quoted = Code.Typespec.type_to_quoted(typedef)

      {"#{kind} #{inspect(module)}.#{name}/#{length(args || [])}", render(quoted)}
    end
  end

  defp specs(functions) do
    functions
    |> Enum.group_by(fn {module, _name, _arity} -> module end)
    |> Enum.flat_map(fn {module, entries} ->
      specs =
        case Code.Typespec.fetch_specs(module) do
          {:ok, specs} -> Map.new(specs)
          :error -> %{}
        end

      for {^module, name, arity} <- entries,
          clauses = Map.get(specs, {name, arity}),
          clauses != nil do
        definition =
          Enum.map_join(clauses, " ; ", &render(Code.Typespec.spec_to_quoted(name, &1)))

        {"spec #{inspect(module)}.#{name}/#{arity}", definition}
      end
    end)
  end

  @doc """
  A quoted definition rendered and normalised.
  """
  @spec render(Macro.t()) :: String.t()
  def render(quoted) do
    quoted
    |> Macro.prewalk(&Macro.update_meta(&1, fn _meta -> [] end))
    |> Macro.to_string()
    |> normalise()
  end

  @doc """
  The normalisation applied to every rendered definition.
  """
  @spec normalise(String.t()) :: String.t()
  def normalise(string) do
    string
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/([(\[{]) /, "\\1")
    |> String.replace(~r/ ([)\]}])/, "\\1")
    |> String.trim()
  end

  @doc """
  The snapshot file the public API test reads.
  """
  @spec path() :: String.t()
  def path, do: "test/fixtures/public_api_types.txt"

  @doc """
  The documented functions, as `test/public_api_test.exs` lists them in
  `@public_api`, read from that file's source.
  """
  @spec public_api() :: [{module(), atom(), arity()}]
  def public_api do
    {:ok, ast} = Code.string_to_quoted(File.read!("test/public_api_test.exs"))

    {_ast, list} =
      Macro.prewalk(ast, nil, fn
        {:@, _, [{:public_api, _, [list]}]} = node, nil -> {node, list}
        node, acc -> {node, acc}
      end)

    Enum.map(list, fn {:{}, _, [{:__aliases__, _, parts}, name, arity]} ->
      {Module.concat(parts), name, arity}
    end)
  end

  @doc """
  Regenerates the snapshot file from the tree it runs in. Run it in a
  worktree of the release the snapshot is anchored to:

      MIX_ENV=test mix run -e "Tincture.Test.ApiSnapshot.write!()"
  """
  @spec write!(String.t()) :: :ok
  def write!(file \\ path()) do
    File.write!(file, public_api() |> entries() |> to_text())
  end

  @doc """
  The entries as the snapshot file stores them: one per line,
  `key<TAB>definition`.
  """
  @spec to_text([{String.t(), String.t()}]) :: String.t()
  def to_text(entries) do
    Enum.map_join(entries, "", fn {key, definition} -> "#{key}\t#{definition}\n" end)
  end

  @doc """
  Parses the snapshot file's text back into `{key, definition}` entries.
  """
  @spec from_text(String.t()) :: [{String.t(), String.t()}]
  def from_text(text) do
    for line <- String.split(text, "\n", trim: true) do
      [key, definition] = String.split(line, "\t", parts: 2)
      {key, definition}
    end
  end

  @doc """
  What breaks the snapshot: each recorded entry that is now missing, or whose
  definition changed. New entries are not reported.
  """
  @spec mismatches([{String.t(), String.t()}], [{String.t(), String.t()}]) ::
          [{:missing, String.t()} | {:changed, String.t(), String.t(), String.t()}]
  def mismatches(snapshot, live) do
    live = Map.new(live)

    for {key, recorded} <- snapshot,
        mismatch = compare(key, recorded, Map.fetch(live, key)),
        mismatch != nil,
        do: mismatch
  end

  defp compare(_key, recorded, {:ok, recorded}), do: nil
  defp compare(key, recorded, {:ok, now}), do: {:changed, key, recorded, now}
  defp compare(key, _recorded, :error), do: {:missing, key}
end

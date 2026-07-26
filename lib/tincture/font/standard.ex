defmodule Tincture.Font.Standard do
  @moduledoc false

  @registry_key {__MODULE__, :registry}

  @base_14 [
    "Courier",
    "Courier-Bold",
    "Courier-Oblique",
    "Courier-BoldOblique",
    "Helvetica",
    "Helvetica-Bold",
    "Helvetica-Oblique",
    "Helvetica-BoldOblique",
    "Times-Roman",
    "Times-Bold",
    "Times-Italic",
    "Times-BoldItalic",
    "Symbol",
    "ZapfDingbats"
  ]

  @spec names() :: [String.t()]
  def names, do: @base_14

  @spec standard_font?(String.t()) :: boolean()
  def standard_font?(font_name) when is_binary(font_name) do
    font_name in @base_14
  end

  @spec fetch_metrics(String.t()) ::
          {:ok,
           %{
             widths_by_code: %{optional(integer()) => number()},
             kern_by_code: %{optional({integer(), integer()}) => number()}
           }}
          | :error
  def fetch_metrics(font_name) when is_binary(font_name) do
    case Map.fetch(registry(), font_name) do
      {:ok, metrics} -> {:ok, metrics}
      :error -> :error
    end
  end

  @spec reload() :: :ok
  def reload do
    :persistent_term.put(@registry_key, build_registry())
    :ok
  end

  defp registry do
    case :persistent_term.get(@registry_key, :missing) do
      :missing ->
        map = build_registry()
        :persistent_term.put(@registry_key, map)
        map

      map ->
        map
    end
  end

  defp build_registry do
    Path.join(Application.app_dir(:tincture, "priv/standard_fonts"), "eg_font_*.erl")
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn path, acc ->
      case parse_module_file(path) do
        {:ok, {font_name, metrics}} -> Map.put(acc, font_name, metrics)
        :error -> acc
      end
    end)
  end

  defp parse_module_file(path) do
    contents = File.read!(path)

    with {:ok, font_name} <- parse_font_name(contents) do
      widths = parse_widths(contents)
      kerns = parse_kerns(contents)
      {:ok, {font_name, %{widths_by_code: widths, kern_by_code: kerns}}}
    else
      _ -> :error
    end
  end

  defp parse_font_name(contents) do
    case Regex.run(~r/fontName\(\)\s*->\s*"([^"]+)"\./, contents, capture: :all_but_first) do
      [name] -> {:ok, name}
      _ -> :error
    end
  end

  defp parse_widths(contents) do
    Regex.scan(~r/^width\((\d+)\)->(-?\d+);$/m, contents, capture: :all_but_first)
    |> Enum.reduce(%{}, fn [code, value], acc ->
      Map.put(acc, String.to_integer(code), String.to_integer(value))
    end)
  end

  defp parse_kerns(contents) do
    Regex.scan(~r/^kern\((\d+),(\d+)\)->(-?\d+);$/m, contents, capture: :all_but_first)
    |> Enum.reduce(%{}, fn [left, right, value], acc ->
      Map.put(acc, {String.to_integer(left), String.to_integer(right)}, String.to_integer(value))
    end)
  end
end

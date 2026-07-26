defmodule Tincture.Font.Metrics do
  @moduledoc false

  alias Tincture.Font.AFM

  @registry_key {__MODULE__, :registry}

  @spec registered_fonts() :: [String.t()]
  def registered_fonts do
    registry()
    |> Map.keys()
    |> Enum.sort()
  end

  @spec fetch_afm(String.t()) :: {:ok, AFM.t()} | :error
  def fetch_afm(font_name) when is_binary(font_name) do
    case Map.fetch(registry(), font_name) do
      {:ok, afm} -> {:ok, afm}
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
    Path.join(Application.app_dir(:tincture, "priv/afm"), "*.afm")
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn path, acc ->
      afm = AFM.parse_file(path)

      if is_binary(afm.font_name) and afm.font_name != "" do
        Map.put(acc, afm.font_name, afm)
      else
        acc
      end
    end)
  end
end

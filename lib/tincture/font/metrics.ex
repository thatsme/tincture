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

  @doc """
  Where AFM font metrics are loaded from.

  Defaults to `priv/afm` inside the application. Point it elsewhere to make
  your own AFM fonts available by name:

      config :tincture, afm_path: "priv/fonts/afm"

  Tincture ships no AFM fonts itself — the PDF Standard 14 metrics live in
  `priv/standard_fonts` and are always available.
  """
  @spec afm_path() :: Path.t()
  def afm_path do
    Application.get_env(:tincture, :afm_path, Application.app_dir(:tincture, "priv/afm"))
  end

  defp build_registry do
    Path.join(afm_path(), "*.afm")
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

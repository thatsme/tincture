defmodule Examples.Fonts do
  @moduledoc """
  Finds a real TrueType font to embed, wherever the example is being run.

  The examples embed fonts on purpose — subsetting and measuring an embedded
  font is most of what makes the output worth looking at — but font paths are
  not portable. This picks the first candidate that exists, so the same script
  produces a sensible document on macOS, on a Linux CI box, or on a machine
  with neither font family installed.
  """

  @serif [
    "/System/Library/Fonts/Supplemental/Georgia.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
    "/usr/share/fonts/TTF/DejaVuSerif.ttf"
  ]

  @sans [
    "/System/Library/Fonts/Supplemental/Verdana.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf"
  ]

  @doc """
  A path to a serif TrueType font, or `nil` if none of the candidates exist.
  """
  def serif, do: Enum.find(@serif, &File.exists?/1)

  @doc """
  A path to a sans TrueType font, or `nil` if none of the candidates exist.
  """
  def sans, do: Enum.find(@sans, &File.exists?/1)

  @doc """
  Register `body` and `heading` fonts on a document.

  Returns `{pdf, embedded?}`. When no TrueType font can be found the names are
  left unregistered, which makes them resolve to the standard 14 — the example
  still renders, it just stops demonstrating embedding, and says so.
  """
  def register(pdf, body_name, sans_name) do
    case {serif(), sans()} do
      {nil, _} ->
        {pdf, false}

      {_, nil} ->
        {pdf, false}

      {serif_path, sans_path} ->
        pdf =
          pdf
          |> Tincture.register_ttf_font(body_name, serif_path)
          |> Tincture.register_ttf_font(sans_name, sans_path)

        {pdf, true}
    end
  end

  @doc """
  Fall back to standard fonts when nothing could be embedded, so an example
  never draws with a font name the document does not know.
  """
  def resolve(name, false) when name in ["Body"], do: "Times-Roman"
  def resolve(name, false) when name in ["Sans"], do: "Helvetica"
  def resolve(name, _embedded?), do: name

  @doc """
  Where an example writes its result. Committed, so the repository shows what
  each script produces without anyone having to run it.
  """
  def output_path(filename) do
    dir = Path.join(__DIR__, "../output") |> Path.expand()
    File.mkdir_p!(dir)
    Path.join(dir, filename)
  end
end

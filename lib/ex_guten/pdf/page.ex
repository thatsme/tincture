defmodule ExGuten.PDF.Page do
  @moduledoc false

  @spec media_box(:a4 | :letter | :legal | {number(), number()}) :: {number(), number()}
  def media_box(:a4), do: {595, 842}
  def media_box(:letter), do: {612, 792}
  def media_box(:legal), do: {612, 1008}
  def media_box({width, height}), do: {width, height}
end

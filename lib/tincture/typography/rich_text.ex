defmodule Tincture.Typography.RichText do
  @moduledoc false

  alias Tincture.Font

  defmodule Run do
    @moduledoc false

    @type t :: %__MODULE__{
            text: String.t(),
            font: String.t(),
            size: number(),
            style: atom() | nil
          }

    defstruct text: "",
              font: "Helvetica",
              size: 12,
              style: nil
  end

  defmodule Word do
    @moduledoc false

    @type t :: %__MODULE__{
            text: String.t(),
            font: String.t(),
            size: number(),
            style: atom() | nil,
            width: number()
          }

    defstruct text: "",
              font: "Helvetica",
              size: 12,
              style: nil,
              width: 0
  end

  defmodule Space do
    @moduledoc false

    @type t :: %__MODULE__{
            text: String.t(),
            font: String.t(),
            size: number(),
            style: atom() | nil,
            width: number()
          }

    defstruct text: " ",
              font: "Helvetica",
              size: 12,
              style: nil,
              width: 0
  end

  defmodule Break do
    @moduledoc false

    @type t :: %__MODULE__{kind: :line}
    defstruct kind: :line
  end

  @type token :: Word.t() | Space.t() | Break.t()

  @type t :: %__MODULE__{
          runs: [Run.t()],
          tokens: [token()]
        }

  defstruct runs: [],
            tokens: []

  @spec from_plain(String.t(), keyword()) :: t()
  def from_plain(text, opts \\ []) when is_binary(text) and is_list(opts) do
    run = %Run{
      text: text,
      font: Keyword.get(opts, :font, "Helvetica"),
      size: Keyword.get(opts, :size, 12),
      style: Keyword.get(opts, :style)
    }

    from_runs([run])
  end

  @spec from_runs([Run.t()]) :: t()
  def from_runs(runs) when is_list(runs) do
    normalized =
      runs
      |> Enum.map(fn
        %Run{} = run -> run
        map when is_map(map) -> struct!(Run, map)
      end)

    %__MODULE__{
      runs: normalized,
      tokens: tokenize_runs(normalized)
    }
  end

  @spec from_tokens([token()]) :: t()
  def from_tokens(tokens) when is_list(tokens) do
    normalized =
      Enum.map(tokens, fn
        %Word{} = token ->
          token

        %Space{} = token ->
          token

        %Break{} = token ->
          token

        map when is_map(map) ->
          cond do
            Map.get(map, :kind) == :line ->
              struct!(Break, map)

            Map.has_key?(map, :width) and Map.get(map, :text, " ") in [" ", "\t"] ->
              struct!(Space, map)

            Map.has_key?(map, :width) ->
              struct!(Word, map)

            true ->
              raise ArgumentError, "invalid rich-text token: #{inspect(map)}"
          end
      end)

    runs = tokens_to_runs(normalized)
    from_runs(runs)
  end

  defp tokenize_runs(runs) do
    {tokens, current_word} =
      Enum.reduce(runs, {[], nil}, fn run, {acc_tokens, acc_word} ->
        tokenize_run(run, acc_tokens, acc_word)
      end)

    maybe_emit_word(tokens, current_word)
  end

  defp tokens_to_runs(tokens) do
    {runs, current_run} =
      Enum.reduce(tokens, {[], nil}, fn token, {acc_runs, acc_current} ->
        token_to_runs(token, acc_runs, acc_current)
      end)

    maybe_emit_run(runs, current_run)
  end

  defp token_to_runs(%Break{}, runs, nil) do
    {runs, %Run{text: "\n"}}
  end

  defp token_to_runs(%Break{}, runs, %Run{} = current_run) do
    {runs, %Run{current_run | text: current_run.text <> "\n"}}
  end

  defp token_to_runs(%Word{} = token, runs, current_run) do
    append_token_run(token, runs, current_run)
  end

  defp token_to_runs(%Space{} = token, runs, current_run) do
    append_token_run(token, runs, current_run)
  end

  defp append_token_run(token, runs, nil) do
    run = %Run{text: token.text, font: token.font, size: token.size, style: token.style}
    {runs, run}
  end

  defp append_token_run(token, runs, %Run{} = current_run) do
    if current_run.font == token.font and current_run.size == token.size and
         current_run.style == token.style do
      {runs, %Run{current_run | text: current_run.text <> token.text}}
    else
      new_run = %Run{text: token.text, font: token.font, size: token.size, style: token.style}
      {runs ++ [current_run], new_run}
    end
  end

  defp maybe_emit_run(runs, nil), do: runs
  defp maybe_emit_run(runs, %Run{} = run), do: runs ++ [run]

  defp tokenize_run(%Run{} = run, tokens, current_word) do
    run.text
    |> String.to_charlist()
    |> Enum.reduce({tokens, current_word}, fn ch, {acc_tokens, acc_word} ->
      cond do
        ch == ?\n ->
          tokens_with_word = maybe_emit_word(acc_tokens, acc_word)
          {tokens_with_word ++ [%Break{}], nil}

        ch == ?\s or ch == ?\t ->
          tokens_with_word = maybe_emit_word(acc_tokens, acc_word)
          space_text = <<ch::utf8>>
          {tokens_with_word ++ [space_token(space_text, run)], nil}

        true ->
          part = <<ch::utf8>>

          case acc_word do
            nil ->
              {acc_tokens, word_token(part, run)}

            %Word{} = word ->
              if same_style?(word, run) do
                {acc_tokens,
                 %Word{word | text: word.text <> part, width: width(word.text <> part, run)}}
              else
                {acc_tokens ++ [word], word_token(part, run)}
              end
          end
      end
    end)
  end

  defp maybe_emit_word(tokens, nil), do: tokens
  defp maybe_emit_word(tokens, %Word{} = word), do: tokens ++ [word]

  defp word_token(text, %Run{} = run) do
    %Word{
      text: text,
      font: run.font,
      size: run.size,
      style: run.style,
      width: width(text, run)
    }
  end

  defp space_token(text, %Run{} = run) do
    %Space{
      text: text,
      font: run.font,
      size: run.size,
      style: run.style,
      width: width(text, run)
    }
  end

  defp same_style?(%Word{} = word, %Run{} = run) do
    word.font == run.font and word.size == run.size and word.style == run.style
  end

  defp width(text, %Run{} = run) do
    Font.text_width(run.font, run.size, text)
  end
end

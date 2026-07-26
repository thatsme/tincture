defmodule Tincture.Typography.RichText do
  @moduledoc """
  Styled text, ready for layout.

  The typography engine works on rich text rather than plain strings, because
  line breaking has to know the width of every word, and width depends on the
  font and size of the run it belongs to.

  Most callers want `from_plain/2`:

      RichText.from_plain("Hello world", font: "Times-Roman", size: 11)

  Use `from_runs/1` when a paragraph mixes styles — a bold lead-in followed by
  regular body text is one paragraph, not two, and must break across lines as
  a unit:

      RichText.from_runs([
        %RichText.Run{text: "Warning: ", font: "Helvetica-Bold", size: 11},
        %RichText.Run{text: "this operation cannot be undone.", font: "Helvetica", size: 11}
      ])

  Internally the runs are tokenised into words, spaces and breaks, which is
  what the line breaker consumes. `from_tokens/1` accepts that form directly
  and exists so text spilling from one page can continue on the next without
  losing its styling.
  """

  alias Tincture.Font.Context

  defmodule Run do
    @moduledoc """
    A span of text sharing one font, size and style.
    """

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
    @moduledoc """
    A single word token, carrying the width it measured to in its run's font.

    `measured?` is false when the font could not be resolved at the time the
    token was built — the width is then a rough estimate from the point size.
    An embedded font is unresolvable until the document is known, so this is
    normal for text built ahead of layout; `RichText.remeasure/2` resolves it.
    """

    @type t :: %__MODULE__{
            text: String.t(),
            font: String.t(),
            size: number(),
            style: atom() | nil,
            width: number(),
            measured?: boolean()
          }

    defstruct text: "",
              font: "Helvetica",
              size: 12,
              style: nil,
              width: 0,
              measured?: true
  end

  defmodule Space do
    @moduledoc """
    An inter-word space. The line breaker stretches and shrinks these when
    justifying, which is why they are tokens rather than part of the words.
    """

    @type t :: %__MODULE__{
            text: String.t(),
            font: String.t(),
            size: number(),
            style: atom() | nil,
            width: number(),
            measured?: boolean()
          }

    defstruct text: " ",
              font: "Helvetica",
              size: 12,
              style: nil,
              width: 0,
              measured?: true
  end

  defmodule Break do
    @moduledoc """
    An explicit line or paragraph break.
    """

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

  @doc """
  Build rich text from a single plain string.

  ## Options

    * `:font` — font name. Defaults to `"Helvetica"`.
    * `:size` — point size. Defaults to `12`.
    * `:style` — an arbitrary style tag carried through to the tokens.
    * `:context` — a `t:Tincture.Font.Context.t/0` used to measure. Needed only
      to measure an **embedded** font up front, since embedded metrics live on
      the document rather than being globally resolvable. The document-aware
      entry points — `Tincture.text_paragraph/6`, `Tincture.Layout.Box.flow_text/7`
      — re-measure against their own document anyway, so this is usually
      unnecessary.

  ## Examples

      RichText.from_plain("Hello world", font: "Times-Roman", size: 11)

      # Measuring an embedded font outside a layout call.
      context = Tincture.Font.Context.from_pdf(pdf)
      RichText.from_plain("Hello", font: "Body", size: 11, context: context)

  """
  @spec from_plain(String.t(), keyword()) :: t()
  def from_plain(text, opts \\ []) when is_binary(text) and is_list(opts) do
    run = %Run{
      text: text,
      font: Keyword.get(opts, :font, "Helvetica"),
      size: Keyword.get(opts, :size, 12),
      style: Keyword.get(opts, :style)
    }

    from_runs([run], opts)
  end

  @doc """
  Build rich text from a list of styled runs.

  Accepts a `:context` option, as `from_plain/2` does.
  """
  @spec from_runs([Run.t()], keyword()) :: t()
  def from_runs(runs, opts \\ []) when is_list(runs) and is_list(opts) do
    normalized =
      runs
      |> Enum.map(fn
        %Run{} = run -> run
        map when is_map(map) -> struct!(Run, map)
      end)

    context = Keyword.get(opts, :context) || Context.new()

    %__MODULE__{
      runs: normalized,
      tokens: tokenize_runs(normalized, context)
    }
  end

  @doc """
  Recompute every token width against a measurement context.

  Token widths are baked in when the rich text is built, so text built without
  a context has measured its embedded fonts wrongly — or failed to measure them
  at all. The document-aware layout functions call this for you; it exists
  publicly for code that lays out text through `Tincture.Typography` directly.

      rich
      |> RichText.remeasure(Tincture.Font.Context.from_pdf(pdf))
      |> Tincture.Typography.layout_paragraph(450, align: :justified)

  Structure is preserved exactly — only widths change — so this is safe to
  apply to text that has already been through a layout pass.
  """
  @spec remeasure(t(), Context.t()) :: t()
  def remeasure(%__MODULE__{} = rich, %Context{} = context) do
    %__MODULE__{rich | tokens: Enum.map(rich.tokens, &remeasure_token(&1, context))}
  end

  defp remeasure_token(%Word{} = token, context) do
    {width, measured?} = measure(token.text, token.font, token.size, context)
    %Word{token | width: width, measured?: measured?}
  end

  defp remeasure_token(%Space{} = token, context) do
    {width, measured?} = measure(token.text, token.font, token.size, context)
    %Space{token | width: width, measured?: measured?}
  end

  defp remeasure_token(%Break{} = token, _context), do: token

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

  defp tokenize_runs(runs, context) do
    {tokens, current_word} =
      Enum.reduce(runs, {[], nil}, fn run, {acc_tokens, acc_word} ->
        tokenize_run(run, acc_tokens, acc_word, context)
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

  defp tokenize_run(%Run{} = run, tokens, current_word, context) do
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
          {tokens_with_word ++ [space_token(space_text, run, context)], nil}

        true ->
          part = <<ch::utf8>>

          case acc_word do
            nil ->
              {acc_tokens, word_token(part, run, context)}

            %Word{} = word ->
              if same_style?(word, run) do
                grown = word.text <> part
                {grown_width, measured?} = width(grown, run, context)

                {acc_tokens, %Word{word | text: grown, width: grown_width, measured?: measured?}}
              else
                {acc_tokens ++ [word], word_token(part, run, context)}
              end
          end
      end
    end)
  end

  defp maybe_emit_word(tokens, nil), do: tokens
  defp maybe_emit_word(tokens, %Word{} = word), do: tokens ++ [word]

  defp word_token(text, %Run{} = run, context) do
    {width, measured?} = width(text, run, context)

    %Word{
      text: text,
      font: run.font,
      size: run.size,
      style: run.style,
      width: width,
      measured?: measured?
    }
  end

  defp space_token(text, %Run{} = run, context) do
    {width, measured?} = width(text, run, context)

    %Space{
      text: text,
      font: run.font,
      size: run.size,
      style: run.style,
      width: width,
      measured?: measured?
    }
  end

  defp same_style?(%Word{} = word, %Run{} = run) do
    word.font == run.font and word.size == run.size and word.style == run.style
  end

  defp width(text, %Run{} = run, context) do
    measure(text, run.font, run.size, context)
  end

  defp measure(text, font, size, %Context{} = context) do
    case Context.measure(context, font, size, text) do
      {:ok, width} -> {width, true}
      {:unresolved, estimate} -> {estimate, false}
    end
  end

  @doc """
  The font names whose widths are still estimates, because no context supplied
  so far could resolve them.

  Empty for text that is ready to lay out.
  """
  @spec unmeasured_fonts(t()) :: [String.t()]
  def unmeasured_fonts(%__MODULE__{tokens: tokens}) do
    tokens
    |> Enum.reject(fn
      %Break{} -> true
      token -> token.measured?
    end)
    |> Enum.map(& &1.font)
    |> Enum.uniq()
  end
end

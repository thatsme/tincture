defmodule ExGuten.Showcase.MarkdownDoc do
  @moduledoc false

  alias ExGuten.Typography
  alias ExGuten.Typography.RichText

  @left_x 48
  @content_width 516
  @top_y 728
  @bottom_y 56
  @default_out "tmp/markdown_showcase.pdf"
  @sample_markdown_path Path.expand("../../../priv/showcase/feature_tour.md", __DIR__)

  @type block ::
          {:heading, 1 | 2 | 3, String.t()}
          | {:paragraph, String.t()}
          | {:list_item, String.t()}
          | {:code_block, [String.t()]}

  @type render_state :: %{
          pdf: ExGuten.PDF.t(),
          page: pos_integer(),
          y: number()
        }

  @type build_result :: %{
          pdf: ExGuten.PDF.t(),
          pages: pos_integer()
        }

  @spec build_document() :: build_result()
  def build_document do
    build_document(sample_markdown())
  end

  @spec build_document(String.t()) :: build_result()
  def build_document(markdown) when is_binary(markdown) do
    blocks = parse_markdown(markdown)
    first_heading = first_heading_text(blocks)

    pdf =
      ExGuten.new()
      |> ExGuten.page_size(:letter)
      |> ExGuten.set_metadata(
        title: "Markdown Showcase Demo",
        author: "ExGuten",
        subject: "Markdown to PDF showcase",
        keywords: "showcase,markdown,pdf"
      )
      |> ExGuten.add_bookmark(first_heading, 1)
      |> draw_page_chrome(1)

    initial_state = %{pdf: pdf, page: 1, y: @top_y}
    final_state = Enum.reduce(blocks, initial_state, &render_block/2)

    %{pdf: final_state.pdf, pages: final_state.page}
  end

  @spec pdf_binary() :: binary()
  def pdf_binary do
    %{pdf: pdf} = build_document()
    ExGuten.export(pdf)
  end

  @spec pdf_binary(String.t()) :: binary()
  def pdf_binary(markdown) when is_binary(markdown) do
    %{pdf: pdf} = build_document(markdown)
    ExGuten.export(pdf)
  end

  @spec write_pdf(Path.t()) :: Path.t()
  def write_pdf(path \\ @default_out) when is_binary(path) do
    write_pdf(path, sample_markdown())
  end

  @spec write_pdf(Path.t(), String.t()) :: Path.t()
  def write_pdf(path, markdown) when is_binary(path) and is_binary(markdown) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, pdf_binary(markdown))
    path
  end

  @spec write_pdf_from_file(Path.t(), Path.t()) :: Path.t()
  def write_pdf_from_file(markdown_path, out_path \\ @default_out)
      when is_binary(markdown_path) and is_binary(out_path) do
    markdown = File.read!(markdown_path)
    write_pdf(out_path, markdown)
  end

  @spec sample_markdown_path() :: Path.t()
  def sample_markdown_path do
    @sample_markdown_path
  end

  @spec sample_markdown() :: String.t()
  def sample_markdown do
    File.read!(@sample_markdown_path)
  end

  defp render_block({:heading, level, text}, state) do
    size =
      case level do
        1 -> 24
        2 -> 16
        3 -> 13
      end

    line_height = size * 1.25
    needed_height = line_height + 10
    state = ensure_space(state, needed_height)

    pdf =
      state.pdf
      |> ExGuten.set_fill_color({0.0, 0.0, 0.0})
      |> ExGuten.set_font("Helvetica-Bold", size)
      |> ExGuten.text_at(@left_x, state.y, text)

    %{state | pdf: pdf, y: state.y - needed_height}
  end

  defp render_block({:paragraph, text}, state) do
    render_paragraph(state, text, "Times-Roman", 11,
      align: :left,
      line_break: :optimal,
      line_height: 14,
      after_gap: 8
    )
  end

  defp render_block({:list_item, text}, state) do
    render_paragraph(state, "- " <> text, "Helvetica", 10,
      align: :left,
      line_break: :optimal,
      line_height: 13,
      after_gap: 4
    )
  end

  defp render_block({:code_block, lines}, state) do
    lines = if lines == [], do: [""], else: lines
    line_height = 11
    box_height = line_height * length(lines) + 10
    needed_height = box_height + 22
    state = ensure_space(state, needed_height)

    top_y = state.y
    box_y = top_y - box_height + 4

    pdf =
      state.pdf
      |> ExGuten.set_fill_color({0.95, 0.95, 0.95})
      |> ExGuten.rectangle(@left_x, box_y, @content_width, box_height)
      |> ExGuten.fill()
      |> ExGuten.set_stroke_color({0.77, 0.77, 0.77})
      |> ExGuten.set_line_width(0.75)
      |> ExGuten.rectangle(@left_x, box_y, @content_width, box_height)
      |> ExGuten.stroke()
      |> ExGuten.set_fill_color({0.0, 0.0, 0.0})

    {pdf, _y} =
      Enum.reduce(lines, {pdf, top_y - 11}, fn line, {acc_pdf, y} ->
        next_pdf =
          acc_pdf
          |> ExGuten.set_font("Courier", 9)
          |> ExGuten.text_at(@left_x + 8, y, line)

        {next_pdf, y - line_height}
      end)

    %{state | pdf: pdf, y: top_y - needed_height}
  end

  defp render_paragraph(state, text, font, size, opts) do
    rich = RichText.from_plain(text, font: font, size: size)

    layout_opts =
      opts
      |> Keyword.take([:align, :line_break, :line_height])
      |> Keyword.put_new(:line_break, :optimal)

    line_height = Keyword.get(layout_opts, :line_height, size * 1.3)
    line_count = max(1, length(Typography.layout_paragraph(rich, @content_width, layout_opts)))
    needed_height = line_height * line_count + Keyword.get(opts, :after_gap, 6)
    state = ensure_space(state, needed_height)

    pdf =
      state.pdf
      |> ExGuten.set_fill_color({0.0, 0.0, 0.0})
      |> ExGuten.text_paragraph(@left_x, state.y, rich, @content_width, layout_opts)

    %{state | pdf: pdf, y: state.y - needed_height}
  end

  defp ensure_space(%{y: y} = state, needed_height) do
    if y - needed_height >= @bottom_y do
      state
    else
      next_page = state.page + 1

      pdf =
        state.pdf
        |> ExGuten.add_page()
        |> ExGuten.set_page(next_page)
        |> draw_page_chrome(next_page)

      %{state | pdf: pdf, page: next_page, y: @top_y}
    end
  end

  defp draw_page_chrome(pdf, page) do
    pdf
    |> ExGuten.set_fill_color({0.0, 0.0, 0.0})
    |> ExGuten.set_font("Helvetica-Bold", 11)
    |> ExGuten.text_at(48, 758, "Markdown Showcase - Page #{page}")
    |> ExGuten.set_font("Helvetica", 9)
    |> ExGuten.text_at(48, 30, "Generated from markdown input")
  end

  defp first_heading_text(blocks) do
    Enum.find_value(blocks, "Markdown Showcase", fn
      {:heading, _level, text} -> text
      _other -> nil
    end)
  end

  @spec parse_markdown(String.t()) :: [block()]
  defp parse_markdown(markdown) do
    markdown
    |> String.split(~r/\r\n|\n|\r/, trim: false)
    |> Enum.reduce(
      %{in_code?: false, code_lines: [], paragraph_lines: [], blocks: []},
      &parse_markdown_line/2
    )
    |> flush_parse_state()
    |> Map.fetch!(:blocks)
  end

  defp parse_markdown_line(line, %{in_code?: true} = state) do
    if String.starts_with?(line, "```") do
      push_code_block(%{state | in_code?: false})
    else
      %{state | code_lines: state.code_lines ++ [line]}
    end
  end

  defp parse_markdown_line(line, %{in_code?: false} = state) do
    cond do
      String.starts_with?(line, "```") ->
        state
        |> push_paragraph()
        |> Map.put(:in_code?, true)
        |> Map.put(:code_lines, [])

      Regex.match?(~r/^\s*$/, line) ->
        push_paragraph(state)

      Regex.match?(~r/^\s*[-*]\s+/, line) ->
        [_, item_text] = Regex.run(~r/^\s*[-*]\s+(.*)$/, line)

        state
        |> push_paragraph()
        |> push_block({:list_item, normalize_inline_markdown(item_text)})

      Regex.match?(~r/^(\#{1,3})\s+/, line) ->
        [_, hashes, heading_text] = Regex.run(~r/^(\#{1,3})\s+(.*)$/, line)
        level = min(3, String.length(hashes))

        state
        |> push_paragraph()
        |> push_block({:heading, level, normalize_inline_markdown(heading_text)})

      true ->
        %{state | paragraph_lines: state.paragraph_lines ++ [String.trim(line)]}
    end
  end

  defp flush_parse_state(state) do
    state
    |> push_paragraph()
    |> push_code_block()
  end

  defp push_paragraph(%{paragraph_lines: []} = state), do: state

  defp push_paragraph(state) do
    paragraph =
      state.paragraph_lines
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")
      |> normalize_inline_markdown()
      |> String.trim()

    if paragraph == "" do
      %{state | paragraph_lines: []}
    else
      state
      |> push_block({:paragraph, paragraph})
      |> Map.put(:paragraph_lines, [])
    end
  end

  defp push_code_block(%{code_lines: []} = state), do: state

  defp push_code_block(state) do
    code_lines =
      Enum.map(state.code_lines, fn line ->
        String.replace(line, "\t", "  ")
      end)

    state
    |> push_block({:code_block, code_lines})
    |> Map.put(:code_lines, [])
    |> Map.put(:in_code?, false)
  end

  defp push_block(state, block) do
    %{state | blocks: state.blocks ++ [block]}
  end

  defp normalize_inline_markdown(text) do
    text
    |> String.trim()
    |> then(&Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, &1, "\\1 (\\2)"))
    |> String.replace("**", "")
    |> String.replace("__", "")
    |> String.replace("`", "")
    |> String.replace(~r/\s+/, " ")
  end
end

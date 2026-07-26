defmodule Tincture.Layout.Template do
  @moduledoc false

  alias Tincture.Layout.Box
  alias Tincture.Layout.Box.FlowResult
  alias Tincture.PDF
  alias Tincture.PDF.Page
  alias Tincture.Typography.RichText

  @type margin_tuple :: {number(), number(), number(), number()}
  @type box :: {float(), float(), float(), float()}

  defmodule Slot do
    @moduledoc false

    @type t :: %__MODULE__{
            text: String.t(),
            font: String.t(),
            size: float()
          }

    defstruct text: "",
              font: "Helvetica",
              size: 10.0
  end

  defmodule RenderResult do
    @moduledoc false

    @type t :: %__MODULE__{
            body_flow: FlowResult.t(),
            overflow?: boolean(),
            spill_text: String.t()
          }

    defstruct body_flow: %FlowResult{},
              overflow?: false,
              spill_text: ""
  end

  defmodule DocumentResult do
    @moduledoc false

    @type t :: %__MODULE__{
            page_results: [RenderResult.t()],
            pages_used: non_neg_integer(),
            overflow?: boolean(),
            spill_text: String.t()
          }

    defstruct page_results: [],
              pages_used: 0,
              overflow?: false,
              spill_text: ""
  end

  @type t :: %__MODULE__{
          page_size: PDF.page_size(),
          margins: %{left: float(), right: float(), top: float(), bottom: float()},
          columns: pos_integer(),
          gutter: float(),
          header_height: float(),
          footer_height: float(),
          body_boxes: [box()],
          header: Slot.t() | nil,
          footer: Slot.t() | nil
        }

  defstruct page_size: :letter,
            margins: %{left: 50.0, right: 50.0, top: 50.0, bottom: 50.0},
            columns: 1,
            gutter: 20.0,
            header_height: 30.0,
            footer_height: 20.0,
            body_boxes: [],
            header: nil,
            footer: nil

  @type option ::
          {:page_size, PDF.page_size()}
          | {:margins, margin_tuple()}
          | {:columns, pos_integer()}
          | {:gutter, number()}
          | {:header_height, number()}
          | {:footer_height, number()}

  @type slot_option :: {:font, String.t()} | {:size, number()} | {:height, number()}
  @type document_option ::
          Box.option()
          | {:page_number_start, pos_integer()}
          | {:page_total, pos_integer()}
          | {:max_pages, pos_integer()}

  @type xml_error ::
          :invalid_xml
          | :missing_body
          | {:invalid_page_size, String.t()}
          | {:invalid_margins, String.t()}
          | {:invalid_columns, String.t()}
          | {:invalid_gutter, String.t()}
          | {:invalid_slot_size, String.t()}
          | {:invalid_slot_height, String.t()}
          | {:invalid_body_size, String.t()}

  @spec new([option()]) :: t()
  def new(opts \\ []) when is_list(opts) do
    page_size = Keyword.get(opts, :page_size, :letter)
    margins = normalize_margins(Keyword.get(opts, :margins, {50, 50, 50, 50}))
    columns = normalize_columns(Keyword.get(opts, :columns, 1))
    gutter = normalize_non_negative(Keyword.get(opts, :gutter, 20), :gutter)
    header_height = normalize_non_negative(Keyword.get(opts, :header_height, 30), :header_height)
    footer_height = normalize_non_negative(Keyword.get(opts, :footer_height, 20), :footer_height)

    body_boxes =
      build_body_boxes(page_size, margins, columns, gutter, header_height, footer_height)

    %__MODULE__{
      page_size: page_size,
      margins: margins,
      columns: columns,
      gutter: gutter,
      header_height: header_height,
      footer_height: footer_height,
      body_boxes: body_boxes
    }
  end

  @spec with_header(t(), String.t(), [slot_option()]) :: t()
  def with_header(%__MODULE__{} = template, text, opts \\ [])
      when is_binary(text) and is_list(opts) do
    slot = %Slot{
      text: text,
      font: Keyword.get(opts, :font, "Helvetica-Bold"),
      size: normalize_positive(Keyword.get(opts, :size, 12), :size)
    }

    header_height =
      case Keyword.get(opts, :height) do
        nil -> template.header_height
        value -> normalize_non_negative(value, :height)
      end

    update_layout(%{template | header: slot, header_height: header_height})
  end

  @spec with_footer(t(), String.t(), [slot_option()]) :: t()
  def with_footer(%__MODULE__{} = template, text, opts \\ [])
      when is_binary(text) and is_list(opts) do
    slot = %Slot{
      text: text,
      font: Keyword.get(opts, :font, "Helvetica"),
      size: normalize_positive(Keyword.get(opts, :size, 10), :size)
    }

    footer_height =
      case Keyword.get(opts, :height) do
        nil -> template.footer_height
        value -> normalize_non_negative(value, :height)
      end

    update_layout(%{template | footer: slot, footer_height: footer_height})
  end

  @spec render(PDF.t(), t(), RichText.t(), [Box.option()]) :: {PDF.t(), RenderResult.t()}
  def render(%PDF{} = pdf, %__MODULE__{} = template, %RichText{} = rich_text, opts \\ [])
      when is_list(opts) do
    page_number = normalize_positive_integer(Keyword.get(opts, :page_number, 1), :page_number)

    page_total =
      normalize_positive_integer(Keyword.get(opts, :page_total, page_number), :page_total)

    flow_opts = Keyword.drop(opts, [:page_number, :page_total])

    {page_width, page_height} = Page.media_box(template.page_size)
    _ = page_width

    with_header =
      case template.header do
        nil ->
          pdf

        %Slot{} = slot ->
          pdf
          |> Tincture.set_font(slot.font, slot.size)
          |> Tincture.text_at(
            template.margins.left,
            page_height - template.margins.top,
            expand_slot_text(slot.text, page_number, page_total)
          )
      end

    with_footer =
      case template.footer do
        nil ->
          with_header

        %Slot{} = slot ->
          with_header
          |> Tincture.set_font(slot.font, slot.size)
          |> Tincture.text_at(
            template.margins.left,
            template.margins.bottom + slot.size,
            expand_slot_text(slot.text, page_number, page_total)
          )
      end

    {rendered_pdf, flow_result} =
      Box.flow_across_boxes(with_footer, rich_text, template.body_boxes, flow_opts)

    result = %RenderResult{
      body_flow: flow_result,
      overflow?: flow_result.overflow?,
      spill_text: flow_result.spill_text
    }

    {rendered_pdf, result}
  end

  @spec render_document(PDF.t(), t(), RichText.t(), [document_option()]) ::
          {PDF.t(), DocumentResult.t()}
  def render_document(%PDF{} = pdf, %__MODULE__{} = template, %RichText{} = rich_text, opts \\ [])
      when is_list(opts) do
    page_number_start =
      normalize_positive_integer(
        Keyword.get(opts, :page_number_start, pdf.current_page),
        :page_number_start
      )

    max_pages = normalize_positive_integer(Keyword.get(opts, :max_pages, 50), :max_pages)
    page_total = Keyword.get(opts, :page_total)
    _ = page_total

    {final_pdf, final_rich, page_results} =
      Enum.reduce_while(0..(max_pages - 1), {pdf, rich_text, []}, fn idx,
                                                                     {acc_pdf, current_rich,
                                                                      results} ->
        current_pdf = if idx == 0, do: acc_pdf, else: Tincture.add_page(acc_pdf)
        page_number = page_number_start + idx

        render_opts =
          opts
          |> Keyword.put(:page_number, page_number)
          |> Keyword.put(:page_total, normalize_page_total(page_total, page_number))

        {next_pdf, page_result} = render(current_pdf, template, current_rich, render_opts)
        next_results = results ++ [page_result]

        if page_result.overflow? do
          next_rich = rich_from_spill(page_result.spill_text, current_rich)
          {:cont, {next_pdf, next_rich, next_results}}
        else
          {:halt, {next_pdf, empty_rich_text(), next_results}}
        end
      end)

    spill_text = rich_to_text(final_rich)

    result = %DocumentResult{
      page_results: page_results,
      pages_used: length(page_results),
      overflow?: spill_text != "",
      spill_text: spill_text
    }

    {final_pdf, result}
  end

  @spec parse_xml(String.t()) :: {:ok, t(), RichText.t()} | {:error, xml_error()}
  def parse_xml(xml) when is_binary(xml) do
    with {:ok, doc} <- parse_xml_doc(xml),
         {:ok, template} <- parse_xml_template(doc),
         {:ok, body} <- parse_xml_body(doc) do
      {:ok, template, body}
    end
  end

  @spec render_xml_document(PDF.t(), String.t(), [document_option()]) ::
          {:ok, PDF.t(), DocumentResult.t()} | {:error, xml_error()}
  def render_xml_document(%PDF{} = pdf, xml, opts \\ []) when is_binary(xml) and is_list(opts) do
    with {:ok, template, body} <- parse_xml(xml) do
      {rendered_pdf, result} = render_document(pdf, template, body, opts)
      {:ok, rendered_pdf, result}
    end
  end

  defp update_layout(%__MODULE__{} = template) do
    boxes =
      build_body_boxes(
        template.page_size,
        template.margins,
        template.columns,
        template.gutter,
        template.header_height,
        template.footer_height
      )

    %{template | body_boxes: boxes}
  end

  defp build_body_boxes(page_size, margins, columns, gutter, header_height, footer_height) do
    {page_width, page_height} = Page.media_box(page_size)
    available_width = page_width - margins.left - margins.right - gutter * (columns - 1)
    column_width = available_width / columns
    body_top = page_height - margins.top - header_height
    body_bottom = margins.bottom + footer_height
    body_height = max(body_top - body_bottom, 0.0)

    0..(columns - 1)
    |> Enum.map(fn idx ->
      x = margins.left + idx * (column_width + gutter)
      {x * 1.0, body_top * 1.0, column_width * 1.0, body_height * 1.0}
    end)
  end

  defp normalize_margins({left, right, top, bottom})
       when is_number(left) and is_number(right) and is_number(top) and is_number(bottom) and
              left >= 0 and right >= 0 and top >= 0 and bottom >= 0 do
    %{left: left * 1.0, right: right * 1.0, top: top * 1.0, bottom: bottom * 1.0}
  end

  defp normalize_margins(other), do: raise(ArgumentError, "invalid margins: #{inspect(other)}")

  defp normalize_columns(value) when is_integer(value) and value > 0, do: value
  defp normalize_columns(_other), do: raise(ArgumentError, "columns must be a positive integer")

  defp normalize_non_negative(value, _field) when is_number(value) and value >= 0, do: value * 1.0
  defp normalize_non_negative(_value, field), do: raise(ArgumentError, "#{field} must be >= 0")

  defp normalize_positive(value, _field) when is_number(value) and value > 0, do: value * 1.0
  defp normalize_positive(_value, field), do: raise(ArgumentError, "#{field} must be > 0")

  defp normalize_positive_integer(value, _field) when is_integer(value) and value > 0, do: value
  defp normalize_positive_integer(_value, field), do: raise(ArgumentError, "#{field} must be > 0")

  defp expand_slot_text(text, page_number, page_total) do
    text
    |> String.replace("{page}", Integer.to_string(page_number))
    |> String.replace("{total}", Integer.to_string(page_total))
  end

  defp normalize_page_total(nil, page_number), do: page_number

  defp normalize_page_total(value, _page_number) do
    normalize_positive_integer(value, :page_total)
  end

  defp rich_from_spill("", _template_rich), do: empty_rich_text()

  defp rich_from_spill(spill_text, %RichText{} = template_rich) do
    case template_rich.runs do
      [first | _] ->
        RichText.from_plain(spill_text, font: first.font, size: first.size, style: first.style)

      [] ->
        RichText.from_plain(spill_text)
    end
  end

  defp rich_to_text(%RichText{} = rich) do
    case rich.tokens do
      [] ->
        Enum.map_join(rich.runs, "", & &1.text)

      tokens ->
        Enum.map_join(tokens, "", fn
          %{kind: :line} -> "\n"
          token -> Map.get(token, :text, "")
        end)
    end
  end

  defp empty_rich_text do
    %RichText{runs: [], tokens: []}
  end

  defp parse_xml_doc(xml) do
    {doc, _rest} = :erlang.apply(:xmerl_scan, :string, [String.to_charlist(xml)])
    {:ok, doc}
  rescue
    _ -> {:error, :invalid_xml}
  catch
    _, _ -> {:error, :invalid_xml}
  end

  defp parse_xml_template(doc) do
    with {:ok, page_size} <- parse_page_size_attr(xpath_string(doc, "/document/@page_size")),
         {:ok, margins} <- parse_margins_attr(xpath_string(doc, "/document/@margins")),
         {:ok, columns} <- parse_columns_attr(xpath_string(doc, "/document/@columns")),
         {:ok, gutter} <- parse_gutter_attr(xpath_string(doc, "/document/@gutter")),
         {:ok, template} <-
           {:ok,
            new(
              page_size: page_size,
              margins: margins,
              columns: columns,
              gutter: gutter
            )},
         {:ok, with_header} <- parse_header_slot(template, doc) do
      parse_footer_slot(with_header, doc)
    end
  end

  defp parse_header_slot(template, doc) do
    if xpath_count(doc, "/document/header") > 0 do
      header_text = xpath_string(doc, "/document/header")

      header_font =
        default_if_blank(xpath_string(doc, "/document/header/@font"), "Helvetica-Bold")

      with {:ok, header_size} <-
             parse_slot_size_attr(xpath_string(doc, "/document/header/@size"), 12.0),
           {:ok, header_height} <-
             parse_slot_height_attr(xpath_string(doc, "/document/header/@height")) do
        header_opts = maybe_put_slot_height([font: header_font, size: header_size], header_height)
        {:ok, with_header(template, header_text, header_opts)}
      end
    else
      {:ok, template}
    end
  end

  defp parse_footer_slot(template, doc) do
    if xpath_count(doc, "/document/footer") > 0 do
      footer_text = xpath_string(doc, "/document/footer")
      footer_font = default_if_blank(xpath_string(doc, "/document/footer/@font"), "Helvetica")

      with {:ok, footer_size} <-
             parse_slot_size_attr(xpath_string(doc, "/document/footer/@size"), 10.0),
           {:ok, footer_height} <-
             parse_slot_height_attr(xpath_string(doc, "/document/footer/@height")) do
        footer_opts = maybe_put_slot_height([font: footer_font, size: footer_size], footer_height)
        {:ok, with_footer(template, footer_text, footer_opts)}
      end
    else
      {:ok, template}
    end
  end

  defp parse_xml_body(doc) do
    if xpath_count(doc, "/document/body") == 0 do
      {:error, :missing_body}
    else
      text = xpath_string(doc, "/document/body")
      font = default_if_blank(xpath_string(doc, "/document/body/@font"), "Helvetica")

      case parse_body_size_attr(xpath_string(doc, "/document/body/@size")) do
        {:ok, size} ->
          {:ok, RichText.from_plain(text, font: font, size: size)}

        {:error, _} = error ->
          error
      end
    end
  end

  defp xpath_string(doc, path) do
    expression = String.to_charlist("string(#{path})")

    case :erlang.apply(:xmerl_xpath, :string, [expression, doc]) do
      {:xmlObj, :string, value} -> List.to_string(value)
      _ -> ""
    end
  end

  defp xpath_count(doc, path) do
    expression = String.to_charlist("count(#{path})")

    case :erlang.apply(:xmerl_xpath, :string, [expression, doc]) do
      {:xmlObj, :number, value} when is_number(value) -> trunc(value)
      _ -> 0
    end
  end

  defp parse_page_size_attr(""), do: {:ok, :letter}

  defp parse_page_size_attr(value) do
    downcased = String.downcase(String.trim(value))

    case downcased do
      "a4" ->
        {:ok, :a4}

      "letter" ->
        {:ok, :letter}

      "legal" ->
        {:ok, :legal}

      _ ->
        case parse_number_list(downcased, 2) do
          {:ok, [w, h]} when w > 0 and h > 0 -> {:ok, {w, h}}
          _ -> {:error, {:invalid_page_size, value}}
        end
    end
  end

  defp parse_margins_attr(""), do: {:ok, {50.0, 50.0, 50.0, 50.0}}

  defp parse_margins_attr(value) do
    case parse_number_list(value, 4) do
      {:ok, [left, right, top, bottom]}
      when left >= 0 and right >= 0 and top >= 0 and bottom >= 0 ->
        {:ok, {left, right, top, bottom}}

      _ ->
        {:error, {:invalid_margins, value}}
    end
  end

  defp parse_columns_attr(""), do: {:ok, 1}

  defp parse_columns_attr(value) do
    with {:ok, number} <- parse_integer(value),
         true <- number > 0 do
      {:ok, number}
    else
      _ -> {:error, {:invalid_columns, value}}
    end
  end

  defp parse_gutter_attr(""), do: {:ok, 20.0}

  defp parse_gutter_attr(value) do
    with {:ok, number} <- parse_float(value),
         true <- number >= 0 do
      {:ok, number}
    else
      _ -> {:error, {:invalid_gutter, value}}
    end
  end

  defp parse_body_size_attr(""), do: {:ok, 12.0}

  defp parse_body_size_attr(value) do
    with {:ok, number} <- parse_float(value),
         true <- number > 0 do
      {:ok, number}
    else
      _ -> {:error, {:invalid_body_size, value}}
    end
  end

  defp parse_slot_size_attr(value, default) do
    case value do
      "" ->
        {:ok, default}

      _ ->
        case parse_float(value) do
          {:ok, number} when number > 0 -> {:ok, number}
          _ -> {:error, {:invalid_slot_size, value}}
        end
    end
  end

  defp parse_slot_height_attr(value) do
    case value do
      "" ->
        {:ok, nil}

      _ ->
        case parse_float(value) do
          {:ok, number} when number >= 0 -> {:ok, number}
          _ -> {:error, {:invalid_slot_height, value}}
        end
    end
  end

  defp maybe_put_slot_height(opts, nil), do: opts
  defp maybe_put_slot_height(opts, height), do: Keyword.put(opts, :height, height)

  defp parse_number_list(value, expected_count) do
    parts =
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if length(parts) == expected_count do
      parts
      |> Enum.map(&parse_float/1)
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, number}, {:ok, acc} -> {:cont, {:ok, acc ++ [number]}}
        _error, _acc -> {:halt, :error}
      end)
      |> case do
        {:ok, numbers} -> {:ok, numbers}
        :error -> :error
      end
    else
      :error
    end
  end

  defp parse_integer(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp parse_float(value) do
    trimmed = String.trim(value)

    case Float.parse(trimmed) do
      {number, ""} ->
        {:ok, number}

      _ ->
        case Integer.parse(trimmed) do
          {number, ""} -> {:ok, number * 1.0}
          _ -> :error
        end
    end
  end

  defp default_if_blank("", default), do: default
  defp default_if_blank(value, _default), do: value
end

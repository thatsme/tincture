defmodule Tincture.PDF.Structure do
  @moduledoc """
  The logical structure of a tagged document.

  An untagged PDF is a picture of a document: the bytes say where every glyph
  sits, and nothing says which glyphs form a heading, which form a table cell,
  or what order a human would read them in. Assistive technology has nothing to
  work with. Tagging adds that missing layer.

  Two halves have to agree:

    * a **structure tree** of elements — `/Document` containing `/H1` and `/P`,
      a `/Table` containing `/TR` containing `/TD` — stored in the document
      catalog;
    * **marked content** in the page's content stream, where drawing operators
      are bracketed by `BDC`/`EMC` and stamped with a marked-content id (MCID).

  An element points at its MCIDs, and a per-page number tree points back from
  each MCID to its element. That two-way link is what lets a reader walk the
  document logically rather than by position.

  This module models the tree. See `Tincture.tag/4` for the API that builds it.

  ## Container and content elements

  Elements divide into two kinds, and the difference decides whether marked
  content is emitted at all:

    * **containers** (`:document`, `:table`, `:tr`, `:l`…) group other elements
      and never wrap drawing operators directly. They get no MCID, because
      there is no content of their own to point at.
    * **content** elements (`:p`, `:h1`, `:td`, `:figure`…) bracket the
      operators that draw them, and carry an MCID.

  Nesting content inside content is legal — a `:span` inside a `:p` — and the
  innermost open sequence owns whatever is drawn. The parent keeps its own MCID
  for everything outside its children.
  """

  @container_tags %{
    document: "Document",
    part: "Part",
    article: "Art",
    section: "Sect",
    div: "Div",
    table: "Table",
    thead: "THead",
    tbody: "TBody",
    tfoot: "TFoot",
    tr: "TR",
    list: "L",
    list_item: "LI",
    toc: "TOC",
    index: "Index"
  }

  @content_tags %{
    p: "P",
    h1: "H1",
    h2: "H2",
    h3: "H3",
    h4: "H4",
    h5: "H5",
    h6: "H6",
    heading: "H",
    th: "TH",
    td: "TD",
    label: "Lbl",
    list_body: "LBody",
    caption: "Caption",
    figure: "Figure",
    formula: "Formula",
    quote: "Quote",
    block_quote: "BlockQuote",
    code: "Code",
    note: "Note",
    reference: "Reference",
    span: "Span",
    link: "Link",
    toc_item: "TOCI"
  }

  @type tag :: atom()
  @type t :: %{
          required(:tag) => tag(),
          required(:page_number) => pos_integer(),
          required(:mcid) => non_neg_integer() | nil,
          required(:kids) => [t()],
          optional(:alt) => String.t(),
          optional(:actual_text) => String.t(),
          optional(:lang) => String.t(),
          optional(:title) => String.t(),
          optional(:scope) => :row | :column | :both
        }

  @doc """
  Every tag this module understands, as `{atom, pdf_name}` pairs.
  """
  @spec tags() :: %{tag() => String.t()}
  def tags, do: Map.merge(@container_tags, @content_tags)

  @doc """
  The PDF structure type name for a tag, e.g. `:h1` becomes `"H1"`.
  """
  @spec tag_name(tag()) :: String.t()
  def tag_name(tag) do
    case Map.fetch(tags(), tag) do
      {:ok, name} ->
        name

      :error ->
        raise ArgumentError,
              "unknown structure tag: #{inspect(tag)}. Known tags: " <>
                (tags() |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &inspect/1))
    end
  end

  @doc """
  Whether a tag groups other elements rather than wrapping drawn content.

  A container gets no marked content and no MCID.
  """
  @spec container?(tag()) :: boolean()
  def container?(tag), do: Map.has_key?(@container_tags, tag)

  @doc """
  Whether a tag brackets drawing operators and so needs an MCID.
  """
  @spec content?(tag()) :: boolean()
  def content?(tag), do: Map.has_key?(@content_tags, tag)

  @doc """
  Walk a tree of elements depth-first, parents before children.

  This is the order elements are written as objects, so an element's id is
  always lower than its children's.
  """
  @spec flatten([t()]) :: [t()]
  def flatten(elements) when is_list(elements) do
    Enum.flat_map(elements, fn element ->
      [element | flatten(element.kids)]
    end)
  end

  @doc """
  Whether a tree contains anything at all.
  """
  @spec empty?([t()]) :: boolean()
  def empty?(elements), do: elements == []
end

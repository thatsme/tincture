defmodule Tincture.PDF do
  @moduledoc """
  Internal PDF state container.
  """

  alias Tincture.Font
  alias Tincture.Font.TTF
  alias Tincture.PDF.Sign
  alias Tincture.PDF.Structure
  require Logger

  @type page_size :: :a4 | :letter | :legal | {number(), number()}
  @type font :: {String.t(), number()}
  @type rgb :: {number(), number(), number()}
  @type embedded_font_subset_mode :: :none | :ascii_basic | :used_text
  @type ttf_metrics :: map()
  @type embedded_font_option ::
          {:subset, embedded_font_subset_mode()}
          | {:enforce_embedding_permissions, boolean()}
  @type text_op :: {:text_at, number(), number(), String.t(), font()}
  @type text_rotated_op :: {:text_at_rotated, number(), number(), number(), String.t(), font()}
  @type paint :: :stroke | :fill | :fill_even_odd | :fill_and_stroke | :none
  @type draw_op :: {:line, number(), number(), number(), number(), paint()}
  @type rect_op :: {:rectangle, number(), number(), number(), number(), paint()}
  @type circle_op :: {:circle, number(), number(), number(), paint()}
  @type move_to_op :: {:move_to, number(), number()}
  @type line_to_op :: {:line_to, number(), number()}
  @type bezier_op :: {:bezier, number(), number(), number(), number(), number(), number()}
  @type stroke_op :: :stroke
  @type fill_op :: :fill
  @type fill_even_odd_op :: :fill_even_odd
  @type clip_op :: :clip
  @type clip_even_odd_op :: :clip_even_odd
  @type line_style_op ::
          {:set_line_width, number()}
          | {:set_line_cap, 0 | 1 | 2}
          | {:set_line_join, 0 | 1 | 2}
          | {:set_dash, [number()], number()}
          | {:set_miter_limit, number()}
  @type graphics_state_op :: :save_state | :restore_state
  @type color_op :: {:set_stroke_color, rgb()} | {:set_fill_color, rgb()}
  @type image_color_space :: :device_gray | :device_rgb | :device_cmyk
  @type embedded_font ::
          %{
            required(:format) => :ttf | :otf,
            required(:name) => String.t(),
            required(:data) => binary(),
            required(:subset) => embedded_font_subset_mode(),
            optional(:ttf_metrics) => ttf_metrics()
          }
  @type image ::
          %{
            required(:format) => :jpeg | :png,
            required(:data) => binary(),
            required(:width) => pos_integer(),
            required(:height) => pos_integer(),
            required(:bits_per_component) => pos_integer(),
            required(:color_space) => image_color_space(),
            optional(:decode_parms) => map(),
            optional(:alpha_data) => binary(),
            optional(:alpha_decode_parms) => map()
          }
  @type image_op :: {:image, number(), number(), number(), number(), pos_integer()}
  @type alpha_op :: {:set_alpha, number(), number()}
  @typedoc """
  A gradient, and the rectangle it fills.

  The shading itself is carried in the operation rather than registered on the
  document, because it needs no object number: `/ExtGState` and `/Shading` are
  plain dictionaries and are written inline into the page's resources.
  """
  @type shading ::
          %{
            required(:type) => :axial | :radial,
            required(:coords) => [number()],
            required(:stops) => [{number(), rgb()}],
            required(:extend) => {boolean(), boolean()}
          }
  @type shading_op :: {:shading, number(), number(), number(), number(), shading()}
  @type begin_marked_content_op :: {:begin_marked_content, String.t(), non_neg_integer()}
  @type end_marked_content_op :: {:end_marked_content}
  @type begin_artifact_op :: {:begin_artifact}
  @type bookmark :: %{required(:title) => String.t(), required(:page_number) => pos_integer()}
  @type link_target :: {:url, String.t()} | {:page, pos_integer()}
  @type annotation_border :: :none | {number(), number(), number()}
  @type annotation ::
          %{
            required(:type) => :link,
            required(:rect) => {number(), number(), number(), number()},
            required(:target) => link_target(),
            required(:border) => annotation_border()
          }
  @type form_field_type :: :text | :checkbox | :choice | :radio | :push_button | :signature
  @typedoc """
  What a push button does when clicked.

  A push button holds no value, so an action is the only reason to have one.
  """
  @type button_action ::
          :reset
          | {:url, String.t()}
          | {:submit, String.t()}
  @typedoc """
  One button within a radio group.

  A radio group is a single field with several on-page widgets, one per choice.
  `export_value` is the value the field takes when that button is the selected
  one, and is what appears in the filled document.
  """
  @type radio_widget ::
          %{
            required(:export_value) => String.t(),
            required(:page_number) => pos_integer(),
            required(:rect) => {number(), number(), number(), number()}
          }
  @type form_field ::
          %{
            required(:type) => form_field_type(),
            required(:name) => String.t(),
            required(:page_number) => pos_integer(),
            required(:rect) => {number(), number(), number(), number()},
            required(:value) => String.t() | boolean(),
            required(:flags) => non_neg_integer(),
            required(:font) => String.t(),
            required(:size) => number(),
            required(:border) => annotation_border(),
            optional(:max_length) => pos_integer(),
            optional(:tooltip) => String.t(),
            optional(:options) => [String.t()],
            optional(:widgets) => [radio_widget()],
            optional(:action) => button_action(),
            optional(:label) => String.t()
          }
  @type op ::
          text_op()
          | text_rotated_op()
          | draw_op()
          | rect_op()
          | circle_op()
          | move_to_op()
          | line_to_op()
          | bezier_op()
          | stroke_op()
          | fill_op()
          | fill_even_odd_op()
          | clip_op()
          | clip_even_odd_op()
          | line_style_op()
          | graphics_state_op()
          | color_op()
          | image_op()
          | alpha_op()
          | shading_op()
          | begin_marked_content_op()
          | begin_artifact_op()
          | end_marked_content_op()

  @type t :: %__MODULE__{
          page_size: page_size(),
          current_font: font(),
          current_page: pos_integer(),
          pages: %{required(pos_integer()) => [op()]},
          images: %{required(pos_integer()) => image()},
          next_image_id: pos_integer(),
          embedded_fonts: %{optional(String.t()) => embedded_font()},
          structure_tree: [Structure.t()],
          structure_stack: [Structure.t()],
          mcid_counters: %{optional(pos_integer()) => non_neg_integer()},
          language: String.t() | nil,
          pdf_a: {2 | 3, :b | :u | :a} | nil,
          signature: map() | nil,
          bookmarks: [bookmark()],
          annotations: %{required(pos_integer()) => [annotation()]},
          form_fields: [form_field()],
          encryption: map() | nil,
          metadata: %{optional(atom()) => String.t()},
          operations: [op()]
        }

  defstruct page_size: :a4,
            current_font: {"Helvetica", 12},
            current_page: 1,
            pages: %{1 => []},
            images: %{},
            next_image_id: 1,
            embedded_fonts: %{},
            structure_tree: [],
            structure_stack: [],
            mcid_counters: %{},
            language: nil,
            pdf_a: nil,
            signature: nil,
            bookmarks: [],
            annotations: %{},
            form_fields: [],
            encryption: nil,
            metadata: %{},
            operations: []

  @spec page_numbers(t()) :: [pos_integer()]
  def page_numbers(%__MODULE__{} = pdf) do
    pdf.pages
    |> Map.keys()
    |> Enum.sort()
  end

  @spec page_operations(t(), pos_integer()) :: [op()]
  def page_operations(%__MODULE__{} = pdf, page_number)
      when is_integer(page_number) and page_number > 0 do
    Map.get(pdf.pages, page_number, [])
  end

  @spec add_page(t()) :: t()
  def add_page(%__MODULE__{} = pdf) do
    next_page =
      pdf
      |> page_numbers()
      |> List.last()
      |> Kernel.+(1)

    pages = Map.put(pdf.pages, next_page, [])
    %__MODULE__{pdf | pages: pages, current_page: next_page, operations: []}
  end

  @spec set_page(t(), pos_integer()) :: t()
  def set_page(%__MODULE__{} = pdf, page_number)
      when is_integer(page_number) and page_number > 0 do
    case Map.fetch(pdf.pages, page_number) do
      {:ok, ops} ->
        %__MODULE__{pdf | current_page: page_number, operations: ops}

      :error ->
        raise ArgumentError, "unknown page: #{page_number}"
    end
  end

  @spec append_current_op(t(), op()) :: t()
  def append_current_op(%__MODULE__{} = pdf, op) do
    current_ops = page_operations(pdf, pdf.current_page)
    updated_ops = current_ops ++ [op]
    pages = Map.put(pdf.pages, pdf.current_page, updated_ops)
    %__MODULE__{pdf | pages: pages, operations: updated_ops}
  end

  @doc """
  Open a structure element, bracketing whatever is drawn until it is closed.

  Content elements also open a marked-content sequence in the page's content
  stream, which is what ties the drawn operators to this element.
  """
  @spec begin_structure(t(), Structure.tag(), keyword()) :: t()
  def begin_structure(%__MODULE__{} = pdf, tag, opts \\ []) do
    name = Structure.tag_name(tag)

    {pdf, mcid} =
      if Structure.content?(tag) do
        {pdf, mcid} = next_mcid(pdf)
        {append_current_op(pdf, {:begin_marked_content, name, mcid}), mcid}
      else
        {pdf, nil}
      end

    element =
      %{tag: tag, page_number: pdf.current_page, mcid: mcid, kids: []}
      |> put_structure_option(:alt, Keyword.get(opts, :alt))
      |> put_structure_option(:actual_text, Keyword.get(opts, :actual_text))
      |> put_structure_option(:lang, Keyword.get(opts, :lang))
      |> put_structure_option(:title, Keyword.get(opts, :title))
      |> put_structure_option(:scope, normalize_scope(tag, Keyword.get(opts, :scope)))

    %__MODULE__{pdf | structure_stack: [element | pdf.structure_stack]}
  end

  @doc """
  Open an artifact: content that is decoration rather than meaning.

  Rules, borders, background shading and repeating page furniture carry no
  information a reader needs. In a tagged document every operator must be
  either tagged or marked as an artifact — content that is neither is a
  conformance failure, and is read out as stray noise.

  An artifact has no structure element and no marked-content id; it exists only
  to say "skip this".
  """
  @spec begin_artifact(t()) :: t()
  def begin_artifact(%__MODULE__{} = pdf) do
    append_current_op(pdf, {:begin_artifact})
  end

  @doc """
  Close the innermost open artifact.
  """
  @spec end_artifact(t()) :: t()
  def end_artifact(%__MODULE__{} = pdf) do
    append_current_op(pdf, {:end_marked_content})
  end

  @doc """
  Close the innermost open structure element.
  """
  @spec end_structure(t()) :: t()
  def end_structure(%__MODULE__{structure_stack: []}) do
    raise ArgumentError, "no structure element is open"
  end

  def end_structure(%__MODULE__{structure_stack: [element | rest]} = pdf) do
    pdf =
      if Structure.content?(element.tag) do
        append_current_op(pdf, {:end_marked_content})
      else
        pdf
      end

    # Kids accumulate reversed, since each is prepended as it closes.
    element = %{element | kids: Enum.reverse(element.kids)}

    case rest do
      [] ->
        %__MODULE__{pdf | structure_stack: [], structure_tree: pdf.structure_tree ++ [element]}

      [parent | ancestors] ->
        parent = %{parent | kids: [element | parent.kids]}
        %__MODULE__{pdf | structure_stack: [parent | ancestors]}
    end
  end

  @doc """
  Set the document's natural language, as a BCP 47 tag such as `"en-GB"`.

  Required for a document to be accessible: without it a screen reader has to
  guess which language to pronounce the text as.
  """
  @spec set_language(t(), String.t()) :: t()
  def set_language(%__MODULE__{} = pdf, language) when is_binary(language) and language != "" do
    %__MODULE__{pdf | language: language}
  end

  def set_language(%__MODULE__{}, other),
    do: raise(ArgumentError, "language must be a non-empty string, got: #{inspect(other)}")

  @doc """
  Declare a PDF/A conformance level, adding what archival validity requires.

  Sets an sRGB output intent, a `/Metadata` stream carrying the PDF/A
  identification, and a file identifier.
  """
  @spec set_pdf_a(t(), atom()) :: t()
  def set_pdf_a(%__MODULE__{} = pdf, level) do
    %__MODULE__{pdf | pdf_a: normalize_pdf_a_level(level)}
  end

  defp normalize_pdf_a_level(:a2b), do: {2, :b}
  defp normalize_pdf_a_level(:a2u), do: {2, :u}
  defp normalize_pdf_a_level(:a2a), do: {2, :a}
  defp normalize_pdf_a_level(:a3b), do: {3, :b}
  defp normalize_pdf_a_level(:a3u), do: {3, :u}
  defp normalize_pdf_a_level(:a3a), do: {3, :a}

  defp normalize_pdf_a_level(other) do
    raise ArgumentError,
          "unknown PDF/A level: #{inspect(other)}. " <>
            "Expected one of :a2b, :a2u, :a2a, :a3b, :a3u, :a3a."
  end

  @doc """
  Record the intent to sign a signature field.

  The signature itself cannot be computed here: it covers the finished file,
  so it is applied during `Tincture.export/2`.
  """
  @spec set_signature(t(), String.t(), keyword()) :: t()
  def set_signature(%__MODULE__{} = pdf, field_name, opts) when is_binary(field_name) do
    field = Enum.find(pdf.form_fields, &(&1.name == field_name and &1.type == :signature))

    unless field do
      names =
        pdf.form_fields
        |> Enum.filter(&(&1.type == :signature))
        |> Enum.map_join(", ", &inspect(&1.name))

      raise ArgumentError,
            "no signature field named #{inspect(field_name)}. " <>
              if(names == "",
                do: "Add one with signature_field/7 before signing.",
                else: "Known signature fields: #{names}."
              )
    end

    if pdf.signature do
      raise ArgumentError,
            "this document is already being signed as #{inspect(pdf.signature.field_name)}. " <>
              "Signing more than one field needs incremental updates, which Tincture " <>
              "does not yet produce."
    end

    signature = %{
      field_name: field_name,
      private_key: Keyword.fetch!(opts, :private_key),
      certificate: Keyword.fetch!(opts, :certificate),
      chain: Keyword.get(opts, :chain, []),
      digest: normalize_digest(Keyword.get(opts, :digest, :sha256)),
      signing_time: Keyword.get_lazy(opts, :signing_time, fn -> DateTime.utc_now() end),
      reserved_bytes: Keyword.get(opts, :reserved_bytes, Sign.default_reserved_bytes()),
      name: Keyword.get(opts, :name),
      reason: Keyword.get(opts, :reason),
      location: Keyword.get(opts, :location),
      contact: Keyword.get(opts, :contact)
    }

    %__MODULE__{pdf | signature: signature}
  end

  defp normalize_digest(digest) when digest in [:sha256, :sha384, :sha512], do: digest

  defp normalize_digest(other),
    do:
      raise(
        ArgumentError,
        "digest must be :sha256, :sha384 or :sha512, got: #{inspect(other)}"
      )

  @doc """
  Whether this document carries logical structure.
  """
  @spec tagged?(t()) :: boolean()
  def tagged?(%__MODULE__{structure_tree: tree}), do: tree != []

  defp next_mcid(%__MODULE__{} = pdf) do
    page = pdf.current_page
    mcid = Map.get(pdf.mcid_counters, page, 0)
    {%__MODULE__{pdf | mcid_counters: Map.put(pdf.mcid_counters, page, mcid + 1)}, mcid}
  end

  defp put_structure_option(element, _key, nil), do: element
  defp put_structure_option(element, key, value), do: Map.put(element, key, value)

  defp normalize_scope(_tag, nil), do: nil

  defp normalize_scope(:th, scope) when scope in [:row, :column, :both], do: scope

  defp normalize_scope(:th, other),
    do:
      raise(
        ArgumentError,
        ":scope must be :row, :column or :both, got: #{inspect(other)}"
      )

  defp normalize_scope(tag, _scope),
    do: raise(ArgumentError, ":scope only applies to a :th element, not #{inspect(tag)}")

  @spec register_image(t(), image()) :: {t(), pos_integer()}
  def register_image(%__MODULE__{} = pdf, image) when is_map(image) do
    image_id = pdf.next_image_id
    images = Map.put(pdf.images, image_id, image)
    {%__MODULE__{pdf | images: images, next_image_id: image_id + 1}, image_id}
  end

  @spec register_ttf_font(t(), String.t(), Path.t()) :: t()
  def register_ttf_font(%__MODULE__{} = pdf, font_name, path)
      when is_binary(font_name) and byte_size(font_name) > 0 and is_binary(path) and
             byte_size(path) > 0 do
    register_ttf_font(pdf, font_name, path, [])
  end

  @spec register_ttf_font(t(), String.t(), Path.t(), [embedded_font_option()]) :: t()
  def register_ttf_font(%__MODULE__{} = pdf, font_name, path, opts)
      when is_binary(font_name) and byte_size(font_name) > 0 and is_binary(path) and
             byte_size(path) > 0 and is_list(opts) do
    register_embedded_font(pdf, font_name, path, :ttf, "TTF", opts)
  end

  @spec register_otf_font(t(), String.t(), Path.t()) :: t()
  def register_otf_font(%__MODULE__{} = pdf, font_name, path)
      when is_binary(font_name) and byte_size(font_name) > 0 and is_binary(path) and
             byte_size(path) > 0 do
    register_otf_font(pdf, font_name, path, [])
  end

  @spec register_otf_font(t(), String.t(), Path.t(), [embedded_font_option()]) :: t()
  def register_otf_font(%__MODULE__{} = pdf, font_name, path, opts)
      when is_binary(font_name) and byte_size(font_name) > 0 and is_binary(path) and
             byte_size(path) > 0 and is_list(opts) do
    register_embedded_font(pdf, font_name, path, :otf, "OTF", opts)
  end

  defp register_embedded_font(%__MODULE__{} = pdf, font_name, path, format, format_label, opts) do
    subset = normalize_subset_option(Keyword.get(opts, :subset, :used_text))

    enforce_embedding_permissions =
      normalize_embedding_permissions_option(
        Keyword.get(opts, :enforce_embedding_permissions, false)
      )

    case File.read(path) do
      {:ok, data} ->
        case parse_embedded_font_metadata(format, data) do
          {:ok, metadata} ->
            warn_embedding_permissions_if_needed(
              metadata,
              subset,
              enforce_embedding_permissions,
              format_label,
              path
            )

            enforce_embedding_permissions!(
              metadata,
              subset,
              enforce_embedding_permissions,
              format_label,
              path
            )

            embedded_font =
              %{format: format, name: font_name, data: data, subset: subset}
              |> Map.merge(metadata)

            %__MODULE__{
              pdf
              | embedded_fonts: Map.put(pdf.embedded_fonts, font_name, embedded_font)
            }

          :error ->
            raise ArgumentError, "invalid #{format_label} file: #{path}"
        end

      {:error, _reason} ->
        raise ArgumentError, "unable to read #{format_label} file: #{path}"
    end
  end

  defp parse_embedded_font_metadata(:ttf, data) do
    with true <- ttf_signature?(data),
         {:ok, ttf_metrics} <- TTF.parse_basic_tables(data) do
      {:ok, %{ttf_metrics: ttf_metrics}}
    else
      _ -> :error
    end
  end

  defp parse_embedded_font_metadata(:otf, <<"OTTO", _::binary>> = data) do
    case TTF.parse_basic_tables(data) do
      {:ok, ttf_metrics} -> {:ok, %{ttf_metrics: ttf_metrics}}
      :error -> {:ok, %{}}
    end
  end

  defp parse_embedded_font_metadata(:otf, _data), do: :error

  defp ttf_signature?(<<0, 1, 0, 0, _::binary>>), do: true
  defp ttf_signature?(<<"true", _::binary>>), do: true
  defp ttf_signature?(<<"typ1", _::binary>>), do: true
  defp ttf_signature?(_data), do: false

  defp normalize_subset_option(:none), do: :none
  defp normalize_subset_option(:ascii_basic), do: :ascii_basic
  defp normalize_subset_option(:used_text), do: :used_text

  defp normalize_subset_option(_other),
    do: raise(ArgumentError, "subset must be :none, :ascii_basic, or :used_text")

  defp normalize_embedding_permissions_option(value) when is_boolean(value), do: value

  defp normalize_embedding_permissions_option(_other),
    do: raise(ArgumentError, "enforce_embedding_permissions must be a boolean")

  defp warn_embedding_permissions_if_needed(
         _metadata,
         _subset,
         true,
         _format_label,
         _path
       ),
       do: :ok

  defp warn_embedding_permissions_if_needed(metadata, subset, false, format_label, path) do
    case Map.get(metadata, :ttf_metrics) do
      %{os2_fs_type: fs_type} when is_integer(fs_type) and fs_type >= 0 ->
        case fs_type_restrictions(fs_type, subset) do
          [] ->
            :ok

          [:restricted] ->
            Logger.warning(
              "embedded font has restrictive OS/2 fsType (#{fs_type}) for #{format_label} file: #{path}; pass enforce_embedding_permissions: true to reject this font"
            )

          [:bitmap_only] ->
            Logger.warning(
              "embedded font is bitmap-only via OS/2 fsType (#{fs_type}) for #{format_label} file: #{path}; pass enforce_embedding_permissions: true to reject this font"
            )

          [:no_subsetting] ->
            Logger.warning(
              "embedded font disallows subsetting via OS/2 fsType (#{fs_type}) for #{format_label} file: #{path}; pass enforce_embedding_permissions: true to reject this font"
            )

          restrictions ->
            Logger.warning(
              "embedded font has OS/2 fsType (#{fs_type}) restrictions (#{format_fs_type_restrictions(restrictions)}) for #{format_label} file: #{path}; pass enforce_embedding_permissions: true to reject this font"
            )
        end

      _ ->
        :ok
    end
  end

  defp enforce_embedding_permissions!(
         _metadata,
         _subset,
         false,
         _format_label,
         _path
       ),
       do: :ok

  defp enforce_embedding_permissions!(metadata, subset, true, format_label, path) do
    case Map.get(metadata, :ttf_metrics) do
      %{os2_fs_type: fs_type} when is_integer(fs_type) and fs_type >= 0 ->
        case fs_type_restrictions(fs_type, subset) do
          [] ->
            :ok

          [:restricted] ->
            raise(
              ArgumentError,
              "font embedding restricted by OS/2 fsType (#{fs_type}) for #{format_label} file: #{path}"
            )

          [:bitmap_only] ->
            raise(
              ArgumentError,
              "font allows bitmap embedding only via OS/2 fsType (#{fs_type}) for #{format_label} file: #{path}"
            )

          [:no_subsetting] ->
            raise(
              ArgumentError,
              "font disallows subsetting via OS/2 fsType (#{fs_type}) for #{format_label} file: #{path}"
            )

          restrictions ->
            raise(
              ArgumentError,
              "font has OS/2 fsType (#{fs_type}) restrictions (#{format_fs_type_restrictions(restrictions)}) for #{format_label} file: #{path}"
            )
        end

      _ ->
        :ok
    end
  end

  defp fs_type_restrictions(fs_type, subset) when is_integer(fs_type) and is_atom(subset) do
    []
    |> maybe_add_fs_type_restriction(Bitwise.band(fs_type, 0x0002) != 0, :restricted)
    |> maybe_add_fs_type_restriction(Bitwise.band(fs_type, 0x0200) != 0, :bitmap_only)
    |> maybe_add_fs_type_restriction(
      subset != :none and Bitwise.band(fs_type, 0x0100) != 0,
      :no_subsetting
    )
  end

  defp maybe_add_fs_type_restriction(restrictions, true, restriction),
    do: restrictions ++ [restriction]

  defp maybe_add_fs_type_restriction(restrictions, false, _restriction), do: restrictions

  defp format_fs_type_restrictions(restrictions) when is_list(restrictions) do
    Enum.map_join(restrictions, ", ", &fs_type_restriction_label/1)
  end

  defp fs_type_restriction_label(:restricted), do: "embedding restricted"
  defp fs_type_restriction_label(:bitmap_only), do: "bitmap embedding only"
  defp fs_type_restriction_label(:no_subsetting), do: "disallows subsetting"

  @spec add_bookmark(t(), String.t(), pos_integer()) :: t()
  def add_bookmark(%__MODULE__{} = pdf, title, page_number)
      when is_binary(title) and byte_size(title) > 0 and is_integer(page_number) and
             page_number > 0 do
    if Map.has_key?(pdf.pages, page_number) do
      bookmark = %{title: title, page_number: page_number}
      %__MODULE__{pdf | bookmarks: pdf.bookmarks ++ [bookmark]}
    else
      raise ArgumentError, "unknown page: #{page_number}"
    end
  end

  @spec page_annotations(t(), pos_integer()) :: [annotation()]
  def page_annotations(%__MODULE__{} = pdf, page_number)
      when is_integer(page_number) and page_number > 0 do
    Map.get(pdf.annotations, page_number, [])
  end

  @spec add_link(t(), {number(), number(), number(), number()}, link_target(), keyword()) :: t()
  def add_link(%__MODULE__{} = pdf, {x1, y1, x2, y2}, target, opts \\ [])
      when is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2) and is_list(opts) do
    annotation = %{
      type: :link,
      # PDF requires the rectangle in lower-left / upper-right order, so
      # normalise rather than emitting a rect a viewer would treat as empty.
      rect: {min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)},
      target: normalize_link_target(pdf, target),
      border: normalize_annotation_border(Keyword.get(opts, :border, :none))
    }

    page_number = Keyword.get(opts, :page, pdf.current_page)

    unless Map.has_key?(pdf.pages, page_number) do
      raise ArgumentError, "unknown page: #{page_number}"
    end

    existing = page_annotations(pdf, page_number)
    annotations = Map.put(pdf.annotations, page_number, existing ++ [annotation])
    %__MODULE__{pdf | annotations: annotations}
  end

  defp normalize_link_target(%__MODULE__{}, {:url, url})
       when is_binary(url) and byte_size(url) > 0 do
    {:url, url}
  end

  # Deliberately not checked against the existing pages here: linking forward to
  # a page you have not added yet is the common case (a table of contents is
  # written before the pages it points at). The reference is resolved at export,
  # once every page exists.
  defp normalize_link_target(%__MODULE__{}, {:page, page_number})
       when is_integer(page_number) and page_number > 0 do
    {:page, page_number}
  end

  defp normalize_link_target(%__MODULE__{} = pdf, url) when is_binary(url) do
    normalize_link_target(pdf, {:url, url})
  end

  defp normalize_link_target(%__MODULE__{}, other) do
    raise ArgumentError,
          "link target must be a URL string, {:url, url}, or {:page, page_number}, got: " <>
            inspect(other)
  end

  defp normalize_annotation_border(:none), do: :none

  defp normalize_annotation_border({horizontal, vertical, width})
       when is_number(horizontal) and is_number(vertical) and is_number(width) and
              horizontal >= 0 and vertical >= 0 and width >= 0 do
    {horizontal, vertical, width}
  end

  defp normalize_annotation_border(other) do
    raise ArgumentError,
          "border must be :none or {horizontal, vertical, width}, got: #{inspect(other)}"
  end

  # Field flag bits from the PDF specification, table 226. Bit numbering is
  # 1-based there, so ReadOnly is bit 1 and the value is 1 <<< 0.
  @field_flag_read_only 1
  @field_flag_required 2
  @field_flag_no_export 4
  @field_flag_multiline 4096
  @field_flag_password 8192
  @field_flag_combo 131_072
  @field_flag_edit 262_144
  @field_flag_sort 524_288
  # Bit 15. Without it a viewer lets the user deselect the whole group by
  # clicking the selected button, which is rarely what a radio group means.
  @field_flag_no_toggle_to_off 16_384
  # Bit 16 turns a /Btn field into a radio group, bit 17 into a push button.
  # A field with neither is a checkbox.
  @field_flag_radio 32_768
  @field_flag_push_button 65_536

  @spec add_form_field(
          t(),
          form_field_type(),
          String.t(),
          {number(), number(), number(), number()},
          keyword()
        ) :: t()
  def add_form_field(%__MODULE__{} = pdf, type, name, {x1, y1, x2, y2}, opts)
      when type in [:text, :checkbox, :choice, :push_button, :signature] and is_binary(name) and
             is_list(opts) do
    if name == "" do
      raise ArgumentError, "form field name must not be empty"
    end

    page_number = Keyword.get(opts, :page, pdf.current_page)

    unless Map.has_key?(pdf.pages, page_number) do
      raise ArgumentError, "unknown page: #{page_number}"
    end

    if Enum.any?(pdf.form_fields, &(&1.name == name)) do
      raise ArgumentError,
            "duplicate form field name: #{inspect(name)}. Field names address values in the " <>
              "filled document, so they must be unique."
    end

    field = %{
      type: type,
      name: name,
      page_number: page_number,
      # PDF wants lower-left / upper-right, so normalise rather than emitting a
      # rectangle a viewer would treat as empty.
      rect: {min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)},
      value: normalize_field_value(type, Keyword.get(opts, :value)),
      flags: field_flags(type, opts),
      font: normalize_field_font(Keyword.get(opts, :font, "Helvetica")),
      size: normalize_field_size(Keyword.get(opts, :size, 0)),
      border: normalize_annotation_border(Keyword.get(opts, :border, :none))
    }

    field =
      field
      |> maybe_put_field(:max_length, normalize_max_length(Keyword.get(opts, :max_length)))
      |> maybe_put_field(:tooltip, Keyword.get(opts, :tooltip))
      |> maybe_put_field(:options, normalize_choice_options(type, Keyword.get(opts, :options)))
      |> maybe_put_field(:action, normalize_action(type, Keyword.get(opts, :action)))
      |> maybe_put_field(:label, normalize_label(type, Keyword.get(opts, :label)))

    %__MODULE__{pdf | form_fields: pdf.form_fields ++ [field]}
  end

  @doc """
  Add a radio button group: one field, one widget per choice.

  Unlike every other field type this is not one dictionary. The specification
  models a radio group as a parent field holding the value, with a kid widget
  for each button, and the button's export value is the name of its "on"
  appearance state. Choosing a button sets the parent's value to that name.

  `buttons` is a list of keyword lists, each needing `:value`, `:x`, `:y` and
  `:size`, and optionally `:page`.
  """
  @spec add_radio_group(t(), String.t(), [keyword()], keyword()) :: t()
  def add_radio_group(%__MODULE__{} = pdf, name, buttons, opts)
      when is_binary(name) and is_list(buttons) and is_list(opts) do
    if name == "" do
      raise ArgumentError, "form field name must not be empty"
    end

    if buttons == [] do
      raise ArgumentError, "a radio group needs at least one button"
    end

    if Enum.any?(pdf.form_fields, &(&1.name == name)) do
      raise ArgumentError,
            "duplicate form field name: #{inspect(name)}. Field names address values in the " <>
              "filled document, so they must be unique."
    end

    widgets = Enum.map(buttons, &normalize_radio_widget(pdf, &1, opts))
    export_values = Enum.map(widgets, & &1.export_value)

    duplicates = export_values -- Enum.uniq(export_values)

    if duplicates != [] do
      raise ArgumentError,
            "duplicate radio button value(s): #{inspect(Enum.uniq(duplicates))}. " <>
              "A button's value identifies which one is selected, so they must be distinct."
    end

    selected = normalize_radio_selection(Keyword.get(opts, :selected), export_values)

    flags =
      opts
      |> field_flags(:radio)
      |> flag_if(Keyword.get(opts, :allow_deselect, false) == false, @field_flag_no_toggle_to_off)

    field =
      %{
        type: :radio,
        name: name,
        # A radio group's own rectangle is meaningless - the kids carry the
        # geometry - but the field shape requires one, so use the first kid's.
        page_number: hd(widgets).page_number,
        rect: hd(widgets).rect,
        value: selected,
        flags: flags,
        font: normalize_field_font(Keyword.get(opts, :font, "Helvetica")),
        size: normalize_field_size(Keyword.get(opts, :size, 0)),
        border: normalize_annotation_border(Keyword.get(opts, :border, :none)),
        widgets: widgets
      }
      |> maybe_put_field(:tooltip, Keyword.get(opts, :tooltip))

    %__MODULE__{pdf | form_fields: pdf.form_fields ++ [field]}
  end

  defp normalize_radio_widget(pdf, button, opts) when is_list(button) do
    value = Keyword.get(button, :value)

    unless is_binary(value) and value != "" do
      raise ArgumentError,
            "each radio button needs a non-empty string :value, got: #{inspect(value)}"
    end

    if value == "Off" do
      raise ArgumentError,
            ~s(a radio button cannot use "Off" as its value: the specification reserves it ) <>
              "for the state where nothing is selected"
    end

    x = fetch_number!(button, :x)
    y = fetch_number!(button, :y)
    size = fetch_number!(button, :size)

    unless size > 0 do
      raise ArgumentError, "radio button :size must be positive, got: #{inspect(size)}"
    end

    page_number = Keyword.get(button, :page, Keyword.get(opts, :page, pdf.current_page))

    unless Map.has_key?(pdf.pages, page_number) do
      raise ArgumentError, "unknown page: #{page_number}"
    end

    %{export_value: value, page_number: page_number, rect: {x, y, x + size, y + size}}
  end

  defp normalize_radio_widget(_pdf, other, _opts),
    do:
      raise(
        ArgumentError,
        "each radio button must be a keyword list with :value, :x, :y and :size, " <>
          "got: #{inspect(other)}"
      )

  defp fetch_number!(button, key) do
    case Keyword.get(button, key) do
      value when is_number(value) ->
        value

      other ->
        raise ArgumentError,
              "radio button #{inspect(key)} must be a number, got: #{inspect(other)}"
    end
  end

  defp normalize_radio_selection(nil, _export_values), do: ""

  defp normalize_radio_selection(selected, export_values) when is_binary(selected) do
    if selected in export_values do
      selected
    else
      raise ArgumentError,
            "selected radio value #{inspect(selected)} is not one of #{inspect(export_values)}"
    end
  end

  defp normalize_radio_selection(other, _export_values),
    do: raise(ArgumentError, ":selected must be a string, got: #{inspect(other)}")

  defp maybe_put_field(field, _key, nil), do: field
  defp maybe_put_field(field, key, value), do: Map.put(field, key, value)

  defp normalize_field_value(:checkbox, nil), do: false
  defp normalize_field_value(:checkbox, value) when is_boolean(value), do: value

  defp normalize_field_value(:checkbox, other),
    do: raise(ArgumentError, "checkbox value must be a boolean, got: #{inspect(other)}")

  # Neither of these holds a value: a push button acts, and a signature field is
  # filled by whoever signs it.
  defp normalize_field_value(type, nil) when type in [:push_button, :signature], do: ""

  defp normalize_field_value(type, _value) when type in [:push_button, :signature],
    do: raise(ArgumentError, "#{type} fields do not take a :value")

  defp normalize_field_value(_type, nil), do: ""
  defp normalize_field_value(_type, value) when is_binary(value), do: value

  defp normalize_field_value(type, other),
    do: raise(ArgumentError, "#{type} field value must be a string, got: #{inspect(other)}")

  # A size of 0 means "auto": the viewer picks a size that fits the box. That
  # is the sane default for a field whose height the caller chose.
  #
  # Whole sizes stay integers so the /DA string reads "0 Tf" rather than
  # "0.0 Tf" - both are legal, but the integer form is what every other
  # generator emits and what a human reading the PDF expects.
  # A field's value is rendered by the viewer from its /DA string, which
  # resolves against the AcroForm resource dictionary - and that can only carry
  # the standard 14 fonts. An embedded font named here would emit a font
  # dictionary no viewer can resolve, so the value would silently not render.
  defp normalize_field_font(font_name) when is_binary(font_name) do
    if Font.standard_font?(font_name) do
      font_name
    else
      raise ArgumentError,
            "form fields can only use the standard 14 fonts, got: #{inspect(font_name)}. " <>
              "A field's value is drawn by the viewer from the AcroForm resource dictionary, " <>
              "which cannot reference an embedded font. Static text is unaffected."
    end
  end

  defp normalize_field_font(other),
    do: raise(ArgumentError, "form field font must be a string, got: #{inspect(other)}")

  defp normalize_field_size(value) when is_integer(value) and value >= 0, do: value

  defp normalize_field_size(value) when is_float(value) and value >= 0 do
    if value == Float.round(value), do: trunc(value), else: value
  end

  defp normalize_field_size(other),
    do: raise(ArgumentError, "font size must be >= 0 (0 means auto), got: #{inspect(other)}")

  defp normalize_max_length(nil), do: nil
  defp normalize_max_length(value) when is_integer(value) and value > 0, do: value

  defp normalize_max_length(other),
    do: raise(ArgumentError, "max_length must be a positive integer, got: #{inspect(other)}")

  defp normalize_choice_options(:choice, options) when is_list(options) and options != [] do
    Enum.map(options, fn
      option when is_binary(option) ->
        option

      other ->
        raise ArgumentError, "choice options must be strings, got: #{inspect(other)}"
    end)
  end

  defp normalize_choice_options(:choice, other),
    do:
      raise(
        ArgumentError,
        "a choice field needs a non-empty :options list, got: #{inspect(other)}"
      )

  defp normalize_choice_options(_type, nil), do: nil

  defp normalize_choice_options(type, _options),
    do: raise(ArgumentError, "#{type} fields do not take :options")

  defp normalize_action(:push_button, nil),
    do:
      raise(
        ArgumentError,
        "a push button needs an :action - it holds no value, so without one it does nothing. " <>
          "Use :reset, {:url, url} or {:submit, url}."
      )

  defp normalize_action(:push_button, :reset), do: :reset

  defp normalize_action(:push_button, {kind, url})
       when kind in [:url, :submit] and is_binary(url) and url != "",
       do: {kind, url}

  defp normalize_action(:push_button, other),
    do:
      raise(
        ArgumentError,
        "unsupported button action: #{inspect(other)}. " <>
          "Expected :reset, {:url, url} or {:submit, url}."
      )

  defp normalize_action(_type, nil), do: nil

  defp normalize_action(type, _action),
    do: raise(ArgumentError, "#{type} fields do not take an :action")

  defp normalize_label(:push_button, nil), do: nil
  defp normalize_label(:push_button, label) when is_binary(label), do: label

  defp normalize_label(:push_button, other),
    do: raise(ArgumentError, "button :label must be a string, got: #{inspect(other)}")

  defp normalize_label(_type, nil), do: nil

  defp normalize_label(type, _label),
    do: raise(ArgumentError, "#{type} fields do not take a :label")

  defp field_flags(opts, type) when is_list(opts), do: field_flags(type, opts)

  defp field_flags(type, opts) do
    base =
      0
      |> flag_if(Keyword.get(opts, :read_only, false), @field_flag_read_only)
      |> flag_if(Keyword.get(opts, :required, false), @field_flag_required)
      |> flag_if(Keyword.get(opts, :no_export, false), @field_flag_no_export)

    type_flags(type, base, opts)
  end

  defp type_flags(:text, base, opts) do
    base
    |> flag_if(Keyword.get(opts, :multiline, false), @field_flag_multiline)
    |> flag_if(Keyword.get(opts, :password, false), @field_flag_password)
  end

  defp type_flags(:choice, base, opts) do
    base
    |> flag_if(Keyword.get(opts, :dropdown, true), @field_flag_combo)
    |> flag_if(Keyword.get(opts, :editable, false), @field_flag_edit)
    |> flag_if(Keyword.get(opts, :sort, false), @field_flag_sort)
  end

  defp type_flags(:checkbox, base, _opts), do: base
  defp type_flags(:radio, base, _opts), do: Bitwise.bor(base, @field_flag_radio)
  defp type_flags(:push_button, base, _opts), do: Bitwise.bor(base, @field_flag_push_button)
  defp type_flags(:signature, base, _opts), do: base

  defp flag_if(flags, true, bit), do: Bitwise.bor(flags, bit)
  defp flag_if(flags, false, _bit), do: flags

  defp flag_if(_flags, other, _bit),
    do: raise(ArgumentError, "form field flags must be booleans, got: #{inspect(other)}")

  @spec set_metadata(t(), map() | keyword()) :: t()
  def set_metadata(%__MODULE__{} = pdf, metadata) when is_map(metadata) or is_list(metadata) do
    normalized =
      metadata
      |> Enum.into(%{})
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        normalized_key =
          case key do
            :title -> :title
            :author -> :author
            :keywords -> :keywords
            :subject -> :subject
            :creator -> :creator
            "title" -> :title
            "author" -> :author
            "keywords" -> :keywords
            "subject" -> :subject
            "creator" -> :creator
            _ -> :ignore
          end

        case normalized_key do
          :ignore ->
            acc

          key_atom ->
            if is_binary(value) do
              Map.put(acc, key_atom, value)
            else
              raise ArgumentError, "metadata values must be strings"
            end
        end
      end)

    %__MODULE__{pdf | metadata: normalized}
  end
end

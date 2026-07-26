defmodule Tincture.PDF do
  @moduledoc """
  Internal PDF state container.
  """

  alias Tincture.Font.TTF
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
  @type draw_op :: {:line, number(), number(), number(), number()}
  @type rect_op :: {:rectangle, number(), number(), number(), number()}
  @type circle_op :: {:circle, number(), number(), number()}
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

  @type t :: %__MODULE__{
          page_size: page_size(),
          current_font: font(),
          current_page: pos_integer(),
          pages: %{required(pos_integer()) => [op()]},
          images: %{required(pos_integer()) => image()},
          next_image_id: pos_integer(),
          embedded_fonts: %{optional(String.t()) => embedded_font()},
          bookmarks: [bookmark()],
          annotations: %{required(pos_integer()) => [annotation()]},
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
            bookmarks: [],
            annotations: %{},
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

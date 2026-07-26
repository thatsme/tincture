defmodule Tincture.PDF.Serialize do
  @moduledoc """
  Turns a `Tincture.PDF` document into PDF bytes.

  `export/1` assembles the object graph — catalog, page tree, content
  streams, resources, annotations, outlines — then writes the cross-reference
  table and trailer.

  Font embedding is a large enough concern to live on its own in
  `Tincture.PDF.FontEmbed`, which this module calls once and then treats as a
  set of object references. Image XObjects, the object table and the page
  structure are handled here.

  Content streams are deflate-compressed, and text is encoded according to the
  font it is drawn with: literal or UTF-16BE for simple fonts, glyph indices
  for composite ones. See `Tincture.PDF.Object` for the string encoding rules.
  """

  require Logger

  alias Tincture.PDF
  alias Tincture.PDF.FontEmbed
  alias Tincture.PDF.Object
  alias Tincture.PDF.Page

  @spec export(PDF.t()) :: binary()
  def export(%PDF{} = pdf) do
    {page_width, page_height} = Page.media_box(pdf.page_size)
    page_numbers = PDF.page_numbers(pdf)
    page_count = length(page_numbers)
    embedded_fonts_start_id = 3 + page_count * 2

    page_object_refs =
      page_numbers
      |> Enum.with_index()
      |> Map.new(fn {page_number, idx} -> {page_number, page_object_id(idx)} end)

    {embedded_font_refs, embedded_font_objects, embedded_font_text_modes, images_start_id} =
      FontEmbed.build_embedded_font_objects(pdf, page_numbers, embedded_fonts_start_id)

    {image_object_refs, image_objects, outlines_start_id} =
      build_image_objects(pdf.images, images_start_id)

    {outlines_ref, outline_objects} =
      build_outline_objects(pdf.bookmarks, page_object_refs, outlines_start_id)

    form_fields_start_id = outlines_start_id + length(outline_objects)

    {form_field_refs, form_field_objects} =
      build_form_field_objects(pdf.form_fields, page_object_refs, form_fields_start_id)

    kids =
      page_numbers
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {_page_number, idx} ->
        "#{page_object_id(idx)} 0 R"
      end)

    page_objects =
      page_numbers
      |> Enum.with_index()
      |> Enum.flat_map(fn {page_number, idx} ->
        operations = PDF.page_operations(pdf, page_number)
        {font_aliases, font_resources} = font_resources(operations, embedded_font_refs)
        xobject_resources = xobject_resources(operations, image_object_refs)
        content_stream = content_stream(operations, font_aliases, embedded_font_text_modes)
        content_length = IO.iodata_length(content_stream)
        resources = resource_dictionary(font_resources, xobject_resources)

        annots =
          annotations_entry(
            PDF.page_annotations(pdf, page_number),
            widget_refs_for_page(form_field_refs, page_number),
            page_object_refs
          )

        page_body =
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{Object.num(page_width)} #{Object.num(page_height)}]#{resources} /Contents #{content_object_id(idx)} 0 R#{annots} >>"

        content_body = ["<< /Length #{content_length} >>\nstream\n", content_stream, "endstream"]

        [page_body, content_body]
      end)

    base_object_bodies = [
      catalog_object_body(outlines_ref, form_field_refs, pdf.form_fields),
      "<< /Type /Pages /Kids [#{kids}] /Count #{page_count} >>"
      | page_objects ++
          embedded_font_objects ++ image_objects ++ outline_objects ++ form_field_objects
    ]

    {object_bodies, info_ref} =
      case info_object_body(pdf.metadata) do
        nil ->
          {base_object_bodies, nil}

        info_body ->
          info_id = length(base_object_bodies) + 1
          {base_object_bodies ++ [info_body], info_id}
      end

    build_pdf(object_bodies, info_ref)
  end

  defp page_object_id(index), do: 3 + index * 2
  defp content_object_id(index), do: page_object_id(index) + 1

  defp catalog_object_body(outlines_ref, form_field_refs, form_fields) do
    outlines =
      case outlines_ref do
        nil -> ""
        id -> " /Outlines #{id} 0 R /PageMode /UseOutlines"
      end

    "<< /Type /Catalog /Pages 2 0 R#{outlines}#{acro_form_entry(form_field_refs, form_fields)} >>"
  end

  defp acro_form_entry([], _form_fields), do: ""

  defp acro_form_entry(form_field_refs, form_fields) do
    fields = Enum.map_join(form_field_refs, " ", fn {_name, {id, _page}} -> "#{id} 0 R" end)

    # /NeedAppearances tells the viewer to build each field's appearance from
    # its /DA string. Generating appearance streams here instead would mean
    # laying out and rendering the value of every field at export time, and
    # getting it wrong shows up as an invisible or clipped value rather than an
    # error. Every mainstream viewer honours the flag.
    #
    # /DR is the resource dictionary the /DA strings resolve font names
    # against; without it a viewer has no font to render the value with.
    " /AcroForm << /Fields [#{fields}] /NeedAppearances true" <>
      " /DA #{Object.format_text(default_appearance_string(form_fields))}" <>
      " /DR << /Font << #{acro_form_font_resources(form_fields)} >> >> >>"
  end

  # The document-level default appearance, used for any field that does not
  # override it.
  defp default_appearance_string(_form_fields), do: "/Helv 0 Tf 0 g"

  defp acro_form_font_resources(form_fields) do
    form_fields
    |> Enum.map(& &1.font)
    |> Enum.uniq()
    |> Enum.map_join(" ", fn font_name ->
      "#{acro_form_font_alias(font_name)} << /Type /Font /Subtype /Type1 " <>
        "/BaseFont /#{Object.sanitize_name(font_name)} /Encoding /WinAnsiEncoding >>"
    end)
  end

  # /Helv is the conventional alias for Helvetica in an AcroForm resource
  # dictionary; anything else gets a name derived from the font.
  defp acro_form_font_alias("Helvetica"), do: "/Helv"
  defp acro_form_font_alias(font_name), do: "/" <> Object.sanitize_name(font_name)

  defp build_outline_objects([], _page_object_refs, _start_id), do: {nil, []}

  defp build_outline_objects(bookmarks, page_object_refs, start_id) do
    count = length(bookmarks)
    root_id = start_id
    item_ids = Enum.to_list((start_id + 1)..(start_id + count))
    first_item_id = hd(item_ids)
    last_item_id = List.last(item_ids)

    root_object =
      "<< /Type /Outlines /First #{first_item_id} 0 R /Last #{last_item_id} 0 R /Count #{count} >>"

    item_objects =
      bookmarks
      |> Enum.with_index()
      |> Enum.map(fn {bookmark, idx} ->
        item_id = Enum.at(item_ids, idx)
        prev_ref = if idx > 0, do: " /Prev #{Enum.at(item_ids, idx - 1)} 0 R", else: ""
        next_ref = if idx + 1 < count, do: " /Next #{Enum.at(item_ids, idx + 1)} 0 R", else: ""
        page_object_id = page_object_refs |> Map.fetch!(bookmark.page_number)
        title = Object.format_text(bookmark.title)

        {
          item_id,
          "<< /Title #{title} /Parent #{root_id} 0 R#{prev_ref}#{next_ref} /Dest [#{page_object_id} 0 R /Fit] >>"
        }
      end)
      |> Enum.sort_by(fn {item_id, _body} -> item_id end)
      |> Enum.map(fn {_item_id, body} -> body end)

    {root_id, [root_object | item_objects]}
  end

  defp build_image_objects(images, start_object_id) do
    image_ids = images |> Map.keys() |> Enum.sort()

    {refs, objects_reversed, next_object_id} =
      Enum.reduce(image_ids, {%{}, [], start_object_id}, fn image_id,
                                                            {acc_refs, acc_objects, next_id} ->
        image = Map.fetch!(images, image_id)

        case Map.get(image, :alpha_data) do
          nil ->
            refs = Map.put(acc_refs, image_id, %{main: next_id})
            object = image_object_body(image, nil)
            {refs, [object | acc_objects], next_id + 1}

          _alpha_data ->
            refs = Map.put(acc_refs, image_id, %{main: next_id, smask: next_id + 1})
            smask_id = next_id + 1
            main_object = image_object_body(image, smask_id)
            alpha_object = alpha_image_object_body(image)
            {refs, [alpha_object, main_object | acc_objects], next_id + 2}
        end
      end)

    {refs, Enum.reverse(objects_reversed), next_object_id}
  end

  defp info_object_body(metadata) when map_size(metadata) == 0, do: nil

  defp info_object_body(metadata) when is_map(metadata) do
    fields =
      [
        {:title, "Title"},
        {:author, "Author"},
        {:subject, "Subject"},
        {:keywords, "Keywords"},
        {:creator, "Creator"}
      ]
      |> Enum.flat_map(fn {key, label} ->
        case Map.get(metadata, key) do
          nil -> []
          value when is_binary(value) -> ["/#{label} #{Object.format_text(value)}"]
        end
      end)

    case fields do
      [] -> nil
      _ -> "<< #{Enum.join(fields, " ")} >>"
    end
  end

  defp build_pdf(object_bodies, info_ref) do
    header = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"

    {objects_reversed, offsets_reversed, cursor} =
      Enum.reduce(Enum.with_index(object_bodies, 1), {[], [], byte_size(header)}, fn {body, id},
                                                                                     {acc_objects,
                                                                                      acc_offsets,
                                                                                      acc_cursor} ->
        object = [Integer.to_string(id), " 0 obj\n", body, "\nendobj\n"]
        next_cursor = acc_cursor + IO.iodata_length(object)
        {[object | acc_objects], [acc_cursor | acc_offsets], next_cursor}
      end)

    objects = Enum.reverse(objects_reversed)
    offsets = Enum.reverse(offsets_reversed)
    xref_offset = cursor
    object_count = length(object_bodies)

    xref =
      ["xref\n0 #{object_count + 1}\n", "0000000000 65535 f \n"] ++
        Enum.map(offsets, fn offset ->
          :io_lib.format("~10..0B 00000 n \n", [offset])
        end)

    info_part =
      case info_ref do
        nil -> ""
        id -> " /Info #{id} 0 R"
      end

    trailer = [
      "trailer\n<< /Size #{object_count + 1} /Root 1 0 R#{info_part} >>\n",
      "startxref\n#{xref_offset}\n",
      "%%EOF\n"
    ]

    IO.iodata_to_binary([header, objects, xref, trailer])
  end

  defp font_resources(operations, embedded_font_refs) do
    fonts = FontEmbed.font_names_from_operations(operations)

    aliases =
      fonts
      |> Enum.with_index(1)
      |> Map.new(fn {font_name, index} ->
        {font_name, "F#{index}"}
      end)

    resources =
      fonts
      |> Enum.with_index(1)
      |> Enum.map_join(" ", fn {font_name, index} ->
        case Map.get(embedded_font_refs, font_name) do
          nil ->
            "/F#{index} << /Type /Font /Subtype /Type1 /BaseFont /#{font_name} >>"

          object_id ->
            "/F#{index} #{object_id} 0 R"
        end
      end)

    {aliases, resources}
  end

  defp xobject_resources(operations, image_object_ids) do
    operations
    |> Enum.flat_map(fn
      {:image, _x, _y, _width, _height, image_id} -> [image_id]
      _ -> []
    end)
    |> Enum.uniq()
    |> Enum.map_join(" ", fn image_id ->
      object_id = image_object_ids |> Map.fetch!(image_id) |> Map.fetch!(:main)
      "/Im#{image_id} #{object_id} 0 R"
    end)
  end

  # Annotation dictionaries are emitted directly inside the page's /Annots
  # array rather than as indirect objects. The specification permits either,
  # and keeping them direct means adding a link does not renumber every object
  # that follows it.
  defp annotations_entry([], [], _page_object_refs), do: ""

  defp annotations_entry(annotations, widget_refs, page_object_refs) do
    # Link annotations are written inline; form widgets have to be indirect,
    # because the catalog's /AcroForm /Fields array references the very same
    # dictionaries and an array cannot hold two copies of one object.
    inline = Enum.map(annotations, &annotation_dictionary(&1, page_object_refs))
    indirect = Enum.map(widget_refs, fn id -> "#{id} 0 R" end)
    " /Annots [#{Enum.join(inline ++ indirect, " ")}]"
  end

  defp build_form_field_objects([], _page_object_refs, _start_id), do: {[], []}

  defp build_form_field_objects(form_fields, page_object_refs, start_id) do
    form_fields
    |> Enum.with_index(start_id)
    |> Enum.map(fn {field, id} ->
      {{field.name, {id, field.page_number}},
       form_field_object_body(field, Map.fetch!(page_object_refs, field.page_number))}
    end)
    |> Enum.unzip()
  end

  # A form field and its on-page widget are one object here. The specification
  # allows splitting them, but that is only needed when one field has several
  # widgets (the same value shown on several pages), which this API cannot
  # express.
  defp form_field_object_body(field, page_ref) do
    {x1, y1, x2, y2} = field.rect

    rect =
      "[#{Object.num(x1)} #{Object.num(y1)} #{Object.num(x2)} #{Object.num(y2)}]"

    "<< /Type /Annot /Subtype /Widget /FT #{field_type_name(field.type)}" <>
      " /T #{Object.format_text(field.name)}" <>
      " /Rect #{rect} /P #{page_ref} 0 R" <>
      " /F 4" <>
      flags_entry(field.flags) <>
      annotation_border_entry_for(field.border) <>
      " /DA #{Object.format_text(field_appearance_string(field))}" <>
      field_value_entries(field) <>
      max_length_entry(field) <>
      options_entry(field) <>
      tooltip_entry(field) <> " >>"
  end

  defp field_type_name(:text), do: "/Tx"
  defp field_type_name(:checkbox), do: "/Btn"
  defp field_type_name(:choice), do: "/Ch"

  defp flags_entry(0), do: ""
  defp flags_entry(flags), do: " /Ff #{flags}"

  defp annotation_border_entry_for(:none), do: " /Border [0 0 0]"

  defp annotation_border_entry_for({horizontal, vertical, width}),
    do: " /Border [#{Object.num(horizontal)} #{Object.num(vertical)} #{Object.num(width)}]"

  # A size of 0 means auto-size: the viewer fits the text to the box.
  defp field_appearance_string(field) do
    "#{acro_form_font_alias(field.font)} #{Object.num(field.size)} Tf 0 g"
  end

  defp field_value_entries(%{type: :checkbox, value: checked}) do
    # A checkbox's states are named. /Yes for on is the near-universal
    # convention; /Off for the unchecked state is required by the spec.
    state = if checked, do: "/Yes", else: "/Off"
    " /V #{state} /DV #{state} /AS #{state}"
  end

  defp field_value_entries(%{value: ""}), do: ""

  defp field_value_entries(%{value: value}) when is_binary(value) do
    " /V #{Object.format_text(value)} /DV #{Object.format_text(value)}"
  end

  defp max_length_entry(%{max_length: max_length}) when is_integer(max_length),
    do: " /MaxLen #{max_length}"

  defp max_length_entry(_field), do: ""

  defp options_entry(%{options: options}) when is_list(options) do
    entries = Enum.map_join(options, " ", &Object.format_text/1)
    " /Opt [#{entries}]"
  end

  defp options_entry(_field), do: ""

  defp tooltip_entry(%{tooltip: tooltip}) when is_binary(tooltip),
    do: " /TU #{Object.format_text(tooltip)}"

  defp tooltip_entry(_field), do: ""

  defp widget_refs_for_page(form_field_refs, page_number) do
    for {_name, {id, field_page}} <- form_field_refs, field_page == page_number, do: id
  end

  defp annotation_dictionary(
         %{type: :link, rect: {x1, y1, x2, y2}, target: target, border: border},
         page_object_refs
       ) do
    rect = "[#{Object.num(x1)} #{Object.num(y1)} #{Object.num(x2)} #{Object.num(y2)}]"

    "<< /Type /Annot /Subtype /Link /Rect #{rect} #{annotation_border_entry(border)} " <>
      "#{link_target_entry(target, page_object_refs)} >>"
  end

  # A zero-width border is the sane default: viewers otherwise draw a black box
  # around every link.
  defp annotation_border_entry(:none), do: "/Border [0 0 0]"

  defp annotation_border_entry({horizontal, vertical, width}),
    do: "/Border [#{Object.num(horizontal)} #{Object.num(vertical)} #{Object.num(width)}]"

  defp link_target_entry({:url, url}, _page_object_refs) do
    "/A << /S /URI /URI #{Object.format_text(url)} >>"
  end

  defp link_target_entry({:page, page_number}, page_object_refs) do
    case Map.fetch(page_object_refs, page_number) do
      {:ok, object_id} ->
        # /XYZ with null coordinates means "top of the page, keep the current
        # zoom", the least surprising behaviour for a cross-reference.
        "/Dest [#{object_id} 0 R /XYZ null null null]"

      :error ->
        # Page links may be created before their target page exists, so this is
        # the first point at which a dangling reference can be detected.
        raise ArgumentError,
              "link points at page #{page_number}, which does not exist in the document"
    end
  end

  defp resource_dictionary(font_resources, xobject_resources) do
    parts =
      []
      |> maybe_add_resource("/Font << #{font_resources} >>", font_resources)
      |> maybe_add_resource("/XObject << #{xobject_resources} >>", xobject_resources)

    case parts do
      [] -> ""
      _ -> " /Resources << #{Enum.join(parts, " ")} >>"
    end
  end

  defp maybe_add_resource(resources, _entry, ""), do: resources
  defp maybe_add_resource(resources, entry, _), do: resources ++ [entry]

  defp image_object_body(image, smask_id) do
    color_space = image_color_space_name(image.color_space)
    length = byte_size(image.data)
    {filter_name, decode_parms} = image_filter_and_decode_parms(image)
    smask_ref = if is_integer(smask_id), do: " /SMask #{smask_id} 0 R", else: ""

    [
      "<< /Type /XObject /Subtype /Image /Width ",
      Integer.to_string(image.width),
      " /Height ",
      Integer.to_string(image.height),
      " /ColorSpace ",
      color_space,
      " /BitsPerComponent ",
      Integer.to_string(image.bits_per_component),
      filter_name,
      decode_parms,
      smask_ref,
      " /Length ",
      Integer.to_string(length),
      " >>\nstream\n",
      image.data,
      "\nendstream"
    ]
  end

  defp alpha_image_object_body(image) do
    alpha_data = Map.fetch!(image, :alpha_data)
    decode_parms = Map.get(image, :alpha_decode_parms)

    [
      "<< /Type /XObject /Subtype /Image /Width ",
      Integer.to_string(image.width),
      " /Height ",
      Integer.to_string(image.height),
      " /ColorSpace /DeviceGray /BitsPerComponent ",
      Integer.to_string(image.bits_per_component),
      " /Filter /FlateDecode",
      format_decode_parms(decode_parms),
      " /Length ",
      Integer.to_string(byte_size(alpha_data)),
      " >>\nstream\n",
      alpha_data,
      "\nendstream"
    ]
  end

  defp image_filter_and_decode_parms(%{format: :jpeg}), do: {" /Filter /DCTDecode", ""}

  defp image_filter_and_decode_parms(%{format: :png} = image) do
    {" /Filter /FlateDecode", format_decode_parms(Map.get(image, :decode_parms))}
  end

  defp format_decode_parms(nil), do: ""

  defp format_decode_parms(decode_parms) do
    predictor = Map.fetch!(decode_parms, :predictor)
    colors = Map.fetch!(decode_parms, :colors)
    bits = Map.fetch!(decode_parms, :bits_per_component)
    columns = Map.fetch!(decode_parms, :columns)

    " /DecodeParms << /Predictor #{predictor} /Colors #{colors} /BitsPerComponent #{bits} /Columns #{columns} >>"
  end

  defp image_color_space_name(:device_gray), do: "/DeviceGray"
  defp image_color_space_name(:device_rgb), do: "/DeviceRGB"
  defp image_color_space_name(:device_cmyk), do: "/DeviceCMYK"

  defp content_stream(operations, font_aliases, embedded_font_text_modes) do
    Enum.map_join(operations, "", fn
      {:text_at, x, y, text, {font_name, size}} ->
        font_ref = Map.fetch!(font_aliases, font_name)
        text_mode = Map.get(embedded_font_text_modes, font_name, :pdf_text)
        encoded_text = Object.format_text(text, text_mode)

        "BT\n/#{font_ref} #{Object.num(size)} Tf\n#{Object.num(x)} #{Object.num(y)} Td\n#{encoded_text} Tj\nET\n"

      {:text_at_rotated, x, y, angle_degrees, text, {font_name, size}} ->
        font_ref = Map.fetch!(font_aliases, font_name)
        text_mode = Map.get(embedded_font_text_modes, font_name, :pdf_text)
        encoded_text = Object.format_text(text, text_mode)
        {a, b, c, d} = rotation_matrix(angle_degrees)

        "BT\n/#{font_ref} #{Object.num(size)} Tf\n#{Object.num(a)} #{Object.num(b)} #{Object.num(c)} #{Object.num(d)} #{Object.num(x)} #{Object.num(y)} Tm\n#{encoded_text} Tj\nET\n"

      {:line, x1, y1, x2, y2} ->
        "#{Object.num(x1)} #{Object.num(y1)} m\n#{Object.num(x2)} #{Object.num(y2)} l\nS\n"

      {:rectangle, x, y, width, height} ->
        "#{Object.num(x)} #{Object.num(y)} #{Object.num(width)} #{Object.num(height)} re\nS\n"

      {:circle, cx, cy, radius} ->
        bezier_circle(cx, cy, radius)

      {:set_stroke_color, {r, g, b}} ->
        "#{Object.num(r)} #{Object.num(g)} #{Object.num(b)} RG\n"

      {:set_fill_color, {r, g, b}} ->
        "#{Object.num(r)} #{Object.num(g)} #{Object.num(b)} rg\n"

      {:move_to, x, y} ->
        "#{Object.num(x)} #{Object.num(y)} m\n"

      {:line_to, x, y} ->
        "#{Object.num(x)} #{Object.num(y)} l\n"

      {:bezier, x1, y1, x2, y2, x3, y3} ->
        "#{Object.num(x1)} #{Object.num(y1)} #{Object.num(x2)} #{Object.num(y2)} #{Object.num(x3)} #{Object.num(y3)} c\n"

      :stroke ->
        "S\n"

      :fill ->
        "f\n"

      :fill_even_odd ->
        "f*\n"

      :clip ->
        "W\nn\n"

      :clip_even_odd ->
        "W*\nn\n"

      {:set_line_width, width} ->
        "#{Object.num(width)} w\n"

      {:set_line_cap, cap} ->
        "#{cap} J\n"

      {:set_line_join, join} ->
        "#{join} j\n"

      {:set_dash, pattern, phase} ->
        "[#{Enum.map_join(pattern, " ", &Object.num/1)}] #{Object.num(phase)} d\n"

      {:set_miter_limit, limit} ->
        "#{Object.num(limit)} M\n"

      :save_state ->
        "q\n"

      :restore_state ->
        "Q\n"

      {:image, x, y, width, height, image_id} ->
        "q\n#{Object.num(width)} 0 0 #{Object.num(height)} #{Object.num(x)} #{Object.num(y)} cm\n/Im#{image_id} Do\nQ\n"
    end)
  end

  defp bezier_circle(cx, cy, radius) do
    k = radius * 0.552_284_749_831
    x0 = cx + radius
    y0 = cy

    x1 = cx + radius
    y1 = cy + k
    x2 = cx + k
    y2 = cy + radius
    x3 = cx
    y3 = cy + radius

    x4 = cx - k
    y4 = cy + radius
    x5 = cx - radius
    y5 = cy + k
    x6 = cx - radius
    y6 = cy

    x7 = cx - radius
    y7 = cy - k
    x8 = cx - k
    y8 = cy - radius
    x9 = cx
    y9 = cy - radius

    x10 = cx + k
    y10 = cy - radius
    x11 = cx + radius
    y11 = cy - k
    x12 = cx + radius
    y12 = cy

    "#{Object.num(x0)} #{Object.num(y0)} m\n" <>
      "#{Object.num(x1)} #{Object.num(y1)} #{Object.num(x2)} #{Object.num(y2)} #{Object.num(x3)} #{Object.num(y3)} c\n" <>
      "#{Object.num(x4)} #{Object.num(y4)} #{Object.num(x5)} #{Object.num(y5)} #{Object.num(x6)} #{Object.num(y6)} c\n" <>
      "#{Object.num(x7)} #{Object.num(y7)} #{Object.num(x8)} #{Object.num(y8)} #{Object.num(x9)} #{Object.num(y9)} c\n" <>
      "#{Object.num(x10)} #{Object.num(y10)} #{Object.num(x11)} #{Object.num(y11)} #{Object.num(x12)} #{Object.num(y12)} c\n" <>
      "S\n"
  end

  defp rotation_matrix(angle_degrees) do
    radians = angle_degrees * :math.pi() / 180
    cos_a = normalized_trig(:math.cos(radians))
    sin_a = normalized_trig(:math.sin(radians))

    {cos_a, sin_a, -sin_a, cos_a}
  end

  defp normalized_trig(value) when abs(value) < 1.0e-12, do: 0.0
  defp normalized_trig(value), do: value
end

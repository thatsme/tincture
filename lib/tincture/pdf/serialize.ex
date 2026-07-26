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

  alias Tincture.Font
  alias Tincture.PDF
  alias Tincture.PDF.Encrypt
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

    {form_field_refs, widget_refs, form_field_objects} =
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
            widget_refs_for_page(widget_refs, page_number),
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

    build_pdf(object_bodies, info_ref, pdf.encryption)
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
    fields = Enum.map_join(form_field_refs, " ", fn id -> "#{id} 0 R" end)

    # Button-like fields (checkbox, radio, push button) carry real appearance
    # streams, because their appearance *is* their content: relying on
    # /NeedAppearances leaves them invisible anywhere the renderer is not an
    # interactive viewer - printing, thumbnails, server-side rasterising.
    #
    # Fields whose appearance is their typed value (text, choice) still defer to
    # /NeedAppearances. Rendering those at export would mean laying out the value
    # ourselves, and getting it wrong shows up as a clipped or invisible value
    # rather than an error. Every mainstream viewer honours the flag.
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

  defp build_pdf(object_bodies, info_ref, encryption) do
    header = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"

    # The /Encrypt dictionary is appended last and is itself never encrypted -
    # a reader has to read it before it holds any key.
    {object_bodies, encrypt_ref} =
      case encryption do
        nil ->
          {object_bodies, nil}

        context ->
          {object_bodies ++ [Encrypt.encrypt_dictionary(context)], length(object_bodies) + 1}
      end

    {objects_reversed, offsets_reversed, cursor} =
      Enum.reduce(Enum.with_index(object_bodies, 1), {[], [], byte_size(header)}, fn {body, id},
                                                                                     {acc_objects,
                                                                                      acc_offsets,
                                                                                      acc_cursor} ->
        body = maybe_encrypt_object(body, id, encrypt_ref, encryption)
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

    encrypt_part =
      case encrypt_ref do
        nil -> ""
        id -> " /Encrypt #{id} 0 R"
      end

    # /ID is required once a document is encrypted, and both halves are the
    # same for a file that has never been incrementally updated.
    id_part =
      case encryption do
        nil ->
          ""

        context ->
          hex = Base.encode16(Encrypt.id(context), case: :upper)
          " /ID [<#{hex}> <#{hex}>]"
      end

    trailer = [
      "trailer\n<< /Size #{object_count + 1} /Root 1 0 R#{info_part}#{encrypt_part}#{id_part} >>\n",
      "startxref\n#{xref_offset}\n",
      "%%EOF\n"
    ]

    IO.iodata_to_binary([header, objects, xref, trailer])
  end

  defp maybe_encrypt_object(body, _id, _encrypt_ref, nil), do: body
  defp maybe_encrypt_object(body, id, id, _encryption), do: body

  defp maybe_encrypt_object(body, _id, _encrypt_ref, context),
    do: Encrypt.encrypt_object(body, context)

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

  defp build_form_field_objects([], _page_object_refs, _start_id), do: {[], [], []}

  defp build_form_field_objects(form_fields, page_object_refs, start_id) do
    {built, _next_id} =
      Enum.map_reduce(form_fields, start_id, &build_form_field(&1, page_object_refs, &2))

    {
      Enum.map(built, & &1.field_ref),
      Enum.flat_map(built, & &1.widget_refs),
      Enum.flat_map(built, & &1.objects)
    }
  end

  # A radio group is the one field that cannot be a single object: the value
  # lives on the parent and each button is its own annotation, so it becomes a
  # parent plus a kid per button. Each kid also needs a pair of appearance
  # streams, because a radio button's export value *is* the name of its "on"
  # appearance state - there is nowhere else to record it.
  defp build_form_field(%{type: :radio} = field, page_object_refs, id) do
    {kids, next_id} =
      Enum.map_reduce(field.widgets, id + 1, fn widget, kid_id ->
        {{widget, kid_id, kid_id + 1, kid_id + 2}, kid_id + 3}
      end)

    # Object order must match the ids allocated above, since bodies are written
    # sequentially from the same starting id.
    kid_objects =
      Enum.flat_map(kids, fn {widget, _kid_id, on_id, off_id} ->
        page_ref = Map.fetch!(page_object_refs, widget.page_number)

        [
          radio_kid_object_body(field, widget, id, page_ref, on_id, off_id),
          radio_appearance_object_body(widget, :on),
          radio_appearance_object_body(widget, :off)
        ]
      end)

    widget_refs =
      Enum.map(kids, fn {widget, kid_id, _on_id, _off_id} -> {kid_id, widget.page_number} end)

    built = %{
      field_ref: id,
      widget_refs: widget_refs,
      objects: [radio_parent_object_body(field, kids) | kid_objects]
    }

    {built, next_id}
  end

  # A checkbox needs the same treatment as a radio button and for the same
  # reason: without an /AP it is drawn only by viewers that honour
  # /NeedAppearances, so it is invisible when printed, thumbnailed or
  # rasterised server-side.
  defp build_form_field(%{type: :checkbox} = field, page_object_refs, id) do
    on_id = id + 1
    off_id = id + 2
    page_ref = Map.fetch!(page_object_refs, field.page_number)

    built = %{
      field_ref: id,
      widget_refs: [{id, field.page_number}],
      objects: [
        form_field_object_body(field, page_ref, checkbox_appearance_entry(on_id, off_id)),
        checkbox_appearance_object_body(field, :on),
        checkbox_appearance_object_body(field, :off)
      ]
    }

    {built, id + 3}
  end

  # A push button's face is entirely appearance - it has no value to render -
  # so without a stream there is nothing to see at all.
  defp build_form_field(%{type: :push_button} = field, page_object_refs, id) do
    appearance_id = id + 1
    page_ref = Map.fetch!(page_object_refs, field.page_number)

    built = %{
      field_ref: id,
      widget_refs: [{id, field.page_number}],
      objects: [
        form_field_object_body(field, page_ref, " /AP << /N #{appearance_id} 0 R >>"),
        push_button_appearance_object_body(field)
      ]
    }

    {built, id + 2}
  end

  defp build_form_field(field, page_object_refs, id) do
    built = %{
      field_ref: id,
      widget_refs: [{id, field.page_number}],
      objects: [form_field_object_body(field, Map.fetch!(page_object_refs, field.page_number))]
    }

    {built, id + 1}
  end

  # For every other type the field and its on-page widget are one object. The
  # specification allows splitting them, but that is only needed when one field
  # has several widgets, which only a radio group has.
  defp form_field_object_body(field, page_ref), do: form_field_object_body(field, page_ref, "")

  defp form_field_object_body(field, page_ref, appearance_entry) do
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
      button_action_entry(field) <>
      button_caption_entry(field) <>
      appearance_entry <>
      tooltip_entry(field) <> " >>"
  end

  defp field_type_name(:text), do: "/Tx"
  defp field_type_name(:checkbox), do: "/Btn"
  defp field_type_name(:choice), do: "/Ch"
  defp field_type_name(:radio), do: "/Btn"
  defp field_type_name(:push_button), do: "/Btn"
  defp field_type_name(:signature), do: "/Sig"

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

  defp widget_refs_for_page(widget_refs, page_number) do
    for {id, widget_page} <- widget_refs, widget_page == page_number, do: id
  end

  # The parent holds the value and the flags; it is a field, not an annotation,
  # so it carries no /Rect and no /Subtype.
  defp radio_parent_object_body(field, kids) do
    kid_refs = Enum.map_join(kids, " ", fn {_widget, kid_id, _on, _off} -> "#{kid_id} 0 R" end)

    "<< /FT /Btn /T #{Object.format_text(field.name)}" <>
      flags_entry(field.flags) <>
      radio_value_entries(field.value) <>
      " /DA #{Object.format_text(field_appearance_string(field))}" <>
      tooltip_entry(field) <>
      " /Kids [#{kid_refs}] >>"
  end

  # A name object, not a string: the value names one of the kids' appearance
  # states. /Off is the reserved name for "nothing selected".
  defp radio_value_entries(""), do: " /V /Off /DV /Off"

  defp radio_value_entries(value),
    do: " /V /#{Object.sanitize_name(value)} /DV /#{Object.sanitize_name(value)}"

  defp radio_kid_object_body(field, widget, parent_id, page_ref, on_id, off_id) do
    {x1, y1, x2, y2} = widget.rect
    rect = "[#{Object.num(x1)} #{Object.num(y1)} #{Object.num(x2)} #{Object.num(y2)}]"
    on_state = "/" <> Object.sanitize_name(widget.export_value)
    appearance_state = if field.value == widget.export_value, do: on_state, else: "/Off"

    "<< /Type /Annot /Subtype /Widget /Parent #{parent_id} 0 R" <>
      " /Rect #{rect} /P #{page_ref} 0 R /F 4" <>
      annotation_border_entry_for(field.border) <>
      " /MK << /BC [0] /BG [1] >>" <>
      " /AS #{appearance_state}" <>
      " /AP << /N << #{on_state} #{on_id} 0 R /Off #{off_id} 0 R >> >> >>"
  end

  # A radio button's appearance has to be a real stream: the /AP /N keys are
  # what name the export values, so there is nowhere else to put them. These
  # are deliberately plain - a ring, and a dot when selected - because a viewer
  # honouring /NeedAppearances may well replace them anyway.
  defp radio_appearance_object_body(widget, state) do
    {x1, y1, x2, y2} = widget.rect
    size = min(x2 - x1, y2 - y1)
    centre = size / 2
    radius = centre - 0.5

    content =
      case state do
        :off ->
          ring_path(centre, centre, radius) <> "S\n"

        :on ->
          ring_path(centre, centre, radius) <>
            "S\n" <> ring_path(centre, centre, radius * 0.5) <> "f\n"
      end

    form_xobject(size, size, "0 G 0 g 1 w\n" <> content, "")
  end

  # Four cubic beziers, the standard circle approximation.
  @circle_kappa 0.5523
  defp ring_path(cx, cy, r) do
    k = r * @circle_kappa

    Enum.map_join(
      [
        "#{Object.num(cx + r)} #{Object.num(cy)} m",
        "#{Object.num(cx + r)} #{Object.num(cy + k)} #{Object.num(cx + k)} #{Object.num(cy + r)} #{Object.num(cx)} #{Object.num(cy + r)} c",
        "#{Object.num(cx - k)} #{Object.num(cy + r)} #{Object.num(cx - r)} #{Object.num(cy + k)} #{Object.num(cx - r)} #{Object.num(cy)} c",
        "#{Object.num(cx - r)} #{Object.num(cy - k)} #{Object.num(cx - k)} #{Object.num(cy - r)} #{Object.num(cx)} #{Object.num(cy - r)} c",
        "#{Object.num(cx + k)} #{Object.num(cy - r)} #{Object.num(cx + r)} #{Object.num(cy - k)} #{Object.num(cx + r)} #{Object.num(cy)} c"
      ],
      "\n",
      & &1
    ) <> "\n"
  end

  defp checkbox_appearance_entry(on_id, off_id),
    do: " /AP << /N << /Yes #{on_id} 0 R /Off #{off_id} 0 R >> >>"

  defp checkbox_appearance_object_body(field, state) do
    {x1, y1, x2, y2} = field.rect
    size = min(x2 - x1, y2 - y1)

    box = "0.5 0.5 #{Object.num(size - 1)} #{Object.num(size - 1)} re\nS\n"

    tick =
      case state do
        :off ->
          ""

        :on ->
          # A check mark as three points, stroked.
          "#{Object.num(size * 0.22)} #{Object.num(size * 0.52)} m\n" <>
            "#{Object.num(size * 0.42)} #{Object.num(size * 0.28)} l\n" <>
            "#{Object.num(size * 0.78)} #{Object.num(size * 0.72)} l\n" <>
            "S\n"
      end

    form_xobject(size, size, "0 G 0 g 1 w\n" <> box <> tick, "")
  end

  defp push_button_appearance_object_body(field) do
    {x1, y1, x2, y2} = field.rect
    width = x2 - x1
    height = y2 - y1

    face =
      "0.93 0.93 0.94 rg\n0 0 #{Object.num(width)} #{Object.num(height)} re\nf\n" <>
        "0.55 0.57 0.60 RG\n0.75 w\n" <>
        "0.4 0.4 #{Object.num(width - 0.8)} #{Object.num(height - 0.8)} re\nS\n"

    {caption, resources} = push_button_caption(field, width, height)
    form_xobject(width, height, face <> caption, resources)
  end

  # The caption is centred, which needs its width - so it is measured with the
  # same standard-font metrics the viewer will use.
  defp push_button_caption(%{label: label} = field, width, height) when is_binary(label) do
    size = if field.size == 0, do: min(height * 0.5, 12), else: field.size
    text_width = Font.text_width(field.font, size, label)
    x = max((width - text_width) / 2, 2)
    y = (height - size * 0.72) / 2

    caption =
      "0 g\nBT\n/Helv #{Object.num(size)} Tf\n" <>
        "#{Object.num(x)} #{Object.num(y)} Td\n" <>
        "#{Object.format_text(label)} Tj\nET\n"

    resources =
      " /Font << /Helv << /Type /Font /Subtype /Type1" <>
        " /BaseFont /#{Object.sanitize_name(field.font)} /Encoding /WinAnsiEncoding >> >>"

    {caption, resources}
  end

  defp push_button_caption(_field, _width, _height), do: {"", ""}

  defp form_xobject(width, height, content, resources) do
    [
      "<< /Type /XObject /Subtype /Form /BBox [0 0 #{Object.num(width)} #{Object.num(height)}]",
      " /Resources <<#{resources} >> /Length #{byte_size(content)} >>\nstream\n",
      content,
      "endstream"
    ]
  end

  defp button_action_entry(%{action: :reset}), do: " /A << /S /ResetForm >>"

  defp button_action_entry(%{action: {:url, url}}),
    do: " /A << /S /URI /URI #{Object.format_text(url)} >>"

  defp button_action_entry(%{action: {:submit, url}}),
    do:
      " /A << /S /SubmitForm /F << /Type /Filespec /FS /URL /F #{Object.format_text(url)} >>" <>
        " /Flags 4 >>"

  defp button_action_entry(_field), do: ""

  # /MK /CA is the caption a viewer draws on the button face.
  defp button_caption_entry(%{label: label}) when is_binary(label),
    do: " /MK << /CA #{Object.format_text(label)} >>"

  defp button_caption_entry(_field), do: ""

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

      {:line, x1, y1, x2, y2, paint} ->
        "#{Object.num(x1)} #{Object.num(y1)} m\n#{Object.num(x2)} #{Object.num(y2)} l\n" <>
          paint_operator(paint)

      {:rectangle, x, y, width, height, paint} ->
        "#{Object.num(x)} #{Object.num(y)} #{Object.num(width)} #{Object.num(height)} re\n" <>
          paint_operator(paint)

      {:circle, cx, cy, radius, paint} ->
        bezier_circle(cx, cy, radius) <> paint_operator(paint)

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

  # A path-painting operator also ends the path, which is why a shape can be
  # stroked or filled but not both by chaining two of them.
  defp paint_operator(:stroke), do: "S\n"
  defp paint_operator(:fill), do: "f\n"
  defp paint_operator(:fill_even_odd), do: "f*\n"
  defp paint_operator(:fill_and_stroke), do: "B\n"
  # `n` ends the path without painting, leaving the caller to paint it.
  defp paint_operator(:none), do: "n\n"

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
      "#{Object.num(x10)} #{Object.num(y10)} #{Object.num(x11)} #{Object.num(y11)} #{Object.num(x12)} #{Object.num(y12)} c\n"
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

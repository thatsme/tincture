defmodule Tincture.PublicApiTest do
  use ExUnit.Case, async: true

  # Snapshot of the API published in v0.3.2, checked against the tree at
  # fe0eebd. It still covers the documented API: v0.3.3 added no function, and
  # v0.3.4 added an option but no documented function. Anchored to a release
  # rather than to main: what Hex shipped is what users can be calling.
  #
  # The assertion is one-directional — snapshot is a subset of what exists now.
  # Adding a function, or a new arity, passes. Removing one, renaming it, or changing
  # its arity fails. Under semver those are breaking changes for a published package,
  # and this suite exists so they are a recorded decision rather than a side effect of
  # satisfying a linter: `lib/tincture.ex` is exempt from Credo's FunctionArity check
  # for exactly the same reason.
  #
  # To remove one deliberately, delete its entry in the same commit and say why.
  #
  # Types and specs are snapshotted too, in test/fixtures/public_api_types.txt:
  # every @type and @opaque of every documented module built from lib/, and the
  # @spec of every function in @public_api, one per line, rendered and
  # normalised as Tincture.Test.ApiSnapshot describes. That snapshot is anchored
  # to v0.3.6. Its check is stricter than the one for functions: every recorded
  # definition must still exist and be identical. A new type or spec passes;
  # any change to a recorded one fails, widening included. To change one
  # deliberately, edit its line in the same commit and say why.
  #
  # Since v0.3.6: Tincture.PDF.Structure's t/0 lost optional(:bbox_unknown) =>
  # :no_content | :spans_pages. Neither value can occur once W2 and W3 raise
  # (stage 1 of 0.4.0).
  #
  # Since v0.3.6, form XObjects (stage 4 of 0.4.0), both widenings:
  # Tincture.PDF's t/0 gained current_stream and form_xobjects, the drawing
  # target inside a form_xobject/5 callback and the defined XObjects; op/0
  # gained form_xobject_op(), a placement. The new types form_xobject/0,
  # form_xobject_op/0 and xobject_name/0, and the specs of form_xobject/5 and
  # place_form_xobject/4,5, are recorded with them.
  #
  # Since v0.3.6, the specs of encrypt/1 and export/1, new entries: explicit
  # clauses added for refusal messages, which replaced the default argument
  # of encrypt/2 and export/2 so that each message names the arity called.
  #
  # Since v0.3.6, form fields may use embedded fonts (stage 5a of 0.4.0), a
  # widening: Tincture.PDF's form_field/0 gained optional(:full_font) => true,
  # set on a text or choice field given full_font: true.
  #
  # To regenerate it for a release, run in a worktree of that release's tag,
  # with test/support/api_snapshot.ex present:
  #
  #     MIX_ENV=test mix run -e "Tincture.Test.ApiSnapshot.write!()"

  alias Tincture.Test.ApiSnapshot

  # Documented API: exported, and shown in the generated docs.
  @public_api [
    {Tincture, :add_bookmark, 3},
    {Tincture, :add_page, 1},
    {Tincture, :artifact, 2},
    {Tincture, :bezier, 7},
    {Tincture, :checkbox, 5},
    {Tincture, :checkbox, 6},
    {Tincture, :choice_field, 6},
    {Tincture, :choice_field, 7},
    {Tincture, :circle, 4},
    {Tincture, :circle, 5},
    {Tincture, :clip, 1},
    {Tincture, :clip_even_odd, 1},
    {Tincture, :encrypt, 1},
    {Tincture, :encrypt, 2},
    {Tincture, :export, 1},
    {Tincture, :export, 2},
    {Tincture, :fill, 1},
    {Tincture, :fill_even_odd, 1},
    {Tincture, :form_xobject, 5},
    {Tincture, :image_jpeg, 6},
    {Tincture, :image_png, 6},
    {Tincture, :line, 5},
    {Tincture, :line, 6},
    {Tincture, :line_to, 3},
    {Tincture, :linear_gradient, 6},
    {Tincture, :linear_gradient, 7},
    {Tincture, :link, 6},
    {Tincture, :link, 7},
    {Tincture, :move_to, 3},
    {Tincture, :new, 0},
    {Tincture, :page_size, 2},
    {Tincture, :pdf_a_violations, 1},
    {Tincture, :pdf_ua_violations, 1},
    {Tincture, :place_form_xobject, 4},
    {Tincture, :place_form_xobject, 5},
    {Tincture, :push_button, 6},
    {Tincture, :push_button, 7},
    {Tincture, :radial_gradient, 6},
    {Tincture, :radial_gradient, 7},
    {Tincture, :radio_group, 3},
    {Tincture, :radio_group, 4},
    {Tincture, :rectangle, 5},
    {Tincture, :rectangle, 6},
    {Tincture, :register_otf_font, 3},
    {Tincture, :register_otf_font, 4},
    {Tincture, :register_ttf_font, 3},
    {Tincture, :register_ttf_font, 4},
    {Tincture, :restore_state, 1},
    {Tincture, :save, 2},
    {Tincture, :save, 3},
    {Tincture, :save_state, 1},
    {Tincture, :set_alpha, 1},
    {Tincture, :set_alpha, 2},
    {Tincture, :set_dash, 3},
    {Tincture, :set_fill_color, 2},
    {Tincture, :set_font, 3},
    {Tincture, :set_language, 2},
    {Tincture, :set_line_cap, 2},
    {Tincture, :set_line_join, 2},
    {Tincture, :set_line_width, 2},
    {Tincture, :set_metadata, 2},
    {Tincture, :set_miter_limit, 2},
    {Tincture, :set_page, 2},
    {Tincture, :set_pdf_a, 2},
    {Tincture, :set_stroke_color, 2},
    {Tincture, :sign, 3},
    {Tincture, :signature_field, 6},
    {Tincture, :signature_field, 7},
    {Tincture, :stroke, 1},
    {Tincture, :tag, 3},
    {Tincture, :tag, 4},
    {Tincture, :tagged?, 1},
    {Tincture, :text_at, 4},
    {Tincture, :text_at_rotated, 5},
    {Tincture, :text_at_rotated_with_fallback, 5},
    {Tincture, :text_at_rotated_with_fallback, 6},
    {Tincture, :text_at_rotated_with_fallback, 7},
    {Tincture, :text_at_with_fallback, 4},
    {Tincture, :text_at_with_fallback, 5},
    {Tincture, :text_at_with_fallback, 6},
    {Tincture, :text_field, 6},
    {Tincture, :text_field, 7},
    {Tincture, :text_link, 5},
    {Tincture, :text_link, 6},
    {Tincture, :text_paragraph, 5},
    {Tincture, :text_paragraph, 6},
    {Tincture.Font.Binary, :bytes, 3},
    {Tincture.Font.Binary, :s16, 2},
    {Tincture.Font.Binary, :s16_list, 1},
    {Tincture.Font.Binary, :slice, 3},
    {Tincture.Font.Binary, :u16, 2},
    {Tincture.Font.Binary, :u16_list, 1},
    {Tincture.Font.Binary, :u32, 2},
    {Tincture.Font.Binary, :u32_list, 1},
    {Tincture.Font.CFF, :decode_index_offsets, 2},
    {Tincture.Font.CFF, :fixed_16_16_to_number, 1},
    {Tincture.Font.CFF, :nondecreasing?, 1},
    {Tincture.Font.CFF, :normalize_name_value, 1},
    {Tincture.Font.CFF, :parse_dict_number, 1},
    {Tincture.Font.CFF, :parse_index, 1},
    {Tincture.Font.CFF, :parse_index_objects, 3},
    {Tincture.Font.CFF, :parse_real_number, 1},
    {Tincture.Font.Context, :from_pdf, 1},
    {Tincture.Font.Context, :kerning_codepoint, 1},
    {Tincture.Font.Context, :measurable?, 2},
    {Tincture.Font.Context, :measure, 4},
    {Tincture.Font.Context, :new, 0},
    {Tincture.Font.Context, :pair_kerning_units, 3},
    {Tincture.Font.Context, :text_width, 4},
    {Tincture.Font.Context, :text_width, 5},
    {Tincture.Font.OpenType.GPOS, :begin_guardrail_scope, 0},
    {Tincture.Font.OpenType.GPOS, :end_guardrail_scope, 1},
    {Tincture.Font.OpenType.GPOS, :guardrail_scope_key, 0},
    {Tincture.Font.OpenType.GPOS, :guardrail_skips, 0},
    {Tincture.Font.TTF, :parse_basic_tables, 1},
    {Tincture.Font.UnicodeRanges, :all_zero?, 1},
    {Tincture.Font.UnicodeRanges, :bit_for_codepoint, 1},
    {Tincture.Font.UnicodeRanges, :supports_codepoint?, 2},
    {Tincture.Layout.Box, :flow_across_boxes, 3},
    {Tincture.Layout.Box, :flow_across_boxes, 4},
    {Tincture.Layout.Box, :flow_text, 6},
    {Tincture.Layout.Box, :flow_text, 7},
    {Tincture.Layout.Table, :render, 5},
    {Tincture.Layout.Table, :render, 6},
    {Tincture.Layout.Template, :new, 0},
    {Tincture.Layout.Template, :new, 1},
    {Tincture.Layout.Template, :parse_xml, 1},
    {Tincture.Layout.Template, :render, 3},
    {Tincture.Layout.Template, :render, 4},
    {Tincture.Layout.Template, :render_document, 3},
    {Tincture.Layout.Template, :render_document, 4},
    {Tincture.Layout.Template, :render_xml_document, 2},
    {Tincture.Layout.Template, :render_xml_document, 3},
    {Tincture.Layout.Template, :with_footer, 2},
    {Tincture.Layout.Template, :with_footer, 3},
    {Tincture.Layout.Template, :with_header, 2},
    {Tincture.Layout.Template, :with_header, 3},
    {Tincture.PDF, :add_link, 3},
    {Tincture.PDF, :add_radio_group, 4},
    {Tincture.PDF, :begin_artifact, 1},
    {Tincture.PDF, :begin_structure, 2},
    {Tincture.PDF, :begin_structure, 3},
    {Tincture.PDF, :end_artifact, 1},
    {Tincture.PDF, :end_structure, 1},
    {Tincture.PDF, :set_language, 2},
    {Tincture.PDF, :set_pdf_a, 2},
    {Tincture.PDF, :set_signature, 3},
    {Tincture.PDF, :tagged?, 1},
    {Tincture.PDF.Accessibility, :describe, 1},
    {Tincture.PDF.Accessibility, :violations, 1},
    {Tincture.PDF.Archival, :describe, 1},
    {Tincture.PDF.Archival, :violations, 1},
    {Tincture.PDF.CMS, :sign_detached, 6},
    {Tincture.PDF.Encrypt, :encrypt, 2},
    {Tincture.PDF.Encrypt, :encrypt_dictionary, 1},
    {Tincture.PDF.Encrypt, :encrypt_object, 2},
    {Tincture.PDF.Encrypt, :id, 1},
    {Tincture.PDF.Encrypt, :new, 0},
    {Tincture.PDF.Encrypt, :new, 1},
    {Tincture.PDF.Encrypt, :permission_flags, 1},
    {Tincture.PDF.ICC, :components, 0},
    {Tincture.PDF.ICC, :output_condition_identifier, 0},
    {Tincture.PDF.ICC, :srgb, 0},
    {Tincture.PDF.Object, :encode_text, 2},
    {Tincture.PDF.Object, :escape_byte, 1},
    {Tincture.PDF.Object, :format_text, 1},
    {Tincture.PDF.Object, :format_text, 2},
    {Tincture.PDF.Object, :num, 1},
    {Tincture.PDF.Object, :sanitize_name, 1},
    {Tincture.PDF.Object, :unicode_text?, 1},
    {Tincture.PDF.Sign, :apply_signature, 2},
    {Tincture.PDF.Sign, :default_reserved_bytes, 0},
    {Tincture.PDF.Sign, :placeholder_dictionary, 1},
    {Tincture.PDF.Structure, :container?, 1},
    {Tincture.PDF.Structure, :content?, 1},
    {Tincture.PDF.Structure, :empty?, 1},
    {Tincture.PDF.Structure, :flatten, 1},
    {Tincture.PDF.Structure, :tag_name, 1},
    {Tincture.PDF.Structure, :tags, 0},
    {Tincture.Telemetry, :enabled?, 0},
    {Tincture.Telemetry, :execute, 3},
    {Tincture.Telemetry, :span, 3},
    {Tincture.Typography, :layout_paragraph, 2},
    {Tincture.Typography, :layout_paragraph, 3},
    {Tincture.Typography, :layout_paragraph_with_spill, 3},
    {Tincture.Typography, :layout_paragraph_with_spill, 4},
    {Tincture.Typography.Hyphen, :hyphenate, 1},
    {Tincture.Typography.Hyphen, :hyphenate, 2},
    {Tincture.Typography.Hyphen, :hyphenate, 3},
    {Tincture.Typography.RichText, :from_plain, 1},
    {Tincture.Typography.RichText, :from_plain, 2},
    {Tincture.Typography.RichText, :from_runs, 1},
    {Tincture.Typography.RichText, :from_runs, 2},
    {Tincture.Typography.RichText, :from_tokens, 1},
    {Tincture.Typography.RichText, :remeasure, 2},
    {Tincture.Typography.RichText, :unmeasured_fonts, 1}
  ]

  # Exported but `@doc false` since fed8a34 ("hide the internals that did not need
  # them"). That commit made them internal to the library while explicitly keeping
  # them callable — "They remain public and callable; they leave the generated docs."
  # So a 0.3.2 user can still be calling them, and they stay protected here.
  #
  # These are the ones to drop at the next major version. Removing one is a deliberate
  # act: delete the entry here, in the commit that removes the function.
  @internal_published [
    {Tincture.Font.CFF, :cff_sid_to_string, 2},
    {Tincture.Font.CFF, :extract_cff_escaped_operator_operand, 2},
    {Tincture.Font.CFF, :extract_cff_operator_operand, 2},
    {Tincture.Font.CFF, :extract_cff_operator_operands, 2},
    {Tincture.Font.CFF, :fetch_cff_metadata, 2},
    {Tincture.Font.CFF, :fetch_cff_top_dict, 2},
    {Tincture.Font.OpenType.Common, :filter_open_type_lookup_entries_by_features, 4},
    {Tincture.Font.OpenType.Common, :invert_cmap_by_code, 1},
    {Tincture.Font.OpenType.Common, :parse_layout_table_metadata, 3},
    {Tincture.Font.OpenType.Common, :parse_open_type_coverage_table, 2},
    {Tincture.Font.OpenType.Common, :parse_open_type_layout_table, 1},
    {Tincture.Font.OpenType.Common, :parse_open_type_lookup_entries, 2},
    {Tincture.Font.OpenType.Common, :valid_unicode_codepoint?, 1},
    {Tincture.Font.OpenType.GPOS, :parse_gpos_pair_kerns, 3},
    {Tincture.Font.OpenType.GSUB, :parse_gsub_ligatures, 3},
    {Tincture.Font.OpenType.GSUB, :parse_gsub_ligatures_all_scripts, 3},
    {Tincture.Font.OpenType.GSUB, :parse_gsub_substitutions_all_scripts, 3},
    {Tincture.Font.TTF.Cmap, :parse_cmap_by_code, 2},
    {Tincture.Font.TTF.Cmap, :parse_cmap_variation_metadata, 2},
    {Tincture.Font.TTF.Glyf, :parse_glyph_metrics, 4},
    {Tincture.Font.TTF.Name, :parse_name_metadata, 2},
    {Tincture.PDF, :add_bookmark, 3},
    {Tincture.PDF, :add_form_field, 5},
    {Tincture.PDF, :add_link, 4},
    {Tincture.PDF, :add_page, 1},
    {Tincture.PDF, :append_current_op, 2},
    {Tincture.PDF, :page_annotations, 2},
    {Tincture.PDF, :page_numbers, 1},
    {Tincture.PDF, :page_operations, 2},
    {Tincture.PDF, :register_image, 2},
    {Tincture.PDF, :register_otf_font, 3},
    {Tincture.PDF, :register_otf_font, 4},
    {Tincture.PDF, :register_ttf_font, 3},
    {Tincture.PDF, :register_ttf_font, 4},
    {Tincture.PDF, :set_metadata, 2},
    {Tincture.PDF, :set_page, 2},
    {Tincture.PDF.FontEmbed, :build_embedded_font_objects, 3},
    {Tincture.PDF.FontEmbed, :font_names_from_operations, 1},
    {Tincture.PDF.Serialize, :export, 1}
  ]

  # Under MIX_ENV=test, test/support compiles into the :tincture application,
  # so only modules built from lib/ count as published.
  defp current_api do
    for module <- Application.spec(:tincture, :modules) || [],
        Code.ensure_loaded?(module),
        ApiSnapshot.in_lib?(module),
        {name, arity} <- module.__info__(:functions),
        into: MapSet.new(),
        do: {module, name, arity}
  end

  test "every listed function belongs to a module built from lib/" do
    outside =
      for {module, name, arity} <- @public_api ++ @internal_published,
          not (Code.ensure_loaded?(module) and ApiSnapshot.in_lib?(module)),
          do: "#{inspect(module)}.#{name}/#{arity}"

    assert outside == [],
           """
           #{length(outside)} listed function(s) are not in a module built from lib/,
           so no package carries them:

           #{Enum.map_join(outside, "\n", &"  #{&1}")}
           """
  end

  test "every function published in v0.3.2 still exists with the same name and arity" do
    current = current_api()

    missing =
      for {kind, entries} <- [documented: @public_api, internal: @internal_published],
          entry <- entries,
          not MapSet.member?(current, entry),
          do: {kind, entry}

    assert missing == [],
           """
           #{length(missing)} function(s) published in v0.3.2 are gone or changed arity.

           This breaks semver for a released package. If it is intentional, remove the
           entries below from @public_api / @internal_published in this same commit.

           #{Enum.map_join(missing, "\n", fn {kind, {module, name, arity}} -> "  [#{kind}] #{inspect(module)}.#{name}/#{arity}" end)}
           """
  end

  defp snapshot, do: ApiSnapshot.path() |> File.read!() |> ApiSnapshot.from_text()

  defp describe_mismatch({:missing, key}), do: "  gone: #{key}"

  defp describe_mismatch({:changed, key, recorded, now}),
    do: "  changed: #{key}\n    recorded: #{recorded}\n    now:      #{now}"

  test "every type and spec in the snapshot still exists with an identical definition" do
    mismatches = ApiSnapshot.mismatches(snapshot(), ApiSnapshot.entries(@public_api))

    assert mismatches == [],
           """
           #{length(mismatches)} recorded type(s) or spec(s) are gone or changed.

           A changed type or spec is a contract change for a published package. If it is
           intentional, edit its line in #{ApiSnapshot.path()} in this same commit and say
           why in the comment above.

           #{Enum.map_join(mismatches, "\n", &describe_mismatch/1)}
           """
  end

  test "the snapshot's types come only from documented modules, and @public_api feeds its specs" do
    assert ApiSnapshot.public_api() == @public_api

    modules =
      snapshot()
      |> Enum.reject(fn {key, _definition} -> String.starts_with?(key, "spec ") end)
      |> Enum.map(fn {key, _definition} ->
        [_kind, name] = String.split(key, " ", parts: 2)
        name |> String.replace(~r/\.[^.]+\/\d+$/, "") |> then(&Module.concat([&1]))
      end)
      |> Enum.uniq()

    assert modules -- ApiSnapshot.documented_modules() == []
  end

  describe "self-check: the comparison" do
    test "reports a definition changed by one value" do
      [{key, definition} | rest] = snapshot()
      altered = [{key, definition <> " | :added_value"} | rest]

      assert [{:changed, ^key, _recorded, ^definition}] =
               ApiSnapshot.mismatches(altered, ApiSnapshot.entries(@public_api))
    end

    test "reports a recorded entry that no longer exists" do
      gone = "type Tincture.NoSuchModule.t/0"

      assert [{:missing, ^gone}] =
               ApiSnapshot.mismatches(
                 [{gone, "t() :: term()"}],
                 ApiSnapshot.entries(@public_api)
               )
    end

    test "passes a new entry that is not in the snapshot" do
      assert ApiSnapshot.mismatches(tl(snapshot()), ApiSnapshot.entries(@public_api)) == []
    end

    test "normalisation removes line wrapping and bracket padding only" do
      assert ApiSnapshot.normalise("foo(\n  a,\n  b\n) ::\n  %{\n    x: [ 1 ]\n  }") ==
               "foo(a, b) :: %{x: [1]}"
    end
  end
end

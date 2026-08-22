defmodule Tincture.LinkStructureTest do
  @moduledoc """
  PDF/UA-1 requires a link annotation to be reachable from the structure tree.
  Four things have to hold together and they fail independently, so each is
  asserted on its own: the /Link element's /OBJR reference, the annotation's
  /StructParent, the page's /StructParents, and the /ParentTree lookups that
  resolve both.

  These assertions parse the rendered output and follow the references. A byte
  snapshot would pin formatting rather than structure, and would be updated
  without thought the first time something unrelated shifted.
  """

  use ExUnit.Case, async: true

  # -- a minimal object parser, enough for a file with no object streams ------

  defp objects(binary) do
    ~r/^(\d+) 0 obj\r?\n(.*?)\r?\nendobj/ms
    |> Regex.scan(binary)
    |> Map.new(fn [_, id, body] -> {String.to_integer(id), body} end)
  end

  defp refs(text) do
    ~r/(\d+) 0 R/ |> Regex.scan(text) |> Enum.map(fn [_, id] -> String.to_integer(id) end)
  end

  defp elements(objects, tag) do
    for {id, body} <- objects,
        body =~ "/Type /StructElem",
        body =~ "/S /#{tag} ",
        into: %{},
        do: {id, body}
  end

  defp pages(objects) do
    for {id, body} <- objects, body =~ "/Type /Page /Parent", into: %{}, do: {id, body}
  end

  defp link_annotations(objects) do
    for {id, body} <- objects, body =~ "/Subtype /Link", into: %{}, do: {id, body}
  end

  defp integer_entry(body, key) do
    case Regex.run(~r/\/#{key} (\d+)(?![\d])/, body) do
      [_, value] -> String.to_integer(value)
      nil -> nil
    end
  end

  # /Nums holds two value shapes: an array for a page key, a bare reference for
  # an annotation key. Parsed into {:array, ids} and {:ref, id} so a test can
  # tell the difference rather than string-matching past it.
  defp parent_tree(binary) do
    objects = objects(binary)

    [_, root_id] = Regex.run(~r/\/StructTreeRoot (\d+) 0 R/, binary)
    root = Map.fetch!(objects, String.to_integer(root_id))

    [_, tree_id] = Regex.run(~r/\/ParentTree (\d+) 0 R/, root)
    tree = Map.fetch!(objects, String.to_integer(tree_id))

    [_, nums] = Regex.run(~r/\/Nums \[(.*)\]/s, tree)
    parse_nums(String.trim(nums), %{})
  end

  defp parse_nums("", acc), do: acc

  defp parse_nums(text, acc) do
    [_, key, rest] = Regex.run(~r/^(\d+)\s+(.*)$/s, text)

    {value, rest} =
      case rest do
        "[" <> _ ->
          [_, inner, tail] = Regex.run(~r/^\[(.*?)\](.*)$/s, rest)
          {{:array, refs(inner)}, tail}

        _ ->
          [_, id, tail] = Regex.run(~r/^(\d+) 0 R(.*)$/s, rest)
          {{:ref, String.to_integer(id)}, tail}
      end

    parse_nums(String.trim_leading(rest), Map.put(acc, String.to_integer(key), value))
  end

  # -- the document under test -------------------------------------------------

  # Two pages, one tagged link on each. A single-link document hides a
  # numbering bug, because every counter is coincidentally zero.
  defp two_tagged_links do
    Tincture.new()
    |> Tincture.set_language("en-GB")
    |> Tincture.tag(:document, fn doc ->
      doc
      |> Tincture.tag(:link, fn page ->
        Tincture.text_link(page, 72, 700, "first", {:url, "https://example.org/one"})
      end)
      |> Tincture.add_page()
      |> Tincture.tag(:link, fn page ->
        Tincture.text_link(page, 72, 700, "second", {:url, "https://example.org/two"})
      end)
    end)
    |> Tincture.export()
  end

  describe "a tagged link is reachable from the structure tree" do
    test "the /Link element's /K holds an /OBJR pointing at the annotation" do
      binary = two_tagged_links()
      objects = objects(binary)
      links = elements(objects, "Link")

      assert map_size(links) == 2

      for {_id, body} <- links do
        assert [_, object_id] = Regex.run(~r/<< \/Type \/OBJR \/Obj (\d+) 0 R >>/, body)

        annotation = Map.fetch!(objects, String.to_integer(object_id))
        assert annotation =~ "/Type /Annot"
        assert annotation =~ "/Subtype /Link"
      end
    end

    test "the annotation carries /StructParent, and is an indirect object" do
      binary = two_tagged_links()
      objects = objects(binary)
      annotations = link_annotations(objects)

      assert map_size(annotations) == 2

      for {_id, body} <- annotations do
        assert is_integer(integer_entry(body, "StructParent"))
      end

      # An inline dictionary has no object number for /OBJR to name, so a
      # tagged link has to be referenced rather than embedded.
      for {_id, body} <- pages(objects) do
        assert Regex.match?(~r/\/Annots \[\d+ 0 R\]/, body)
      end
    end

    test "the page carries /StructParents" do
      binary = two_tagged_links()
      keys = for {_id, body} <- pages(objects(binary)), do: integer_entry(body, "StructParents")

      assert Enum.sort(keys) == [0, 1]
    end

    test "/ParentTree resolves the annotation key to its /Link element" do
      binary = two_tagged_links()
      objects = objects(binary)
      nums = parent_tree(binary)

      for {element_id, body} <- elements(objects, "Link") do
        [_, object_id] = Regex.run(~r/\/Obj (\d+) 0 R/, body)
        annotation = Map.fetch!(objects, String.to_integer(object_id))
        key = integer_entry(annotation, "StructParent")

        assert Map.fetch!(nums, key) == {:ref, element_id},
               "key #{key} should resolve to the /Link element #{element_id}"
      end
    end

    test "/ParentTree resolves the page key to an array of marked-content parents" do
      binary = two_tagged_links()
      nums = parent_tree(binary)

      for {_id, body} <- pages(objects(binary)) do
        key = integer_entry(body, "StructParents")
        assert {:array, [_ | _]} = Map.fetch!(nums, key)
      end
    end

    test "page and annotation keys share one number space without colliding" do
      binary = two_tagged_links()
      objects = objects(binary)
      nums = parent_tree(binary)

      page_keys = for {_id, body} <- pages(objects), do: integer_entry(body, "StructParents")

      annotation_keys =
        for {_id, body} <- link_annotations(objects), do: integer_entry(body, "StructParent")

      assert page_keys -- annotation_keys == page_keys
      assert map_size(nums) == length(page_keys) + length(annotation_keys)

      [_, next_key] = Regex.run(~r/\/ParentTreeNextKey (\d+)/, binary)
      assert String.to_integer(next_key) > Enum.max(page_keys ++ annotation_keys)
    end
  end

  describe "an untagged link" do
    test "stays an inline dictionary, so untagged documents do not move" do
      binary =
        Tincture.new()
        |> Tincture.link(72, 700, 120, 14, "https://example.org")
        |> Tincture.export()

      assert binary =~ "/Annots [<< /Type /Annot /Subtype /Link"
      refute binary =~ "/OBJR"
      refute binary =~ "/StructParent"
    end
  end

  describe "conformance reporting" do
    test "a tagged document refuses a link that is outside the structure tree" do
      pdf =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.tag(:document, fn doc ->
          Tincture.tag(doc, :p, fn page ->
            page
            |> Tincture.set_font("Helvetica", 12)
            |> Tincture.text_at(72, 720, "body")
          end)
        end)
        |> Tincture.link(72, 700, 120, 14, "https://example.org")

      assert [violation] = Tincture.pdf_ua_violations(pdf)
      assert violation.rule == :link_outside_structure
      assert violation.message =~ "not in the structure tree"

      assert_raise ArgumentError, ~r/not in the structure tree/, fn ->
        Tincture.export(pdf)
      end
    end

    test "a link nested in the wrong element is named as such" do
      pdf =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.tag(:document, fn doc ->
          Tincture.tag(doc, :p, fn page ->
            Tincture.text_link(page, 72, 700, "target", {:url, "https://example.org"})
          end)
        end)

      assert [violation] = Tincture.pdf_ua_violations(pdf)
      assert violation.rule == :link_in_wrong_element
      assert violation.message =~ ":p element"
    end

    test "an untagged document claims nothing, so reports nothing" do
      pdf =
        Tincture.new()
        |> Tincture.link(72, 700, 120, 14, "https://example.org")

      assert Tincture.pdf_ua_violations(pdf) == []
    end

    # The rules are gated on the document being tagged, and nothing else. If
    # they fired on the presence of a link, every existing caller of link/6
    # would break on upgrade for a reason that does not apply to them.
    test "an untagged document full of links still exports, unenforced" do
      pdf =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.link(72, 700, 120, 14, "https://example.org")
        |> Tincture.text_link(72, 680, "inline", {:url, "https://example.org/two"})
        |> Tincture.add_page()
        |> Tincture.link(72, 700, 120, 14, {:page, 1})
        |> Tincture.link(72, 660, 120, 14, "https://example.org/three", page: 1)

      assert Tincture.pdf_ua_violations(pdf) == []

      binary = Tincture.export(pdf)
      assert binary =~ "/Subtype /Link"
      refute binary =~ "/StructTreeRoot"
    end

    # Tagging some of a document does not make its untagged links exempt: the
    # claim is made document-wide, so the check is too.
    test "a document that tags anything is held to the rule everywhere" do
      pdf =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.tag(:document, fn doc ->
          Tincture.tag(doc, :p, fn page ->
            page
            |> Tincture.set_font("Helvetica", 12)
            |> Tincture.text_at(72, 720, "body")
          end)
        end)
        |> Tincture.add_page()
        |> Tincture.link(72, 700, 120, 14, "https://example.org")

      assert [%{rule: :link_outside_structure}] = Tincture.pdf_ua_violations(pdf)
    end
  end
end

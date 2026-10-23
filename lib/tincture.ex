defmodule Tincture do
  @moduledoc """
  Typographic-quality PDF generation, in pure Elixir.

  A document is an immutable struct threaded through a pipeline. Nothing is
  written until `export/1`, so a document can be built, inspected and tested
  before any bytes exist.

      Tincture.new()
      |> Tincture.page_size(:a4)
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_at(72, 700, "Hello")
      |> Tincture.export()

  ## Coordinates

  PDF user space has its origin at the **bottom-left** of the page, with y
  increasing upwards — the opposite of most screen coordinate systems. A y of
  700 on A4 is near the top. All positions and sizes are in points (1/72
  inch), so A4 is 595 x 842 and US Letter is 612 x 792.

  ## Text

  `text_at/4` draws a single string at a point. For anything that needs to
  wrap, use `text_paragraph/6`, which runs the typography engine: TeX
  hyphenation and Knuth-Plass line breaking, the same global optimisation TeX
  uses, rather than greedy first-fit.

      rich = Tincture.Typography.RichText.from_plain(body, font: "Times-Roman", size: 11)

      Tincture.text_paragraph(pdf, 72, 700, rich, 450,
        align: :justified,
        line_break: :optimal
      )

  For multi-page documents with headers, footers and page numbering, see
  `Tincture.Layout.Template`.

  ## Fonts

  The 14 standard PDF fonts are always available by name. TrueType and
  OpenType fonts are embedded with `register_ttf_font/4` and
  `register_otf_font/4`, and are **subsetted by default** — only the glyphs
  the document draws are embedded, which typically cuts an embedded font by
  70-90%.

  ## Architecture

  Each layer is usable on its own; the one above it is a convenience.

  ```mermaid
  flowchart TD
      A["Tincture<br/>drawing, text, links, images"] --> B
      B["Tincture.Layout<br/>boxes, tables, page templates"] --> C
      C["Tincture.Typography<br/>hyphenation, line breaking, kerning"] --> D
      D["Tincture.PDF<br/>document state, fonts, serialisation"] --> E
      E["Tincture.Font<br/>TrueType, OpenType, CFF parsing"]
  ```

  ## Zero runtime dependencies

  No Chrome, no wkhtmltopdf, no NIFs, no ports. The whole pipeline — font
  parsing, subsetting, hyphenation, line breaking, PDF serialisation — is
  Elixir and Erlang/OTP. It runs anywhere the BEAM runs.
  """

  import Bitwise

  require Logger

  alias Tincture.Font
  alias Tincture.Font.Context
  alias Tincture.Font.UnicodeRanges
  alias Tincture.PDF
  alias Tincture.PDF.Accessibility
  alias Tincture.PDF.Archival
  alias Tincture.PDF.Ops
  alias Tincture.PDF.Serialize
  alias Tincture.PDF.Structure
  alias Tincture.PDF.TextExtent
  alias Tincture.Typography
  alias Tincture.Typography.Line
  alias Tincture.Typography.RichText
  alias Tincture.Typography.RichText.Break
  alias Tincture.Typography.RichText.Space
  alias Tincture.Typography.RichText.Word
  alias Tincture.Unicode

  @type page_size :: :a4 | :letter | :legal | {number(), number()}
  @typedoc "How a shape is painted. See `rectangle/6`."
  @type paint :: PDF.paint()
  @type rich_text :: RichText.t()
  @type paragraph_option ::
          {:align, :left | :center | :right | :justified}
          | {:line_height, number()}
          | {:line_break, :greedy | :optimal}
          | {:optimal_cost_model, :quadratic | :box_glue}
          | {:justify_max_space_multiplier, number() | :infinity}
          | {:justify_min_space_multiplier, number()}
          | {:widow_penalty, number()}
          | {:orphan_penalty, number()}
          | {:hyphen_penalty, number()}
          | {:fitness_class_penalty, number()}
          | {:consecutive_hyphen_penalty, number()}
          | {:rotate, number()}
          | {:fallback_fonts, [String.t()]}
          | {:bidi, :off | :basic}
          | {:shaping, :off | :latin_ligatures | :gsub_ligatures}
          | {:kerning, :off | :gpos}

  @doc """
  Create a new PDF state struct.
  """
  @spec new() :: PDF.t()
  def new do
    %PDF{}
  end

  @doc """
  Set the current page size.
  """
  @spec page_size(PDF.t(), page_size()) :: PDF.t()
  def page_size(%PDF{} = pdf, size) when size in [:a4, :letter, :legal] do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.page_size/2")
    %PDF{pdf | page_size: size}
  end

  def page_size(%PDF{} = pdf, {width, height})
      when is_number(width) and is_number(height) and width > 0 and height > 0 do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.page_size/2")
    %PDF{pdf | page_size: {width, height}}
  end

  @doc """
  Set document metadata fields (for example: `:title`, `:author`, `:keywords`).
  """
  @spec set_metadata(PDF.t(), map() | keyword()) :: PDF.t()
  def set_metadata(%PDF{} = pdf, metadata) when is_map(metadata) or is_list(metadata) do
    PDF.set_metadata(pdf, metadata)
  end

  @doc """
  Add a new page and make it the current page.

  Close any content tag or `artifact/2` block first. A marked-content sequence
  has to begin and end in the same content stream, and each page is its own
  stream. Calling this while a content tag such as `tag(:p, ...)` or
  `tag(:figure, ...)`, or an `artifact/2` block, is open on the current page
  raises `ArgumentError`, naming what is open, because marked content cannot
  span content streams. A grouping tag such as `:section` may stay open
  across pages.

  Paint any path first, too. Calling this while a path is open on the current
  page, one nothing has painted, raises `ArgumentError`, because the page's
  content stream would end inside the path.
  """
  @spec add_page(PDF.t()) :: PDF.t()
  def add_page(%PDF{} = pdf) do
    PDF.add_page(pdf)
  end

  @doc """
  Switch the current page by page number (1-based).

  Close any content tag or `artifact/2` block first, as for `add_page/1`.
  Switching to another page while one is open on the current page raises
  `ArgumentError`, because marked content cannot span content streams.
  Switching to the page already current does not. The same holds for a path
  open on the current page that nothing has painted.
  """
  @spec set_page(PDF.t(), pos_integer()) :: PDF.t()
  def set_page(%PDF{} = pdf, page_number) when is_integer(page_number) and page_number > 0 do
    PDF.set_page(pdf, page_number)
  end

  @doc """
  Add a document bookmark pointing to a page number.
  """
  @spec add_bookmark(PDF.t(), String.t(), pos_integer()) :: PDF.t()
  def add_bookmark(%PDF{} = pdf, title, page_number) do
    PDF.add_bookmark(pdf, title, page_number)
  end

  @doc """
  Add a clickable link over a rectangular region of the current page.

  `target` is one of:

    * a URL string, or `{:url, url}` — an external link;
    * `{:page, page_number}` — a cross-reference within this document;
    * `{:file, path}` — another PDF file, opened at its first page;
    * `{:file, path, page_number}` — another PDF file, at a given page.

  Page numbers count from 1 everywhere, including into a remote file:
  `{:file, "report.pdf", 13}` means the thirteenth page.

  ## Linking to another file

  `path` is relative to the document that carries the link, which is how a set
  of documents that ship together refer to each other:

      Main.pdf
      Attached documents/
          Secondary-1.pdf

      Tincture.link(pdf, 72, 700, 200, 14,
        {:file, "Attached documents/Secondary-1.pdf", 13},
        contents: "appendix B, page 13"
      )

  Backslashes are converted to forward slashes, since a PDF file specification
  uses them regardless of the platform that wrote the file. Absolute paths and
  non-ASCII paths are refused: the first names a location on your machine
  rather than the reader's, and the second cannot be carried portably by the
  string form this uses.

  Two limitations worth knowing before you rely on this.

  **The page number is a promise about a file Tincture never reads.** Nothing
  can check it — not the path, not the page count. If the target is
  regenerated with an extra page near the front, every link into it is
  silently off by one, in a document you may no longer control. Named
  destinations would survive that; they are not implemented. Tincture also
  cannot detect a missing or renamed target, and what a viewer does with a
  file specification that resolves to nothing is not specified here — it has
  not been observed.

  **Viewer support is not universal.** Some desktop readers follow these links;
  browser-embedded viewers generally do not, because they refuse local-file
  navigation as a matter of policy. Observed by hand, not checked in CI: at
  0.3.2, SumatraPDF followed them, Microsoft Edge rendered the link but did
  nothing on click, and Firefox's viewer did not act on them; at 0.3.3, macOS
  Preview, the default PDF viewer on macOS, showed a permission alert on click
  and did not open the target (macOS 26.6.2). A set of documents that relies on these links
  needs a desktop reader that follows them; SumatraPDF is the one observed.

  Coordinates are in PDF user space, with the origin at the bottom-left of the
  page — the same space `text_at/4` and `rectangle/5` use. The rectangle is
  given as `x`, `y`, `width`, `height`; corners are normalised, so a negative
  width or height still produces a valid region rather than a dead link.

  Linking does not draw anything. Use `text_link/5` to draw text and make it
  clickable in one call, or pair this with your own `rectangle/5` and
  `set_fill_color/2` calls.

  In a tagged document a link needs two things, and `export/2` refuses without
  either. Create it inside `tag(:link, ...)`, which puts the annotation in the
  structure tree so a reader navigating by structure can reach it at all; and
  give it `:contents`, the alternate description that reader announces:

      Tincture.tag(pdf, :link, fn page ->
        Tincture.text_link(page, 72, 700, "Elixir",
          "https://elixir-lang.org",
          contents: "the Elixir home page"
        )
      end)

  ## Options

    * `:page` — which page to attach the link to. Defaults to the current page.
    * `:border` — `:none` (default) or `{horizontal, vertical, width}`. The
      default suppresses the black rectangle most viewers would otherwise draw
      around every link.
    * `:new_window` — `true` or `false`, for a link into another file. Both
      write `/NewWindow`; **omitting the option omits the key**, which is a
      different instruction — it leaves the choice to the reader's viewer
      rather than overriding a preference they may have set.
    * `:contents` — the link's alternate description, written as `/Contents`.
      A reader that reaches the annotation has nothing else to announce, so
      say where the link goes: `"the 2026 tariff schedule"`, not `"link"`.
      Required in a tagged document, where `export/2` refuses without it.

  ## Examples

      pdf
      |> Tincture.link(72, 700, 120, 14, "https://elixir-lang.org")

      # Internal cross-reference to page 3.
      Tincture.link(pdf, 72, 680, 120, 14, {:page, 3})

      # Attach a link to a page other than the current one.
      Tincture.link(pdf, 72, 660, 120, 14, "https://hex.pm", page: 1)

  """
  @spec link(PDF.t(), number(), number(), number(), number(), PDF.link_target()) ::
          PDF.t()
  def link(%PDF{} = pdf, x, y, width, height, target) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.link/6")
    link(pdf, x, y, width, height, target, [])
  end

  @doc """
  Add a clickable link over a rectangle on the page, with options.

  Behaves as `link/6`. The options — `:page`, `:border`, `:new_window` and
  `:contents` — are described there.
  """
  @spec link(
          PDF.t(),
          number(),
          number(),
          number(),
          number(),
          PDF.link_target(),
          keyword()
        ) :: PDF.t()
  def link(%PDF{} = pdf, x, y, width, height, target, opts)
      when is_number(x) and is_number(y) and is_number(width) and is_number(height) and
             is_list(opts) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.link/7")
    PDF.add_link(pdf, {x, y, x + width, y + height}, target, opts)
  end

  @doc """
  Draw text at X/Y and make it clickable.

  The link rectangle is measured from the text using the current font, so it
  covers exactly the drawn glyphs. Takes the same options as `link/7`, plus:

    * `:color` — an `{r, g, b}` fill colour to draw the text in. The colour
      change is wrapped in a save/restore of the graphics state, so it does not
      leak into later drawing. Defaults to leaving the colour alone, so links
      are not silently recoloured.

  A remote link is still a link, so a tagged document needs the same two things
  from it: create it inside `tag(:link, ...)` and give it `:contents`.
  "Secondary-1.pdf" tells a reader nothing, and the target is a document they
  cannot see, so the description matters more here rather than less.

  `:contents` additionally accepts `:text`, which reuses the drawn text as the
  alternate description. It is opt-in and deliberately not the default:
  veraPDF's rule checks only that a description is present (PDF/UA-1
  7.18.5-2), so one that mechanically repeats the link text passes it while
  telling a screen reader user nothing, and `"click here"` is precisely
  the case where it does harm. Use it where the text already says where the
  link goes.

  Calling this while a path is open raises `ArgumentError`, as for
  `text_at/4`.

      # The text is the description.
      Tincture.text_link(pdf, 72, 700, "Elixir home page", url, contents: :text)

      # The text is not.
      Tincture.text_link(pdf, 72, 680, "here", url, contents: "the Elixir home page")

  ## Examples

      pdf
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_link(72, 700, "Elixir", "https://elixir-lang.org")

      # Conventional blue link.
      Tincture.text_link(pdf, 72, 680, "Hex", "https://hex.pm", color: {0.0, 0.3, 0.8})

  """
  @spec text_link(PDF.t(), number(), number(), String.t(), PDF.link_target()) ::
          PDF.t()
  def text_link(%PDF{} = pdf, x, y, text, target) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.text_link/5")
    Ops.refuse_open_path(pdf, "Tincture.text_link/5", "the text")
    draw_text_link(pdf, x, y, text, target, [])
  end

  @doc """
  Draw text at X/Y and make it clickable, with options.

  Behaves as `text_link/5`, which describes `:color` and `contents: :text`. The
  remaining options are those of `link/7`.
  """
  @spec text_link(
          PDF.t(),
          number(),
          number(),
          String.t(),
          PDF.link_target(),
          keyword()
        ) :: PDF.t()
  def text_link(%PDF{} = pdf, x, y, text, target, opts)
      when is_number(x) and is_number(y) and is_binary(text) and is_list(opts) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.text_link/6")
    Ops.refuse_open_path(pdf, "Tincture.text_link/6", "the text")
    draw_text_link(pdf, x, y, text, target, opts)
  end

  # text_link/5 and /6 refuse and warn under their own names, then draw here,
  # so a call warns once. The guards are text_link/6's, which text_link/5
  # reached before.
  # credo:disable-for-next-line /^Elixir\.Credo\.Check\.Refactor\.(ABCSize|CyclomaticComplexity)$/
  defp draw_text_link(pdf, x, y, text, target, opts)
       when is_number(x) and is_number(y) and is_binary(text) and is_list(opts) do
    # `contents: :text` reuses the drawn text as the alternate description.
    # Opt-in rather than the default: an alternate description that mechanically
    # repeats the link text passes a validator and tells a screen reader user
    # nothing, and "click here" is exactly where that goes wrong.
    opts =
      case Keyword.get(opts, :contents) do
        :text -> Keyword.put(opts, :contents, text)
        _other -> opts
      end

    {font_name, font_size} = pdf.current_font
    {width, ascent, descent} = TextExtent.extent(pdf, font_name, font_size, text)

    {drawn, link_opts} =
      case Keyword.pop(opts, :color) do
        {nil, rest} ->
          {Ops.text_at(pdf, x, y, text), rest}

        {{_r, _g, _b} = rgb, rest} ->
          drawn =
            pdf
            |> Ops.save_state()
            |> set_fill_color(rgb)
            |> Ops.text_at(x, y, text)
            |> Ops.restore_state()

          {drawn, rest}
      end

    link(drawn, x, y - descent, width, ascent + descent, target, link_opts)
  end

  @doc """
  Add a fillable text field.

  The field is a widget on the current page and an entry in the document's
  interactive form. `name` addresses the field's value in the filled document,
  so it must be unique.

  ## Options

    * `:value` — the initial value. Defaults to empty.
    * `:size` — font size. Defaults to `0`, meaning auto-size, which is
      usually what you want for a field whose height you chose: the field's
      appearance uses the largest size up to 12 that fits the box, and a
      viewer fits the text again when someone edits it.
    * `:align` — `:left` (default), `:center` or `:right`, written as `/Q`.
    * `:font` — one of the standard 14, or a font registered with
      `register_ttf_font/4` or `register_otf_font/4`. Defaults to
      `"Helvetica"`. See "Embedded fonts" below.
    * `:full_font` — embed the field's font whole, for the whole document,
      so that a viewer can draw any character someone types. Required for an
      editable field with an embedded font, unless the font was registered
      with `subset: :none`. Ignored with a standard-14 font, which is never
      embedded.
    * `:multiline` — allow line breaks. Defaults to `false`. The appearance
      breaks the value at each line break and wraps it at spaces to the
      box's width.
    * `:password` — mask the value as it is typed. Defaults to `false`. The
      field's appearance draws nothing, but a `:value` is still written to the
      file, where anyone who opens it can read it.
    * `:max_length` — maximum characters accepted.
    * `:read_only`, `:required`, `:no_export` — field flags, all `false` by
      default.
    * `:tooltip` — hover text.
    * `:border` — `:none` (default) or `{horizontal, vertical, width}`.
    * `:page` — which page to place the widget on. Defaults to the current
      page.

  ## In a tagged document

  Every form field needs a `:tooltip`. It is written as `/TU`, the name a
  screen reader announces for the field. Every form field must also be created
  inside a `tag/4` scope, so that a reader can reach it from the structure
  tree. `export/2` warns for each field that breaks either rule, and 0.4.0
  raises. An untagged document is not checked.

  ## Appearance

  The field carries its own appearance stream, its value laid out by
  Tincture, so it displays the same in every viewer, and when printed,
  thumbnailed or rendered by a tool that does not regenerate fields. A viewer
  that lets someone edit the field builds a new appearance from `/DA` and the
  form's font resources.

  When someone types characters the field's font cannot encode, PDFium
  (Chrome, Edge) draws them with a font of its own, which it does not embed
  and which depends on the fonts installed where the file is edited. This
  happens even with an embedded font that has the characters. Tincture
  cannot prevent it from inside the file.

  ## Characters a standard font can draw

  A standard-14 font is written with WinAnsi encoding, and the appearance
  draws the value in it, so a field using one can only hold characters
  WinAnsi encodes: Latin text such as `"Größe"`, but not `"Ελλάδα"`. A value
  with any other character raises `ArgumentError` when the field is created.
  A line break is fine in the value of a `multiline: true` field, whose
  appearance breaks the line there; in a single-line value it raises like any
  other character. For other characters, use an embedded font.

  ## Embedded fonts

  A field may use a registered TrueType or OpenType font. It is written as a
  `Type0` font with Identity-H encoding, so any character the font has can be
  drawn. If page text uses the same font, both share one font dictionary and
  one font program.

  A field is editable unless it is `read_only: true`. Someone may type any
  character into an editable field, so its font must be embedded whole:
  pass `full_font: true`, or register the font with `subset: :none`.
  Otherwise the call raises `ArgumentError`. A whole font covers every
  character in it, and page text in the same font then carries the whole
  program too. The font's licence must also allow editable embedding: an
  editable field raises `ArgumentError` if the font's OS/2 `fsType` allows
  only Restricted License, Preview & Print or bitmap embedding, whatever
  `enforce_embedding_permissions:` was given at registration. A read-only
  field's font is subset to its value, like page text.

  ## Examples

      pdf
      |> Tincture.text_field(72, 700, 300, 24, "full_name", tooltip: "Your full name")
      |> Tincture.text_field(72, 640, 300, 80, "notes", multiline: true)

  """
  @spec text_field(PDF.t(), number(), number(), number(), number(), String.t(), keyword()) ::
          PDF.t()
  def text_field(%PDF{} = pdf, x, y, width, height, name, opts \\ [])
      when is_number(x) and is_number(y) and is_number(width) and is_number(height) and
             is_binary(name) and is_list(opts) do
    PDF.add_form_field(pdf, :text, name, {x, y, x + width, y + height}, opts)
  end

  @doc """
  Add a checkbox.

  Checkboxes are square, so a single `size` gives both dimensions.

  ## Options

    * `:value` — `true` for checked. Defaults to `false`.
    * `:read_only`, `:required`, `:no_export` — field flags.
    * `:tooltip`, `:border`, `:page` — as for `text_field/7`.

  In a tagged document, a checkbox needs a `:tooltip` and must be created
  inside a `tag/4` scope, as for `text_field/7`.

  ## Examples

      Tincture.checkbox(pdf, 72, 700, 14, "accept_terms", value: false)

  """
  @spec checkbox(PDF.t(), number(), number(), number(), String.t(), keyword()) :: PDF.t()
  def checkbox(%PDF{} = pdf, x, y, size, name, opts \\ [])
      when is_number(x) and is_number(y) and is_number(size) and is_binary(name) and
             is_list(opts) do
    PDF.add_form_field(pdf, :checkbox, name, {x, y, x + size, y + size}, opts)
  end

  @doc """
  Add a radio button group: one field, several buttons, at most one selected.

  A radio group is the one field type that is not a single widget. The value
  lives on the group and each button is its own widget, so buttons are given as
  a list rather than added one at a time — a lone radio button is not a
  meaningful thing to place.

  Each button needs `:value`, `:x`, `:y` and `:size`. The `:value` is what the
  field takes when that button is chosen, and is what appears in the filled
  document. `"Off"` is reserved by the specification for "nothing selected" and
  is rejected as a button value.

  ## Options

    * `:selected` — the `:value` of the initially selected button. Defaults to
      none selected.
    * `:allow_deselect` — let clicking the selected button turn it off again.
      Defaults to `false`, which is what a radio group usually means.
    * `:read_only`, `:required`, `:no_export` — field flags.
    * `:tooltip`, `:border`, `:font`, `:size` — as for `text_field/7`.
    * `:page` — the default page for buttons that do not name their own.

  In a tagged document, the group needs one `:tooltip` and must be created
  inside a `tag/4` scope, as for `text_field/7`.

  ## Examples

      Tincture.radio_group(pdf, "delivery", [
        [value: "standard", x: 72, y: 700, size: 12],
        [value: "express", x: 72, y: 680, size: 12],
        [value: "collect", x: 72, y: 660, size: 12]
      ], selected: "standard")

  """
  @spec radio_group(PDF.t(), String.t(), [keyword()], keyword()) :: PDF.t()
  def radio_group(%PDF{} = pdf, name, buttons, opts \\ [])
      when is_binary(name) and is_list(buttons) and is_list(opts) do
    PDF.add_radio_group(pdf, name, buttons, opts)
  end

  @doc """
  Add a push button.

  A push button holds no value — it exists to do something when clicked — so
  `:action` is required.

  ## Options

    * `:action` — required. One of:
      * `:reset` — clear every field in the form.
      * `{:url, url}` — open a URL.
      * `{:submit, url}` — submit the form's values to a URL.
    * `:label` — the caption drawn on the button face.
    * `:read_only`, `:required`, `:no_export` — field flags.
    * `:tooltip`, `:border`, `:font`, `:size`, `:page` — as for `text_field/7`.

  In a tagged document, a push button needs a `:tooltip` and must be created
  inside a `tag/4` scope, as for `text_field/7`. Its `:label` may only use
  characters WinAnsi encodes, as a text field's value (`text_field/7`), and
  a line break in it raises.

  ## Examples

      pdf
      |> Tincture.push_button(72, 100, 90, 24, "submit", label: "Send",
           action: {:submit, "https://example.com/apply"})
      |> Tincture.push_button(180, 100, 90, 24, "reset", label: "Clear",
           action: :reset)

  """
  @spec push_button(PDF.t(), number(), number(), number(), number(), String.t(), keyword()) ::
          PDF.t()
  def push_button(%PDF{} = pdf, x, y, width, height, name, opts \\ [])
      when is_number(x) and is_number(y) and is_number(width) and is_number(height) and
             is_binary(name) and is_list(opts) do
    PDF.add_form_field(pdf, :push_button, name, {x, y, x + width, y + height}, opts)
  end

  @doc """
  Add a signature field: a place for someone to sign.

  On its own this reserves the field, unsigned, for a viewer to fill. To sign it
  as the document is exported, pass its name to `sign/3`.

  The widget carries no appearance stream, so a static render shows nothing for
  the field, and a document that declares PDF/A refuses to export with one.

  ## Options

    * `:read_only`, `:required`, `:no_export` — field flags.
    * `:tooltip`, `:border`, `:page` — as for `text_field/7`.

  In a tagged document, a signature field needs a `:tooltip` and must be
  created inside a `tag/4` scope, as for `text_field/7`.

  ## Examples

      Tincture.signature_field(pdf, 72, 120, 220, 48, "signature",
        tooltip: "Sign here")

  """
  @spec signature_field(PDF.t(), number(), number(), number(), number(), String.t(), keyword()) ::
          PDF.t()
  def signature_field(%PDF{} = pdf, x, y, width, height, name, opts \\ [])
      when is_number(x) and is_number(y) and is_number(width) and is_number(height) and
             is_binary(name) and is_list(opts) do
    PDF.add_form_field(pdf, :signature, name, {x, y, x + width, y + height}, opts)
  end

  @doc """
  Add a choice field — a dropdown by default, or a list box.

  ## Options

    * `:options` — **required**, the list of choices.
    * `:value` — the initially selected choice. Unless the field is
      `editable: true`, it must be one of `:options`: any other value raises
      `ArgumentError`.
    * `:dropdown` — `true` (default) for a combo box, `false` for a list box.
    * `:editable` — allow a value outside the list. Defaults to `false`.
    * `:sort` — write the options sorted, which is the order a viewer shows
      them in: alphabetically ignoring case, with the exact text breaking
      ties. Defaults to `false`, which keeps the order given.
    * `:read_only`, `:required`, `:no_export`, `:tooltip`, `:border`,
      `:page`, `:font`, `:full_font`, `:size`, `:align` — as for
      `text_field/7`.

  The field carries its own appearance, as a text field does
  (`text_field/7`). A dropdown shows its value. A list box shows as many
  options as fit, in the order written, with the selected one highlighted;
  when the selection would fall below the box, the list is scrolled to show
  it, and the first option shown is written as `/TI`.

  In a tagged document, a choice field needs a `:tooltip` and must be created
  inside a `tag/4` scope, as for `text_field/7`. With a standard-14 font, its
  `:value` and every one of its `:options` may only use characters WinAnsi
  encodes, as a text field's value (`text_field/7`), and a line break in any
  of them raises.

  A choice field may use an embedded font, as a text field may. It is
  editable when given `editable: true` and not `read_only: true`, and then its
  font must be embedded whole and licensed for editable embedding, as
  `text_field/7` describes. Otherwise its font is subset to its value and
  every one of its `:options`.

  ## Examples

      Tincture.choice_field(pdf, 72, 700, 200, 24, "country",
        options: ["Italy", "Norway", "Japan"],
        value: "Italy"
      )

  """
  @spec choice_field(PDF.t(), number(), number(), number(), number(), String.t(), keyword()) ::
          PDF.t()
  def choice_field(%PDF{} = pdf, x, y, width, height, name, opts \\ [])
      when is_number(x) and is_number(y) and is_number(width) and is_number(height) and
             is_binary(name) and is_list(opts) do
    PDF.add_form_field(pdf, :choice, name, {x, y, x + width, y + height}, opts)
  end

  @doc """
  Encrypt the document with AES-256.

  Uses the standard security handler at revision 6 (`/V 5 /R 6`), the
  encryption defined by PDF 2.0. The test suite decrypts the output with an
  independent implementation of the specification's reader-side algorithms;
  no third-party reader is run against it in CI.

  ## What this protects

  A **user password** is real encryption. Without it the document cannot be
  read at all.

      Tincture.encrypt(pdf, user_password: "hunter2")

  An **owner password on its own is not.** The document is encrypted under the
  empty user password, so any reader can open it; the permissions below are
  advisory, enforced only by a reader that chooses to, and a tool that ignores
  them can rewrite the file without them, no password needed. This is how the
  PDF format works, not a limitation of this implementation.

      # Anyone can open this; the restriction is a request, not a control.
      Tincture.encrypt(pdf, owner_password: "master", permissions: [:print])

  Use an owner password to express intent, and a user password when the
  content genuinely must not be read.

  ## Options

    * `:user_password` — required to open the document. Defaults to `""`.
    * `:owner_password` — grants full rights. Defaults to the user password.
    * `:permissions` — what a viewer is asked to allow. Defaults to
      everything. One or more of `:print`, `:modify`, `:copy`, `:annotate`,
      `:fill_forms`, `:extract_for_accessibility`, `:assemble`,
      `:print_high_quality`.
    * `:encrypt_metadata` — encrypt document metadata too. Defaults to `true`.

  ## Examples

      pdf
      |> Tincture.text_at(72, 700, "Confidential")
      |> Tincture.encrypt(user_password: "hunter2", permissions: [:print])
      |> Tincture.export()

  Calling this twice replaces the earlier settings; the document is encrypted
  once, at export.

  A signed document cannot be encrypted. Calling this on a document that
  `sign/3` has been called on raises `ArgumentError`, and so does calling
  `sign/3` on an encrypted document.
  """
  @spec encrypt(PDF.t(), keyword()) :: PDF.t()
  def encrypt(%PDF{} = pdf, opts) when is_list(opts) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.encrypt/2")
    PDF.refuse_encrypting_signed!(pdf, "Tincture.encrypt/2")
    %PDF{pdf | encryption: Tincture.PDF.Encrypt.new(opts)}
  end

  @doc """
  Encrypt the document with the default options: `encrypt(pdf, [])`.

  See `encrypt/2`. As there, calling this on a signed document raises
  `ArgumentError`.
  """
  @spec encrypt(PDF.t()) :: PDF.t()
  def encrypt(%PDF{} = pdf) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.encrypt/1")
    PDF.refuse_encrypting_signed!(pdf, "Tincture.encrypt/1")
    %PDF{pdf | encryption: Tincture.PDF.Encrypt.new([])}
  end

  @doc """
  Set the current font name and size.
  """
  @spec set_font(PDF.t(), String.t(), number()) :: PDF.t()
  def set_font(%PDF{} = pdf, font_name, size) do
    Ops.set_font(pdf, font_name, size)
  end

  @doc """
  Register an embedded TrueType font by name from a `.ttf` file path.
  """
  @spec register_ttf_font(PDF.t(), String.t(), Path.t()) :: PDF.t()
  def register_ttf_font(%PDF{} = pdf, font_name, path) do
    register_ttf_font(pdf, font_name, path, [])
  end

  @doc """
  Register an embedded TrueType font by name from a `.ttf` file path with embedding options.

  ## Options

    * `:subset` — how much of the font to embed. Defaults to `:used_text`.

      * `:used_text` — embed only the glyphs the document actually draws.
        Typically cuts an embedded font by 70-90%.
      * `:ascii_basic` — embed the printable ASCII range (32..126). Useful when
        you intend to edit the text later with an external tool.
      * `:none` — embed the font verbatim.

      Subsetted fonts carry the six-letter `/BaseFont` tag the PDF
      specification requires (for example `ABCDEF+Inter`). If a font cannot be
      subsetted safely, Tincture logs a warning and embeds it in full rather
      than producing a broken document.

    * `:enforce_embedding_permissions` — when `true`, raise instead of warn if
      the font's OS/2 `fsType` restricts embedding or subsetting. Defaults to
      `false`.

  ## Examples

      Tincture.new()
      |> Tincture.register_ttf_font("Inter", "priv/fonts/Inter.ttf")
      |> Tincture.set_font("Inter", 12)

      # Embed the whole font, e.g. for a template others will edit.
      Tincture.register_ttf_font(pdf, "Inter", path, subset: :none)

  """
  @spec register_ttf_font(PDF.t(), String.t(), Path.t(), keyword()) :: PDF.t()
  def register_ttf_font(%PDF{} = pdf, font_name, path, opts) when is_list(opts) do
    PDF.register_ttf_font(pdf, font_name, path, opts)
  end

  @doc """
  Register an embedded OpenType font by name from an `.otf` file path.
  """
  @spec register_otf_font(PDF.t(), String.t(), Path.t()) :: PDF.t()
  def register_otf_font(%PDF{} = pdf, font_name, path) do
    register_otf_font(pdf, font_name, path, [])
  end

  @doc """
  Register an embedded OpenType font by name from an `.otf` file path with embedding options.

  Takes the same options as `register_ttf_font/4`, including `:subset`, which
  defaults to `:used_text`.
  """
  @spec register_otf_font(PDF.t(), String.t(), Path.t(), keyword()) :: PDF.t()
  def register_otf_font(%PDF{} = pdf, font_name, path, opts) when is_list(opts) do
    PDF.register_otf_font(pdf, font_name, path, opts)
  end

  @doc """
  Place text at X/Y coordinates on the current page.

  Calling this while a path is open, after `move_to/3`, `line_to/3`,
  `bezier/7` or a shape drawn with `paint: :none` and before the path is
  painted, raises `ArgumentError`: the text would be written inside the path,
  where PDF does not allow it.
  """
  @spec text_at(PDF.t(), number(), number(), String.t()) :: PDF.t()
  def text_at(%PDF{} = pdf, x, y, text) do
    Ops.refuse_open_path(pdf, "Tincture.text_at/4", "the text")
    Ops.text_at(pdf, x, y, text)
  end

  @doc """
  Place text at X/Y coordinates, splitting glyph runs across fallback fonts when needed.

  Calling this while a path is open raises `ArgumentError`, as for
  `text_at/4`.
  """
  @spec text_at_with_fallback(PDF.t(), number(), number(), String.t(), [String.t()]) :: PDF.t()
  def text_at_with_fallback(%PDF{} = pdf, x, y, text, fallback_fonts \\ [])
      when is_number(x) and is_number(y) and is_binary(text) and is_list(fallback_fonts) do
    Ops.refuse_open_path(pdf, "Tincture.text_at_with_fallback/5", "the text")
    draw_fallback_text(pdf, x, y, text, fallback_fonts, [])
  end

  @doc """
  Place text at X/Y coordinates, splitting glyph runs across fallback fonts when
  needed, with shaping and kerning options.

  ## Options

    * `:shaping` — `:off` (default) draws the text as given. `:latin_ligatures`
      replaces sequences such as `fi`, `fl` and `ffi` with ligature characters,
      using the font's GSUB `liga` substitutions for Latin and a built-in set of
      f-ligatures. `:gsub_ligatures` uses the font's `liga`, `rlig` and `ccmp`
      substitutions across all scripts. A sequence is replaced only where a font
      in the fallback chain has a glyph for the ligature.
    * `:kerning` — `:off` (default) or `:gpos`, which applies the embedded
      font's GPOS pair adjustments between consecutive characters. Kerned text
      is drawn one character per text operation. Standard fonts carry no GPOS
      data, so the option has no effect on them.
  """
  @spec text_at_with_fallback(
          PDF.t(),
          number(),
          number(),
          String.t(),
          [String.t()],
          keyword()
        ) :: PDF.t()
  def text_at_with_fallback(%PDF{} = pdf, x, y, text, fallback_fonts, opts)
      when is_number(x) and is_number(y) and is_binary(text) and is_list(fallback_fonts) and
             is_list(opts) do
    Ops.refuse_open_path(pdf, "Tincture.text_at_with_fallback/6", "the text")
    draw_fallback_text(pdf, x, y, text, fallback_fonts, opts)
  end

  # Both arities warn under their own name, then draw here; the segments are
  # drawn with Ops.text_at/4, which does not warn again.
  defp draw_fallback_text(pdf, x, y, text, fallback_fonts, opts) do
    shaping = normalize_shaping_option(Keyword.get(opts, :shaping, :off))
    kerning = normalize_kerning_option(Keyword.get(opts, :kerning, :off))

    {next_pdf, _rendered_width} =
      draw_text_with_fallback(
        pdf,
        x,
        y,
        text,
        fallback_fonts,
        shaping,
        kerning,
        fn doc, draw_x, draw_y, segment ->
          Ops.text_at(doc, draw_x, draw_y, segment)
        end
      )

    next_pdf
  end

  @doc """
  Place rotated text at X/Y, splitting glyph runs across fallback fonts when needed.

  Calling this while a path is open raises `ArgumentError`, as for
  `text_at/4`.
  """
  @spec text_at_rotated_with_fallback(
          PDF.t(),
          number(),
          number(),
          number(),
          String.t(),
          [String.t()]
        ) :: PDF.t()
  def text_at_rotated_with_fallback(
        %PDF{} = pdf,
        x,
        y,
        angle_degrees,
        text,
        fallback_fonts \\ []
      )
      when is_number(x) and is_number(y) and is_number(angle_degrees) and is_binary(text) and
             is_list(fallback_fonts) do
    Ops.refuse_open_path(pdf, "Tincture.text_at_rotated_with_fallback/6", "the text")
    draw_rotated_fallback_text(pdf, x, y, angle_degrees, text, fallback_fonts, [])
  end

  @doc """
  Place rotated text at X/Y, splitting glyph runs across fallback fonts when
  needed, with shaping and kerning options.

  Takes the same options as `text_at_with_fallback/6`.
  """
  @spec text_at_rotated_with_fallback(
          PDF.t(),
          number(),
          number(),
          number(),
          String.t(),
          [String.t()],
          keyword()
        ) :: PDF.t()
  def text_at_rotated_with_fallback(
        %PDF{} = pdf,
        x,
        y,
        angle_degrees,
        text,
        fallback_fonts,
        opts
      )
      when is_number(x) and is_number(y) and is_number(angle_degrees) and is_binary(text) and
             is_list(fallback_fonts) and is_list(opts) do
    Ops.refuse_open_path(pdf, "Tincture.text_at_rotated_with_fallback/7", "the text")
    draw_rotated_fallback_text(pdf, x, y, angle_degrees, text, fallback_fonts, opts)
  end

  # As draw_fallback_text/6, rotated.
  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp draw_rotated_fallback_text(pdf, x, y, angle_degrees, text, fallback_fonts, opts) do
    shaping = normalize_shaping_option(Keyword.get(opts, :shaping, :off))
    kerning = normalize_kerning_option(Keyword.get(opts, :kerning, :off))

    {next_pdf, _rendered_width} =
      draw_text_with_fallback(
        pdf,
        x,
        y,
        text,
        fallback_fonts,
        shaping,
        kerning,
        fn doc, draw_x, draw_y, segment ->
          Ops.text_at_rotated(doc, draw_x, draw_y, angle_degrees, segment)
        end
      )

    next_pdf
  end

  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp draw_text_with_fallback(
         %PDF{} = pdf,
         x,
         y,
         text,
         fallback_fonts,
         shaping,
         kerning,
         draw_fun
       ) do
    {primary_font, size} = pdf.current_font
    entry_font = pdf.current_font
    fallback_fonts = normalize_fallback_fonts(pdf, fallback_fonts, primary_font)
    font_order = [primary_font | fallback_fonts]
    shaped_text = shape_text_for_fonts(text, shaping, pdf, font_order)

    if shaped_text == "" do
      {pdf, 0.0}
    else
      shaped_text
      |> split_text_by_fallback_font(pdf, font_order, primary_font)
      |> Enum.reduce({pdf, x * 1.0, 0.0}, fn {font_name, segment},
                                             {acc_pdf, cursor_x, total_width} ->
        {next_pdf, segment_width} =
          acc_pdf
          |> set_font(font_name, size)
          |> draw_text_segment(
            cursor_x,
            y,
            segment,
            font_name,
            size,
            kerning,
            draw_fun
          )

        next_x = cursor_x + segment_width
        {next_pdf, next_x, total_width + segment_width}
      end)
      |> then(fn {next_pdf, _cursor_x, total_width} ->
        # credo:disable-for-lines:2 Credo.Check.Refactor.Nesting
        restored_pdf =
          if next_pdf.current_font == entry_font do
            next_pdf
          else
            {entry_name, entry_size} = entry_font
            set_font(next_pdf, entry_name, entry_size)
          end

        {restored_pdf, total_width}
      end)
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp draw_text_segment(
         %PDF{} = pdf,
         cursor_x,
         y,
         segment,
         font_name,
         size,
         :gpos,
         draw_fun
       ) do
    graphemes = String.graphemes(segment)

    with true <- length(graphemes) > 1,
         %{ttf_metrics: ttf_metrics} <- Map.get(pdf.embedded_fonts, font_name),
         true <- is_map(ttf_metrics),
         units_per_em when is_integer(units_per_em) and units_per_em > 0 <-
           Map.get(ttf_metrics, :units_per_em),
         gpos_pair_kerns when is_map(gpos_pair_kerns) and map_size(gpos_pair_kerns) > 0 <-
           Map.get(ttf_metrics, :gpos_pair_kerns) do
      {next_pdf, next_x, _prev_codepoint} =
        Enum.reduce(graphemes, {pdf, cursor_x, nil}, fn grapheme,
                                                        {acc_pdf, acc_x, prev_codepoint} ->
          current_codepoint = Context.kerning_codepoint(grapheme)

          kerning_units =
            Context.pair_kerning_units(prev_codepoint, current_codepoint, gpos_pair_kerns)

          draw_x = acc_x + kerning_units * size / units_per_em
          next_pdf = draw_fun.(acc_pdf, draw_x, y, grapheme)
          grapheme_width = text_width_for_font(next_pdf, font_name, size, grapheme)

          # credo:disable-for-lines:2 Credo.Check.Refactor.Nesting
          next_prev_codepoint =
            if is_integer(current_codepoint) and current_codepoint >= 0 do
              current_codepoint
            else
              prev_codepoint
            end

          {next_pdf, draw_x + grapheme_width, next_prev_codepoint}
        end)

      {next_pdf, next_x - cursor_x}
    else
      _other ->
        next_pdf = draw_fun.(pdf, cursor_x, y, segment)
        {next_pdf, text_width_for_font(next_pdf, font_name, size, segment)}
    end
  end

  defp draw_text_segment(
         %PDF{} = pdf,
         cursor_x,
         y,
         segment,
         font_name,
         size,
         _kerning,
         draw_fun
       ) do
    next_pdf = draw_fun.(pdf, cursor_x, y, segment)
    {next_pdf, text_width_for_font(next_pdf, font_name, size, segment)}
  end

  @doc """
  Place text at X/Y coordinates rotated by the given angle in degrees.

  Calling this while a path is open raises `ArgumentError`, as for
  `text_at/4`.
  """
  @spec text_at_rotated(PDF.t(), number(), number(), number(), String.t()) :: PDF.t()
  def text_at_rotated(%PDF{} = pdf, x, y, angle_degrees, text) do
    Ops.refuse_open_path(pdf, "Tincture.text_at_rotated/5", "the text")
    Ops.text_at_rotated(pdf, x, y, angle_degrees, text)
  end

  @doc """
  Draw a stroked line between two points.

  `paint` takes the modes `rectangle/6` describes, `:none` included. Drawn
  with a paint while a path is open, the line paints that path too, as
  `rectangle/6` explains.
  """
  @spec line(PDF.t(), number(), number(), number(), number(), paint()) :: PDF.t()
  def line(%PDF{} = pdf, x1, y1, x2, y2, paint \\ :stroke) do
    Ops.line(pdf, x1, y1, x2, y2, paint)
  end

  @doc """
  Draw a rectangle.

  ## Painting

  `paint` selects how the shape is painted, and defaults to `:stroke`:

    * `:stroke` — outline only
    * `:fill` — filled with the current fill colour
    * `:fill_even_odd` — filled using the even-odd rule
    * `:fill_and_stroke` — both
    * `:none` — emit the path without painting, to be painted by a later
      `fill/1`, `stroke/1` or `clip/1`. Until 0.3.8 the path was ended at
      once, so the later call painted or clipped nothing.

  A PDF path-painting operator also *ends* the path, so a shape can be painted
  once. Calling `fill/1` after a shape that already stroked itself fills
  nothing, because there is no longer a path to fill: it writes no operator
  and warns. Pass `:fill` or `:fill_and_stroke` here instead.

  A shape drawn with a paint while a path is open, after `move_to/3` or a
  shape drawn with `:none`, paints that path too: its rectangle joins the
  current path, as PDF defines it. The same holds for `line/6` and
  `circle/5`.

  ## Examples

      # A filled band across the top of the page.
      pdf
      |> Tincture.set_fill_color({0.06, 0.35, 0.55})
      |> Tincture.rectangle(0, 746, 595, 96, :fill)

  """
  @spec rectangle(PDF.t(), number(), number(), number(), number(), paint()) :: PDF.t()
  def rectangle(%PDF{} = pdf, x, y, width, height, paint \\ :stroke) do
    Ops.rectangle(pdf, x, y, width, height, paint)
  end

  @doc """
  Draw a circle. See `rectangle/6` for the `paint` modes. Drawn with a paint
  while a path is open, the circle paints that path too, as `rectangle/6`
  explains.
  """
  @spec circle(PDF.t(), number(), number(), number(), paint()) :: PDF.t()
  def circle(%PDF{} = pdf, cx, cy, radius, paint \\ :stroke) do
    Ops.circle(pdf, cx, cy, radius, paint)
  end

  @doc """
  Set stroke color using normalized RGB values (0..1).
  """
  @spec set_stroke_color(PDF.t(), {number(), number(), number()}) :: PDF.t()
  def set_stroke_color(%PDF{} = pdf, rgb) do
    Ops.set_stroke_color(pdf, rgb)
  end

  @doc """
  Set fill color using normalized RGB values (0..1).
  """
  @spec set_fill_color(PDF.t(), {number(), number(), number()}) :: PDF.t()
  def set_fill_color(%PDF{} = pdf, rgb) do
    Ops.set_fill_color(pdf, rgb)
  end

  @doc """
  Move current path point to X/Y.
  """
  @spec move_to(PDF.t(), number(), number()) :: PDF.t()
  def move_to(%PDF{} = pdf, x, y) do
    Ops.move_to(pdf, x, y)
  end

  @doc """
  Add a line segment from current path point to X/Y.
  """
  @spec line_to(PDF.t(), number(), number()) :: PDF.t()
  def line_to(%PDF{} = pdf, x, y) do
    Ops.line_to(pdf, x, y)
  end

  @doc """
  Add a cubic Bezier segment to the current path.
  """
  @spec bezier(PDF.t(), number(), number(), number(), number(), number(), number()) :: PDF.t()
  def bezier(%PDF{} = pdf, x1, y1, x2, y2, x3, y3) do
    Ops.bezier(pdf, x1, y1, x2, y2, x3, y3)
  end

  @doc """
  Stroke the current path.

  A path must be open: started with `move_to/3`, continued with `line_to/3` or
  `bezier/7`, or left open by a shape drawn with `paint: :none`. Called with no
  open path - typically after a shape that already painted itself with its
  default `:stroke` - this raises `ArgumentError`, since the operator would be
  invalid and ignored by viewers. Pass the shape's own `paint` argument
  instead.
  """
  @spec stroke(PDF.t()) :: PDF.t()
  def stroke(%PDF{} = pdf) do
    Ops.stroke(pdf)
  end

  @doc """
  Fill the current path.

  A path must be open: started with `move_to/3`, continued with `line_to/3` or
  `bezier/7`, or left open by a shape drawn with `paint: :none`. Called with no
  open path - typically after a shape that already painted itself with its
  default `:stroke` - this raises `ArgumentError`, since the operator would be
  invalid and ignored by viewers. Pass the shape's own `paint` argument
  instead.
  """
  @spec fill(PDF.t()) :: PDF.t()
  def fill(%PDF{} = pdf) do
    Ops.fill(pdf)
  end

  @doc """
  Fill the current path using the even-odd rule.

  A path must be open: started with `move_to/3`, continued with `line_to/3` or
  `bezier/7`, or left open by a shape drawn with `paint: :none`. Called with no
  open path - typically after a shape that already painted itself with its
  default `:stroke` - this raises `ArgumentError`, since the operator would be
  invalid and ignored by viewers. Pass the shape's own `paint` argument
  instead.
  """
  @spec fill_even_odd(PDF.t()) :: PDF.t()
  def fill_even_odd(%PDF{} = pdf) do
    Ops.fill_even_odd(pdf)
  end

  @doc """
  Set the clipping path from the current path.

  A path must be open: started with `move_to/3`, continued with `line_to/3` or
  `bezier/7`, or left open by a shape drawn with `paint: :none`. Called with no
  open path - typically after a shape that already painted itself with its
  default `:stroke` - this raises `ArgumentError`, since the operator would be
  invalid and ignored by viewers. Pass the shape's own `paint` argument
  instead.
  """
  @spec clip(PDF.t()) :: PDF.t()
  def clip(%PDF{} = pdf) do
    Ops.clip(pdf)
  end

  @doc """
  Set the clipping path from the current path using the even-odd rule.

  A path must be open: started with `move_to/3`, continued with `line_to/3` or
  `bezier/7`, or left open by a shape drawn with `paint: :none`. Called with no
  open path - typically after a shape that already painted itself with its
  default `:stroke` - this raises `ArgumentError`, since the operator would be
  invalid and ignored by viewers. Pass the shape's own `paint` argument
  instead.
  """
  @spec clip_even_odd(PDF.t()) :: PDF.t()
  def clip_even_odd(%PDF{} = pdf) do
    Ops.clip_even_odd(pdf)
  end

  @doc """
  Set constant alpha for everything drawn until the graphics state is restored.

  A number sets both fill and stroke alpha; a keyword list sets them
  separately. `1.0` is opaque, `0.0` invisible.

  Alpha is graphics state, not a property of a shape: it applies to everything
  drawn after it. Wrap it in `save_state/1` and `restore_state/1` unless the
  rest of the page is meant to inherit it.

  ## Examples

      # A watermark behind the content.
      pdf
      |> Tincture.save_state()
      |> Tincture.set_alpha(0.12)
      |> Tincture.set_fill_color({0.0, 0.0, 0.0})
      |> Tincture.rectangle(80, 400, 435, 120, :fill)
      |> Tincture.restore_state()

      # A translucent fill with a solid outline.
      pdf |> Tincture.set_alpha(fill: 0.4, stroke: 1.0)

  """
  @spec set_alpha(PDF.t(), number() | keyword()) :: PDF.t()
  def set_alpha(pdf, opacity_or_opts \\ 1.0)

  def set_alpha(%PDF{} = pdf, opacity) when is_number(opacity) do
    Ops.set_alpha(pdf, opacity, opacity)
  end

  def set_alpha(%PDF{} = pdf, opts) when is_list(opts) do
    Ops.set_alpha(pdf, Keyword.get(opts, :fill, 1.0), Keyword.get(opts, :stroke, 1.0))
  end

  @doc """
  Fill a rectangle with a linear gradient.

  `stops` is a list of `{offset, {r, g, b}}`, with offsets ascending from 0.0
  to 1.0 and at least two entries. Two stops interpolate directly; more are
  stitched together, so a multi-stop gradient costs nothing extra to ask for.

  Options:

    * `:direction` — `:vertical` (the default, first stop at the top),
      `:horizontal` (first stop at the left), or an explicit
      `{x0, y0, x1, y1}` axis in page coordinates
    * `:extend` — `{before?, after?}`, whether the end colours continue beyond
      the axis. Defaults to `{true, true}`, which is what makes a gradient
      whose axis is shorter than its rectangle fill the corners rather than
      leave them blank.

  Unlike a shape, this paints immediately and does not use the current fill
  colour — a gradient *is* the paint.

  ## Examples

      # A report cover: deep blue at the top fading to near-black.
      pdf
      |> Tincture.linear_gradient(0, 500, 595, 342, [
        {0.0, {0.05, 0.32, 0.55}},
        {1.0, {0.02, 0.06, 0.12}}
      ])

      # Three stops, left to right.
      pdf
      |> Tincture.linear_gradient(40, 700, 515, 8, [
        {0.0, {0.85, 0.20, 0.30}},
        {0.5, {0.95, 0.70, 0.20}},
        {1.0, {0.20, 0.55, 0.45}}
      ], direction: :horizontal)

  Calling this while a path is open raises `ArgumentError`: the
  gradient would be written inside the path, where PDF does not allow it.
  """
  @spec linear_gradient(
          PDF.t(),
          number(),
          number(),
          number(),
          number(),
          [{number(), {number(), number(), number()}}],
          keyword()
        ) :: PDF.t()
  def linear_gradient(%PDF{} = pdf, x, y, width, height, stops, opts \\ []) do
    Ops.refuse_open_path(pdf, "Tincture.linear_gradient/7", "the gradient")

    coords =
      case Keyword.get(opts, :direction, :vertical) do
        # The first stop reads as the top of the rectangle, which is what a
        # caller means by "vertical" - PDF's y axis points up, so that is the
        # higher coordinate.
        :vertical -> [x, y + height, x, y]
        :horizontal -> [x, y, x + width, y]
        {x0, y0, x1, y1} -> [x0, y0, x1, y1]
        other -> raise ArgumentError, "unknown gradient direction: #{inspect(other)}"
      end

    Ops.shading(pdf, x, y, width, height, %{
      type: :axial,
      coords: coords,
      stops: validate_stops!(stops),
      extend: Keyword.get(opts, :extend, {true, true})
    })
  end

  @doc """
  Fill a rectangle with a radial gradient.

  `stops` works as in `linear_gradient/7`, running from the centre outwards.

  Options:

    * `:center` — `{x, y}`, defaulting to the centre of the rectangle
    * `:radius` — the outer radius, defaulting to half the longer side, so the
      gradient reaches the corners
    * `:inner_radius` — the radius at which the first stop sits, default `0`
    * `:extend` — as in `linear_gradient/7`

  ## Examples

      pdf
      |> Tincture.radial_gradient(180, 480, 240, 240, [
        {0.0, {1.0, 0.95, 0.80}},
        {1.0, {0.85, 0.35, 0.10}}
      ])

  Calling this while a path is open raises `ArgumentError`, as for
  `linear_gradient/7`.
  """
  @spec radial_gradient(
          PDF.t(),
          number(),
          number(),
          number(),
          number(),
          [{number(), {number(), number(), number()}}],
          keyword()
        ) :: PDF.t()
  def radial_gradient(%PDF{} = pdf, x, y, width, height, stops, opts \\ []) do
    Ops.refuse_open_path(pdf, "Tincture.radial_gradient/7", "the gradient")
    {cx, cy} = Keyword.get(opts, :center, {x + width / 2, y + height / 2})
    outer = Keyword.get(opts, :radius, max(width, height) / 2)
    inner = Keyword.get(opts, :inner_radius, 0)

    Ops.shading(pdf, x, y, width, height, %{
      type: :radial,
      coords: [cx, cy, inner, cx, cy, outer],
      stops: validate_stops!(stops),
      extend: Keyword.get(opts, :extend, {true, true})
    })
  end

  # A gradient with one stop is a fill, and one with unordered offsets is a
  # mistake the format will not report: the viewer draws something, just not
  # what was asked for. Both are worth refusing here, where the caller can see
  # which call was wrong.
  # credo:disable-for-next-line /^Elixir\.Credo\.Check\.Refactor\.(ABCSize|CyclomaticComplexity)$/
  defp validate_stops!(stops) when is_list(stops) and length(stops) >= 2 do
    Enum.each(stops, fn
      {offset, {r, g, b}}
      when is_number(offset) and offset >= 0 and offset <= 1 and
             is_number(r) and r >= 0 and r <= 1 and
             is_number(g) and g >= 0 and g <= 1 and
             is_number(b) and b >= 0 and b <= 1 ->
        :ok

      other ->
        raise ArgumentError,
              "each gradient stop must be {offset, {r, g, b}} with every value " <>
                "between 0 and 1, got: #{inspect(other)}"
    end)

    offsets = Enum.map(stops, fn {offset, _colour} -> offset end)

    if offsets != Enum.sort(offsets) do
      raise ArgumentError, "gradient stop offsets must ascend, got: #{inspect(offsets)}"
    end

    stops
  end

  defp validate_stops!(stops) do
    raise ArgumentError, "a gradient needs at least two stops, got: #{inspect(stops)}"
  end

  @doc """
  Set stroke line width.
  """
  @spec set_line_width(PDF.t(), number()) :: PDF.t()
  def set_line_width(%PDF{} = pdf, width) do
    Ops.set_line_width(pdf, width)
  end

  @doc """
  Set line cap style: 0 butt, 1 round, 2 projecting square.
  """
  @spec set_line_cap(PDF.t(), 0 | 1 | 2) :: PDF.t()
  def set_line_cap(%PDF{} = pdf, cap) do
    Ops.set_line_cap(pdf, cap)
  end

  @doc """
  Set line join style: 0 miter, 1 round, 2 bevel.
  """
  @spec set_line_join(PDF.t(), 0 | 1 | 2) :: PDF.t()
  def set_line_join(%PDF{} = pdf, join) do
    Ops.set_line_join(pdf, join)
  end

  @doc """
  Set dash pattern and phase.
  """
  @spec set_dash(PDF.t(), [number()], number()) :: PDF.t()
  def set_dash(%PDF{} = pdf, pattern, phase) do
    Ops.set_dash(pdf, pattern, phase)
  end

  @doc """
  Set miter limit for stroked joins.
  """
  @spec set_miter_limit(PDF.t(), number()) :: PDF.t()
  def set_miter_limit(%PDF{} = pdf, limit) do
    Ops.set_miter_limit(pdf, limit)
  end

  @doc """
  Save graphics state.

  Calling this while a path is open raises `ArgumentError`: `q` cannot
  be written inside a path, which holds only path construction until it is
  painted. Paint the path first.
  """
  @spec save_state(PDF.t()) :: PDF.t()
  def save_state(%PDF{} = pdf) do
    Ops.refuse_open_path(pdf, "Tincture.save_state/1", "the saved graphics state")
    Ops.save_state(pdf)
  end

  @doc """
  Restore graphics state.

  Calling this while a path is open raises `ArgumentError`, as for
  `save_state/1`.
  """
  @spec restore_state(PDF.t()) :: PDF.t()
  def restore_state(%PDF{} = pdf) do
    Ops.refuse_open_path(pdf, "Tincture.restore_state/1", "the restored graphics state")
    Ops.restore_state(pdf)
  end

  @doc """
  Draw a JPEG image at X/Y with the given width and height.

  Calling this while a path is open raises `ArgumentError`: the image
  would be written inside the path, where PDF does not allow it.
  """
  @spec image_jpeg(PDF.t(), number(), number(), number(), number(), Path.t()) :: PDF.t()
  def image_jpeg(%PDF{} = pdf, x, y, width, height, path) do
    Ops.refuse_open_path(pdf, "Tincture.image_jpeg/6", "the image")
    Ops.image_jpeg(pdf, x, y, width, height, path)
  end

  @doc """
  Draw a PNG image at X/Y with the given width and height.

  Calling this while a path is open raises `ArgumentError`, as for
  `image_jpeg/6`.
  """
  @spec image_png(PDF.t(), number(), number(), number(), number(), Path.t()) :: PDF.t()
  def image_png(%PDF{} = pdf, x, y, width, height, path) do
    Ops.refuse_open_path(pdf, "Tincture.image_png/6", "the image")
    Ops.image_png(pdf, x, y, width, height, path)
  end

  @doc """
  Tag a block of content with its logical role, making the document accessible.

  An untagged PDF is a picture of a document: the bytes record where each glyph
  sits and nothing records what it *means*, so a screen reader has no headings
  to navigate by, no table structure, and no reliable reading order. Tagging
  adds that layer — a structure tree in the catalog, and marked content in the
  page linking the drawn operators to it.

  Everything drawn inside `fun` belongs to the element:

      pdf
      |> Tincture.set_language("en-GB")
      |> Tincture.tag(:document, fn pdf ->
        pdf
        |> Tincture.tag(:h1, fn pdf ->
          Tincture.text_at(pdf, 50, 760, "Quarterly report")
        end)
        |> Tincture.tag(:p, fn pdf ->
          Tincture.text_at(pdf, 50, 730, "Revenue rose by nine per cent.")
        end)
      end)

  Nesting is how structure is expressed, so a table is a `:table` containing
  `:tr` containing `:th` and `:td`:

      Tincture.tag(pdf, :table, fn pdf ->
        Tincture.tag(pdf, :tr, fn pdf ->
          pdf
          |> Tincture.tag(:th, [scope: :column], &Tincture.text_at(&1, 50, 700, "Region"))
          |> Tincture.tag(:th, [scope: :column], &Tincture.text_at(&1, 200, 700, "Revenue"))
        end)
      end)

  ## Tags

  Container tags group other elements and wrap no content of their own:
  `:document`, `:part`, `:article`, `:section`, `:div`, `:table`, `:thead`,
  `:tbody`, `:tfoot`, `:tr`, `:list`, `:list_item`, `:toc`, `:index`.

  Content tags bracket what is drawn: `:p`, `:h1` to `:h6`, `:heading`, `:th`,
  `:td`, `:label`, `:list_body`, `:caption`, `:figure`, `:formula`, `:quote`,
  `:block_quote`, `:code`, `:note`, `:reference`, `:span`, `:link`,
  `:toc_item`.

  ## Options

    * `:alt` — alternative text. **Required in practice for `:figure`**: an
      image with no alt text is invisible to a screen reader.
    * `:bbox` — `{left, bottom, right, top}` in points, the rectangle that
      encloses a `:figure`'s visible content, used as given instead of the
      computed one. Normally unnecessary: the box is computed from what the
      figure draws, with text estimated from its font's metric width and
      size. It must be four numbers with `left < right` and `bottom < top`,
      within the page, and only on `:figure`; otherwise `tag/4` raises
      `ArgumentError`.
    * `:actual_text` — the text this content really represents, for when the
      glyphs are not the words (a ligature, a decorative capital).
    * `:lang` — a BCP 47 tag, when this element differs from the document.
    * `:title` — a human-readable title for the element.
    * `:scope` — `:row`, `:column` or `:both`. Only valid on `:th`, and what
      tells a reader which cells a header governs.
    * `:id` — an identifier for the element, registered in the document's
      `/IDTree`. Only `:note` carries one, and one is generated automatically,
      so this is for a caller who needs a stable name to reference from
      outside the document. Must be unique within the document.

  ## What this does and does not give you

  It produces the structure: `/StructTreeRoot`, marked content, the parent
  tree, `/MarkInfo`, `/Lang`, alt text and table scope. That is what assistive
  technology reads.

  Layout attributes are written where the standard calls for them. A figure
  gets the bounding box of what it draws (`/BBox`); one that draws nothing
  raises `ArgumentError` when it closes, unless it is given `:bbox`. A figure
  cannot span pages: changing page while it is open raises. An inline element —
  `:link`, `:note`, `:span`, `:quote`, `:reference`, `:code`, `:figure`,
  `:formula` — placed directly in `:document`, `:part`, `:article`,
  `:section` or `:div` is declared a block (`/Placement /Block`), since that is
  how it is laid out; inside a `:p`, a heading or a cell it stays inline.

  It does not *certify* PDF/UA conformance. That is a validation exercise
  against a checker such as veraPDF or PAC, and it imposes further rules — on
  fonts, colour contrast, and metadata — that a library cannot enforce on your
  behalf. Tag your documents and then verify them.

  Opening a content tag while a path is open raises `ArgumentError`: its
  marked content would begin inside the path, where PDF does not allow it.
  Closing one while a path started inside `fun` is still open raises too: its
  marked content would end inside the path. Paint the path before the tag
  closes. A grouping tag such as `:section` writes no marked content and is
  not refused.
  """
  @spec tag(PDF.t(), atom(), keyword(), (PDF.t() -> PDF.t())) :: PDF.t()
  def tag(pdf, tag, opts \\ [], fun)

  def tag(%PDF{} = pdf, tag, opts, fun)
      when is_atom(tag) and is_list(opts) and is_function(fun, 1) do
    # Refused inside a form XObject before anything else, so a call made
    # there is refused for that. Only a content tag writes marked content
    # (BDC) into the stream.
    PDF.refuse_in_form_xobject!(pdf, "Tincture.tag/4")

    if Structure.content?(tag),
      do: Ops.refuse_open_path(pdf, "Tincture.tag/4", "the marked content")

    pdf
    |> PDF.begin_structure(tag, opts)
    |> fun.()
    |> case do
      %PDF{} = tagged ->
        if Structure.content?(tag),
          do:
            Ops.refuse_closed_over_path(tagged, "Tincture.tag/4 closed tag(:#{tag}, ...)", "tag")

        PDF.end_structure(tagged)

      other ->
        raise ArgumentError,
              "the function passed to tag/4 must return a %Tincture.PDF{}, got: #{inspect(other)}"
    end
  end

  @doc """
  Mark a block of drawing as an artifact: decoration, not meaning.

  Rules, borders, background shading, page furniture — content a sighted reader
  parses as visual structure and a screen reader should skip entirely. In a
  tagged document every operator must be either tagged or marked as an
  artifact; anything that is neither is read out as stray noise, and breaks
  PDF/UA-1 (veraPDF rule 7.1-3).

      pdf
      |> Tincture.artifact(fn pdf ->
        pdf
        |> Tincture.set_stroke_color({0.85, 0.86, 0.88})
        |> Tincture.line(50, 700, 545, 700)
      end)

  `Tincture.Layout.Table.render/6` does this for its own borders when it is
  tagging.

  Calling this while a path is open raises `ArgumentError`: its marked
  content would begin inside the path, where PDF does not allow it. Returning
  from `fun` while a path started inside it is still open raises too: its
  marked content would end inside the path. Paint the path before the artifact
  closes.
  """
  @spec artifact(PDF.t(), (PDF.t() -> PDF.t())) :: PDF.t()
  def artifact(%PDF{} = pdf, fun) when is_function(fun, 1) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.artifact/2")
    Ops.refuse_open_path(pdf, "Tincture.artifact/2", "the marked content")

    pdf
    |> PDF.begin_artifact()
    |> fun.()
    |> case do
      %PDF{} = marked ->
        Ops.refuse_closed_over_path(marked, "Tincture.artifact/2 closed", "artifact")
        PDF.end_artifact(marked)

      other ->
        raise ArgumentError,
              "the function passed to artifact/2 must return a %Tincture.PDF{}, " <>
                "got: #{inspect(other)}"
    end
  end

  @doc """
  Define a form XObject: content drawn once and placed any number of times.

  `fun` receives the document and draws the XObject's content with the usual
  functions. Nothing is drawn on the page; place the XObject with
  `place_form_xobject/5`. It is written once, as one object, however many
  times it is placed, and on however many pages.

      pdf
      |> Tincture.form_xobject(:stamp, 200, 40, fn pdf ->
        pdf
        |> Tincture.set_font("Helvetica", 10)
        |> Tincture.text_at(4, 14, "APPROVED")
        |> Tincture.rectangle(0.5, 0.5, 199, 39, :stroke)
      end)
      |> Tincture.place_form_xobject(:stamp, 72, 600)
      |> Tincture.place_form_xobject(:stamp, 72, 300, scale: 0.5)

  ## Name and size

  The name is an atom or a non-empty string; `:stamp` and `"stamp"` are the
  same name. Defining a name twice raises `ArgumentError`. The XObject's
  coordinate space is `width` by `height`, with its origin at the bottom left,
  as on a page, and nothing outside it is drawn.

  ## Inside the callback

  Drawing starts afresh: the XObject's content does not depend on anything
  drawn or set on the page before the call, and the font starts as Helvetica
  12, whatever font the page had set. When the callback returns, the page's
  font is restored, and drawing continues on the page exactly as if the call
  had not been made.

  Only drawing is allowed inside the callback: shapes and paths, colours and
  other graphics state, text, images, `set_font/3`, and registering fonts.
  Everything else raises `ArgumentError`, because a form XObject is a content
  stream with no page, structure or annotations of its own: adding or
  changing pages, `tag/4` and `artifact/2`, links, form fields, signing,
  bookmarks, document settings such as `set_metadata/2` or `encrypt/2`,
  `export/2` and `save/3`, and defining or placing another form XObject. In a
  tagged document that includes `Tincture.Layout.Box` and
  `Tincture.Layout.Table`, which tag what they draw.

  The callback must leave every `save_state/1` restored and no path open;
  otherwise it raises `ArgumentError`.

  ## What a placement inherits

  A form XObject is drawn with whatever graphics state is in effect where it
  is placed, except for what it sets itself. Its position and scale come from
  the placement, and the page's clipping applies to it. An XObject that sets
  no colour draws in the colour current where it is placed, and one that sets
  no line width strokes with the line width current there. Nothing it sets
  carries over to the page after it.

  ## In a tagged document

  A placement is content like any other drawing. For PDF/UA it belongs inside
  a content tag or an `artifact/2` block, as an image does; Tincture does not
  check this, and a validator does. Since the callback cannot open a tag, an
  XObject carries no structure of its own and may be placed inside any number
  of structure elements.
  """
  @spec form_xobject(PDF.t(), atom() | String.t(), number(), number(), (PDF.t() -> PDF.t())) ::
          PDF.t()
  def form_xobject(%PDF{} = pdf, name, width, height, fun)
      when is_number(width) and width > 0 and is_number(height) and height > 0 and
             is_function(fun, 1) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.form_xobject/5")
    {begun, caller_font} = PDF.begin_form_xobject(pdf, name, width, height)

    case fun.(begun) do
      %PDF{} = drawn ->
        PDF.end_form_xobject(drawn, caller_font)

      other ->
        raise ArgumentError,
              "the function passed to form_xobject/5 must return a %Tincture.PDF{}, " <>
                "got: #{inspect(other)}"
    end
  end

  @doc """
  Place a form XObject on the current page, with its origin at X/Y and at its
  own size.

  See `place_form_xobject/5`.
  """
  @spec place_form_xobject(PDF.t(), atom() | String.t(), number(), number()) :: PDF.t()
  def place_form_xobject(%PDF{} = pdf, name, x, y) when is_number(x) and is_number(y) do
    PDF.place_form_xobject(pdf, name, x, y, [], "Tincture.place_form_xobject/4")
  end

  @doc """
  Place a form XObject defined with `form_xobject/5` on the current page, with
  its origin at X/Y.

  ## Options

    * `:scale` — a positive number scaling both directions. Defaults to 1.
    * `:width` — the width to draw it at. Alone, it scales both directions
      alike, keeping the XObject's proportions.
    * `:height` — the height to draw it at. Alone, it scales both directions
      alike.

  Given `:width` and `:height` together, the XObject is stretched to both, as
  an image is. `:scale` cannot be combined with either.

  The name must already be defined. A placement cannot be made while a path
  is being built: paint the path first. Inside a `tag/4` scope, the placement
  belongs to that structure element.
  """
  @spec place_form_xobject(PDF.t(), atom() | String.t(), number(), number(), keyword()) ::
          PDF.t()
  def place_form_xobject(%PDF{} = pdf, name, x, y, opts)
      when is_number(x) and is_number(y) and is_list(opts) do
    PDF.place_form_xobject(pdf, name, x, y, opts, "Tincture.place_form_xobject/5")
  end

  @doc """
  Set the document's natural language, as a BCP 47 tag such as `"en-GB"`.

  Without it a screen reader has to guess which language to pronounce the text
  as, so this is a requirement for an accessible document rather than a nicety.
  """
  @spec set_language(PDF.t(), String.t()) :: PDF.t()
  def set_language(%PDF{} = pdf, language) do
    PDF.set_language(pdf, language)
  end

  @doc """
  Sign a signature field, so the document can be shown not to have changed.

  Place the field first with `signature_field/7`, then sign it:

      pdf
      |> Tincture.signature_field(50, 120, 220, 48, "signature")
      |> Tincture.sign("signature",
        private_key: key,
        certificate: certificate,
        reason: "I approve this document",
        location: "Sheffield"
      )

  Unlike everything else in Tincture, this cannot take effect until the file
  exists: a signature covers the finished bytes, including where every object
  landed. So it is applied during `export/2` — the document merely records the
  intent. See `Tincture.PDF.Sign` for how that works.

  ## Options

    * `:private_key` — required. A decoded key, as
      `:public_key.pem_entry_decode/1` returns.
    * `:certificate` — required. The signer's certificate, in DER.
    * `:chain` — intermediate certificates in DER, for a verifier that does not
      already hold them. Defaults to `[]`.
    * `:digest` — `:sha256` (default), `:sha384` or `:sha512`.
    * `:signing_time` — a `DateTime`. Defaults to now. Pass one explicitly to
      make output reproducible.
    * `:name`, `:reason`, `:location`, `:contact` — shown by the reader.
    * `:reserved_bytes` — space set aside for the signature. Defaults to 16 kB,
      enough for RSA-4096 with a chain. Export raises rather than truncates if
      the signature does not fit.

  ## Reading a key and certificate

      [key_entry] = :public_key.pem_decode(File.read!("key.pem"))
      key = :public_key.pem_entry_decode(key_entry)

      [{:Certificate, certificate, _}] = :public_key.pem_decode(File.read!("cert.pem"))

  ## What a signature here does and does not prove

  It proves the document has not changed since it was signed, and who signed it
  — as far as the certificate can be trusted. It does **not** prove *when*:
  there is no timestamp authority, so the time is the signing machine's own
  claim. Long-term validation needs an RFC 3161 timestamp, which Tincture does
  not yet produce.

  Signing one document twice, or signing after changing it, needs incremental
  updates, which Tincture also does not yet produce — so one signature per
  document.

  An encrypted document cannot be signed. Calling this on a document that
  `encrypt/2` has been called on raises `ArgumentError`, and so does calling
  `encrypt/2` on a signed document.
  """
  @spec sign(PDF.t(), String.t(), keyword()) :: PDF.t()
  def sign(%PDF{} = pdf, field_name, opts) when is_binary(field_name) and is_list(opts) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.sign/3")
    PDF.refuse_signing_encrypted!(pdf, "Tincture.sign/3")
    PDF.set_signature(pdf, field_name, opts)
  end

  @doc """
  Declare a PDF/A conformance level, for a document that has to outlive its
  software.

  PDF/A (ISO 19005) is what records-retention policies specify. It is mostly a
  set of constraints rather than new capability, and this adds the three things
  a document cannot be valid without: an sRGB output intent, so device colour
  has a defined meaning; XMP metadata carrying the conformance claim; and a
  file identifier.

      pdf
      |> Tincture.set_pdf_a(:a2b)
      |> Tincture.set_metadata(title: "Annual report 2026")

  ## Levels

    * `:a2b` — basic. Visual reproduction is preserved.
    * `:a2u` — as `:a2b`, and all text has a Unicode mapping, so it can be
      extracted and searched.
    * `:a2a` — as `:a2u`, and the document is tagged. Combine with
      `tag/4` and `set_language/2`.

  `:a3b`, `:a3u` and `:a3a` select part 3, which differs only in permitting
  arbitrary embedded files.

  ## What `export/2` refuses

  A declared level is checked when the document is exported. `export/2` raises
  on a document that breaks a PDF/A rule Tincture can see, naming the clause,
  unless it is given `enforce: false`. It refuses:

    * a font that is not embedded, so the standard 14 are not usable, since
      they are referenced by name rather than embedded;
    * encryption;
    * text and choice fields, signature fields and push buttons;
    * at `:a2a` and `:a3a`, a document that is not tagged.

  `pdf_a_violations/1` lists the same violations without exporting. See
  `Tincture.PDF.Archival`.

  That check is not a conformance check. Tincture sees the document it built,
  not the file a validator sees, so passing it means only that nothing Tincture
  knows of is wrong. Validate the result. `veraPDF` is free:

      verapdf --flavour 2b out.pdf

  ## Colour

  The output intent is sRGB, built into the library rather than read from the
  system, so a document is reproducible anywhere. Any RGB colour you set is
  therefore interpreted as sRGB. CMYK is not covered by this output intent and
  would need its own.
  """
  @spec set_pdf_a(PDF.t(), atom()) :: PDF.t()
  def set_pdf_a(%PDF{} = pdf, level) when is_atom(level) do
    PDF.set_pdf_a(pdf, level)
  end

  @doc """
  Whether the document carries logical structure.
  """
  @spec tagged?(PDF.t()) :: boolean()
  def tagged?(%PDF{} = pdf), do: PDF.tagged?(pdf)

  @doc """
  Export a PDF struct to a binary.

  ## Options

    * `:enforce` — whether to refuse a document that breaks a conformance it
      claims: a PDF/A level declared with `set_pdf_a/2`, or the PDF/UA
      structure a tagged document claims. Defaults to `true`. A document that
      declares no level and is not tagged is not checked.

  A conformance claim is written into the file's metadata, so exporting a
  document that declares PDF/A and violates it produces a file that lies about
  itself — and nothing discovers that until someone tries to rely on it. Rather
  than emit one, this raises and names what is wrong.

  Pass `enforce: false` to export anyway. The claim stays in the file, so the
  result asserts a conformance it does not have; the violations are logged as a
  warning. It exists for iterating, not for shipping.

      Tincture.export(pdf)                   # refuses a false claim
      Tincture.export(pdf, enforce: false)   # exports it, and says so

  See `pdf_a_violations/1` and `pdf_ua_violations/1` to inspect without
  exporting.

  ## Form fields in a tagged document

  In a tagged document, export warns for each form field with no `:tooltip`,
  and for each form field created outside every `tag/4` scope. The document
  still exports, unchanged. 0.4.0 refuses both, following `:enforce` like the
  other PDF/UA checks. See `text_field/7`.

  ## Signed and encrypted

  A document cannot be both signed and encrypted. `sign/3` and `encrypt/2`
  each refuse the combination when called; a document that carries both
  anyway, because its fields were set directly, raises `ArgumentError` here.

  ## A path left open

  A path open on the current page that nothing has painted raises
  `ArgumentError`, whatever `:enforce` says: it is invalid content, not a
  conformance claim.
  """
  @spec export(PDF.t(), keyword()) :: binary()
  def export(%PDF{} = pdf, opts) when is_list(opts) do
    export(pdf, opts, "Tincture.export/2")
  end

  @doc """
  Export a PDF struct to a binary with the default options: `export(pdf, [])`.

  See `export/2`.
  """
  @spec export(PDF.t()) :: binary()
  def export(%PDF{} = pdf), do: export(pdf, [], "Tincture.export/1")

  defp export(%PDF{} = pdf, opts, caller) do
    PDF.refuse_in_form_xobject!(pdf, caller)
    refuse_signed_and_encrypted!(pdf, caller)
    enforce? = Keyword.get(opts, :enforce, true)

    # Warnings for what 0.4.0 refuses in a tagged form; they do not change
    # what is exported.
    Accessibility.warn_form_deprecations(pdf)

    # A path nothing painted on the current page is refused; a page left with
    # one was refused when it was left. No enforce: escape - it is invalid
    # content, not a conformance claim.
    Ops.refuse_unpainted_path(pdf, caller)

    pdf
    |> check_archival(enforce?)
    |> check_accessibility(enforce?)
    |> Serialize.export()
  end

  # sign/3 and encrypt/2 refuse the combination, but the struct's fields can
  # still be set directly. Without this, export would fail inside the signer,
  # unable to find the reserved space the encryptor had encrypted.
  defp refuse_signed_and_encrypted!(%PDF{signature: signature, encryption: encryption}, caller)
       when signature != nil and encryption != nil do
    raise ArgumentError,
          "#{caller} was given a document that is both signed and encrypted. Tincture " <>
            "cannot sign an encrypted document: sign it without encryption, or encrypt " <>
            "it without a signature."
  end

  defp refuse_signed_and_encrypted!(%PDF{}, _caller), do: :ok

  defp check_archival(%PDF{} = pdf, enforce?) do
    case {enforce?, Archival.violations(pdf)} do
      {_enforce, []} ->
        pdf

      {false, violations} ->
        Logger.warning(
          "exporting a document that claims PDF/A and does not conform, because " <>
            "enforce: false was given. The file asserts a conformance it does not have:\n" <>
            Archival.describe(violations)
        )

        pdf

      {true, violations} ->
        {part, conformance} = pdf.pdf_a
        level = "#{part}#{conformance |> Atom.to_string() |> String.upcase()}"

        raise ArgumentError,
              "this document declares PDF/A-#{level} but does not conform:\n" <>
                Archival.describe(violations) <>
                "\n\nExporting would write a conformance claim into a file that does not " <>
                "meet it. Fix the above, drop set_pdf_a/2, or pass enforce: false to " <>
                "export regardless."
    end
  end

  defp check_accessibility(%PDF{} = pdf, enforce?) do
    case {enforce?, Accessibility.violations(pdf)} do
      {_enforce, []} ->
        pdf

      {false, violations} ->
        Logger.warning(
          "exporting a tagged document that does not meet PDF/UA, because enforce: false " <>
            "was given. Assistive technology will find structure it cannot describe:\n" <>
            Accessibility.describe(violations)
        )

        pdf

      {true, violations} ->
        raise ArgumentError,
              "this document is tagged, which claims PDF/UA structure, but does not " <>
                "meet it:\n" <>
                Accessibility.describe(violations) <>
                "\n\nA reader announces an element it cannot describe, which is worse than " <>
                "no tag at all. Fix the above or pass enforce: false to export regardless."
    end
  end

  @doc """
  Every PDF/A violation Tincture can detect in this document.

  Empty for a document that declares no level. **Not a conformance check** —
  Tincture sees the document it built, not the file a validator sees, and
  PDF/A has requirements no library can settle for you. Validate the output
  with `verapdf --flavour 2b`.
  """
  @spec pdf_a_violations(PDF.t()) :: [Archival.violation()]
  def pdf_a_violations(%PDF{} = pdf), do: Archival.violations(pdf)

  @doc """
  Every PDF/UA violation Tincture can detect in this document.

  Empty for an untagged document, since nothing is being claimed. **Not a
  conformance check** — whether a heading level is the right one, or an
  alternative text accurate rather than merely present, is not something a
  library can settle. Validate with `verapdf --flavour ua1`, and with PAC,
  which applies checks veraPDF does not.
  """
  @spec pdf_ua_violations(PDF.t()) :: [Accessibility.violation()]
  def pdf_ua_violations(%PDF{} = pdf), do: Accessibility.violations(pdf)

  @doc """
  Export and write a PDF to disk.

  Takes the same options as `export/2`.
  """
  @spec save(PDF.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def save(%PDF{} = pdf, path, opts \\ []) when is_binary(path) and is_list(opts) do
    PDF.refuse_in_form_xobject!(pdf, "Tincture.save/3")

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, export(pdf, opts))
    end
  end

  @doc """
  Render a laid-out paragraph of rich text at X/Y origin using typography layout.

  Calling this while a path is open raises `ArgumentError`, as for
  `text_at/4`.
  """
  @spec text_paragraph(PDF.t(), number(), number(), rich_text(), number(), [paragraph_option()]) ::
          PDF.t()
  # credo:disable-for-next-line /^Elixir\.Credo\.Check\.Refactor\.(ABCSize|CyclomaticComplexity)$/
  def text_paragraph(%PDF{} = pdf, x, y, %RichText{} = rich_text, max_width, opts \\ [])
      when is_number(x) and is_number(y) and is_number(max_width) and max_width > 0 and
             is_list(opts) do
    Ops.refuse_open_path(pdf, "Tincture.text_paragraph/6", "the text")
    rotate = Keyword.get(opts, :rotate)
    fallback_fonts = Keyword.get(opts, :fallback_fonts, [])
    bidi = Keyword.get(opts, :bidi, :off)
    shaping = Keyword.get(opts, :shaping, :off)
    kerning = Keyword.get(opts, :kerning, :off)

    if not is_nil(rotate) and not is_number(rotate) do
      raise ArgumentError, "rotate option must be a number of degrees"
    end

    if not is_list(fallback_fonts) do
      raise ArgumentError, "fallback_fonts option must be a list"
    end

    bidi = normalize_bidi_option(bidi)
    shaping = normalize_shaping_option(shaping)
    kerning = normalize_kerning_option(kerning)

    layout_opts = Keyword.drop(opts, [:rotate, :fallback_fonts, :bidi, :shaping, :kerning])

    # Token widths are baked in at construction, where an embedded font cannot
    # be resolved - its metrics live on this document. Re-measure before layout.
    rich_text = RichText.remeasure(rich_text, Context.from_pdf(pdf))

    Typography.layout_paragraph(rich_text, max_width, layout_opts)
    |> Enum.reduce(pdf, fn %Line{} = line, acc_pdf ->
      render_line(
        acc_pdf,
        x + line.x,
        y + line.y,
        line.tokens,
        rotate,
        fallback_fonts,
        bidi,
        shaping,
        kerning
      )
    end)
  end

  defp render_line(pdf, start_x, line_y, tokens, rotate, fallback_fonts, bidi, shaping, kerning) do
    visual_tokens = bidi_visual_tokens(tokens, bidi)

    {pdf, _cursor_x} =
      Enum.reduce(visual_tokens, {pdf, start_x * 1.0}, fn token, {acc_pdf, cursor_x} ->
        render_token(
          token,
          acc_pdf,
          cursor_x,
          line_y * 1.0,
          rotate,
          fallback_fonts,
          shaping,
          kerning
        )
      end)

    pdf
  end

  defp render_token(
         %Word{} = word,
         pdf,
         cursor_x,
         line_y,
         rotate,
         fallback_fonts,
         shaping,
         kerning
       ) do
    {next_pdf, rendered_width} =
      pdf
      |> set_font(word.font, word.size)
      |> then(fn doc ->
        case rotate do
          degrees when is_number(degrees) ->
            draw_text_with_fallback(
              doc,
              cursor_x,
              line_y,
              word.text,
              fallback_fonts,
              shaping,
              kerning,
              fn draw_doc, draw_x, draw_y, segment ->
                Ops.text_at_rotated(draw_doc, draw_x, draw_y, degrees, segment)
              end
            )

          _ ->
            draw_text_with_fallback(
              doc,
              cursor_x,
              line_y,
              word.text,
              fallback_fonts,
              shaping,
              kerning,
              # credo:disable-for-next-line Credo.Check.Refactor.Nesting
              fn draw_doc, draw_x, draw_y, segment ->
                Ops.text_at(draw_doc, draw_x, draw_y, segment)
              end
            )
        end
      end)

    {next_pdf, cursor_x + rendered_width}
  end

  defp render_token(
         %Space{} = space,
         pdf,
         cursor_x,
         _line_y,
         _rotate,
         _fallback_fonts,
         _shaping,
         _kerning
       ) do
    {pdf, cursor_x + space.width}
  end

  defp render_token(
         %Break{},
         pdf,
         cursor_x,
         _line_y,
         _rotate,
         _fallback_fonts,
         _shaping,
         _kerning
       ) do
    {pdf, cursor_x}
  end

  defp normalize_bidi_option(:off), do: :off
  defp normalize_bidi_option(:basic), do: :basic

  defp normalize_bidi_option(_other),
    do: raise(ArgumentError, "bidi option must be :off or :basic")

  defp normalize_shaping_option(:off), do: :off
  defp normalize_shaping_option(:latin_ligatures), do: :latin_ligatures
  defp normalize_shaping_option(:gsub_ligatures), do: :gsub_ligatures

  defp normalize_shaping_option(_other),
    do:
      raise(
        ArgumentError,
        "shaping option must be :off, :latin_ligatures, or :gsub_ligatures"
      )

  defp normalize_kerning_option(:off), do: :off
  defp normalize_kerning_option(:gpos), do: :gpos

  defp normalize_kerning_option(_other),
    do: raise(ArgumentError, "kerning option must be :off or :gpos")

  defp bidi_visual_tokens(tokens, :off), do: tokens

  defp bidi_visual_tokens(tokens, :basic) do
    entries =
      tokens
      |> Enum.map(fn token -> %{token: token, dir: token_direction(token)} end)

    base_dir = first_strong_dir(entries) || :ltr
    resolved = resolve_neutral_token_dirs(entries, base_dir)
    runs = chunk_by_dir(resolved)

    runs =
      case base_dir do
        :rtl -> Enum.reverse(runs)
        _ -> runs
      end

    Enum.flat_map(runs, fn
      {:rtl, run_entries} ->
        run_entries
        |> Enum.reverse()
        |> Enum.map(&reverse_rtl_token_text(&1.token))

      {_dir, run_entries} ->
        Enum.map(run_entries, & &1.token)
    end)
  end

  defp token_direction(%Word{text: text}), do: word_direction(text)
  defp token_direction(%Space{}), do: :neutral
  defp token_direction(%Break{}), do: :neutral

  defp word_direction(text) when is_binary(text) do
    text
    |> String.to_charlist()
    |> Enum.find_value(:neutral, fn codepoint ->
      cond do
        rtl_codepoint?(codepoint) -> :rtl
        ltr_codepoint?(codepoint) -> :ltr
        true -> nil
      end
    end)
  end

  defp rtl_codepoint?(cp) do
    (cp >= 0x0590 and cp <= 0x08FF) or (cp >= 0xFB1D and cp <= 0xFEFC)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp ltr_codepoint?(cp) do
    (cp >= ?A and cp <= ?Z) or (cp >= ?a and cp <= ?z) or (cp >= ?0 and cp <= ?9) or
      (cp >= 0x00C0 and cp <= 0x02AF)
  end

  defp first_strong_dir(entries), do: Enum.find_value(entries, &strong_dir/1)

  defp strong_dir(%{dir: dir}) when dir in [:ltr, :rtl], do: dir
  defp strong_dir(_entry), do: nil

  # A neutral takes the nearest strong direction before it, then after it, then
  # the paragraph's. Both neighbours come from one pass each way rather than a
  # scan per neutral, which was quadratic in the token count.
  defp resolve_neutral_token_dirs(entries, base_dir) do
    prev_dirs = nearest_strong_dirs(entries)
    next_dirs = entries |> Enum.reverse() |> nearest_strong_dirs() |> Enum.reverse()

    [entries, prev_dirs, next_dirs]
    |> Enum.zip_with(fn
      [%{dir: :neutral} = entry, prev, next] -> %{entry | dir: prev || next || base_dir}
      [entry, _prev, _next] -> entry
    end)
  end

  # For each entry, the last strong direction seen strictly before it.
  defp nearest_strong_dirs(entries) do
    {dirs, _last} =
      Enum.map_reduce(entries, nil, fn entry, last ->
        {last, strong_dir(entry) || last}
      end)

    dirs
  end

  defp chunk_by_dir([]), do: []

  defp chunk_by_dir([first | rest]) do
    {runs_reversed, current_dir, current_entries} =
      Enum.reduce(rest, {[], first.dir, [first]}, fn entry, {runs_acc, dir, entries_acc} ->
        if entry.dir == dir do
          {runs_acc, dir, [entry | entries_acc]}
        else
          {[{dir, Enum.reverse(entries_acc)} | runs_acc], entry.dir, [entry]}
        end
      end)

    Enum.reverse([{current_dir, Enum.reverse(current_entries)} | runs_reversed])
  end

  defp reverse_rtl_token_text(%Word{text: text} = word) do
    %Word{word | text: reverse_graphemes(text)}
  end

  defp reverse_rtl_token_text(token), do: token

  defp reverse_graphemes(text) do
    text
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.join()
  end

  defp shape_text_for_fonts(text, :off, _pdf, _font_order), do: text

  defp shape_text_for_fonts(text, shaping_mode, pdf, font_order)
       when shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    Enum.reduce(
      ordered_ligature_replacements(pdf, font_order, shaping_mode),
      text,
      fn {source, target}, acc ->
        target_codepoint =
          target
          |> String.to_charlist()
          |> hd()

        source_length = source |> String.graphemes() |> length()

        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        if Enum.any?(font_order, fn font_name ->
             font_supports_ligature_replacement?(
               pdf,
               font_name,
               source,
               target,
               target_codepoint,
               source_length,
               shaping_mode
             )
           end) do
          String.replace(acc, source, target)
        else
          acc
        end
      end
    )
  end

  defp ordered_ligature_replacements(%PDF{} = pdf, font_order, shaping_mode)
       when is_list(font_order) and shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    gsub_ligature_replacements =
      font_order
      |> Enum.reduce([], fn font_name, acc ->
        acc ++ font_gsub_ligature_replacements(pdf, font_name, shaping_mode)
      end)
      |> Enum.uniq()

    defaults =
      latin_ligature_replacements()
      |> Enum.reject(fn replacement -> Enum.member?(gsub_ligature_replacements, replacement) end)

    (gsub_ligature_replacements ++ defaults)
    |> Enum.sort_by(fn {source, _target} -> {-String.length(source), source} end)
  end

  defp font_gsub_ligature_replacements(%PDF{} = pdf, font_name, shaping_mode)
       when shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: ttf_metrics} when is_map(ttf_metrics) ->
        gsub_ligatures = font_gsub_ligature_map(ttf_metrics, shaping_mode)

        gsub_ligatures
        |> Enum.filter(fn {source, target} ->
          is_binary(source) and byte_size(source) > 0 and is_binary(target) and
            byte_size(target) > 0
        end)
        |> Enum.map(fn {source, target} -> {source, target} end)

      _ ->
        []
    end
  end

  defp font_gsub_ligature_map(ttf_metrics, :latin_ligatures) when is_map(ttf_metrics) do
    case Map.get(ttf_metrics, :gsub_ligatures) do
      gsub_ligatures when is_map(gsub_ligatures) -> gsub_ligatures
      _other -> %{}
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp font_gsub_ligature_map(ttf_metrics, :gsub_ligatures) when is_map(ttf_metrics) do
    case Map.get(ttf_metrics, :gsub_substitutions_all) do
      gsub_substitutions_all
      when is_map(gsub_substitutions_all) and map_size(gsub_substitutions_all) > 0 ->
        gsub_substitutions_all

      _other ->
        case Map.get(ttf_metrics, :gsub_ligatures_all) do
          gsub_ligatures_all when is_map(gsub_ligatures_all) ->
            gsub_ligatures_all

          _other ->
            # credo:disable-for-next-line Credo.Check.Refactor.Nesting
            case Map.get(ttf_metrics, :gsub_ligatures) do
              gsub_ligatures when is_map(gsub_ligatures) -> gsub_ligatures
              _other -> %{}
            end
        end
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp font_supports_ligature_replacement?(
         %PDF{} = pdf,
         font_name,
         source,
         target,
         target_codepoint,
         source_length,
         shaping_mode
       )
       when is_binary(source) and byte_size(source) > 0 and is_binary(target) and
              byte_size(target) > 0 and is_integer(target_codepoint) and target_codepoint >= 0 and
              is_integer(source_length) and source_length >= 1 and
              shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    font_supports_codepoint?(pdf, font_name, target_codepoint) and
      ligature_mapping_supported?(pdf, font_name, source, target, shaping_mode) and
      ligature_feature_supported?(pdf, font_name, shaping_mode) and
      ligature_context_length_allowed?(pdf, font_name, source_length)
  end

  defp ligature_mapping_supported?(%PDF{} = pdf, font_name, source, target, shaping_mode)
       when shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: ttf_metrics} when is_map(ttf_metrics) ->
        gsub_ligatures = font_gsub_ligature_map(ttf_metrics, shaping_mode)

        if map_size(gsub_ligatures) > 0 do
          Map.get(gsub_ligatures, source) == target
        else
          Enum.member?(latin_ligature_replacements(), {source, target})
        end

      _ ->
        Enum.member?(latin_ligature_replacements(), {source, target})
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp ligature_feature_supported?(%PDF{} = pdf, font_name, shaping_mode)
       when shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: %{gsub_features: gsub_features, gsub_scripts: gsub_scripts}}
      when is_list(gsub_features) and is_list(gsub_scripts) ->
        feature_ok? =
          case shaping_mode do
            :latin_ligatures ->
              gsub_features == [] or Enum.member?(gsub_features, "liga")

            :gsub_ligatures ->
              gsub_features == [] or
                Enum.any?(["liga", "rlig", "ccmp"], &Enum.member?(gsub_features, &1))
          end

        script_ok? = ligature_script_supported?(gsub_scripts, shaping_mode)
        feature_ok? and script_ok?

      _ ->
        true
    end
  end

  defp ligature_script_supported?(gsub_scripts, :latin_ligatures) when is_list(gsub_scripts),
    do: gsub_scripts == [] or Enum.member?(gsub_scripts, "latn")

  defp ligature_script_supported?(_gsub_scripts, :gsub_ligatures), do: true

  defp ligature_context_length_allowed?(%PDF{} = pdf, font_name, source_length)
       when is_integer(source_length) and source_length >= 1 do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: %{os2_max_context: max_context}}
      when is_integer(max_context) and max_context > 0 ->
        source_length <= max_context

      _ ->
        true
    end
  end

  defp latin_ligature_replacements do
    [
      {"ffl", "ﬄ"},
      {"ffi", "ﬃ"},
      {"ff", "ﬀ"},
      {"fi", "ﬁ"},
      {"fl", "ﬂ"}
    ]
  end

  defp normalize_fallback_fonts(%PDF{} = pdf, fallback_fonts, primary_font) do
    fallback_fonts
    |> Enum.map(fn font_name ->
      if is_binary(font_name) and byte_size(font_name) > 0 do
        font_name
      else
        raise ArgumentError, "fallback fonts must be non-empty font-name strings"
      end
    end)
    |> Enum.reject(&(&1 == primary_font))
    |> Enum.uniq()
    |> Enum.map(fn font_name ->
      if font_available_in_pdf?(pdf, font_name) do
        font_name
      else
        raise ArgumentError, "unknown font: #{font_name}"
      end
    end)
  end

  defp append_segment([], font_name, segment), do: [{font_name, segment}]

  defp append_segment([{font_name, text} | rest], font_name, segment),
    do: [{font_name, text <> segment} | rest]

  defp append_segment(segments, font_name, segment), do: [{font_name, segment} | segments]

  defp split_text_by_fallback_font(text, pdf, font_order, primary_font) do
    text
    |> String.graphemes()
    |> Enum.reduce([], fn grapheme, acc ->
      selected_font = select_fallback_font_for_grapheme(pdf, font_order, primary_font, grapheme)
      append_segment(acc, selected_font, grapheme)
    end)
    |> Enum.reverse()
  end

  defp select_fallback_font_for_grapheme(%PDF{} = pdf, font_order, primary_font, grapheme) do
    case String.to_charlist(grapheme) do
      [base_codepoint, selector_codepoint] ->
        if Unicode.variation_selector_codepoint?(selector_codepoint) do
          Enum.find(font_order, fn font_name ->
            font_has_non_default_variation?(pdf, font_name, base_codepoint, selector_codepoint)
          end) ||
            Enum.find(font_order, primary_font, fn font_name ->
              font_supports_variation_grapheme?(
                pdf,
                font_name,
                base_codepoint,
                selector_codepoint
              )
            end)
        else
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          Enum.find(font_order, primary_font, fn font_name ->
            font_supports_grapheme_codepoints?(pdf, font_name, [
              base_codepoint,
              selector_codepoint
            ])
          end)
        end

      codepoints ->
        Enum.find(font_order, primary_font, fn font_name ->
          font_supports_grapheme_codepoints?(pdf, font_name, codepoints)
        end)
    end
  end

  defp font_supports_variation_grapheme?(
         %PDF{} = pdf,
         font_name,
         base_codepoint,
         selector_codepoint
       )
       when is_integer(base_codepoint) and is_integer(selector_codepoint) do
    font_has_non_default_variation?(pdf, font_name, base_codepoint, selector_codepoint) or
      font_supports_codepoint?(pdf, font_name, base_codepoint)
  end

  defp font_supports_grapheme_codepoints?(%PDF{} = pdf, font_name, codepoints)
       when is_list(codepoints) do
    Enum.all?(codepoints, fn codepoint ->
      Unicode.zero_advance_codepoint?(codepoint) or
        font_supports_codepoint?(pdf, font_name, codepoint)
    end)
  end

  defp font_has_non_default_variation?(
         %PDF{} = pdf,
         font_name,
         base_codepoint,
         selector_codepoint
       )
       when is_integer(base_codepoint) and is_integer(selector_codepoint) do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: %{cmap_non_default_uvs: cmap_non_default_uvs}}
      when is_map(cmap_non_default_uvs) ->
        Map.has_key?(cmap_non_default_uvs, {base_codepoint, selector_codepoint})

      _ ->
        false
    end
  end

  defp font_available_in_pdf?(%PDF{} = pdf, font_name) do
    Font.font_available?(font_name) or Map.has_key?(pdf.embedded_fonts, font_name)
  end

  defp font_supports_codepoint?(%PDF{} = pdf, font_name, codepoint)
       when is_integer(codepoint) and codepoint >= 0 do
    if Font.font_available?(font_name) do
      codepoint <= 255
    else
      embedded_font_supports_codepoint?(Map.get(pdf.embedded_fonts, font_name), codepoint)
    end
  end

  defp embedded_font_supports_codepoint?(
         %{ttf_metrics: %{cmap_by_code: cmap_by_code}},
         codepoint
       )
       when is_map(cmap_by_code) and map_size(cmap_by_code) > 0 do
    Map.has_key?(cmap_by_code, codepoint)
  end

  defp embedded_font_supports_codepoint?(
         %{ttf_metrics: %{cmap_by_code: cmap_by_code} = ttf_metrics},
         codepoint
       )
       when is_map(cmap_by_code) and map_size(cmap_by_code) == 0 do
    unicode_ranges = Map.get(ttf_metrics, :os2_unicode_ranges)
    code_page_ranges = Map.get(ttf_metrics, :os2_code_page_ranges)

    cond do
      is_tuple(unicode_ranges) and not UnicodeRanges.all_zero?(unicode_ranges) ->
        UnicodeRanges.supports_codepoint?(unicode_ranges, codepoint)

      is_tuple(code_page_ranges) and not code_page_ranges_all_zero?(code_page_ranges) ->
        code_page_ranges_support_codepoint?(code_page_ranges, codepoint)

      true ->
        codepoint <= 255
    end
  end

  defp embedded_font_supports_codepoint?(%{}, codepoint), do: codepoint <= 255
  defp embedded_font_supports_codepoint?(_other, _codepoint), do: false

  # credo:disable-for-next-line /^Elixir\.Credo\.Check\.Refactor\.(ABCSize|CyclomaticComplexity)$/
  defp code_page_ranges_support_codepoint?({range1, range2}, codepoint)
       when is_integer(range1) and is_integer(range2) and is_integer(codepoint) do
    cond do
      codepoint < 0 ->
        false

      codepoint <= 0x7F ->
        true

      codepoint <= 0xFF ->
        latin_1_supported? = (range1 &&& 1 <<< 0) != 0
        latin_1_supported?

      codepoint >= 0x0100 and codepoint <= 0x024F ->
        latin_2_supported? = (range1 &&& 1 <<< 1) != 0
        turkish_supported? = (range1 &&& 1 <<< 4) != 0 and turkish_codepoint?(codepoint)
        baltic_supported? = (range1 &&& 1 <<< 7) != 0 and baltic_codepoint?(codepoint)
        vietnamese_supported? = (range1 &&& 1 <<< 8) != 0 and vietnamese_codepoint?(codepoint)
        latin_2_supported? or turkish_supported? or baltic_supported? or vietnamese_supported?

      codepoint >= 0x0400 and codepoint <= 0x04FF ->
        cyrillic_supported? = (range1 &&& 1 <<< 2) != 0
        cyrillic_supported?

      codepoint >= 0x0370 and codepoint <= 0x03FF ->
        greek_supported? = (range1 &&& 1 <<< 3) != 0
        greek_supported?

      codepoint >= 0x0590 and codepoint <= 0x05FF ->
        hebrew_supported? = (range1 &&& 1 <<< 5) != 0
        hebrew_supported?

      codepoint >= 0x0600 and codepoint <= 0x06FF ->
        arabic_supported? = (range1 &&& 1 <<< 6) != 0
        arabic_supported?

      codepoint >= 0x0E00 and codepoint <= 0x0E7F ->
        thai_supported? = (range2 &&& 1 <<< 0) != 0
        thai_supported?

      true ->
        false
    end
  end

  defp code_page_ranges_support_codepoint?(_ranges, _codepoint), do: false

  defp turkish_codepoint?(0x011E), do: true
  defp turkish_codepoint?(0x011F), do: true
  defp turkish_codepoint?(0x0130), do: true
  defp turkish_codepoint?(0x0131), do: true
  defp turkish_codepoint?(0x015E), do: true
  defp turkish_codepoint?(0x015F), do: true
  defp turkish_codepoint?(_codepoint), do: false

  defp baltic_codepoint?(0x0104), do: true
  defp baltic_codepoint?(0x0105), do: true
  defp baltic_codepoint?(0x010C), do: true
  defp baltic_codepoint?(0x010D), do: true
  defp baltic_codepoint?(0x0112), do: true
  defp baltic_codepoint?(0x0113), do: true
  defp baltic_codepoint?(0x0116), do: true
  defp baltic_codepoint?(0x0117), do: true
  defp baltic_codepoint?(0x0122), do: true
  defp baltic_codepoint?(0x0123), do: true
  defp baltic_codepoint?(0x012A), do: true
  defp baltic_codepoint?(0x012B), do: true
  defp baltic_codepoint?(0x012E), do: true
  defp baltic_codepoint?(0x012F), do: true
  defp baltic_codepoint?(0x0136), do: true
  defp baltic_codepoint?(0x0137), do: true
  defp baltic_codepoint?(0x013B), do: true
  defp baltic_codepoint?(0x013C), do: true
  defp baltic_codepoint?(0x0145), do: true
  defp baltic_codepoint?(0x0146), do: true
  defp baltic_codepoint?(0x014C), do: true
  defp baltic_codepoint?(0x014D), do: true
  defp baltic_codepoint?(0x0156), do: true
  defp baltic_codepoint?(0x0157), do: true
  defp baltic_codepoint?(0x0160), do: true
  defp baltic_codepoint?(0x0161), do: true
  defp baltic_codepoint?(0x016A), do: true
  defp baltic_codepoint?(0x016B), do: true
  defp baltic_codepoint?(0x0172), do: true
  defp baltic_codepoint?(0x0173), do: true
  defp baltic_codepoint?(0x017D), do: true
  defp baltic_codepoint?(0x017E), do: true
  defp baltic_codepoint?(_codepoint), do: false

  defp vietnamese_codepoint?(0x01A0), do: true
  defp vietnamese_codepoint?(0x01A1), do: true
  defp vietnamese_codepoint?(0x01AF), do: true
  defp vietnamese_codepoint?(0x01B0), do: true
  defp vietnamese_codepoint?(_codepoint), do: false

  defp code_page_ranges_all_zero?({0, 0}), do: true
  defp code_page_ranges_all_zero?(_ranges), do: false

  # `set_font/3` does not validate, so a document can be drawing with a font
  # nothing knows about. Estimating keeps that cosmetic rather than fatal.
  defp text_width_for_font(%PDF{} = pdf, font_name, size, text) do
    pdf
    |> Context.from_pdf()
    |> Context.text_width(font_name, size, text, on_unknown: :estimate)
  end
end

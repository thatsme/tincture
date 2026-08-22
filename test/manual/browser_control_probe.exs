# Does a viewer refuse /GoToR specifically, or ignore link annotations?
#
# Browser-embedded viewers do not follow remote links. Firefox's does nothing,
# Edge renders the link and does nothing on click. Two negatives with no
# positive control cannot distinguish "this viewer refuses GoToR" from
# "something is wrong with the document", so this writes both together:
#
#   1  GoToR with /D          the feature
#   2  GoToR without /D       the feature
#   3  URI action             control - every viewer opens a web page
#   4  GoTo, internal         control - every viewer jumps within a document
#
# If 3 and 4 work while 1 and 2 do not, the viewer implements link annotations
# and destinations and is refusing GoToR on purpose. If none work, the document
# is at fault.
#
# Run it, then open the result in whichever viewer is in question:
#
#     mix run test/manual/browser_control_probe.exs
#
# Writes to _build/, alongside a two-page secondary to point at.

secondary_path = "Attached documents/Secondary.pdf"
out = Path.join(File.cwd!(), "_build/browser-control")
File.mkdir_p!(Path.join(out, "Attached documents"))

# Something to link into: 20 pages, numbered large enough to read at a glance
# so a wrong landing page is visible without counting.
secondary =
  Enum.reduce(1..20, Tincture.new() |> Tincture.page_size(:a4), fn n, acc ->
    acc = if n == 1, do: acc, else: Tincture.add_page(acc)

    acc
    |> Tincture.set_font("Helvetica-Bold", 200)
    |> Tincture.set_fill_color(if n == 13, do: {0.7, 0.1, 0.1}, else: {0.15, 0.15, 0.18})
    |> Tincture.text_at(180, 400, "#{n}")
    |> Tincture.set_font("Helvetica", 16)
    |> Tincture.set_fill_color({0.35, 0.35, 0.4})
    |> Tincture.text_at(60, 760, "Secondary.pdf - page #{n} of 20")
  end)

File.write!(Path.join(out, secondary_path), Tincture.export(secondary))

label = fn pdf, y, text, size ->
  pdf
  |> Tincture.set_fill_color({0.13, 0.14, 0.16})
  |> Tincture.set_font("Helvetica", size)
  |> Tincture.text_at(50, y, text)
end

main =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> label.(790, "Which actions does this viewer implement?", 16)
  |> label.(768, "Two remote links, then two controls every viewer handles.", 10)
  |> label.(720, "1  GoToR + /D  ->  Secondary.pdf, page 13", 12)
  |> Tincture.set_fill_color({0.0, 0.0, 0.8})
  |> Tincture.set_font("Helvetica-Bold", 12)
  |> Tincture.text_link(50, 698, ">> CLICK 1: remote file, page 13", {:file, secondary_path, 13})
  |> label.(650, "2  GoToR, no /D  ->  Secondary.pdf, unspecified page", 12)
  |> Tincture.set_fill_color({0.0, 0.0, 0.8})
  |> Tincture.set_font("Helvetica-Bold", 12)
  |> Tincture.text_link(50, 628, ">> CLICK 2: remote file, no page", {:file, secondary_path})
  |> Tincture.set_fill_color({0.6, 0.0, 0.0})
  |> Tincture.set_font("Helvetica-Bold", 12)
  |> Tincture.text_at(50, 570, "CONTROLS - these must work in any viewer")
  |> label.(550, "If these do nothing either, the document is at fault.", 10)
  |> label.(510, "3  URI action  ->  a web page", 12)
  |> Tincture.set_fill_color({0.0, 0.0, 0.8})
  |> Tincture.set_font("Helvetica-Bold", 12)
  |> Tincture.text_link(50, 488, ">> CLICK 3: open a web page", {:url, "https://example.org"})
  |> label.(440, "4  GoTo  ->  page 2 of this file", 12)
  |> Tincture.set_fill_color({0.0, 0.0, 0.8})
  |> Tincture.set_font("Helvetica-Bold", 12)
  |> Tincture.text_link(50, 418, ">> CLICK 4: jump to page 2 here", {:page, 2})
  |> Tincture.add_page()
  |> Tincture.set_fill_color({0.13, 0.14, 0.16})
  |> Tincture.set_font("Helvetica-Bold", 40)
  |> Tincture.text_at(50, 500, "PAGE 2")
  |> label.(450, "CLICK 4 worked: this viewer executes GoTo destinations.", 14)

main_path = Path.join(out, "Main.pdf")
File.write!(main_path, Tincture.export(main))

IO.puts("""
wrote #{Path.relative_to_cwd(out)}/
  Main.pdf
  #{secondary_path}

Open Main.pdf and click all four. Observed so far:

  SumatraPDF   1 -> page 13, 2 -> page 1, both in a new tab
  Edge         links rendered, clicks do nothing
  Firefox      does not act on them
""")

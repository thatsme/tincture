# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-07-26

First release under the Tincture name.

Tincture is a fork of [ex_guten](https://github.com/hwatkins/ex_guten) by Hugh
Watkins (MIT), which is itself an Elixir port of Joe Armstrong's Erlang
[erlguten](https://github.com/CarlWright/NGerlguten). Most of the engine — the
TrueType/OpenType parser, the Knuth-Plass line breaker, the TeX hyphenation
port, the PDF object serialiser — is his work, carried forward here. See
[NOTICE](NOTICE) for the full attribution chain.

`0.1.0` rather than a higher number is deliberate. The engine is mature, but
the public API under this name is new and may still move before 1.0.

### Added

- **Hyperlinks and annotations** — external URLs and internal page targets, via
  `Tincture.link/6` and `Tincture.text_link/5`. Previously the library emitted
  no `/Annot` objects at all.
- **Interactive forms (AcroForm)** — text fields, checkboxes and choice fields,
  via `Tincture.text_field/7`, `Tincture.checkbox/6` and
  `Tincture.choice_field/7`. Supports field flags (multiline, password,
  read-only, required, dropdown, editable, sort), maximum length, tooltips and
  initial values.
- **AES-256 encryption** — `Tincture.encrypt/2`, standard security handler
  revision 6 (`/V 5 /R 6`, PDF 2.0). User and owner passwords, permission
  flags, optional metadata encryption. Note that an owner password alone is
  advisory: the document is then encrypted under the empty user password and
  any reader can open it. Only a user password is real protection.
- `Tincture.Font.UnicodeRanges` — the complete OpenType `OS/2 ulUnicodeRange`
  bit table.
- `mix check`, which runs every gate CI runs, in the same order.

### Changed

- **Font subsetting is now on by default** (`subset: :used_text`). Only the
  glyphs a document draws are embedded, which typically cuts an embedded font
  by 70–90%. Previously it defaulted to `:none` and was undocumented. Pass
  `subset: :none` for the old behaviour.
- Decomposed the two modules that held most of the library. `Font.TTF` went
  from 4,530 lines with a single public function to a coordinator delegating to
  `TTF.Cmap`, `TTF.Glyf`, `TTF.Name`, `OpenType.GPOS`, `OpenType.GSUB`,
  `OpenType.Common`, `Font.CFF` and `Font.Binary`. `PDF.Serialize` went from
  3,491 lines to 516, with font embedding extracted to `PDF.FontEmbed` and PDF
  syntax primitives to `PDF.Object`.
- Documentation. The layout and typography API — 15 public functions across
  five modules — was `@moduledoc false` and invisible in generated docs.

### Fixed

- **Subsetting silently fell back to embedding the whole font** for any text
  containing a space. A glyph with no outline is encoded as zero bytes, which
  the subsetter treated as malformed, aborting the subset. Since almost every
  string contains a space, subsetting was effectively never applied.
- **A malformed `name` table crashed the parse.** `:unicode.characters_to_binary/3`
  signals bad input by returning a tuple rather than raising, so a rescue never
  fired and the tuple reached a function expecting a binary. A truncated
  UTF-16BE font name — what a bad subsetter produces — raised
  `FunctionClauseError` instead of being skipped.
- **The `OS/2` Unicode range table was 91% missing.** Only 11 of ~123
  `ulUnicodeRange` bits were mapped, all below 32, so `div(bit, 32)` was always
  0 and the font's `ulUnicodeRange2/3/4` words were parsed and then ignored.
  Any CJK, Hangul, punctuation, currency or math codepoint was reported as
  unsupported.
- `Typography.Hyphen` called `File.stream!/3` with the argument order deprecated
  in Elixir 1.16 — on the `:en_gb` path, the default locale.
- The `t:Tincture.rich_text/0` type was declared as a plain map while every caller requires a
  `%RichText{}` struct.
- A divide-by-zero in `Benchmark.Document` when `:timer.tc` reports 0µs on a
  fast machine.

### Infrastructure

- CI now passes. Upstream's 13 workflow runs all failed at
  `mix format --check-formatted`, so its test suite had never executed in CI.
  Tincture runs format, warnings-as-errors, Credo, Dialyzer and coverage,
  with the test suite on Elixir 1.16, 1.17, 1.18 and 1.19.
- 1,011 tests, up from 444 (one of which failed).
- Coverage measured and gated at 80%; currently 88.3%.
- Credo at `--strict` with zero issues, down from 174.
- Dialyzer passing, with a documented ignore file for defensive clauses that
  keep functions total.

[Unreleased]: https://github.com/thatsme/tincture/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/thatsme/tincture/releases/tag/v0.1.0

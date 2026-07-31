# Fonts used by the examples

Two faces, vendored so that `mix examples` produces the same bytes on every
machine.

| | |
|---|---|
| Fonts | Liberation Serif Regular, Liberation Sans Regular |
| Version | 2.1.4 |
| Licence | SIL Open Font License 1.1 — see [LICENSE](LICENSE) |
| Upstream | <https://github.com/liberationfonts/liberation-fonts> |

The version and licence above were read out of each font's own `name` table
rather than taken on trust.

## Why these are here

An embedded font is embedded *byte for byte*, so the output of an example
depends on which font the machine happened to have. Before this, running
`mix examples` on a different machine rewrote all seven PDFs with no change to
any source file — the committed output could only be reproduced by whoever
generated it. With a font in the repository the output is reproducible
anywhere, and a diff in `examples/output/` means something changed.

## What this is not

These are **not** shipped in the Hex package — `files:` in `mix.exs` excludes
`examples/` entirely. Tincture itself carries no fonts beyond the standard 14
metric tables, which are metrics rather than font programs.

Nothing here constrains what you embed in your own documents. Pass any font you
have the right to use to `Tincture.register_ttf_font/3`; if its `OS/2 fsType`
restricts embedding or subsetting, Tincture warns, and
`enforce_embedding_permissions: true` turns that into a refusal.

`support/fonts.exs` prefers these and falls back to system fonts if the
directory is missing. Setting `TINCTURE_EXAMPLES_NO_FONTS=1` skips both, which
is how CI exercises the standard-14 path a machine with no fonts would take.

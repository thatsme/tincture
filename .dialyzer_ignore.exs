# Dialyzer warnings that are intentional and must not be "fixed".
#
# Every entry here covers defensive clauses that Dialyzer can prove the
# *current* callers never reach. They are kept deliberately: each one keeps its
# function total, so a future caller gets a clear error (or a safe default)
# instead of a FunctionClauseError. Deleting them would trade an intentional
# failure mode for an accidental one.
#
# This file is NOT a place to park real findings. Anything that represents an
# actual defect gets fixed, not listed. Three real bugs were found by Dialyzer
# on the first run and fixed rather than added here:
#
#   * Font.UnicodeRanges — only 11 of ~123 OS/2 ulUnicodeRange bits were mapped,
#     so div(bit, 32) was always 0 and range2/3/4 were read then ignored.
#   * Typography.Hyphen  — File.stream!/3 called with the argument order
#     deprecated in Elixir 1.16.
#   * Tincture.rich_text/0 — typed as a plain map while the code requires a
#     %RichText{} struct.
#
# Filters are {file, warning_type} rather than {file, warning_type, line}:
# line-scoped filters go stale on every formatter run, and a stale filter is
# worse than a broad one because it silently stops matching.

[
  # Catch-all raise for an unsupported hyphenation locale. Reachable only if a
  # caller passes a locale outside the supported set; the public API normalises
  # before dispatch, so Dialyzer sees it as dead.
  {"lib/tincture/typography/hyphen.ex", :pattern_match_cov},

  # embedded_font_supports_codepoint?/2 final clause. The preceding clause
  # matches `%{}`, which in pattern position matches ANY map, so the non-map
  # fallback is unreachable while every caller passes a font metrics map.
  {"lib/tincture.ex", :pattern_match},

  # CFF / cmap / loca / glyf parser fallbacks. Each guards a malformed-font path
  # where preceding clauses already cover every shape Dialyzer can infer from
  # the parse pipeline. Font files are untrusted input, so these stay.
  #
  # These moved from pdf/serialize.ex to pdf/font_embed.ex when the font
  # embedding cluster was extracted; serialize.ex now has no suppressed
  # warnings of its own.
  {"lib/tincture/font/ttf.ex", :pattern_match_cov},
  {"lib/tincture/font/ttf/layout.ex", :pattern_match_cov},
  {"lib/tincture/pdf/font_embed.ex", :pattern_match_cov},
  {"lib/tincture/pdf/font_embed.ex", :pattern_match}
]

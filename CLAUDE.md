# Working on Tincture

Standing rules. They exist because each one was learned by getting it wrong in
a way that shipped.

## Publishing is Alessio's

Never run `mix hex.publish`. The upload is irreversible and tied to a
maintainer's account identity, so it stays a decision rather than a consequence
of finishing a task. Prepare to the tag, verify, and hand over.

`RELEASE.md` is the checklist. Order matters: Hex first, then the GitHub
release. A GitHub release announcing a version that then fails to publish is a
public promise you have to retract; a published package whose release entry
lags by ten minutes misleads nobody.

## Conformance statements come from a validator run, never from recall

Every claim about PDF/UA or PDF/A — a clause number, whether a rule is machine-
checkable, whether a document conforms — comes from running veraPDF against the
tree in front of you, or from reading veraPDF's profile XML. Not from memory,
not from reasoning about the specification text, not from what a sibling comment
in the same file says.

veraPDF is installed locally and runs in CI, which uploads its reports as a
build artifact. There is no excuse for an unverified clause number.

Two defects reached users this way, and they share a shape:

- Tagged link annotations were unreachable from the structure tree through
  0.1.0 and 0.2.0. veraPDF checks this — ISO 14289-1 clause 7.18.5 test 1, a
  machine rule — but `compliant.pdf` contained no link annotations, so the rule
  never fired. **A rule with nothing to match counts as passed.**
- ISO 19005-2 clause 6.5.1 sat unverified in shipped code for two releases. It
  turned out to be correct. That was luck, not method.

So: when a release adds a construct, the question is not "does the corpus still
pass" but **"does the corpus emit the new construct at all?"** If it does not,
the rules covering it have never run.

## Assert the complement, not the members

When a claim is about coverage, test for what is *absent*. Presence-only
coverage cannot see absence.

`test/tincture/corpus_coverage_test.exs` pins the set of structure types the
validated documents never emit, and fails both when a type becomes covered and
when a new uncovered one appears. It found four blind spots within hours of
being written — heading levels H3 through H6 — in an audit that had been done by
hand and believed correct.

## Design documents live in `docs/design/`, committed before the code

A design that lives anywhere else cannot be checked against source, and will
accumulate claims about the repository that are not true of it. This has
already cost one round of work: a briefing asserted a `render/2` function, a
`compress: false` option, `qpdf`, and veraPDF profiles "already on the machine"
— none of which existed.

Write the document into the repository first. Then the code.

## Scope discipline

Do the work described. If you find something else wrong — and on this codebase
you will — report it and stop rather than fixing it in passing. An unrelated
fix riding along in a defect release makes both harder to reason about, and the
finding is usually worth more attention than a drive-by patch gives it.

Defects do not wait behind features. A known-broken construct ships its fix
alone rather than sitting through a feature release.

## Claims in documentation are load-bearing

The README, ROADMAP and CHANGELOG make checkable assertions: rule counts, test
counts, what the corpus exercises, which constructs are known broken. Re-derive
them from source rather than transcribing them, including from a conversation
that just measured them. Two false statements were caught this way immediately
before 0.3.0 shipped — an install snippet pointing at the previous version, and
a claim that veraPDF ran in CI when it did not.

State known defects plainly, with clause numbers, in the user-facing
documentation. Published gaps are an asset: they turn "verified PDF/UA-1" from
a claim into a scope, which is the stronger thing to have.

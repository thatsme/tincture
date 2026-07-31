# Release Checklist

Each release is published to Hex.pm via GitHub Actions in
`.github/workflows/publish_hex.yml`.

## One-time setup

GitHub secret, under environment `hex-publish`:

- `HEX_API_KEY` — a Hex API key with `api:write`

## Before every release

Everything here has to pass locally before the tag is pushed. CI runs the same
gates, but a failure discovered after tagging costs a version number.

1. **Every gate CI runs, in the same order.**

       mix check

   That alias is `format --check-formatted`, `compile --force
   --warnings-as-errors`, `credo --strict`, `dialyzer`, and `coveralls`. The
   coverage floor lives in `coveralls.json`.

2. **The examples, both ways.**

       mix examples
       TINCTURE_EXAMPLES_NO_FONTS=1 mix examples

   The second run forces the standard-14 fallback, which is what a machine with
   no fonts installed gets — a slim container, or a Windows box without the
   candidate families. Both must complete. Examples are not covered by the test
   suite, and they are the first thing a reader runs.

   Note that `examples/output/*.pdf` are committed, and their bytes depend on
   which font the host had available: regenerating on a different machine will
   show a diff even though nothing changed. `signed.pdf` differs on every run,
   because a signature carries the signing time. Only commit regenerated output
   when the document itself changed.

3. **The docs build clean.**

       mix docs

4. **The package builds, and contains what it should.**

       mix hex.build

   `examples/` and `docs/` are deliberately not shipped — see `files:` in
   `mix.exs`. Check that `priv/plts` has not crept in.

5. **CHANGELOG is honest.**

   - Move everything under `## [Unreleased]` to a new `## [X.Y.Z] — YYYY-MM-DD`
     heading, leaving `[Unreleased]` empty.
   - Update the link definitions at the foot of the file: the `[Unreleased]`
     compare link points at the new tag, and a new `[X.Y.Z]` release link is
     added.
   - Anything shipped in `lib/` belongs in there. Code that reaches users
     without a changelog entry is how a release becomes hard to describe.

6. **Version and counts.**

   - Bump `@version` in `mix.exs`.
   - Update the test count and coverage figure in `README.md` and `ROADMAP.md`
     if they have moved. `mix test` prints the count; `mix coveralls` prints the
     percentage.

7. **ROADMAP reflects what just shipped.** Move completed items out of "next"
   and strike them through in their section, as the existing entries do.

## Publishing

1. Commit the version bump and changelog.
2. Tag and push:

       git tag vX.Y.Z
       git push origin main --tags

3. Confirm the `Publish Hex` workflow succeeds.
4. Confirm <https://hexdocs.pm/tincture> shows the new version.

## After publishing

- Bump the ElixirForum thread with what changed. Link the changelog section
  rather than restating it, and lead with the thing a reader can see.

## Notes

- The tag must match `mix.exs` exactly — `v0.2.0` for `version: "0.2.0"`.
- A manual publish is available via `workflow_dispatch`.
- `0.x` means the API may still move. Say so in the release notes when it does.

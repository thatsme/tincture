# Release Checklist

Releases are published to Hex.pm **manually, by a maintainer**, with
`mix hex.publish`. That is how 0.1.0 went out, and it is deliberate: the upload
is the one step that cannot be undone, so it stays a decision rather than a
consequence of pushing a tag.

There is no publish workflow. One existed, fired on the `v0.1.0` tag with no
`HEX_API_KEY` configured, failed, and was removed rather than left sitting red.
**Tagging records the release on GitHub; it does not publish to Hex.**

Should this ever move into CI, it needs a Hex API key with `api:write` held as a
repository secret, and a workflow triggered on `v*` tags that verifies the tag
matches `@version` in `mix.exs` before uploading.

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

1. Commit the version bump and changelog, and let CI go green on `main`.
2. Tag and push:

       git tag vX.Y.Z
       git push origin main --tags

3. Publish to Hex, from a maintainer's machine:

       mix hex.publish

   This uploads the package *and* the documentation, and asks for confirmation
   before doing either. Check the file list it prints: `examples/` and `docs/`
   should not be in it.

4. Confirm <https://hex.pm/packages/tincture> lists the new release, and
   <https://hexdocs.pm/tincture> serves its docs.
5. Draft the GitHub release for the tag, with the changelog section as its body.

## After publishing

- Bump the ElixirForum thread with what changed. Link the changelog section
  rather than restating it, and lead with the thing a reader can see.

## Notes

- The tag must match `mix.exs` exactly — `v0.2.0` for `version: "0.2.0"`.
- A Hex release cannot be unpublished after an hour, and a version number can
  never be reused. Check the file list `mix hex.publish` prints before saying
  yes to it.
- `0.x` means the API may still move. Say so in the release notes when it does.

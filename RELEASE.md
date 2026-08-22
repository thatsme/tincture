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

   `examples/output/*.pdf` are committed and are reproducible: the examples
   embed a font vendored under `examples/fonts/`, so regenerating on any
   machine gives identical bytes and a diff there means something actually
   changed. The one exception is `signed.pdf`, which differs on every run
   because a signature carries the signing time.

3. **The validators, against the documents that exercise the features.**

       verapdf --flavour ua1 examples/output/compliant.pdf
       verapdf --flavour ua1 examples/output/accessible.pdf
       verapdf --flavour 2b  examples/output/archival.pdf
       verapdf --flavour 2u  examples/output/archival.pdf
       verapdf --flavour 2a  examples/output/archival.pdf
       verapdf --flavour ua1 examples/output/archival.pdf
       verapdf --flavour ua1 "examples/output/linked/Main-report.pdf"
       verapdf --flavour ua1 "examples/output/linked/Attached documents/Appendix-A.pdf"

   All must report `PASS`. CI runs the same five and uploads the reports, so
   this is a pre-flight rather than the only run — but veraPDF belongs on the
   machine where the work happens too: a conformance question that has to wait
   for a tool somewhere else is a question that gets answered by reasoning
   instead.

   Read the pass with the corpus in mind. veraPDF scores rules, not features,
   and a rule with nothing to match counts as passed — which is how 0.1.0 and
   0.2.0 scored 106/106 on PDF/UA while writing link annotations that were
   unreachable from the structure tree. `compliant.pdf` had no links in it. So
   when a release adds a construct, the checklist question is not "does the
   corpus still pass" but **"does the corpus emit the new construct at all?"**
   If it does not, the rules covering it have never run.

4. **The docs build clean.**

       mix docs

5. **The package builds, and contains what it should.**

       mix hex.build

   `examples/` and `docs/` are deliberately not shipped — see `files:` in
   `mix.exs`. Check that `priv/plts` has not crept in.

6. **CHANGELOG is honest.**

   - Move everything under `## [Unreleased]` to a new `## [X.Y.Z] — YYYY-MM-DD`
     heading, leaving `[Unreleased]` empty.
   - Update the link definitions at the foot of the file: the `[Unreleased]`
     compare link points at the new tag, and a new `[X.Y.Z]` release link is
     added.
   - Anything shipped in `lib/` belongs in there. Code that reaches users
     without a changelog entry is how a release becomes hard to describe.

7. **Version and counts.**

   - Bump `@version` in `mix.exs`.
   - Update the test count and coverage figure in `README.md` and `ROADMAP.md`
     if they have moved. `mix test` prints the count; `mix coveralls` prints the
     percentage.

8. **ROADMAP reflects what just shipped.** Move completed items out of "next"
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
   <https://hexdocs.pm/tincture> serves its docs. Pull the published tarball
   and check it contains what the tag does — the upload is what users get, and
   it is the artifact worth verifying rather than the plan:

       curl -sL -o t.tar https://repo.hex.pm/tarballs/tincture-X.Y.Z.tar

5. **Create the GitHub release, from the tag, after Hex.**

   The ordering is deliberate. A GitHub release announcing a version that then
   fails to publish is a public promise you have to retract; `mix hex.publish`
   can still fail at that point on auth or on something in the file list. A
   published package whose release entry lags by ten minutes misleads nobody.
   The HexDocs URL also does not exist until you publish, so writing the body
   first means links that 404.

       gh release create vX.Y.Z --title "vX.Y.Z — what changed"          --notes-file body.md --verify-tag reports/*.xml

   The body pastes the changelog's `### Changed` and `### Fixed` sections
   **verbatim**. Do not summarise them. Behaviour breaks are the most valuable
   content in a release and should not live only in a file inside the package —
   0.3.0 renumbered objects in tagged documents and made `export/2` refuse
   documents it had previously written, and someone upgrading needs to meet
   that before their build does.

   **Attach the veraPDF XML reports as release assets.** CI uploads them as a
   build artifact, and build artifacts expire — ninety days by default. Release
   assets do not. A conformance claim whose evidence has expired is a claim
   people have to take on trust again, which is the thing this project is
   trying not to ask of them. Download the artifact from the run that validated
   the tagged commit, confirm the run's `head_sha` matches the tag, and upload
   the reports with the release.

## After publishing

- Bump the ElixirForum thread with what changed. Link the changelog section
  rather than restating it, and lead with the thing a reader can see.

## Notes

- The tag must match `mix.exs` exactly — `v0.2.0` for `version: "0.2.0"`.
- **A tag may be re-cut before publishing, never after.** Until a version
  exists on Hex nothing has consumed the tag, and a tag that does not reproduce
  the published tarball is worse than one that moved once. Check what actually
  changed: only the paths in `files:` affect the package, so a commit touching
  `docs/`, `examples/` or `test/` leaves the tarball identical and the tag can
  stay. Once `mix hex.publish` has run, the tag is a permanent record of what
  was uploaded and the next change is a new version.
- A Hex release cannot be unpublished after an hour, and a version number can
  never be reused. Check the file list `mix hex.publish` prints before saying
  yes to it.
- `0.x` means the API may still move. Say so in the release notes when it does.

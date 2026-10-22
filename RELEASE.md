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

1. **The Lint and Test gates CI runs, in the same order.**

       mix check
       elixir scripts/check_absolute_paths.exs --self-test
       elixir scripts/check_absolute_paths.exs

   That alias is `format --check-formatted`, `compile --force
   --warnings-as-errors`, `credo --strict`, `dialyzer`, and `coveralls`. The
   coverage floor lives in `coveralls.json`. The absolute-path check is a
   script rather than a Mix task, so the alias does not run it. The Examples
   job's gates are steps 2 and 3.

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
   changed. CI checks this on every commit. The one exception is
   `signed.pdf`, which differs on every run because the example mints a new
   key each time.

3. **The validators, against the documents that exercise the features.**

       verapdf --flavour ua1 examples/output/compliant.pdf
       verapdf --flavour ua1 examples/output/accessible.pdf
       verapdf --flavour 2b  examples/output/archival.pdf
       verapdf --flavour 2u  examples/output/archival.pdf
       verapdf --flavour 2a  examples/output/archival.pdf
       verapdf --flavour ua1 examples/output/archival.pdf
       verapdf --flavour ua1 "examples/output/linked/Main-report.pdf"
       verapdf --flavour ua1 "examples/output/linked/Attached documents/Appendix-A.pdf"

   All must report `PASS`. CI runs the same eight and uploads the reports, so
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

4. **The PAC claim still describes audited files.**

   The README, ROADMAP and `examples/README.md` cite a PAC audit by date and by
   the commit whose files it ran on. Compare the five PDF/UA documents at the
   release commit with those at the cited commit:

       git diff --stat <audited-commit> HEAD -- \
         examples/output/compliant.pdf examples/output/accessible.pdf \
         examples/output/archival.pdf examples/output/linked/

   If none changed, the claim stands as written. If any did, either run PAC
   again on the new files and update the date and commit everywhere the claim
   appears, or leave the claim citing the older commit exactly as it is, so it
   still names the files that were audited. A PAC result must never come to
   describe files nobody ran it on. veraPDF does not need this step: it runs on
   every commit.

5. **The docs build clean.**

       mix docs --output tmp/docs-check

   The output goes to `tmp/` so `doc/` is never written: on a machine where
   `doc/` holds a checkout of the generated documentation, a plain `mix docs`
   rewrites it.

6. **The package builds, and contains what it should.**

       mix hex.build

   `examples/` and `docs/` are deliberately not shipped — see `files:` in
   `mix.exs`. Check that `priv/plts` has not crept in.

7. **CHANGELOG is honest.**

   - Move everything under `## [Unreleased]` to a new `## [X.Y.Z] — YYYY-MM-DD`
     heading, leaving `[Unreleased]` empty.
   - Update the link definitions at the foot of the file: the `[Unreleased]`
     compare link points at the new tag, and a new `[X.Y.Z]` release link is
     added.
   - Anything shipped in `lib/` belongs in there. Code that reaches users
     without a changelog entry is how a release becomes hard to describe.

8. **Version and counts.**

   - Bump `@version` in `mix.exs`.
   - Update the test count and coverage in `README.md` and `ROADMAP.md`.
     `mix test` prints the count. Coverage is stated two ways. First, the
     enforced floor: `minimum_coverage` in `coveralls.json`, quoted as "CI
     fails below N%". Second, the measured value: the `[TOTAL]` that the Lint
     job's `mix coveralls` printed on the release head, quoted as "N% in CI at
     X.Y.Z". If the CI runs on the release branch printed different figures,
     quote the lowest and highest instead, as "A–B% in CI at X.Y.Z". A local
     run is not used.
   - Re-derive the veraPDF rule and check counts the documentation quotes "at
     X.Y.Z", from the `verapdf-reports` artifact of the CI run on the release
     commit (`<details passedRules … passedChecks …>` in each report), and
     update every place that quotes them: `README.md`, `ROADMAP.md` and
     `examples/README.md`. Change "at X.Y.Z" to the new version even where a
     count has not moved, so every figure names the release it was measured
     at.
   - Every verification claim names the tool that checks it, and that check is
     a CI step or a test, never a tool run once by hand. The one exception is
     the PAC audit, which cites its date and the commit it ran on (step 4).

9. **ROADMAP reflects what just shipped.** Move completed items out of "next"
   and strike them through in their section, as the existing entries do.

## Publishing

Every command here runs from the repository root, in Git Bash on Windows or a
shell on macOS. Two steps need the maintainer's Hex credentials, and so must
run on the machine that holds them: the pre-flight in step 2, and
`mix hex.publish` in step 4. Tagging and the GitHub release need push access
to the repository and an authenticated `gh`, and can run anywhere that has
them.

1. Commit the version bump and changelog, and let CI go green on `main`.
2. **Pre-flight, on the machine that will publish, before anything is
   tagged:**

       mix hex.user whoami

   It must name the maintainer account. If it fails — a key can be revoked on
   hex.pm while its local copy still decrypts — re-authenticate with
   `mix hex.user auth` now. A pushed tag whose upload then fails is the state
   this prevents: the tag is public, and the package is not.
3. Tag, with an annotated tag, and push only that tag:

       git tag -a vX.Y.Z -m "vX.Y.Z"
       git push origin vX.Y.Z

   `--tags` would push every local tag, including any that were never meant to
   leave the machine.

4. Publish to Hex, from the machine that passed step 2, from a fresh worktree
   of the tag:

       git worktree add tmp/publish vX.Y.Z
       cd tmp/publish
       mix deps.get
       mix hex.publish
       cd ../..
       git worktree remove tmp/publish

   This uploads the package *and* the documentation, and asks for confirmation
   before doing either. Check the file list it prints: `examples/` and `docs/`
   should not be in it.

   If `git worktree remove` refuses, list what is inside first:

       git -C tmp/publish status --porcelain --ignored

   Add `--force` only when the only extra content is gitignored build output —
   `deps/`, `_build/`, `doc/`. Anything else is a stop: something reached the
   worktree that is not in the tag, and the package may have carried it.

   The worktree is what makes the upload exactly the tagged tree. It holds
   nothing but the tag's files, so no uncommitted change or untracked file in
   the working copy can reach the package. And it has no `doc/`, which is
   gitignored, so `mix hex.publish` builds the documentation from empty. A
   `doc/` left over from an earlier build can keep assets that the new pages no
   longer match, such as a previous release's sidebar and search index, and
   whatever is in `doc/` is what HexDocs receives.

5. Confirm <https://hex.pm/packages/tincture> lists the new release, and
   <https://hexdocs.pm/tincture> serves its docs. Pull the published tarball
   and check it contains what the tag does — the upload is what users get, and
   it is the artifact worth verifying rather than the plan:

       curl -sL -o tmp/t.tar https://repo.hex.pm/tarballs/tincture-X.Y.Z.tar

6. **Create the GitHub release, from the tag, after Hex.**

   The ordering is deliberate. A GitHub release announcing a version that then
   fails to publish is a public promise you have to retract; `mix hex.publish`
   can still fail at that point on auth or on something in the file list. A
   published package whose release entry lags by ten minutes misleads nobody.
   The HexDocs URL also does not exist until you publish, so writing the body
   first means links that 404.

       gh release create vX.Y.Z -R thatsme/tincture \
         --title "vX.Y.Z — what changed" \
         --notes-file body.md --verify-tag verapdf-reports/*.xml

   The body pastes, **verbatim**, the version's lead sentence (when it has
   one) and its `### Deprecated`, `### Changed` and `### Fixed` sections. Do
   not summarise them. Deprecations belong there for the same reason as
   behaviour changes: they are what an upgrader has to act on before the next
   release turns them into errors. Behaviour breaks are the most valuable
   content in a release and should not live only in a file inside the package —
   0.3.0 renumbered objects in tagged documents and made `export/2` refuse
   documents it had previously written, and someone upgrading needs to meet
   that before their build does.

   **Attach the veraPDF XML reports as release assets.** CI uploads them as a
   build artifact, and build artifacts expire — ninety days by default. Release
   assets do not. A conformance claim whose evidence has expired is a claim
   people have to take on trust again, which is the thing this project is
   trying not to ask of them. Take the reports from the run that validated the
   tagged commit, into `verapdf-reports/`, which `.gitignore` excludes. Empty
   it first, in the same command block: the folder outlives a release, and the
   `*.xml` glob above would attach a previous release's reports alongside the
   new ones.

       rm -rf verapdf-reports
       gh run download <run-id> -R thatsme/tincture -n verapdf-reports -D verapdf-reports

   Then confirm the run validated the tagged commit. The two hashes must be
   equal:

       gh run view <run-id> -R thatsme/tincture --json headSha --jq .headSha
       git rev-parse 'vX.Y.Z^{commit}'

   Use `^{commit}`: an annotated tag's own hash is the tag object's, not the
   commit's, so comparing against the bare tag name never matches.

   `-R` keeps every `gh` command on this repository. In a clone that also
   carries an `upstream` remote, `gh` without it can resolve to that repository
   instead.

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

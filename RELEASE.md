# Release Checklist

Each release is published to Hex.pm via GitHub Actions in `.github/workflows/publish_hex.yml`.

1. Ensure GitHub secret is set:
   - Environment: `hex-publish`
   - Secret: `HEX_API_KEY` (Hex API key with `api:write`)
2. Bump version in `mix.exs` (for example `0.1.1`).
3. Run local validation:
   - `mix deps.get`
   - `mix test`
   - `mix docs`
   - `mix hex.build`
4. Commit and push the version change.
5. Create and push a matching git tag:
   - `git tag v0.1.1`
   - `git push origin main --tags`
6. Confirm the `Publish Hex` workflow succeeds.

## Notes

- Tag must match `mix.exs` version exactly (for example `v0.1.1` for `version: "0.1.1"`).
- Manual publish trigger is also available via `workflow_dispatch`.
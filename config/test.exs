import Config

# The AFM registry is empty by default: Tincture ships no AFM fonts. Tests
# point it at a synthetic fixture so the AFM code path stays covered.
config :tincture, afm_path: Path.expand("../test/fixtures/afm", __DIR__)

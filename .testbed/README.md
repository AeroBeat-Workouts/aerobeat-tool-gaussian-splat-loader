# AeroBeat Gaussian Splat Testbed

This hidden GodotEnv project is the repo-local validation sandbox for
`aerobeat-tool-gaussian-splat-loader`.

## Rules

- Edit real code in repo-root `src/`.
- Use `.testbed/` for validation assets, smoke scenes, and tests.
- Do **not** treat `.testbed/addons/` as source of truth. GodotEnv generates that mirror state from `addons.jsonc`, and the truthful runtime surface is the repo-root `src/AeroGaussianSplatManager.gd` class.

## Install / refresh addons

From the repo root:

```bash
cd .testbed
godotenv addons install
```

## Validate

Import + tests:

```bash
godot --headless --path . --import
godot --headless --path . --script addons/aerobeat-vendor-godot-unit-test/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Smoke scene load attempt:

```bash
godot --headless --path . --scene res://scenes/splat_loader_smoke.tscn --quit-after 2
```

## Notes

- The smoke scene intentionally performs a real gaussian splat load attempt.
- Known render-visibility issues are non-blocking for this slice; successful decode/build may not produce stable visible output in screenshots.
- `addons.jsonc` installs this repo's root surface directly so the testbed exercises the same public API a repo-root consumer would use.

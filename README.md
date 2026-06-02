# AeroBeat Tool - Gaussian Splat Loader

`aerobeat-tool-gaussian-splat-loader` is the AeroBeat Gaussian splat runtime wrapper.
The real implementation now lives in this repo's `src/` scripts, and the hidden
`.testbed/` project installs that repo-root surface directly through GodotEnv.
There is no longer a separate tracked lower-package implementation inside this
repo, and there is no `src/AeroToolManager.gd` compatibility wrapper anymore;
anything generated under `.testbed/addons/` is disposable mirror state.

## Architecture truth

- `src/AeroGaussianSplatManager.gd` is the real public/runtime class and singleton-shaped entrypoint.
- `src/gaussian_splat_runtime.gd` and the local background helper scripts contain the real load/decode/build/runtime logic.
- `src/AeroGaussianSplatEnvironmentFulfillment.gd` is the environment-loader integration seam for contract-shaped requests/results.
- `.testbed/` is the only supported local validation sandbox. Do real work in repo-root `src/` and `.testbed/`, not in generated addon mirrors.

## Public runtime surface

`AeroGaussianSplatManager` is responsible for loading, placing, rotating, and unloading gaussian splats.

The canonical consumer-facing placement contract is now nested under `options.transform` with:

- `position`
- `rotation_degrees`
- `scale`

A narrow temporary compatibility seam still accepts flat top-level `position` / `rotation_degrees` / `scale` keys for direct tool callers while downstream repos finish migrating, but new code should treat nested `transform` as the only stable public contract.

Core methods:

- `load_gaussian_resource_from_path(absolute_path)`
- `create_splat_node_from_path(absolute_path)`
- `load_splat(absolute_path, parent := null, options := {})`
- `place_splat(node, parent := null, options := {})`
- `rotate_splat(node, rotation_degrees)`
- `unload_splat(node)`
- `begin_load_gaussian_resource_from_path(absolute_path)`
- `begin_create_splat_node_from_path(absolute_path)`
- `get_background_load_status()`
- `configure_world_environment(world_environment)`
- `get_renderer_support_status()`

Supported formats:

- `.ply`
- `.compressed.ply`
- `.splat`
- `.sog`

Current path expectations:

- load calls expect **absolute/local paths**
- background loading currently supports only `.ply` and `.compressed.ply`
- `.splat` and `.sog` still use the synchronous path

## Environment-loader seam

For generic environment loading, use `AeroGaussianSplatEnvironmentFulfillment`.
It keeps environment-loader concerns contract-shaped while delegating real splat
work to `AeroGaussianSplatManager`.

`AeroGaussianSplatEnvironmentFulfillment` can:

- accept a `Dictionary` request or typed `AeroEnvironmentRequest`
- enforce the current official environment contract for `.compressed.ply`
- return typed `AeroEnvironmentResult` / `AeroEnvironmentError`
- apply YAML sidecar transform config after load (`.config.yaml`)
- consume placement requests through `context.transform`
- optionally configure a provided `WorldEnvironment`
- bridge async runtime progress into contract progress/result/error objects

The important seam is:

- `AeroGaussianSplatManager` owns splat runtime behavior
- `AeroGaussianSplatEnvironmentFulfillment` owns environment-contract translation

## Renderer support truth

Use `get_renderer_support_status()` before claiming visible render support.

- renderer paths without a `RenderingDevice` are **unsupported** for visible gaussian splat rendering
- renderer paths with a `RenderingDevice` are still only **experimental**
- in the current validation slice, Forward+ / Vulkan has reproduced compositor-side crashes after a successful load, so visible output should not be overclaimed yet

Successful loads may therefore decode/build correctly even when screenshots do
not show stable visible splat output.

## GodotEnv testbed flow

From the repo root:

```bash
cd .testbed
godotenv addons install
godot --headless --path . --import
godot --headless --path . --script addons/aerobeat-vendor-godot-unit-test/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Smoke scene load attempt:

```bash
godot --headless --path .testbed --scene res://scenes/splat_loader_smoke.tscn --quit-after 2
```

## `.testbed` layout

- `addons.jsonc` - GodotEnv manifest for the hidden validation project
- `assets/splats/` - sample splat payloads used for real load attempts
- `scenes/splat_loader_smoke.tscn` - direct runtime smoke scene
- `scripts/splat_loader_smoke.gd` - smoke scene logic
- `tests/` - repo-local GUT coverage

## Usage examples

### Load + place a splat

```gdscript
var manager := AeroGaussianSplatManager.new()
add_child(manager)

var result := manager.load_splat("/absolute/path/to/scene.ply", self, {
    "transform": {
        "position": Vector3(0, 0, 0),
        "rotation_degrees": Vector3(0, 45, 0),
        "scale": Vector3.ONE,
    },
})
if result.ok:
    print("Loaded %d points" % int(result.point_count))
```

### Rotate or unload an existing splat

```gdscript
manager.rotate_splat(result.node, Vector3(0, 90, 0))
manager.unload_splat(result.node)
```

### Configure compositor support when available

```gdscript
var world_environment := WorldEnvironment.new()
manager.configure_world_environment(world_environment)
```

### Contract-shaped environment fulfillment

```gdscript
const AeroEnvironmentRequest := preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_request.gd")

var manager := AeroGaussianSplatManager.new()
add_child(manager)

var fulfillment := AeroGaussianSplatEnvironmentFulfillment.new(manager)
var result = fulfillment.fulfill(AeroEnvironmentRequest.new({
    "request_id": "req-1",
    "kind": "splat",
    "asset_path": "/absolute/path/to/scene.compressed.ply",
    "context": {
        "transform": {
            "position": [0, 0, 0],
            "rotation_degrees": [0, 45, 0],
            "scale": [1, 1, 1]
        }
    }
}))
if result.ok:
    add_child(result.details["node"])
```

### Async environment fulfillment

```gdscript
var operation = fulfillment.begin_fulfill(AeroEnvironmentRequest.new({
    "request_id": "req-async-1",
    "kind": "splat",
    "asset_path": "/absolute/path/to/scene.compressed.ply"
}))
operation.progressed.connect(func(progress):
    var snapshot := progress.to_dict()
    print("%s / %s: %0.1f%%" % [snapshot.get("status", ""), snapshot.get("phase", ""), float(snapshot.get("progress", 0.0)) * 100.0])
)
operation.finished.connect(func(_op):
    if operation.result != null and operation.result.ok:
        add_child(operation.result.details["node"])
)
```

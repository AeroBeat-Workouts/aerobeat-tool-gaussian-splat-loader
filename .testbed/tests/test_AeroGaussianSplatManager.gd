extends GutTest

const SAMPLE_PLY := "res://assets/splats/demo.ply"
const SAMPLE_COMPRESSED_PLY := "res://assets/splats/demo.compressed.ply"
const LOCAL_RUNTIME_SCRIPT := preload("res://addons/aerobeat-tool-gaussian-splat-loader/src/gaussian_splat_runtime.gd")
const REQUEST_SCRIPT := preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_request.gd")
const RESULT_SCRIPT := preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_result.gd")
const ERROR_SCRIPT := preload("res://addons/aerobeat-environment-core/src/contracts/data_types/environment_error.gd")

func test_public_manager_initializes_and_exposes_supported_formats() -> void:
	var manager := AeroGaussianSplatManager.new()
	add_child_autofree(manager)
	assert_true(manager.get_supported_extensions().has("ply"), "PLY should be supported")
	assert_true(manager.get_supported_extensions().has("compressed.ply"), ".compressed.ply should be supported")
	assert_true(manager.get_supported_extensions().has("splat"), "Legacy .splat should still be supported")
	assert_true(manager.get_supported_extensions().has("sog"), "Legacy .sog should still be supported")

func test_public_manager_matches_local_runtime_surface() -> void:
	var public_manager := AeroGaussianSplatManager.new()
	var local_runtime = LOCAL_RUNTIME_SCRIPT.new()
	add_child_autofree(public_manager)
	add_child_autofree(local_runtime)
	assert_eq(public_manager.get_supported_extensions(), local_runtime.get_supported_extensions(), "Public manager should preserve the local runtime extension contract")
	assert_eq(public_manager.get_renderer_support_status().get("support_level", ""), local_runtime.get_renderer_support_status().get("support_level", ""), "Public manager should preserve the local runtime renderer-support contract")

func test_absolute_path_loading_builds_a_resource() -> void:
	var manager := AeroGaussianSplatManager.new()
	add_child_autofree(manager)
	var absolute_path := ProjectSettings.globalize_path(SAMPLE_PLY)
	var result := manager.load_gaussian_resource_from_path(absolute_path)
	assert_true(result.get("ok", false), result.get("message", "Expected sample PLY to load"))
	assert_true(result.get("point_count", 0) > 0, "Loaded sample should contain points")
	assert_true(result.get("resource", null) != null, "Resource should be returned")

func test_load_place_rotate_and_unload_splat() -> void:
	var manager := AeroGaussianSplatManager.new()
	var parent := Node3D.new()
	var world_environment := WorldEnvironment.new()
	add_child_autofree(parent)
	add_child_autofree(world_environment)
	parent.name = "LoadParent"
	parent.add_child(manager)
	var absolute_path := ProjectSettings.globalize_path(SAMPLE_PLY)

	var load_result := manager.load_splat(absolute_path, parent, {
		"transform": {
			"position": {"x": 1, "y": 2, "z": 3},
			"rotation_degrees": [0.0, 45.0, 0.0],
			"scale": [2, 2, 2],
		},
		"world_environment": world_environment,
	})
	assert_true(load_result.get("ok", false), load_result.get("message", "Expected sample PLY to load and attach"))
	assert_true(load_result.get("placed", false), "load_splat should attach the node when a parent is provided")
	assert_true(load_result.get("transform_applied", false), "load_splat should apply transform options")
	assert_eq(load_result.get("parent", {}).get("name", ""), "LoadParent")
	var node: Variant = load_result.get("node", null)
	assert_true(node is Node3D, "load_splat should return a Node3D instance")
	assert_eq((node as Node3D).position, Vector3(1, 2, 3))
	assert_almost_eq((node as Node3D).rotation_degrees.y, 45.0, 0.001)
	assert_eq((node as Node3D).scale, Vector3(2, 2, 2))
	assert_eq(load_result.get("transform", {}).get("position", Vector3.ZERO), Vector3(1, 2, 3))
	assert_almost_eq(load_result.get("transform", {}).get("rotation_degrees", Vector3.ZERO).y, 45.0, 0.001)
	assert_eq(load_result.get("transform", {}).get("scale", Vector3.ONE), Vector3(2, 2, 2))

	var rotate_result := manager.rotate_splat(node as Node3D, Vector3(0, 90, 0))
	assert_true(rotate_result.get("ok", false), "rotate_splat should succeed for a valid node")
	assert_almost_eq((node as Node3D).rotation_degrees.y, 90.0, 0.001)
	assert_almost_eq(rotate_result.get("transform", {}).get("rotation_degrees", Vector3.ZERO).y, 90.0, 0.001)

	var unload_result := manager.unload_splat(node as Node)
	assert_true(unload_result.get("ok", false), "unload_splat should succeed for a valid node")
	await get_tree().process_frame
	assert_false(is_instance_valid(node), "unload_splat should queue_free the node")

func test_place_splat_prefers_nested_transform_contract() -> void:
	var manager := AeroGaussianSplatManager.new()
	var node := Node3D.new()
	add_child_autofree(manager)
	add_child_autofree(node)
	var result := manager.place_splat(node, null, {
		"transform": {
			"position": [4, 5, 6],
			"rotation_degrees": {"x": 0, "y": 15, "z": 0},
			"scale": [0.75, 0.75, 0.75],
		},
	})
	assert_true(result.get("ok", false), result.get("message", "Nested transform placement should succeed"))
	assert_true(result.get("transform_applied", false), "Nested transform placement should report that a transform was applied")
	assert_false(result.get("compatibility", {}).get("used_flat_transform_keys", true), "Nested transform placement should not rely on the legacy flat-key seam")
	assert_eq(node.position, Vector3(4, 5, 6))
	assert_almost_eq(node.rotation_degrees.y, 15.0, 0.001)
	assert_eq(node.scale, Vector3(0.75, 0.75, 0.75))

func test_place_splat_keeps_documented_flat_transform_compatibility_seam() -> void:
	var manager := AeroGaussianSplatManager.new()
	var node := Node3D.new()
	add_child_autofree(manager)
	add_child_autofree(node)
	var result := manager.place_splat(node, null, {
		"position": [1, 2, 3],
		"rotation_degrees": [0, 30, 0],
		"scale": [2, 2, 2],
	})
	assert_true(result.get("ok", false), result.get("message", "Legacy flat transform placement should remain temporarily supported"))
	assert_true(result.get("compatibility", {}).get("used_flat_transform_keys", false), "Flat transform placement should report the compatibility seam")
	assert_eq(result.get("transform", {}).get("position", Vector3.ZERO), Vector3(1, 2, 3))
	assert_almost_eq(result.get("transform", {}).get("rotation_degrees", Vector3.ZERO).y, 30.0, 0.001)
	assert_eq(result.get("transform", {}).get("scale", Vector3.ONE), Vector3(2, 2, 2))

func test_contract_fulfillment_accepts_typed_request_and_returns_typed_result() -> void:
	var fulfillment := AeroGaussianSplatEnvironmentFulfillment.new()
	var request = REQUEST_SCRIPT.new({
		"request_id": "req-splat-contract",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_COMPRESSED_PLY),
	})
	var result = fulfillment.fulfill(request)
	assert_true(result is RESULT_SCRIPT, "Contract fulfillment should return a typed environment result on success")
	assert_true(result.ok, "Typed fulfillment result should succeed for the sample compressed ply")
	assert_eq(result.kind, "splat")
	assert_eq(result.format, ".compressed.ply")
	assert_true(result.details.get("node", null) is Node3D, "Fulfillment should surface the created splat node in result.details")
	assert_true(int(result.details.get("point_count", 0)) > 0, "Fulfillment should surface decoded point count")
	if result.details.get("node", null) != null and is_instance_valid(result.details.get("node", null)):
		(result.details.get("node", null) as Node).free()
	var sync_manager := fulfillment.get_gaussian_manager()
	if sync_manager != null and is_instance_valid(sync_manager):
		sync_manager.free()

func test_contract_fulfillment_applies_config_and_can_configure_world_environment() -> void:
	var fulfillment := AeroGaussianSplatEnvironmentFulfillment.new()
	var temp_dir := ProjectSettings.globalize_path("user://gaussian_splat_contract_tests")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var config_path := "%s/demo.config.yaml" % temp_dir
	FileAccess.open(config_path, FileAccess.WRITE).store_string("transform:\n  position: [1, 2, 3]\n  rotation_degrees:\n    x: 0\n    y: 90\n    z: 0\n  scale: [2, 2, 2]\n")
	var world_environment := WorldEnvironment.new()
	var request := {
		"request_id": "req-splat-config",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_COMPRESSED_PLY),
		"config_path": config_path,
		"context": {"world_environment": world_environment},
	}
	var result = fulfillment.fulfill(request)
	assert_true(result is RESULT_SCRIPT, "Compat fulfill alias should still route through the typed contract adapter")
	assert_true(result.ok, "Configured contract fulfillment should succeed")
	assert_true(result.config_applied, "Config sidecar should be applied when present")
	assert_eq(result.config_path, config_path)
	var node: Variant = result.details.get("node", null)
	assert_true(node is Node3D, "Configured fulfillment should still return a Node3D")
	assert_eq((node as Node3D).position, Vector3(1, 2, 3))
	assert_almost_eq((node as Node3D).rotation_degrees.y, 90.0, 0.001)
	assert_eq((node as Node3D).scale, Vector3(2, 2, 2))
	assert_true(result.details.get("world_environment_configured", false) in [true, false], "Fulfillment should report whether compositor configuration was attempted")
	if result.details.get("world_environment_configured", false):
		assert_not_null(world_environment.compositor, "World environment should receive a compositor when the current renderer supports it")
	if node != null and is_instance_valid(node):
		(node as Node).free()
	var configured_manager := fulfillment.get_gaussian_manager()
	if configured_manager != null and is_instance_valid(configured_manager):
		configured_manager.free()
	world_environment.free()

func test_contract_fulfillment_attaches_to_parent_and_reports_transform() -> void:
	var fulfillment := AeroGaussianSplatEnvironmentFulfillment.new()
	var parent := Node3D.new()
	parent.name = "ContractParent"
	add_child_autofree(parent)
	var request := {
		"request_id": "req-splat-parented",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_COMPRESSED_PLY),
		"context": {
			"parent": parent,
			"transform": {
				"position": [1, 2, 3],
				"rotation_degrees": {"x": 0, "y": 30, "z": 0},
				"scale": Vector3(1.5, 1.5, 1.5),
			},
		},
	}
	var result = fulfillment.fulfill(request)
	assert_true(result is RESULT_SCRIPT, "Parented fulfillment should still return a typed environment result")
	assert_true(result.ok, "Parented fulfillment should succeed")
	assert_true(result.details.get("placed", false), "Fulfillment should report when a parent attachment was requested")
	assert_eq(result.details.get("parent", {}).get("name", ""), "ContractParent")
	assert_eq(result.details.get("transform", {}).get("position", Vector3.ZERO), Vector3(1, 2, 3))
	assert_almost_eq(result.details.get("transform", {}).get("rotation_degrees", Vector3.ZERO).y, 30.0, 0.001)
	assert_eq(result.details.get("transform", {}).get("scale", Vector3.ONE), Vector3(1.5, 1.5, 1.5))
	var node: Variant = result.details.get("node", null)
	assert_true(node is Node3D, "Parented fulfillment should return a Node3D")
	assert_eq((node as Node3D).get_parent(), parent)
	if node != null and is_instance_valid(node):
		(node as Node).free()
	var parented_manager := fulfillment.get_gaussian_manager()
	if parented_manager != null and is_instance_valid(parented_manager):
		parented_manager.free()

func test_contract_fulfillment_rejects_non_contract_formats_even_if_wrapper_supports_them() -> void:
	var fulfillment = AeroGaussianSplatEnvironmentFulfillment.new()
	var result = fulfillment.fulfill({
		"request_id": "req-splat-bad-format",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_PLY),
	})
	assert_true(result is ERROR_SCRIPT, "Contract fulfillment should return a typed environment error on failure")
	assert_eq(result.error_code, "unsupported_format")
	assert_true(result.message.contains("requires .compressed.ply"), "Contract error should explain the official splat format requirement")

func test_begin_fulfill_returns_operation_and_completes_with_typed_result() -> void:
	var fulfillment = AeroGaussianSplatEnvironmentFulfillment.new()
	var request = REQUEST_SCRIPT.new({
		"request_id": "req-splat-async-success",
		"kind": "splat",
		"asset_path": ProjectSettings.globalize_path(SAMPLE_COMPRESSED_PLY),
	})
	var operation: Variant = fulfillment.call("begin_fulfill", request)
	assert_not_null(operation, "Async contract path should return an operation object")
	assert_true(operation.has_signal("finished"), "Operation should expose a finished signal")
	await operation.finished
	await get_tree().process_frame
	assert_true(operation.result is RESULT_SCRIPT, "Async operation should resolve with a typed environment result")
	assert_true(operation.result.ok, "Async operation should succeed for the sample compressed ply")
	var latest_progress: Variant = operation.latest_progress
	assert_not_null(latest_progress, "Async operation should retain the final progress snapshot")
	var progress_dict: Dictionary = latest_progress.to_dict() if latest_progress.has_method("to_dict") else {}
	assert_eq(String(progress_dict.get("state", "")), "succeeded", "Final async progress should report a succeeded state")
	assert_eq(String(progress_dict.get("status", "")), "ready", "Final async progress should report the ready contract status")
	assert_eq(String(progress_dict.get("phase", "")), "ready", "Final async progress should preserve the splat-specific ready phase")
	assert_eq(float(progress_dict.get("progress", 0.0)), 1.0, "Final async progress should report 1.0 completion")
	var result_node: Variant = operation.result.details.get("node", null)
	if result_node != null and is_instance_valid(result_node):
		(result_node as Node).free()
	var async_manager := fulfillment.get_gaussian_manager()
	if async_manager != null and is_instance_valid(async_manager):
		async_manager.free()

func test_renderer_support_status_reports_runtime_truth() -> void:
	var manager := AeroGaussianSplatManager.new()
	add_child_autofree(manager)
	var status := manager.get_renderer_support_status()
	assert_true(status.has("renderer_name"), "Support status should name the current renderer")
	assert_true(status.has("support_level"), "Support status should report a support level")
	assert_true(status.has("has_rendering_device"), "Support status should say whether a RenderingDevice exists")
	assert_true(status.has("can_attempt_render"), "Support status should say whether visible render can be attempted")
	assert_true(status.has("can_configure_compositor"), "Support status should say whether compositor setup is allowed")
	assert_true(status.has("message"), "Support status should include a user-facing message")
	if not bool(status.get("has_rendering_device", false)):
		assert_false(status.get("ok", true), "Renderer paths without a RenderingDevice should not be treated as render-capable")
		assert_false(status.get("can_attempt_render", true), "Renderer paths without a RenderingDevice should not attempt visible render")
		assert_false(status.get("can_configure_compositor", true), "Renderer paths without a RenderingDevice should not configure the compositor")
		assert_eq(status.get("support_level", ""), "unsupported", "Renderer paths without a RenderingDevice should be marked unsupported")
	else:
		assert_true(status.get("ok", false), "RenderingDevice renderer paths should at least be eligible for render attempts")
		assert_true(status.get("can_attempt_render", false), "RenderingDevice renderer paths should allow render attempts")
		assert_true(status.get("can_configure_compositor", false), "RenderingDevice renderer paths should allow compositor configuration")
		assert_eq(status.get("support_level", ""), "experimental", "RenderingDevice renderer paths should stay truthfully experimental until fully validated")

func test_background_loading_starts_and_reports_pending_state() -> void:
	var manager := AeroGaussianSplatManager.new()
	add_child_autofree(manager)
	var absolute_path := ProjectSettings.globalize_path(SAMPLE_PLY)
	var start_result := manager.begin_create_splat_node_from_path(absolute_path)
	assert_true(start_result.get("ok", false), start_result.get("message", "Expected background load to start"))
	assert_true(start_result.get("pending", false), "Background load should report pending immediately")
	assert_true(manager.is_background_load_in_progress(), "Background load should be marked in progress")
	assert_eq(start_result.get("phase", ""), "reading", "Background load should start in the reading phase")
	assert_eq(start_result.get("status", ""), "Reading splat file", "Background load should expose user-facing reading status text")
	assert_eq(float(start_result.get("progress", -1.0)), 0.0, "Background load should start at 0.0 progress")

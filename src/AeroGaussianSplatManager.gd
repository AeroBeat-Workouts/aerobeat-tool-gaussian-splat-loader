class_name AeroGaussianSplatManager
extends "gaussian_splat_runtime.gd"

func load_splat(asset_path: String, parent: Node = null, options: Dictionary = {}) -> Dictionary:
	var load_result := create_splat_node_from_path(asset_path)
	if not load_result.get("ok", false):
		return load_result

	var node: Variant = load_result.get("node", null)
	if not (node is Node3D):
		return _error(ERR_BUG, "Gaussian splat load did not produce a Node3D instance")

	var placement_result := place_splat(node as Node3D, parent, options)
	if not placement_result.get("ok", false):
		if node != null and is_instance_valid(node):
			(node as Node).queue_free()
		return placement_result

	load_result["placed"] = placement_result.get("placed", false)
	load_result["parent"] = placement_result.get("parent", {})
	load_result["transform_applied"] = placement_result.get("transform_applied", false)
	load_result["transform"] = placement_result.get("transform", {})
	load_result["world_environment_configured"] = placement_result.get("world_environment_configured", false)
	load_result["compatibility"] = placement_result.get("compatibility", {})
	return load_result

func place_splat(node: Node3D, parent: Node = null, options: Dictionary = {}) -> Dictionary:
	if node == null:
		return _error(ERR_INVALID_PARAMETER, "No gaussian splat node was provided for placement")

	if parent != null:
		if node.get_parent() == null:
			parent.add_child(node)
		elif node.get_parent() != parent:
			node.reparent(parent)

	var normalized_options_result := _normalize_placement_options(options)
	if not normalized_options_result.get("ok", false):
		return _error(ERR_INVALID_PARAMETER, String(normalized_options_result.get("message", "Gaussian splat options were invalid")))
	var normalized_options: Dictionary = normalized_options_result.get("options", {})

	var transform_result := _apply_splat_options(node, normalized_options)
	if not transform_result.get("ok", false):
		return _error(ERR_INVALID_PARAMETER, String(transform_result.get("message", "Gaussian splat options were invalid")))

	var world_environment_configured := false
	var world_environment: Variant = normalized_options.get("world_environment", null)
	if world_environment is WorldEnvironment:
		configure_world_environment(world_environment as WorldEnvironment)
		world_environment_configured = world_environment.compositor != null and world_environment.compositor.compositor_effects.size() > 0

	return {
		"ok": true,
		"node": node,
		"placed": parent != null and node.get_parent() == parent,
		"parent": _build_parent_report(node),
		"transform_applied": transform_result.get("applied", false),
		"transform": _build_transform_report(node),
		"world_environment_configured": world_environment_configured,
		"compatibility": normalized_options_result.get("compatibility", {}),
	}

func rotate_splat(node: Node3D, rotation_degrees: Vector3) -> Dictionary:
	if node == null:
		return _error(ERR_INVALID_PARAMETER, "No gaussian splat node was provided for rotation")
	node.rotation_degrees = rotation_degrees
	return {
		"ok": true,
		"node": node,
		"rotation_degrees": node.rotation_degrees,
		"transform": _build_transform_report(node),
	}

func unload_splat(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return _error(ERR_INVALID_PARAMETER, "No gaussian splat node was provided for unload")
	node.queue_free()
	return {
		"ok": true,
		"unloaded": true,
	}

func get_default_transform() -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"rotation_degrees": Vector3.ZERO,
		"scale": Vector3.ONE,
	}

func normalize_transform(transform_config: Dictionary) -> Dictionary:
	var result := _normalize_transform_result(transform_config)
	if result.get("ok", false):
		return result.get("transform", get_default_transform())
	return get_default_transform()

func _normalize_placement_options(options: Dictionary) -> Dictionary:
	var normalized_options := {
		"world_environment": options.get("world_environment", null),
	}
	var compatibility := {
		"used_flat_transform_keys": false,
		"used_flat_rotation_radians": false,
	}

	if options.has("transform"):
		var transform_value: Variant = options.get("transform", {})
		if not (transform_value is Dictionary):
			return {
				"ok": false,
				"message": "Gaussian splat option 'transform' must be a Dictionary.",
			}
		var normalized_transform_result := _normalize_transform_result(Dictionary(transform_value))
		if not normalized_transform_result.get("ok", false):
			return normalized_transform_result
		normalized_options["transform"] = normalized_transform_result["transform"]
	elif options.has("position") or options.has("rotation_degrees") or options.has("scale"):
		compatibility["used_flat_transform_keys"] = true
		var legacy_transform := {}
		if options.has("position"):
			legacy_transform["position"] = options["position"]
		if options.has("rotation_degrees"):
			legacy_transform["rotation_degrees"] = options["rotation_degrees"]
		if options.has("scale"):
			legacy_transform["scale"] = options["scale"]
		var normalized_legacy_transform_result := _normalize_transform_result(legacy_transform)
		if not normalized_legacy_transform_result.get("ok", false):
			return normalized_legacy_transform_result
		normalized_options["transform"] = normalized_legacy_transform_result["transform"]

	if options.has("rotation") and not options.has("transform") and not options.has("rotation_degrees"):
		var rotation_result := _coerce_vector3_option(options["rotation"], "rotation")
		if not rotation_result.get("ok", false):
			return rotation_result
		normalized_options["legacy_rotation"] = rotation_result["value"]
		compatibility["used_flat_rotation_radians"] = true

	return {
		"ok": true,
		"options": normalized_options,
		"compatibility": compatibility,
	}

func _apply_splat_options(node: Node3D, options: Dictionary) -> Dictionary:
	var applied := false
	var transform := _dictionary_or_empty(options.get("transform", {}))

	if transform.has("position"):
		node.position = transform["position"]
		applied = true

	if transform.has("rotation_degrees"):
		node.rotation_degrees = transform["rotation_degrees"]
		applied = true
	elif options.has("legacy_rotation"):
		node.rotation = options["legacy_rotation"]
		applied = true

	if transform.has("scale"):
		node.scale = transform["scale"]
		applied = true

	return {
		"ok": true,
		"applied": applied,
	}

func _coerce_vector3_option(value: Variant, option_name: String) -> Dictionary:
	if value is Vector3:
		return {
			"ok": true,
			"value": value,
		}
	if value is Array and value.size() == 3:
		return {
			"ok": true,
			"value": Vector3(float(value[0]), float(value[1]), float(value[2])),
		}
	if value is Dictionary and value.has("x") and value.has("y") and value.has("z"):
		return {
			"ok": true,
			"value": Vector3(float(value["x"]), float(value["y"]), float(value["z"])),
		}
	return {
		"ok": false,
		"message": "Gaussian splat option '%s' must be a Vector3, [x, y, z] array, or {x, y, z} dictionary" % option_name,
	}

func _normalize_transform_result(transform_config: Dictionary) -> Dictionary:
	var normalized := get_default_transform()
	for key in ["position", "rotation_degrees", "scale"]:
		if not transform_config.has(key):
			continue
		var value_result := _coerce_vector3_option(transform_config[key], "transform.%s" % key)
		if not value_result.get("ok", false):
			return value_result
		normalized[key] = value_result["value"]
	return {
		"ok": true,
		"transform": normalized,
	}

func _build_transform_report(node: Node3D) -> Dictionary:
	var parent_node := node.get_parent_node_3d()
	return {
		"position": node.position,
		"rotation": node.rotation,
		"rotation_degrees": node.rotation_degrees,
		"scale": node.scale,
		"global_position": node.global_position if node.is_inside_tree() else node.position,
		"global_rotation": node.global_rotation if node.is_inside_tree() else node.rotation,
		"global_rotation_degrees": node.global_rotation_degrees if node.is_inside_tree() else node.rotation_degrees,
		"global_scale": node.global_basis.get_scale() if node.is_inside_tree() else node.scale,
		"parent_name": parent_node.name if parent_node != null else "",
	}

func _build_parent_report(node: Node3D) -> Dictionary:
	var parent_node := node.get_parent()
	if parent_node == null:
		return {
			"attached": false,
			"name": "",
			"path": "",
		}
	return {
		"attached": true,
		"name": String(parent_node.name),
		"path": String(parent_node.get_path()) if node.is_inside_tree() else String(parent_node.name),
	}

func _dictionary_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return Dictionary(value).duplicate(true)
	return {}

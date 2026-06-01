extends Node3D

const LOAD_POSITION := Vector3(1.0, 0.35, -0.25)
const LOAD_ROTATION_DEGREES := Vector3(0.0, 45.0, 0.0)
const LOAD_SCALE := Vector3(1.5, 1.5, 1.5)

var _tool_manager: AeroGaussianSplatManager
var _world_environment: WorldEnvironment
var _camera: Camera3D
var _loaded_splat: Node3D
var _splat_anchor: Node3D
var _status_label: Label
var _last_load_result: Dictionary = {}

func _ready() -> void:
	_tool_manager = AeroGaussianSplatManager.new()
	add_child(_tool_manager)
	_setup_scene()

	var sample_path := ProjectSettings.globalize_path("res://assets/splats/demo.ply")
	var result := _tool_manager.load_splat(sample_path, _splat_anchor, {
		"transform": {
			"position": LOAD_POSITION,
			"rotation_degrees": LOAD_ROTATION_DEGREES,
			"scale": LOAD_SCALE,
		},
		"world_environment": _world_environment,
	})
	_last_load_result = result.duplicate(true)
	if result.get("ok", false):
		_loaded_splat = result.get("node", null)
		print("Gaussian splat load ok: %s (%d points, support=%s)" % [sample_path, int(result.get("point_count", 0)), String(_tool_manager.get_renderer_support_status().get("support_level", "unknown"))])
		print(_build_status_text())
	else:
		push_warning(result.get("message", "Unknown splat load failure"))
	_update_status_label()

func _process(_delta: float) -> void:
	_update_status_label()

func _setup_scene() -> void:
	_camera = Camera3D.new()
	_camera.look_at_from_position(Vector3(0.0, 1.5, 6.0), Vector3(0.0, 0.5, 0.0))
	add_child(_camera)

	_world_environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.07, 0.09)
	_world_environment.environment = env
	add_child(_world_environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	add_child(light)

	_splat_anchor = Node3D.new()
	_splat_anchor.name = "SplatAnchor"
	_splat_anchor.position = Vector3(-0.75, 0.5, 0.0)
	_splat_anchor.rotation_degrees = Vector3(0.0, 20.0, 0.0)
	add_child(_splat_anchor)
	_add_anchor_visuals()
	_add_status_overlay()

func _add_anchor_visuals() -> void:
	var axis_materials := {
		"x": _make_unshaded_material(Color(1.0, 0.35, 0.35)),
		"y": _make_unshaded_material(Color(0.35, 1.0, 0.45)),
		"z": _make_unshaded_material(Color(0.35, 0.65, 1.0)),
	}
	_splat_anchor.add_child(_make_axis_box("AxisX", Vector3(0.6, 0.03, 0.03), Vector3(0.3, 0.0, 0.0), axis_materials["x"]))
	_splat_anchor.add_child(_make_axis_box("AxisY", Vector3(0.03, 0.6, 0.03), Vector3(0.0, 0.3, 0.0), axis_materials["y"]))
	_splat_anchor.add_child(_make_axis_box("AxisZ", Vector3(0.03, 0.03, 0.6), Vector3(0.0, 0.0, 0.3), axis_materials["z"]))
	var pivot := MeshInstance3D.new()
	pivot.name = "AnchorPivot"
	var pivot_mesh := SphereMesh.new()
	pivot_mesh.radius = 0.06
	pivot_mesh.height = 0.12
	pivot.mesh = pivot_mesh
	pivot.material_override = _make_unshaded_material(Color(1.0, 0.95, 0.4))
	_splat_anchor.add_child(pivot)

func _add_status_overlay() -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "StatusCanvas"
	add_child(canvas_layer)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.position = Vector2(16.0, 16.0)
	_status_label.size = Vector2(1100.0, 260.0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	canvas_layer.add_child(_status_label)

func _make_axis_box(name: String, size: Vector3, local_position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = local_position
	mesh_instance.material_override = material
	return mesh_instance

func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func _update_status_label() -> void:
	if _status_label == null:
		return
	_status_label.text = _build_status_text()

func _build_status_text() -> String:
	var support: Dictionary = _tool_manager.get_renderer_support_status() if _tool_manager != null else {}
	var transform: Dictionary = _last_load_result.get("transform", _current_transform_report())
	var parent_report: Dictionary = _last_load_result.get("parent", {})
	var status_lines := PackedStringArray([
		"Gaussian Splat Smoke Testbed",
		"Renderer support: %s (%s)" % [String(support.get("support_level", "unknown")), String(support.get("renderer_name", "unknown"))],
		"Known limitation: visible splat rendering remains experimental; trust the transform report first.",
		"Anchor transform: pos=%s rot=%s scale=%s" % [_format_vector3(_splat_anchor.position), _format_vector3(_splat_anchor.rotation_degrees), _format_vector3(_splat_anchor.scale)],
		"Requested local transform: pos=%s rot=%s scale=%s" % [_format_vector3(LOAD_POSITION), _format_vector3(LOAD_ROTATION_DEGREES), _format_vector3(LOAD_SCALE)],
		"Actual local transform: pos=%s rot=%s scale=%s" % [_format_vector3(transform.get("position", Vector3.ZERO)), _format_vector3(transform.get("rotation_degrees", Vector3.ZERO)), _format_vector3(transform.get("scale", Vector3.ONE))],
		"Actual global transform: pos=%s rot=%s scale=%s" % [_format_vector3(transform.get("global_position", Vector3.ZERO)), _format_vector3(transform.get("global_rotation_degrees", Vector3.ZERO)), _format_vector3(transform.get("global_scale", Vector3.ONE))],
		"Parent attachment: attached=%s name=%s path=%s" % [str(parent_report.get("attached", false)), String(parent_report.get("name", "")), String(parent_report.get("path", ""))],
		"Load result: ok=%s placed=%s transformed=%s points=%d" % [str(_last_load_result.get("ok", false)), str(_last_load_result.get("placed", false)), str(_last_load_result.get("transform_applied", false)), int(_last_load_result.get("point_count", 0))],
	])
	return "\n".join(status_lines)

func _current_transform_report() -> Dictionary:
	if _loaded_splat == null or not is_instance_valid(_loaded_splat):
		return {}
	return {
		"position": _loaded_splat.position,
		"rotation_degrees": _loaded_splat.rotation_degrees,
		"scale": _loaded_splat.scale,
		"global_position": _loaded_splat.global_position,
		"global_rotation_degrees": _loaded_splat.global_rotation_degrees,
		"global_scale": _loaded_splat.global_basis.get_scale(),
	}

func _format_vector3(value: Variant) -> String:
	var vector: Vector3 = value if value is Vector3 else Vector3.ZERO
	return "(%.2f, %.2f, %.2f)" % [vector.x, vector.y, vector.z]

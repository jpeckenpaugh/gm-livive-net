class_name ExcavationFinale
extends Node3D

## Whole-cube extraction finale for Gem Miner.
##
## Owned by VolumetricCubeController, instantiated from code (no scene edit).
## Schedules every shell tile through VolumetricTile3D.play_extraction(), pulls
## the camera back, then reveals a procedural faceted mother-lode core. All
## animation is driven by one finite master tween plus a small _process spin;
## there are no looping tweens, timers, or awaits. cancel() is restart-safe.

signal status_changed(text: String)

const SWEEP_OFFSET: float = 0.10
const SWEEP_SPAN: float = 2.30
const GEM_BIAS: float = 0.10
const TILE_TAIL: float = 0.70

const CAMERA_OUT_DELAY: float = 0.20
const CAMERA_OUT_DIST: float = 2.5
const CAMERA_OUT_TIME: float = 1.2
const CAMERA_IN_DIST: float = 1.5
const CAMERA_IN_TIME: float = 1.0
const REVEAL_HOLD: float = 1.40

const CORE_RADIUS_FACTOR: float = 0.49
const CORE_Y_SCALE: float = 1.10
const CORE_SPAWN_SCALE: float = 0.15
const CORE_GROW_TIME: float = 0.65
const SPIN_SPEED: float = 0.22
const HEART_SPIN_SPEED: float = -0.35

const LIGHT_BASE: float = 2.2
const LIGHT_WAVE: float = 0.3
const LIGHT_FLASH: float = 4.5
const LIGHT_FLASH_DECAY: float = 6.0

var _running: bool = false
var _finished: bool = false

var _rind: MeshInstance3D = null
var _camera: Camera3D = null
var _gems_secured: int = 0
var _gems_cracked: int = 0

var _cube_half: float = 4.5
var _core_radius: float = 3.92
var _cam_base: Vector3 = Vector3.ZERO
var _cam_dolly_ready: bool = false
var _elapsed: float = 0.0

var _core_root: Node3D = null
var _heart: MeshInstance3D = null
var _core_light: OmniLight3D = null

var _seq: Tween = null
var _cam_tween: Tween = null
var _core_tween: Tween = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)

func is_running() -> bool:
	return _running

func has_finished() -> bool:
	return _finished

## Schedules the whole-cube sequence. Safe to call once per claim; the
## controller latches victory, and this method also refuses a second start.
func begin(tiles: Dictionary, rind: MeshInstance3D, camera: Camera3D,
		cube_size: int, spacing: float, gems_secured: int,
		gems_cracked: int = 0) -> void:
	if _running or _finished:
		return
	if not is_inside_tree():
		return

	_running = true
	_finished = false
	_rind = rind
	_camera = camera
	_gems_secured = gems_secured
	_gems_cracked = gems_cracked
	_cube_half = (cube_size - 1) * 0.5 * spacing
	_core_radius = maxf((cube_size - 2) * spacing * CORE_RADIUS_FACTOR, 1.0)
	_cam_base = camera.position if camera != null else Vector3.ZERO
	_cam_dolly_ready = camera != null
	_elapsed = 0.0

	var max_delay: float = _schedule_tiles(tiles, spacing)
	var reveal_at: float = maxf(max_delay + TILE_TAIL, 0.90)

	_kill_seq_tween()
	_seq = create_tween()
	_seq.tween_interval(CAMERA_OUT_DELAY)
	_seq.tween_callback(_start_camera_out)
	_seq.tween_interval(maxf(reveal_at - CAMERA_OUT_DELAY, 0.01))
	_seq.tween_callback(_reveal_core)
	_seq.tween_interval(REVEAL_HOLD)
	_seq.tween_callback(_finish)

## Kills everything this helper owns and restores the pre-finale board view.
## Must be called before the controller frees / rebuilds the elastic pivot.
func cancel() -> void:
	_running = false
	_finished = false
	_elapsed = 0.0
	_kill_seq_tween()
	_kill_cam_tween()
	_kill_core_tween()
	set_process(false)

	if _core_root != null and is_instance_valid(_core_root):
		_core_root.free()
	_core_root = null
	_heart = null
	_core_light = null

	if _rind != null and is_instance_valid(_rind):
		_rind.visible = true
	_rind = null
	_camera = null
	_cam_dolly_ready = false
	_gems_secured = 0
	_gems_cracked = 0

func _process(delta: float) -> void:
	if _core_root == null or not is_instance_valid(_core_root):
		return
	_elapsed += delta
	_core_root.rotation.y += SPIN_SPEED * delta
	if _heart != null and is_instance_valid(_heart):
		_heart.rotation.y += HEART_SPIN_SPEED * delta
	if _core_light != null and is_instance_valid(_core_light):
		var idle: float = LIGHT_BASE + sin(_elapsed * 1.8) * LIGHT_WAVE
		var flash: float = LIGHT_FLASH * exp(-_elapsed * LIGHT_FLASH_DECAY)
		_core_light.light_energy = maxf(idle, flash)

# --- Sweep -------------------------------------------------------------------

## Returns the largest delay handed to a tile, so the core reveal can wait for
## the final crystal pulse.
func _schedule_tiles(tiles: Dictionary, spacing: float) -> float:
	var step: float = maxf(spacing, 0.001)
	var entries: Array = []
	for value in tiles.values():
		var tile := value as VolumetricTile3D
		if tile == null or not is_instance_valid(tile) or not tile.is_inside_tree():
			continue
		var p: Vector3 = tile.global_position
		entries.append({
			"tile": tile,
			"layer": int(round((_cube_half - p.z) / step)),
			"radial": Vector2(p.x, p.y).length(),
			"angle": atan2(p.y, p.x),
		})

	if entries.is_empty():
		return 0.0

	entries.sort_custom(_compare_entries)

	var count: int = entries.size()
	var max_delay: float = 0.0
	for i in range(count):
		var entry: Dictionary = entries[i]
		var t: float = 0.0 if count <= 1 else float(i) / float(count - 1)
		var delay: float = SWEEP_OFFSET + t * SWEEP_SPAN
		var tile: VolumetricTile3D = entry["tile"]
		if tile.is_gem:
			delay += GEM_BIAS
		max_delay = maxf(max_delay, delay)
		tile.play_extraction(delay)
	return max_delay

## Camera-depth peel: near face first, then each perimeter ring, far face last.
## Within a layer the wave travels from the view axis outward, then by angle.
static func _compare_entries(a: Dictionary, b: Dictionary) -> bool:
	var a_layer: int = a["layer"]
	var b_layer: int = b["layer"]
	if a_layer != b_layer:
		return a_layer < b_layer
	var a_radial: float = a["radial"]
	var b_radial: float = b["radial"]
	if not is_equal_approx(a_radial, b_radial):
		return a_radial < b_radial
	return float(a["angle"]) < float(b["angle"])

# --- Camera ------------------------------------------------------------------

func _start_camera_out() -> void:
	if not _running or _camera == null or not is_instance_valid(_camera):
		return
	_cam_base = _camera.position
	_cam_dolly_ready = true
	_kill_cam_tween()
	_cam_tween = create_tween()
	_cam_tween.tween_property(
		_camera, "position",
		_cam_base + Vector3(0.0, 0.0, CAMERA_OUT_DIST),
		CAMERA_OUT_TIME
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _start_camera_in() -> void:
	if _camera == null or not is_instance_valid(_camera) or not _cam_dolly_ready:
		return
	_kill_cam_tween()
	_cam_tween = create_tween()
	_cam_tween.tween_property(
		_camera, "position",
		_cam_base + Vector3(0.0, 0.0, CAMERA_OUT_DIST - CAMERA_IN_DIST),
		CAMERA_IN_TIME
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

# --- Core reveal -------------------------------------------------------------

func _reveal_core() -> void:
	if not _running:
		return
	if _rind != null and is_instance_valid(_rind):
		_rind.visible = false
	_build_core()
	_start_camera_in()
	set_process(true)
	status_changed.emit("MOTHER LODE REVEALED — all six faces surveyed · %s…" % _secured_phrase())

func _build_core() -> void:
	if _core_root != null and is_instance_valid(_core_root):
		return

	_core_root = Node3D.new()
	_core_root.name = "MotherLodeCore"
	_core_root.rotation_degrees = Vector3(-6.0, 24.0, 3.0)
	_core_root.scale = Vector3.ONE * CORE_SPAWN_SCALE
	add_child(_core_root)

	var body := MeshInstance3D.new()
	body.name = "FacetedBody"
	body.mesh = _make_icosphere(_core_radius, 1)
	body.material_override = _make_body_material()
	_core_root.add_child(body)

	_heart = MeshInstance3D.new()
	_heart.name = "GemHeart"
	_heart.mesh = _make_icosphere(_core_radius * 0.60, 0)
	_heart.material_override = _make_heart_material()
	_heart.rotation_degrees = Vector3(18.0, 30.0, 12.0)
	_core_root.add_child(_heart)

	_core_light = OmniLight3D.new()
	_core_light.name = "CoreLight"
	_core_light.light_color = Color(0.45, 0.95, 1.0)
	_core_light.light_energy = LIGHT_FLASH
	_core_light.omni_range = 16.0
	_core_light.shadow_enabled = false
	_core_root.add_child(_core_light)

	_kill_core_tween()
	_core_tween = create_tween()
	_core_tween.tween_property(
		_core_root, "scale",
		Vector3(1.0, CORE_Y_SCALE, 1.0),
		CORE_GROW_TIME
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _finish() -> void:
	if not _running:
		return
	_running = false
	_finished = true
	status_changed.emit(
		"CLAIM COMPLETE — all six faces surveyed · %s" % _secured_phrase()
	)

## Secured always includes cracked gems; the parenthetical only clarifies how
## many of the secured gems were cracked rather than cleanly staked.
func _secured_phrase() -> String:
	var noun: String = "gem" if _gems_secured == 1 else "gems"
	if _gems_cracked > 0:
		return "%d %s secured (%d cracked)" % [_gems_secured, noun, _gems_cracked]
	return "%d %s secured" % [_gems_secured, noun]

func _make_body_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.90, 0.94, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	mat.metallic = 0.30
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.85, 0.95)
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat

func _make_heart_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 1.0, 0.85, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.35, 1.0, 0.85)
	mat.emission_energy_multiplier = 3.0
	return mat

## Flat-shaded icosphere built from an icosahedron. Each triangle gets three
## unique vertices and one face normal, so low subdivision counts read as cut
## facets instead of a smooth ball.
func _make_icosphere(radius: float, subdivisions: int) -> ArrayMesh:
	var t: float = (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in range(verts.size()):
		verts[i] = verts[i].normalized()

	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7),
		Vector3i(0, 7, 10), Vector3i(0, 10, 11), Vector3i(1, 5, 9),
		Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6),
		Vector3i(7, 1, 8), Vector3i(3, 9, 4), Vector3i(3, 4, 2),
		Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10),
		Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]

	for _s in range(subdivisions):
		var next_faces: Array[Vector3i] = []
		for face in faces:
			var a: Vector3 = verts[face.x]
			var b: Vector3 = verts[face.y]
			var c: Vector3 = verts[face.z]
			var ab: Vector3 = ((a + b) * 0.5).normalized()
			var bc: Vector3 = ((b + c) * 0.5).normalized()
			var ca: Vector3 = ((c + a) * 0.5).normalized()
			var iab: int = verts.size()
			verts.append(ab)
			var ibc: int = verts.size()
			verts.append(bc)
			var ica: int = verts.size()
			verts.append(ca)
			next_faces.append(Vector3i(face.x, iab, ica))
			next_faces.append(Vector3i(face.y, ibc, iab))
			next_faces.append(Vector3i(face.z, ica, ibc))
			next_faces.append(Vector3i(iab, ibc, ica))
		faces = next_faces

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var a: Vector3 = verts[face.x].normalized() * radius
		var b: Vector3 = verts[face.y].normalized() * radius
		var c: Vector3 = verts[face.z].normalized() * radius
		var n: Vector3 = (b - a).cross(c - a)
		if n.dot(a + b + c) < 0.0:
			var tmp: Vector3 = b
			b = c
			c = tmp
			n = -n
		n = n.normalized()
		st.set_normal(n)
		st.add_vertex(a)
		st.set_normal(n)
		st.add_vertex(b)
		st.set_normal(n)
		st.add_vertex(c)
	return st.commit()

func _kill_seq_tween() -> void:
	if _seq != null and _seq.is_valid():
		_seq.kill()
	_seq = null

func _kill_cam_tween() -> void:
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = null

func _kill_core_tween() -> void:
	if _core_tween != null and _core_tween.is_valid():
		_core_tween.kill()
	_core_tween = null

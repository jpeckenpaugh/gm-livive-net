class_name VolumetricTile3D
extends Area3D

signal tile_clicked(coord: Vector3i, button_index: int)
signal tile_pressed(coord: Vector3i)

const TILE_SIZE: float = 0.94
const FACE_LABEL_OFFSET: float = 0.49
const STAKE_OFFSET: float = 0.488
const CRYSTAL_OFFSET: float = 0.465
const STAKE_BAR_SIZE: Vector3 = Vector3(1.20, 0.16, 0.05)
const ROCK_SINK: float = 0.50
const GEM_SINK: float = 0.35
const ROCK_SHRINK: float = 0.85
const GEM_RISE: float = 0.40
const ROCK_ANIM_TIME: float = 0.45
const GEM_ANIM_TIME: float = 0.55
const LONG_PRESS_SECONDS: float = 0.35

var coord: Vector3i = Vector3i.ZERO
var exterior_faces: Array[int] = []

var is_gem: bool = false
var is_revealed: bool = false
var is_marked: bool = false
var is_cracked: bool = false

# Map of Face enum -> int (count of gems touching this cell on that specific face)
var face_neighbor_gems: Dictionary = {}

var solid_mesh: MeshInstance3D
# Map of Face enum -> Label3D (one label per exterior face of this voxel)
var face_labels: Dictionary = {}
# Lazily built overlays; null until first marked/cracked.
var stake_overlay: Node3D = null
var crystal_overlay: Node3D = null
# Map of Face enum -> Node3D group holding this face's overlay meshes
var stake_face_groups: Dictionary = {}
var crystal_face_groups: Dictionary = {}

var is_pressing_left: bool = false
var press_start_time: float = 0.0
var long_press_triggered: bool = false

var _is_hovered: bool = false
var _extraction_started: bool = false
var _extraction_tween: Tween
var _rock_tween: Tween
var _lift_tween: Tween
var _pulse_tween: Tween

# Outward normal for each face enum in cube coordinates
const FACE_NORMALS = [
	Vector3(0, 0, 1),   # FRONT (+Z)
	Vector3(1, 0, 0),   # RIGHT (+X)
	Vector3(0, 0, -1),  # BACK (-Z)
	Vector3(-1, 0, 0),  # LEFT (-X)
	Vector3(0, 1, 0),   # TOP (+Y)
	Vector3(0, -1, 0)   # BOTTOM (-Y)
]

const NUMBER_COLORS = [
	Color(0.2, 0.4, 1.0),   # 1: Blue
	Color(0.2, 0.8, 0.2),   # 2: Green
	Color(1.0, 0.2, 0.2),   # 3: Red
	Color(0.3, 0.1, 0.7),   # 4: Dark Blue / Purple
	Color(0.6, 0.1, 0.1),   # 5: Maroon
	Color(0.1, 0.7, 0.7),   # 6: Cyan
	Color(0.1, 0.1, 0.1),   # 7: Black
	Color(0.5, 0.5, 0.5)    # 8: Gray
]

# Shared, immutable visual resources. Created once for all 488 tiles.
static var _shared_ready: bool = false
static var _rock_mesh: BoxMesh
static var _rock_shape: BoxShape3D
static var _stake_bar_mesh: BoxMesh
static var _stake_boss_mesh: CylinderMesh
static var _shard_main_mesh: CylinderMesh
static var _shard_small_mesh: CylinderMesh
static var _fracture_mesh: TorusMesh
static var _fissure_long_mesh: BoxMesh
static var _fissure_short_mesh: BoxMesh
static var _mat_rock: StandardMaterial3D
static var _mat_rock_hover: StandardMaterial3D
static var _mat_rock_excavated: StandardMaterial3D
static var _mat_rock_charred: StandardMaterial3D
static var _mat_stake: StandardMaterial3D
static var _mat_gem_intact: StandardMaterial3D
static var _mat_gem_cracked: StandardMaterial3D
static var _mat_crack: StandardMaterial3D

static func _make_material(albedo: Color, roughness: float, metallic: float, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat

static func _ensure_shared_resources() -> void:
	if _shared_ready:
		return
	_shared_ready = true

	_rock_mesh = BoxMesh.new()
	_rock_mesh.size = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)

	_rock_shape = BoxShape3D.new()
	_rock_shape.size = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)

	_stake_bar_mesh = BoxMesh.new()
	_stake_bar_mesh.size = STAKE_BAR_SIZE

	_stake_boss_mesh = CylinderMesh.new()
	_stake_boss_mesh.top_radius = 0.09
	_stake_boss_mesh.bottom_radius = 0.09
	_stake_boss_mesh.height = 0.06
	_stake_boss_mesh.radial_segments = 6
	_stake_boss_mesh.rings = 1
	_stake_boss_mesh.cap_top = true
	_stake_boss_mesh.cap_bottom = true

	_shard_main_mesh = CylinderMesh.new()
	_shard_main_mesh.top_radius = 0.045
	_shard_main_mesh.bottom_radius = 0.15
	_shard_main_mesh.height = 0.30
	_shard_main_mesh.radial_segments = 6
	_shard_main_mesh.rings = 1
	_shard_main_mesh.cap_top = true
	_shard_main_mesh.cap_bottom = false

	_shard_small_mesh = CylinderMesh.new()
	_shard_small_mesh.top_radius = 0.03
	_shard_small_mesh.bottom_radius = 0.085
	_shard_small_mesh.height = 0.18
	_shard_small_mesh.radial_segments = 6
	_shard_small_mesh.rings = 1
	_shard_small_mesh.cap_top = true
	_shard_small_mesh.cap_bottom = false

	_fracture_mesh = TorusMesh.new()
	_fracture_mesh.outer_radius = 0.165
	_fracture_mesh.inner_radius = 0.135
	_fracture_mesh.rings = 3
	_fracture_mesh.ring_segments = 6

	_fissure_long_mesh = BoxMesh.new()
	_fissure_long_mesh.size = Vector3(0.32, 0.030, 0.012)

	_fissure_short_mesh = BoxMesh.new()
	_fissure_short_mesh.size = Vector3(0.22, 0.024, 0.012)

	_mat_rock = _make_material(Color(0.16, 0.17, 0.20), 0.85, 0.05, Color.BLACK, 0.0)
	_mat_rock_hover = _make_material(Color(0.26, 0.28, 0.34), 0.80, 0.05, Color.BLACK, 0.0)
	_mat_rock_excavated = _make_material(Color(0.38, 0.35, 0.30), 0.92, 0.0, Color.BLACK, 0.0)
	_mat_rock_charred = _make_material(Color(0.28, 0.14, 0.12), 0.90, 0.0, Color(0.65, 0.08, 0.04), 0.45)
	_mat_stake = _make_material(Color(1.0, 0.60, 0.12), 0.35, 0.35, Color(1.0, 0.50, 0.06), 0.5)
	_mat_gem_intact = _make_material(Color(0.10, 0.90, 0.94), 0.15, 0.25, Color(0.15, 0.85, 0.95), 1.4)
	_mat_gem_cracked = _make_material(Color(0.24, 0.56, 0.60), 0.18, 0.20, Color(0.10, 0.42, 0.48), 0.45)
	_mat_crack = _make_material(Color(0.90, 0.16, 0.12), 0.55, 0.0, Color(1.0, 0.10, 0.05), 1.0)

func setup(c: Vector3i, ext_faces: Array[int]) -> void:
	coord = c
	exterior_faces = ext_faces
	name = "VTile_%d_%d_%d" % [c.x, c.y, c.z]
	_ensure_shared_resources()

	# Idle tiles must not run _process; it is enabled only during a left press.
	set_process(false)

	# 1. Collision Shape (Real 3D Cube: 0.94 x 0.94 x 0.94)
	var col := CollisionShape3D.new()
	col.shape = _rock_shape
	add_child(col)

	# 2. Solid rock cube mesh (shared mesh + shared state materials)
	solid_mesh = MeshInstance3D.new()
	solid_mesh.mesh = _rock_mesh
	solid_mesh.material_override = _mat_rock
	add_child(solid_mesh)

	# 3. Number labels for each exterior face (eager; no hidden meshes)
	for f in exterior_faces:
		_create_face_label(f)

	# Mouse signal connections
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

# setup() runs before the tile enters the tree; the engine re-enables idle
# processing on tree entry, so enforce the idle state once it is inside.
func _ready() -> void:
	set_process(false)

func _create_face_label(f: int) -> void:
	var lbl := Label3D.new()
	lbl.transform.origin = FACE_NORMALS[f] * FACE_LABEL_OFFSET
	lbl.font_size = 54
	lbl.pixel_size = 0.009
	lbl.double_sided = false
	lbl.no_depth_test = false
	lbl.render_priority = 10
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.visible = false
	add_child(lbl)
	face_labels[f] = lbl

static func _face_basis(normal: Vector3) -> Basis:
	var up := Vector3.UP
	if absf(normal.dot(Vector3.UP)) > 0.9:
		up = Vector3(0, 0, 1)
	var right := up.cross(normal).normalized()
	var real_up := normal.cross(right).normalized()
	return Basis(right, real_up, normal)

# Shards are modelled along local Y (CylinderMesh); map that axis onto +Z and
# optionally lean it toward lean_dir by tilt radians.
static func _shard_transform(pos: Vector3, spin: float, lean_dir: Vector3, tilt: float) -> Transform3D:
	var b := Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3(0, 0, 1), spin)
	if tilt != 0.0 and lean_dir.length_squared() > 0.0001:
		var axis := Vector3(-lean_dir.y, lean_dir.x, 0.0).normalized()
		b = Basis(axis, tilt) * b
	return Transform3D(b, pos)

func _visual_seed() -> int:
	return absi(coord.x * 73856093 ^ coord.y * 19349663 ^ coord.z * 83492791)

func _process(_delta: float) -> void:
	if _extraction_started or not is_pressing_left or long_press_triggered:
		set_process(false)
		return
	var elapsed := (Time.get_ticks_msec() / 1000.0) - press_start_time
	if elapsed >= LONG_PRESS_SECONDS:
		long_press_triggered = true
		set_process(false)
		tile_clicked.emit(coord, MOUSE_BUTTON_RIGHT)

func _cancel_left_press() -> void:
	is_pressing_left = false
	long_press_triggered = false
	press_start_time = 0.0
	set_process(false)

func _on_input_event(_cam: Camera3D, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if _extraction_started:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_pressing_left = true
				press_start_time = Time.get_ticks_msec() / 1000.0
				long_press_triggered = false
				set_process(true)
				tile_pressed.emit(coord)
			else:
				if is_pressing_left and not long_press_triggered:
					tile_clicked.emit(coord, MOUSE_BUTTON_LEFT)
				_cancel_left_press()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_left_press()
			tile_pressed.emit(coord)
			tile_clicked.emit(coord, MOUSE_BUTTON_RIGHT)

func _on_mouse_entered() -> void:
	if _extraction_started:
		return
	_is_hovered = true
	_apply_rock_material()

func _on_mouse_exited() -> void:
	if _extraction_started:
		return
	_cancel_left_press()
	_is_hovered = false
	_apply_rock_material()

# Single authoritative rock colour for the current state. Hover is transient
# and never applies to revealed, marked, or cracked cells.
func _apply_rock_material() -> void:
	if solid_mesh == null:
		return
	if is_cracked:
		solid_mesh.material_override = _mat_rock_charred
	elif is_revealed:
		solid_mesh.material_override = _mat_rock_excavated
	elif _is_hovered and not is_marked:
		solid_mesh.material_override = _mat_rock_hover
	else:
		solid_mesh.material_override = _mat_rock

func set_gem(value: bool) -> void:
	is_gem = value

func set_face_counts(counts: Dictionary) -> void:
	face_neighbor_gems = counts.duplicate()
	if is_revealed:
		_populate_face_numbers()

# Staked gem / misplaced stake: keep the rock cube and overlay the amber X.
func set_marked(value: bool) -> void:
	if _extraction_started or is_revealed or is_cracked:
		return
	if is_marked == value:
		return
	is_marked = value
	if is_marked:
		if stake_overlay == null:
			_build_stake_overlay()
		if stake_overlay != null:
			stake_overlay.visible = true
	else:
		_hide_stake_overlay()
	_apply_rock_material()

# Excavated rock: lighter rock, face-local numbers, no stake overlay.
func excavate() -> void:
	if _extraction_started or is_revealed or is_gem:
		return
	is_revealed = true
	is_marked = false
	_hide_stake_overlay()
	_apply_rock_material()
	_populate_face_numbers()

# Cracked gem: terminal. Charred rock plus a dim faceted crystal cluster.
func strike() -> void:
	if _extraction_started or is_cracked:
		return
	is_cracked = true
	is_marked = true
	is_gem = true
	_is_hovered = false
	_hide_stake_overlay()
	_build_crystal_overlay(false)
	if crystal_overlay != null:
		crystal_overlay.visible = true
	_apply_rock_material()
	for value in face_labels.values():
		var lbl: Label3D = value
		lbl.visible = false

func _populate_face_numbers() -> void:
	for f in face_labels:
		var lbl: Label3D = face_labels[f]
		var n_gems := int(face_neighbor_gems.get(f, 0))
		if n_gems > 0:
			lbl.text = str(n_gems)
			var color_idx := clampi(n_gems - 1, 0, NUMBER_COLORS.size() - 1)
			lbl.modulate = NUMBER_COLORS[color_idx]
		else:
			lbl.text = ""

# Update label visibility and upright alignment for the viewed face
func update_label_display(active_face: int, camera_up_world: Vector3) -> void:
	if _extraction_started:
		for value in face_labels.values():
			var hidden_lbl: Label3D = value
			hidden_lbl.visible = false
		return

	for f in face_labels:
		var lbl: Label3D = face_labels[f]
		var n_gems := int(face_neighbor_gems.get(f, 0))
		if not is_revealed or is_gem or n_gems == 0 or f != active_face:
			lbl.visible = false
		else:
			lbl.visible = true
			# Align this label upright with camera
			# Face outward normal in world space:
			var face_normal: Vector3 = FACE_NORMALS[f]
			var norm_world: Vector3 = global_transform.basis * face_normal
			# Camera up projected onto face plane in world space:
			var up_proj: Vector3 = (camera_up_world - norm_world * camera_up_world.dot(norm_world)).normalized()
			var right_proj: Vector3 = up_proj.cross(norm_world)
			var world_lbl_basis := Basis(right_proj, up_proj, norm_world)
			var det := global_transform.basis.determinant()
			if absf(det) > 0.0001:
				lbl.transform.basis = global_transform.basis.inverse() * world_lbl_basis
			else:
				lbl.transform.basis = world_lbl_basis

# --- Lazy overlays -----------------------------------------------------------

func _build_stake_overlay() -> void:
	_ensure_shared_resources()
	stake_overlay = Node3D.new()
	stake_overlay.name = "StakeOverlay"
	stake_overlay.visible = false
	add_child(stake_overlay)

	for f in exterior_faces:
		var n: Vector3 = FACE_NORMALS[f]
		var group := Node3D.new()
		group.name = "Stake_%d" % f
		group.transform = Transform3D(_face_basis(n), n * STAKE_OFFSET)

		for side in [-1.0, 1.0]:
			var bar := MeshInstance3D.new()
			bar.mesh = _stake_bar_mesh
			bar.material_override = _mat_stake
			bar.transform = Transform3D(Basis(Vector3(0, 0, 1), side * PI * 0.25), Vector3.ZERO)
			group.add_child(bar)

		var boss := MeshInstance3D.new()
		boss.mesh = _stake_boss_mesh
		boss.material_override = _mat_stake
		boss.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.027))
		group.add_child(boss)

		stake_overlay.add_child(group)
		stake_face_groups[f] = group

func _hide_stake_overlay() -> void:
	if stake_overlay != null:
		stake_overlay.visible = false

func _build_crystal_overlay(intact: bool) -> void:
	if crystal_overlay != null:
		return
	_ensure_shared_resources()
	crystal_overlay = Node3D.new()
	crystal_overlay.name = "CrystalOverlay"
	crystal_overlay.visible = false
	add_child(crystal_overlay)

	var shard_mat: StandardMaterial3D = _mat_gem_intact if intact else _mat_gem_cracked
	var seed := _visual_seed()

	for f in exterior_faces:
		var n: Vector3 = FACE_NORMALS[f]
		var group := Node3D.new()
		group.name = "Crystal_%d" % f
		group.transform = Transform3D(_face_basis(n), n * CRYSTAL_OFFSET)

		var spin := float((seed + f * 37) % 60) * PI / 180.0

		var main := MeshInstance3D.new()
		main.mesh = _shard_main_mesh
		main.material_override = shard_mat
		main.transform = _shard_transform(Vector3(0, 0, 0.15), spin, Vector3.ZERO, 0.0)
		group.add_child(main)

		var offsets := [Vector3(0.15, 0.09, 0.09), Vector3(-0.15, -0.09, 0.09)]
		for i in range(offsets.size()):
			var off: Vector3 = offsets[i]
			var satellite := MeshInstance3D.new()
			satellite.mesh = _shard_small_mesh
			satellite.material_override = shard_mat
			satellite.transform = _shard_transform(
				off,
				spin + 0.5 * (1.0 if i == 0 else -1.0),
				Vector3(off.x, off.y, 0.0),
				0.38
			)
			group.add_child(satellite)

		if not intact:
			var fracture := MeshInstance3D.new()
			fracture.mesh = _fracture_mesh
			fracture.material_override = _mat_crack
			var fracture_basis := Basis(Vector3.RIGHT, PI * 0.5 + 0.26) * Basis(Vector3(0, 0, 1), spin)
			fracture.transform = Transform3D(fracture_basis, Vector3(0, 0, 0.11))
			group.add_child(fracture)

			var angle0 := float((seed * 13 + f * 47) % 360) * PI / 180.0
			var angles := [angle0, angle0 + 2.1]
			var fissure_meshes := [_fissure_long_mesh, _fissure_short_mesh]
			for i in range(2):
				var fissure := MeshInstance3D.new()
				fissure.mesh = fissure_meshes[i]
				fissure.material_override = _mat_crack
				var dir := Vector3(cos(angles[i]), sin(angles[i]), 0.0)
				fissure.transform = Transform3D(
					Basis(Vector3(0, 0, 1), angles[i]),
					dir * 0.28 + Vector3(0, 0, 0.012)
				)
				group.add_child(fissure)

		crystal_overlay.add_child(group)
		crystal_face_groups[f] = group

# --- Extraction hook (Phase 3) ----------------------------------------------

func play_extraction(delay: float) -> void:
	if _extraction_started or not is_inside_tree():
		return
	_extraction_started = true
	_cancel_left_press()
	_is_hovered = false
	set_deferred("input_ray_pickable", false)
	if _extraction_tween and _extraction_tween.is_valid():
		_extraction_tween.kill()
	_extraction_tween = create_tween()
	_extraction_tween.tween_interval(maxf(delay, 0.0))
	_extraction_tween.tween_callback(_begin_extraction)

func _begin_extraction() -> void:
	if not is_inside_tree():
		return
	for value in face_labels.values():
		var lbl: Label3D = value
		lbl.visible = false

	var outward := position
	if outward.length_squared() < 0.0001:
		outward = Vector3.UP
	outward = outward.normalized()
	var inward := -outward

	if is_gem:
		# Staked gems reveal an intact crystal; cracked gems keep their cracked one.
		_hide_stake_overlay()
		if crystal_overlay == null:
			_build_crystal_overlay(not is_cracked)
		if crystal_overlay != null:
			crystal_overlay.visible = true
			_prepare_crystal_pulse(not is_cracked)
			_animate_crystal_out(outward, GEM_RISE)
		_animate_rock_away(inward, GEM_SINK)
	else:
		_animate_rock_away(inward, ROCK_SINK)

func _animate_rock_away(inward: Vector3, sink: float) -> void:
	if solid_mesh == null:
		return
	if _rock_tween and _rock_tween.is_valid():
		_rock_tween.kill()
	_rock_tween = create_tween()
	_rock_tween.set_parallel(true)
	_rock_tween.tween_property(solid_mesh, "position", solid_mesh.position + inward * sink, ROCK_ANIM_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_rock_tween.tween_property(solid_mesh, "scale", Vector3.ONE * ROCK_SHRINK, ROCK_ANIM_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_rock_tween.set_parallel(false)
	_rock_tween.tween_callback(_hide_solid_mesh)

func _hide_solid_mesh() -> void:
	if is_instance_valid(solid_mesh):
		solid_mesh.visible = false

func _animate_crystal_out(outward: Vector3, rise: float) -> void:
	if crystal_overlay == null:
		return
	if _lift_tween and _lift_tween.is_valid():
		_lift_tween.kill()
	_lift_tween = create_tween()
	_lift_tween.tween_property(crystal_overlay, "position", crystal_overlay.position + outward * rise, GEM_ANIM_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Duplicate the crystal material once per tile so the finite glow pulse never
# mutates the shared resources used by other tiles.
func _prepare_crystal_pulse(intact: bool) -> void:
	if crystal_overlay == null:
		return
	var base_mat: StandardMaterial3D = _mat_gem_intact if intact else _mat_gem_cracked
	var pulse_mat := base_mat.duplicate() as StandardMaterial3D
	for value in crystal_face_groups.values():
		var group: Node3D = value
		for child in group.get_children():
			var mesh_instance := child as MeshInstance3D
			if mesh_instance != null and mesh_instance.material_override == base_mat:
				mesh_instance.material_override = pulse_mat

	var peak := 1.6 if intact else 0.9
	var base_energy := base_mat.emission_energy_multiplier
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(pulse_mat, "emission_energy_multiplier", peak, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(pulse_mat, "emission_energy_multiplier", base_energy, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

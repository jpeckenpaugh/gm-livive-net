class_name VolumetricCubeController
extends Node3D

signal face_surveyed(face: int)
signal claim_complete()

@export var initial_cube_size: int = 10
@export var total_gems: int = 60
@export var tile_spacing: float = 1.0

var grid: VolumetricGrid = VolumetricGrid.new()

# Map of Vector3i -> VolumetricTile3D (488 physical shell voxels)
var tile_nodes: Dictionary = {}
var inner_core_mesh: MeshInstance3D
var _finale: ExcavationFinale = null

var current_viewed_face: int = VolumetricGrid.Face.FRONT
var is_navigating: bool = false
var game_over: bool = false
var game_won: bool = false

# Faces already reported by face_surveyed; reset on a new game.
var surveyed_faces: Dictionary = {}
var _auto_stake_done: bool = false
var _claim_triggered: bool = false

enum Difficulty {
	EASY = 0,
	MEDIUM = 1,
	HARD = 2
}

const DIFFICULTY_STRIKES = {
	Difficulty.EASY: 9,
	Difficulty.MEDIUM: 3,
	Difficulty.HARD: 0
}

var current_difficulty: int = Difficulty.EASY
var max_strikes: int = 9
var strikes: int = 0

@onready var cube_root: Node3D = $CubeRoot
@onready var elastic_pivot: Node3D = $CubeRoot/ElasticPivot
@onready var camera: Camera3D = $Camera3D

@onready var face_info_label: Label = $UI/Panel/VBoxContainer/FaceInfoLabel
@onready var stats_label: Label = $UI/Panel/VBoxContainer/StatsLabel
@onready var difficulty_option: OptionButton = $UI/Panel/VBoxContainer/ActionRow/DifficultyOption
@onready var restart_button: Button = $UI/Panel/VBoxContainer/ActionRow/RestartButton

var elastic_tween: Tween
var nav_tween: Tween
var shake_tween: Tween
var camera_home: Vector3 = Vector3.ZERO

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	difficulty_option.selected = current_difficulty
	difficulty_option.item_selected.connect(_on_difficulty_selected)
	restart_button.pressed.connect(reset_game)
	reset_game()

func _on_difficulty_selected(index: int) -> void:
	current_difficulty = index
	reset_game()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if is_navigating or game_over or game_won:
			return
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			rotate_cube_view(Vector3.UP, PI * 0.5)
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			rotate_cube_view(Vector3.UP, -PI * 0.5)
		elif event.keycode == KEY_UP or event.keycode == KEY_W:
			rotate_cube_view(Vector3.RIGHT, PI * 0.5)
		elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
			rotate_cube_view(Vector3.RIGHT, -PI * 0.5)

func reset_game() -> void:
	if _finale != null and is_instance_valid(_finale):
		_finale.cancel()
	for tween in [nav_tween, elastic_tween, shake_tween]:
		if tween and tween.is_valid():
			tween.kill()
	nav_tween = null
	elastic_tween = null
	shake_tween = null
	game_over = false
	game_won = false
	is_navigating = false
	strikes = 0
	max_strikes = DIFFICULTY_STRIKES.get(current_difficulty, 9)
	surveyed_faces.clear()
	_auto_stake_done = false
	_claim_triggered = false
	current_viewed_face = VolumetricGrid.Face.FRONT

	cube_root.transform = Transform3D.IDENTITY
	elastic_pivot.transform = Transform3D.IDENTITY

	for child in elastic_pivot.get_children():
		if child is VolumetricTile3D:
			child.input_ray_pickable = false
			child.set_process(false)
		child.queue_free()

	tile_nodes.clear()
	grid.init_grid(initial_cube_size)

	# Set up Camera
	var cam_dist = initial_cube_size * 0.5 + 13.0
	camera_home = Vector3(0, 0, cam_dist)
	camera.position = camera_home
	camera.look_at(Vector3.ZERO, Vector3.UP)

	# Build Solid Core block beneath the outer skin
	_build_inner_core()

	# Build the 488 shell voxels
	_build_all_shell_voxels()
	_update_hud()

func _build_inner_core() -> void:
	inner_core_mesh = MeshInstance3D.new()
	inner_core_mesh.name = "InnerSolidCore"
	var bmesh = BoxMesh.new()
	var inner_sz = (initial_cube_size - 2) * tile_spacing * 0.98
	bmesh.size = Vector3(inner_sz, inner_sz, inner_sz)
	inner_core_mesh.mesh = bmesh

	var cmat = StandardMaterial3D.new()
	cmat.albedo_color = Color(0.12, 0.13, 0.17)
	cmat.roughness = 0.6
	cmat.metallic = 0.1
	inner_core_mesh.material_override = cmat
	elastic_pivot.add_child(inner_core_mesh)

func _build_all_shell_voxels() -> void:
	var half = (initial_cube_size - 1) * 0.5 * tile_spacing

	for cell in grid.all_cells:
		var tile = VolumetricTile3D.new()
		var pos = Vector3(
			cell.coord.x * tile_spacing - half,
			cell.coord.y * tile_spacing - half,
			cell.coord.z * tile_spacing - half
		)
		tile.position = pos
		tile.setup(cell.coord, cell.exterior_faces)
		tile.tile_clicked.connect(_on_tile_clicked)
		tile.tile_pressed.connect(_on_tile_pressed)
		elastic_pivot.add_child(tile)
		tile_nodes[cell.coord] = tile

# Free 90-degree world axis cube view rotation
func rotate_cube_view(axis: Vector3, angle_rad: float) -> void:
	if is_navigating or game_over or game_won:
		return
	is_navigating = true

	var target_basis = Basis(axis, angle_rad) * cube_root.basis

	if nav_tween and nav_tween.is_valid():
		nav_tween.kill()

	nav_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var start_q = cube_root.basis.get_rotation_quaternion()
	var end_q = target_basis.get_rotation_quaternion()

	nav_tween.tween_method(func(t: float):
		cube_root.basis = Basis(start_q.slerp(end_q, t)), 0.0, 1.0, 0.45
	)

	nav_tween.finished.connect(func():
		is_navigating = false
		_identify_current_front_face()
		_refresh_all_labels()
		_update_hud()
	)

func _refresh_all_labels() -> void:
	var cam_up = camera.global_transform.basis.y
	for tile in tile_nodes.values():
		if tile and is_instance_valid(tile):
			tile.update_label_display(current_viewed_face, cam_up)

# Determine which face is currently pointing directly at +Z (toward the camera)
func _identify_current_front_face() -> void:
	var face_normals = [
		Vector3(0, 0, 1),   # FRONT (+Z)
		Vector3(1, 0, 0),   # RIGHT (+X)
		Vector3(0, 0, -1),  # BACK (-Z)
		Vector3(-1, 0, 0),  # LEFT (-X)
		Vector3(0, 1, 0),   # TOP (+Y)
		Vector3(0, -1, 0)   # BOTTOM (-Y)
	]
	var best_face = 0
	var max_dot = -999.0
	for f in range(6):
		var world_norm = cube_root.basis * face_normals[f]
		var dot = world_norm.dot(Vector3(0, 0, 1))
		if dot > max_dot:
			max_dot = dot
			best_face = f
	current_viewed_face = best_face

# Tactile elastic spring impulse (applied to ElasticPivot child)
func _on_tile_pressed(coord: Vector3i) -> void:
	if is_navigating or game_over or game_won:
		return
	var half = (initial_cube_size - 1) * 0.5
	var tile_pos = Vector3(coord.x - half, coord.y - half, coord.z - half)
	# Project tile position in screen space relative to camera
	var screen_pos = cube_root.basis * tile_pos
	var norm_u = clamp(screen_pos.x / half, -1.0, 1.0)
	var norm_v = clamp(screen_pos.y / half, -1.0, 1.0)

	var pitch = -norm_v * 3.0
	var yaw = norm_u * 3.0
	var flex_rot = Vector3(pitch, yaw, 0.0)

	if elastic_tween and elastic_tween.is_valid():
		elastic_tween.kill()

	elastic_tween = create_tween()
	elastic_tween.parallel().tween_property(elastic_pivot, "rotation_degrees", flex_rot, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	elastic_tween.parallel().tween_property(elastic_pivot, "position:z", -0.15, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	elastic_tween.chain().tween_property(elastic_pivot, "rotation_degrees", Vector3.ZERO, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elastic_tween.parallel().tween_property(elastic_pivot, "position:z", 0.0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Left click excavates rock or cracks a gem; right click stakes, unstakes, or chords.
func _on_tile_clicked(coord: Vector3i, button_index: int) -> void:
	if is_navigating or game_over or game_won:
		return

	var cell: VolumetricGrid.CellData = grid.get_cell_at(coord)
	var tile: VolumetricTile3D = tile_nodes.get(coord, null)
	if not cell or not tile:
		return

	if button_index == MOUSE_BUTTON_RIGHT:
		if cell.is_detonated:
			# A cracked gem is permanently staked.
			return
		if not cell.is_revealed:
			cell.is_marked = not cell.is_marked
			tile.set_marked(cell.is_marked)
			_after_mutation()
		elif cell.face_neighbor_gems.get(current_viewed_face, 0) > 0:
			_chord_excavate_neighbors(coord)

	elif button_index == MOUSE_BUTTON_LEFT:
		if cell.is_marked or cell.is_revealed or cell.is_detonated:
			return

		if not grid.gems_populated:
			grid.populate_gems(coord, total_gems)
			_sync_tiles_from_grid()

		if cell.is_gem:
			_after_mutation(_on_gem_struck(coord))
		else:
			_flood_excavate(coord)
			_refresh_all_labels()
			_after_mutation()

func _sync_tiles_from_grid() -> void:
	for cell in grid.all_cells:
		var tile: VolumetricTile3D = tile_nodes.get(cell.coord, null)
		if tile and is_instance_valid(tile):
			tile.set_gem(cell.is_gem)
			tile.set_face_counts(cell.face_neighbor_gems)

# Continuous 3D BFS flood-fill wrapping over edges and corners
func _flood_excavate(start_coord: Vector3i) -> void:
	var queue: Array[Vector3i] = [start_coord]
	var visited = {}

	while queue.size() > 0:
		var curr_coord = queue.pop_front()
		if visited.has(curr_coord):
			continue
		visited[curr_coord] = true

		var c: VolumetricGrid.CellData = grid.get_cell_at(curr_coord)
		var t: VolumetricTile3D = tile_nodes.get(curr_coord, null)
		if not c or not t:
			continue

		if c.is_revealed or c.is_marked or c.is_gem:
			continue

		c.is_revealed = true
		t.excavate()

		# Check if this cell has 0 gems touching it on ANY of its exterior faces (blank space)
		var has_zero_face = false
		for f in c.exterior_faces:
			if c.face_neighbor_gems.get(f, 0) == 0:
				has_zero_face = true
				break

		# If cell is 0 on a face, auto-cascade across all 3D wrap-around neighbors
		if has_zero_face:
			for neighbor in grid.get_neighbors(curr_coord):
				if not neighbor.is_revealed and not neighbor.is_marked and not neighbor.is_gem:
					queue.append(neighbor.coord)

# Chording logic on current face
func _chord_excavate_neighbors(coord: Vector3i) -> void:
	var c: VolumetricGrid.CellData = grid.get_cell_at(coord)
	if not c:
		return
	var req_gems = c.face_neighbor_gems.get(current_viewed_face, 0)
	var neighbors = grid.get_face_neighbors(current_viewed_face, coord)
	var accounted = 0
	var undecided: Array[VolumetricGrid.CellData] = []

	for n in neighbors:
		if n.is_marked:
			accounted += 1
		elif not n.is_revealed:
			undecided.append(n)

	if accounted != req_gems or undecided.size() == 0:
		return

	var messages: Array[String] = []
	for n in undecided:
		if n.is_gem:
			var struck: String = _on_gem_struck(n.coord)
			if struck != "":
				messages.append(struck)
			if game_over:
				break
		else:
			_flood_excavate(n.coord)
	_refresh_all_labels()
	_after_mutation(" ".join(messages))

# Cracks a gem: costs a strike, auto-stakes it, and returns a HUD message.
func _on_gem_struck(coord: Vector3i) -> String:
	var c: VolumetricGrid.CellData = grid.get_cell_at(coord)
	var t: VolumetricTile3D = tile_nodes.get(coord, null)
	if not c or not c.is_gem or c.is_marked or c.is_detonated:
		return ""

	strikes += 1
	c.is_detonated = true
	c.is_marked = true
	if t and is_instance_valid(t):
		t.strike()

	_shake_camera()

	if max_strikes == 0:
		game_over = true
		return "Gem cracked on Hard mode - claim lost!"
	if strikes >= max_strikes:
		game_over = true
		return "Pick integrity gone (%d/%d strikes) - claim lost!" % [strikes, max_strikes]
	return "Gem cracked - staked automatically (%d/%d strikes)." % [strikes, max_strikes]

func _shake_camera() -> void:
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()
	camera.position = camera_home
	shake_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	shake_tween.tween_property(camera, "position", camera_home + Vector3(0.3, -0.25, 0), 0.05)
	shake_tween.tween_property(camera, "position", camera_home + Vector3(-0.3, 0.25, 0), 0.05)
	shake_tween.tween_property(camera, "position", camera_home, 0.05)

# One post-mutation pipeline, called once per top-level action.
func _after_mutation(message: String = "") -> void:
	if game_over:
		_update_hud(message if message != "" else "Claim lost.")
		return

	var parts: Array[String] = []
	if message != "":
		parts.append(message)

	if _apply_auto_stake():
		parts.append("All rock surveyed - remaining gems staked.")

	var newly: Array[int] = _collect_newly_surveyed_faces()
	if newly.size() == 1:
		parts.append("%s face surveyed!" % VolumetricGrid.FACE_NAMES[newly[0]])
	elif newly.size() > 1:
		var names: Array[String] = []
		for f in newly:
			names.append(VolumetricGrid.FACE_NAMES[f])
		parts.append("%s faces surveyed!" % ", ".join(names))

	_update_hud("   ".join(parts))

	_check_victory()

# Stakes every unresolved gem once all rock is excavated. Never reveals rock.
func _apply_auto_stake() -> bool:
	if _auto_stake_done or game_over or not grid.gems_populated:
		return false
	if not grid.get_board_stats()["all_rock_excavated"]:
		return false

	_auto_stake_done = true
	var staked: int = 0
	for cell in grid.all_cells:
		if cell.is_gem and not cell.is_marked and not cell.is_detonated:
			cell.is_marked = true
			staked += 1
			var tile: VolumetricTile3D = tile_nodes.get(cell.coord, null)
			if tile and is_instance_valid(tile):
				tile.set_marked(true)
	return staked > 0

func _collect_newly_surveyed_faces() -> Array[int]:
	var newly: Array[int] = []
	for f in range(6):
		if surveyed_faces.has(f):
			continue
		if grid.get_face_stats(f)["is_face_complete"]:
			surveyed_faces[f] = true
			newly.append(f)
			face_surveyed.emit(f)
	return newly

func _check_victory() -> void:
	if game_over or game_won or _claim_triggered or not grid.gems_populated:
		return
	if grid.is_board_complete():
		_trigger_claim_complete()

# Only entry point to the finale (Phase 3). Must stay idempotent.
func _trigger_claim_complete() -> void:
	if _claim_triggered:
		return
	_claim_triggered = true
	game_won = true
	is_navigating = false
	if nav_tween and nav_tween.is_valid():
		nav_tween.kill()
	if elastic_tween and elastic_tween.is_valid():
		elastic_tween.kill()
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()
	camera.position = camera_home
	elastic_pivot.transform = Transform3D.IDENTITY

	var board: Dictionary = grid.get_board_stats()
	var gems_secured: int = int(board["gems_staked"]) + int(board["gems_cracked"])
	var gems_cracked: int = int(board["gems_cracked"])

	claim_complete.emit()
	_update_hud("CLAIM COMPLETE — mother lode extraction begins…")
	_ensure_finale()
	_finale.begin(
		tile_nodes, inner_core_mesh, camera,
		initial_cube_size, tile_spacing, gems_secured, gems_cracked
	)

func _ensure_finale() -> void:
	if _finale != null and is_instance_valid(_finale):
		return
	_finale = ExcavationFinale.new()
	_finale.name = "ExcavationFinale"
	_finale.status_changed.connect(_on_finale_status)
	add_child(_finale)

func _on_finale_status(text: String) -> void:
	_update_hud(text)

func _update_hud(override_msg: String = "") -> void:
	var fname = VolumetricGrid.FACE_NAMES[current_viewed_face]
	var board = grid.get_board_stats()
	var face = grid.get_face_stats(current_viewed_face)

	if override_msg != "":
		face_info_label.text = override_msg
	elif game_won:
		face_info_label.text = "Claim staked - all six faces surveyed!"
	elif not board["gems_populated"]:
		face_info_label.text = "Viewing: %s Face - survey the geode to begin (arrows rotate)" % fname
	else:
		var face_stakes: int = face["face_gems_staked"] + face["face_gems_cracked"] + face["face_misplaced_marks"]
		face_info_label.text = "Viewing: %s Face  |  Rock %d  |  Stakes %d" % [
			fname,
			face["face_rock_excavated"],
			face_stakes
		]

	stats_label.text = _build_stats_line(board)

func _build_stats_line(board: Dictionary) -> String:
	if not board["gems_populated"]:
		var expected_rock: int = max(grid.all_cells.size() - total_gems, 0)
		return "Rock excavated 0/%d  ·  Stakes placed %d  ·  Integrity %s" % [
			expected_rock, board["misplaced_marks"], _integrity_text()
		]

	var stakes: int = board["gems_staked"] + board["gems_cracked"] + board["misplaced_marks"]
	return "Rock excavated %d/%d  ·  Stakes placed %d  ·  Integrity %s" % [
		board["rock_excavated"], board["rock_total"], stakes, _integrity_text()
	]

func _integrity_text() -> String:
	if max_strikes == 0:
		return "fragile (one crack ends the run)"
	var remaining: int = max(max_strikes - strikes, 0)
	return "%d/%d" % [remaining, max_strikes]

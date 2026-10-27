extends RefCounted

# End-to-end controller flow against the real scene, headless.
#
# The scene is instantiated after the runner's deferred start so _ready() and
# @onready assignments run. No mouse picking or rendering is used: behavior is
# driven through the controller hooks frozen in docs/GEM_MINER_PLAN.md §6.

const Grid = preload("res://volumetric_grid.gd")
const CENTER := Vector3i(5, 4, 9)

var game
var claim_hits: Array[int] = [0]
var surveyed_faces: Array[int] = []

func suite_name() -> String:
	return "controller_flow"

func run(t) -> void:
	if not t.ok(t.tree != null, "runner provided a SceneTree"):
		return

	var packed = load("res://volumetric_minesweeper.tscn")
	game = packed.instantiate()
	t.tree.root.add_child(game)

	game.claim_complete.connect(func() -> void: claim_hits[0] += 1)
	game.face_surveyed.connect(func(f: int) -> void: surveyed_faces.append(f))

	_test_boot(t)
	_test_first_click(t)
	_test_mark_unmark(t)
	_test_cascade(t)
	_test_chord(t)
	_test_wrong_mark_chord_quirk(t)
	_test_strike(t)
	_test_hard_mode_loss(t)
	_test_loss_suppresses_progress(t)
	_test_auto_stake_and_claim(t)
	_test_face_survey_signal(t)
	_test_won_input_lock(t)
	_test_reset(t)

	game.queue_free()

func _start_game(gems: int = 60, difficulty: int = 0) -> void:
	game.total_gems = gems
	game.current_difficulty = difficulty
	game.reset_game()

func _count_gems() -> int:
	var count := 0
	for cell in game.grid.all_cells:
		if cell.is_gem:
			count += 1
	return count

func _find_gem(min_faces: int = 1):
	for cell in game.grid.all_cells:
		if cell.is_gem and cell.exterior_faces.size() >= min_faces:
			return cell
	return null

func _find_unrevealed_rock():
	for cell in game.grid.all_cells:
		if not cell.is_gem and not cell.is_revealed:
			return cell
	return null

func _test_boot(t) -> void:
	t.group("scene boot")
	t.ok(game.is_inside_tree(), "controller scene is in the tree")
	t.eq(game.grid.all_cells.size(), 488, "grid built 488 shell cells")
	t.eq(game.tile_nodes.size(), 488, "controller built 488 tile nodes")
	t.ok(not game.grid.gems_populated, "gems are deferred until the first click")
	t.ok(not game.game_over, "not game over at boot")
	t.ok(not game.game_won, "not won at boot")
	t.eq(game.max_strikes, 9, "Easy default has 9 strikes")
	t.ok(game.stats_label.text.contains("Stakes placed 0"), "stats HUD uses neutral stake copy")
	t.ok(
		not game.stats_label.text.contains("Gems secured"),
		"stats HUD hides live gem progress before the first pick"
	)
	t.ok(
		not game.stats_label.text.contains("Misplaced stakes"),
		"stats HUD hides live stake placement before the first pick"
	)
	t.ok(
		game.face_info_label.text.contains("survey the geode to begin"),
		"face HUD prompts the first pick"
	)

func _test_first_click(t) -> void:
	t.group("first click populates lazily and safely")
	_start_game(60)
	seed(4242)
	t.ok(not game.grid.gems_populated, "no gems before the first click")
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

	t.ok(game.grid.gems_populated, "first left-click populates gems")
	t.eq(_count_gems(), 60, "60 gems placed")
	t.ok(not game.grid.get_cell_at(CENTER).is_gem, "clicked cell is safe")
	var neighbors: Array = game.grid.get_neighbors(CENTER)
	t.eq(neighbors.size(), 8, "clicked center has 8 global neighbors")
	var unsafe := 0
	for n in neighbors:
		if n.is_gem:
			unsafe += 1
	t.eq(unsafe, 0, "all first-click neighbors are safe")

	var sync_bad := 0
	for cell in game.grid.all_cells:
		var tile = game.tile_nodes.get(cell.coord)
		if tile == null:
			sync_bad += 1
		elif tile.is_gem != cell.is_gem:
			sync_bad += 1
		elif tile.face_neighbor_gems != cell.face_neighbor_gems:
			sync_bad += 1
	t.eq(sync_bad, 0, "tiles mirror grid gem state and face counts")

func _test_mark_unmark(t) -> void:
	t.group("mark, unmark, and misplaced stakes")
	_start_game(60)
	seed(99)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

	var rock = _find_unrevealed_rock()
	t.ok(rock != null, "found an unrevealed rock")
	if rock == null:
		return

	game._on_tile_clicked(rock.coord, MOUSE_BUTTON_RIGHT)
	t.ok(rock.is_marked, "right-click stakes rock")
	game._on_tile_clicked(rock.coord, MOUSE_BUTTON_LEFT)
	t.ok(not rock.is_revealed, "staked rock cannot be excavated")
	t.ok(not game.grid.is_cell_resolved(rock), "staked rock remains unresolved")
	t.eq(game.grid.get_board_stats()["misplaced_marks"], 1, "misplaced stake counted")

	game._on_tile_clicked(rock.coord, MOUSE_BUTTON_RIGHT)
	t.ok(not rock.is_marked, "second right-click unstakes rock")
	t.eq(game.grid.get_board_stats()["misplaced_marks"], 0, "misplaced stake cleared")
	game._on_tile_clicked(rock.coord, MOUSE_BUTTON_LEFT)
	t.ok(rock.is_revealed, "unmarked rock excavates")

func _test_cascade(t) -> void:
	t.group("full-board cascade")
	var claim_before: int = claim_hits[0]
	_start_game(0)
	seed(7)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

	var board: Dictionary = game.grid.get_board_stats()
	t.eq(board["rock_excavated"], 488, "one click cascades across all 488 shell cells")
	t.eq(board["rock_remaining"], 0, "no rock remains")
	t.ok(game.grid.is_board_complete(), "zero-gem board completes")
	t.ok(game.game_won, "game won after full cascade")
	t.eq(claim_hits[0], claim_before + 1, "claim emitted once")

func _pick_chord_pair() -> Array:
	var neighbors: Array = game.grid.get_face_neighbors(Grid.Face.FRONT, CENTER)
	var target = null
	var marker = null
	for n in neighbors:
		if target == null and not n.is_gem:
			target = n
		elif marker == null:
			marker = n
	return [target, marker]

func _test_chord(t) -> void:
	t.group("chord uses face-local neighbors")
	_start_game(60)
	seed(777)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

	var center = game.grid.get_cell_at(CENTER)
	var neighbors: Array = game.grid.get_face_neighbors(Grid.Face.FRONT, CENTER)
	t.eq(neighbors.size(), 8, "front face has 8 face-local neighbors")
	var pair: Array = _pick_chord_pair()
	var target = pair[0]
	var marker = pair[1]
	t.ok(target != null and marker != null, "found a chord target and a marker")
	if target == null or marker == null:
		return

	for n in neighbors:
		if n == target:
			n.is_revealed = false
		elif n == marker:
			n.is_marked = true
			n.is_revealed = false
		else:
			n.is_revealed = true
	center.is_revealed = true
	center.face_neighbor_gems[Grid.Face.FRONT] = 1
	game.current_viewed_face = Grid.Face.FRONT
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_RIGHT)
	t.ok(target.is_revealed, "satisfied number excavates its undecided face neighbor")

	_start_game(60)
	seed(777)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)
	center = game.grid.get_cell_at(CENTER)
	neighbors = game.grid.get_face_neighbors(Grid.Face.FRONT, CENTER)
	pair = _pick_chord_pair()
	target = pair[0]
	marker = pair[1]
	if target == null or marker == null:
		return
	for n in neighbors:
		if n == target:
			n.is_revealed = false
		elif n == marker:
			n.is_marked = true
			n.is_revealed = false
		else:
			n.is_revealed = true
	center.is_revealed = true
	center.face_neighbor_gems[Grid.Face.FRONT] = 2
	game.current_viewed_face = Grid.Face.FRONT
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_RIGHT)
	t.ok(not target.is_revealed, "unsatisfied number does not chord")

func _test_wrong_mark_chord_quirk(t) -> void:
	t.group("KNOWN QUIRK: wrong stake can satisfy a chord")
	_start_game(60)
	var center = game.grid.get_cell_at(CENTER)
	var neighbors: Array = game.grid.get_face_neighbors(Grid.Face.FRONT, CENTER)
	var wrong_stake = neighbors[0]
	var hidden_gem = neighbors[1]
	wrong_stake.is_marked = true
	hidden_gem.is_gem = true
	center.is_revealed = true
	center.face_neighbor_gems[Grid.Face.FRONT] = 1
	game.current_viewed_face = Grid.Face.FRONT

	var strikes_before: int = game.strikes
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_RIGHT)
	t.eq(game.strikes, strikes_before + 1, "wrong stake satisfies the number")
	t.ok(hidden_gem.is_detonated, "real gem is cracked by the chord")
	t.ok(hidden_gem.is_marked, "cracked gem is auto-staked")

func _test_strike(t) -> void:
	t.group("gem strike and idempotence")
	_start_game(60)
	seed(808)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

	var gem = _find_gem(2)
	t.ok(gem != null, "found an edge gem")
	if gem == null:
		return

	var strikes_before: int = game.strikes
	game._on_gem_struck(gem.coord)
	t.eq(game.strikes, strikes_before + 1, "strike costs one integrity point")
	t.ok(gem.is_detonated, "gem is cracked")
	t.ok(gem.is_marked, "cracked gem is auto-staked")
	t.ok(not game.game_over, "Easy survives one strike")

	game._on_gem_struck(gem.coord)
	game._on_tile_clicked(gem.coord, MOUSE_BUTTON_LEFT)
	t.eq(game.strikes, strikes_before + 1, "repeated strike attempts are ignored")

func _test_hard_mode_loss(t) -> void:
	t.group("hard mode loss precedence")
	var claim_before: int = claim_hits[0]
	_start_game(60, 2)
	seed(909)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

	var last_gem = _find_gem()
	t.ok(last_gem != null, "found a gem")
	if last_gem == null:
		return
	for cell in game.grid.all_cells:
		if cell.is_gem and cell != last_gem:
			cell.is_marked = true
		elif not cell.is_gem:
			cell.is_revealed = true
	t.ok(not game.grid.is_board_complete(), "one unresolved gem keeps the board incomplete")

	game._on_gem_struck(last_gem.coord)
	t.ok(game.game_over, "first crack ends a Hard run")
	t.ok(game.grid.is_board_complete(), "board resolves after the crack")
	game._check_victory()
	t.ok(not game.game_won, "loss has precedence over victory")
	t.eq(claim_hits[0], claim_before, "no claim is emitted on a lost run")

func _test_auto_stake_and_claim(t) -> void:
	t.group("auto-stake and claim idempotence")
	var claim_before: int = claim_hits[0]
	_start_game(60)
	seed(31337)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

	var unrevealed_rocks := []
	for cell in game.grid.all_cells:
		if not cell.is_gem and not cell.is_revealed:
			unrevealed_rocks.append(cell)
	t.ok(unrevealed_rocks.size() > 1, "board has multiple unrevealed rocks")
	if unrevealed_rocks.size() == 0:
		return

	var last_rock = unrevealed_rocks[0]
	for i in range(1, unrevealed_rocks.size()):
		unrevealed_rocks[i].is_revealed = true

	var surveyed_before: int = surveyed_faces.size()
	game._on_tile_clicked(last_rock.coord, MOUSE_BUTTON_LEFT)
	var board: Dictionary = game.grid.get_board_stats()
	t.ok(board["all_rock_excavated"], "last rock is excavated")
	t.eq(board["gems_remaining"], 0, "remaining gems are auto-staked")
	t.ok(game.grid.is_board_complete(), "board completes after auto-stake")
	t.ok(game.game_won, "victory reached through the click path")
	t.eq(claim_hits[0], claim_before + 1, "claim emitted once")

	var newly: Array = surveyed_faces.slice(surveyed_before)
	t.eq(newly.size(), 6, "winning click surveys all six faces")
	t.eq(newly, [0, 1, 2, 3, 4, 5], "each face is reported exactly once, in enum order")

	game._trigger_claim_complete()
	game._trigger_claim_complete()
	game._check_victory()
	t.eq(claim_hits[0], claim_before + 1, "claim completion is idempotent")

func _test_face_survey_signal(t) -> void:
	t.group("face survey signal")
	_start_game(60)
	seed(2027)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)
	var surveyed_before: int = surveyed_faces.size()

	for cell in game.grid.face_cells[Grid.Face.FRONT]:
		if cell.is_gem:
			cell.is_marked = true
		else:
			cell.is_revealed = true

	var scratch = null
	for cell in game.grid.all_cells:
		if not cell.is_gem and not cell.is_revealed and not (Grid.Face.FRONT in cell.exterior_faces):
			scratch = cell
			break
	t.ok(scratch != null, "found an off-front scratch rock")
	if scratch == null:
		return

	game._on_tile_clicked(scratch.coord, MOUSE_BUTTON_RIGHT)
	t.eq(surveyed_faces.size(), surveyed_before + 1, "completing a face emits once")
	t.eq(surveyed_faces[surveyed_faces.size() - 1], Grid.Face.FRONT, "emitted face is Front")
	game._on_tile_clicked(scratch.coord, MOUSE_BUTTON_RIGHT)
	t.eq(surveyed_faces.size(), surveyed_before + 1, "survey is not re-emitted")

func _test_loss_suppresses_progress(t) -> void:
	t.group("loss suppresses surveys and auto-stake")
	for difficulty in [1, 2]:
		_start_game(60, difficulty)
		seed(909)
		game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

		var surveyed_before: int = surveyed_faces.size()
		var claims_before: int = claim_hits[0]
		var strikes_needed: int = game.max_strikes if game.max_strikes > 0 else 1
		var gems := []
		for cell in game.grid.all_cells:
			if cell.is_gem:
				gems.append(cell)
		t.ok(gems.size() >= strikes_needed, "difficulty %d has enough gems to lose" % difficulty)

		for i in range(strikes_needed):
			game._on_tile_clicked(gems[i].coord, MOUSE_BUTTON_LEFT)

		t.ok(game.game_over, "difficulty %d run ends after %d strike(s)" % [difficulty, strikes_needed])
		t.eq(game.strikes, strikes_needed, "difficulty %d counts every strike" % difficulty)
		t.eq(surveyed_faces.size(), surveyed_before, "no face is surveyed on a lost run")
		t.eq(claim_hits[0], claims_before, "no claim is emitted on a lost run")
		t.ok(not game._auto_stake_done, "auto-stake never runs on a lost run")
		t.ok(not game.game_won, "a lost run is not a win")
		t.ok(game.stats_label.text.contains("Stakes placed"), "lost-run HUD keeps neutral copy")

func _test_won_input_lock(t) -> void:
	t.group("input is locked while won")
	var claim_before: int = claim_hits[0]
	_start_game(0)
	seed(7)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)
	t.ok(game.game_won, "zero-gem cascade wins")
	t.eq(claim_hits[0], claim_before + 1, "winning click emits one claim")

	var basis_before: Basis = game.cube_root.basis
	var strikes_before: int = game.strikes
	game.rotate_cube_view(Vector3.UP, PI * 0.5)
	t.ok(not game.is_navigating, "rotation is ignored while won")
	t.ok(game.cube_root.basis.is_equal_approx(basis_before), "cube transform is unchanged")

	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_RIGHT)
	t.eq(game.strikes, strikes_before, "clicks do not cost strikes while won")
	t.eq(claim_hits[0], claim_before + 1, "clicks emit no extra claim")

func _test_reset(t) -> void:
	t.group("reset behavior")
	_start_game(60)
	seed(5)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)
	t.ok(game.grid.gems_populated, "game is populated before reset")
	var old_tile = game.tile_nodes.values()[0]

	game.reset_game()
	t.eq(game.grid.all_cells.size(), 488, "reset rebuilds 488 cells")
	t.eq(game.tile_nodes.size(), 488, "reset rebuilds 488 tile nodes")
	t.ok(not game.grid.gems_populated, "reset clears gems_populated")
	t.ok(not game.game_over, "reset clears game_over")
	t.ok(not game.game_won, "reset clears game_won")
	t.eq(game.strikes, 0, "reset clears strikes")
	t.eq(game.max_strikes, 9, "reset restores Easy integrity")
	t.ok(game.surveyed_faces.is_empty(), "reset clears surveyed faces")
	t.ok(not game._claim_triggered, "reset clears the claim latch")
	t.ok(game.stats_label.text.contains("Stakes placed 0"), "reset refreshes the neutral HUD copy")
	t.ok(
		not game.stats_label.text.contains("Gems secured"),
		"reset HUD hides live gem progress again"
	)

	t.ok(old_tile.is_queued_for_deletion(), "old tiles are queued for deferred free")
	t.ok(not old_tile.input_ray_pickable, "old tiles stop picking immediately")
	t.ok(not old_tile.is_processing(), "old tiles stop idling immediately")
	var new_tile = game.tile_nodes.values()[0]
	t.ok(new_tile != old_tile, "reset creates new tile instances")

	seed(6)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)
	t.ok(game.grid.gems_populated, "reset game repopulates on first click")
	t.eq(_count_gems(), 60, "reset game still places 60 gems")

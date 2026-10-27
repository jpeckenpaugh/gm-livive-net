extends RefCounted

# Async finale lifecycle against the real scene, headless.
#
# Requires `--fixed-fps 60` (make test) so frame budgets are deterministic:
# a full sweep is ~275 frames and a mid-sweep reset lands during the camera
# dolly. No rendering or mouse picking is involved; behavior is driven through
# the frozen controller hooks and the helper's public is_running()/has_finished().
#
# Deferred frees: never assert pivot child counts in the frame that called
# reset_game(); `queue_free()` completes after idle frames.

const CENTER := Vector3i(5, 4, 9)
const CAMERA_HOME := Vector3(0.0, 0.0, 18.0)
const FULL_FINALE_FRAMES := 900
const PIVOT_CHILDREN := 489  # 488 shell tiles + the inner solid core

var game
var claim_hits: int = 0
var surveyed_faces: Array[int] = []

func suite_name() -> String:
	return "finale_lifecycle"

func run(t) -> void:
	if not t.ok(t.tree != null, "runner provided a SceneTree"):
		return

	var packed = load("res://volumetric_minesweeper.tscn")
	game = packed.instantiate()
	t.tree.root.add_child(game)
	game.claim_complete.connect(func() -> void: claim_hits += 1)
	game.face_surveyed.connect(func(f: int) -> void: surveyed_faces.append(f))

	await _test_lazy_helper(t)
	await _test_win_starts_once(t)
	await _test_input_lock(t)
	await _test_reset_mid_sweep(t)
	await _test_win_again_and_finish(t)
	await _test_reset_after_finish(t)
	await _test_camera_stability(t)
	await _test_cracked_final_copy(t)
	await _test_no_leaks(t)

	game.queue_free()
	await _wait(t, 2)
	t.ok(not is_instance_valid(game), "finale scene is freed")

func _finale():
	return game.get_node_or_null("ExcavationFinale")

func _wait(t, frames: int) -> void:
	for i in range(frames):
		await t.tree.process_frame

func _wait_until(t, predicate: Callable, budget: int) -> int:
	var used := 0
	while used < budget and not bool(predicate.call()):
		await t.tree.process_frame
		used += 1
	return used

func _populate() -> void:
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

## Resolves the board through the mutation-free hook so the lifecycle is driven
## by the same entry point the controller uses after its final mutation.
func _force_win() -> void:
	for cell in game.grid.all_cells:
		if cell.is_gem:
			cell.is_marked = true
		else:
			cell.is_revealed = true
	game._check_victory()

func _test_lazy_helper(t) -> void:
	t.group("finale helper is lazy")
	await _wait(t, 2)
	t.ok(_finale() == null, "no finale node before victory")
	t.eq(claim_hits, 0, "no claim before victory")
	t.ok(game.stats_label.text.contains("Stakes placed 0"), "pre-population HUD is neutral")

func _test_win_starts_once(t) -> void:
	t.group("victory starts the sweep once")
	_populate()
	_force_win()
	t.ok(game.game_won, "game is won")
	t.eq(claim_hits, 1, "exactly one claim is emitted")

	var finale = _finale()
	t.ok(finale != null, "finale helper exists after victory")
	if finale == null:
		return
	t.ok(finale.is_running(), "sweep is running")
	t.ok(not finale.has_finished(), "sweep has not finished")
	t.eq(finale.get_child_count(), 0, "no mother-lode core before the reveal")

	var started := 0
	for coord in [Vector3i(0, 0, 0), CENTER, Vector3i(9, 9, 9)]:
		var tile = game.tile_nodes.get(coord)
		if tile != null and tile._extraction_started:
			started += 1
	t.eq(started, 3, "sampled tiles are scheduled for extraction")

	game._trigger_claim_complete()
	game._trigger_claim_complete()
	t.eq(claim_hits, 1, "claim completion is idempotent")

func _test_input_lock(t) -> void:
	t.group("input is locked while won")
	var basis_before: Basis = game.cube_root.basis
	var strikes_before: int = game.strikes
	var marks_before := 0
	for cell in game.grid.all_cells:
		if cell.is_marked:
			marks_before += 1

	game.rotate_cube_view(Vector3.UP, PI * 0.5)
	t.ok(not game.is_navigating, "rotation is ignored")
	t.ok(game.cube_root.basis.is_equal_approx(basis_before), "cube transform is unchanged")

	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_RIGHT)
	t.eq(game.strikes, strikes_before, "clicks do not cost strikes")
	var marks_after := 0
	for cell in game.grid.all_cells:
		if cell.is_marked:
			marks_after += 1
	t.eq(marks_after, marks_before, "clicks do not change stakes")
	t.eq(claim_hits, 1, "clicks emit no extra claim")

func _test_reset_mid_sweep(t) -> void:
	t.group("reset mid-sweep")
	var finale = _finale()
	if finale == null:
		t.ok(false, "finale helper exists for the mid-sweep reset")
		return

	var frames := await _wait_until(
		t, func() -> bool: return game.camera.position.z > CAMERA_HOME.z + 0.05, 120
	)
	t.ok(frames < 120, "camera dolly starts before the reset (%d frames)" % frames)

	var old_rind: MeshInstance3D = game.inner_core_mesh
	var helper_id: int = finale.get_instance_id()
	var claims_before: int = claim_hits
	var surveyed_before: int = surveyed_faces.size()

	game.reset_game()

	t.ok(not finale.is_running(), "cancel stops the sweep")
	t.ok(not finale.has_finished(), "a cancelled sweep is not finished")
	t.ok(old_rind.visible, "cancel restores the rind")
	t.ok(not game.game_won, "reset clears game_won")
	t.ok(not game._claim_triggered, "reset clears the claim latch")
	t.ok(game.surveyed_faces.is_empty(), "reset clears surveyed faces")
	t.eq(claim_hits, claims_before, "reset emits no claim")
	t.eq(surveyed_faces.size(), surveyed_before, "reset emits no survey")
	t.ok(game.camera.position.is_equal_approx(CAMERA_HOME), "reset restores the camera")
	t.eq(_finale().get_instance_id(), helper_id, "finale helper instance is reused")
	t.ok(_finale().get_node_or_null("MotherLodeCore") == null, "no core survives the cancel")

	await _wait(t, 3)
	t.eq(game.tile_nodes.size(), 488, "reset rebuilds 488 tiles")
	t.eq(game.elastic_pivot.get_child_count(), PIVOT_CHILDREN, "pivot holds the tiles plus the inner core")
	t.ok(not is_instance_valid(old_rind), "old rind is freed after the deferred rebuild")
	t.eq(_finale().get_child_count(), 0, "finale helper owns no nodes after cancel")
	t.eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), 0, "no orphan nodes after cancel")

func _test_win_again_and_finish(t) -> void:
	t.group("win again and run to finish")
	_populate()
	_force_win()
	t.eq(claim_hits, 2, "second win emits a second claim")

	var finale = _finale()
	t.ok(finale.is_running(), "second sweep is running")
	var frames := await _wait_until(t, func() -> bool: return finale.has_finished(), FULL_FINALE_FRAMES)
	t.ok(frames < FULL_FINALE_FRAMES, "finale finishes inside its timeline (%d frames)" % frames)
	t.ok(not finale.is_running(), "finished sweep is not running")
	t.ok(game.game_won, "win state survives the finale")
	t.ok(not game.inner_core_mesh.visible, "rind stays hidden after the reveal")
	t.eq(finale.get_child_count(), 1, "finale owns the mother-lode core")
	t.ok(finale.get_node_or_null("MotherLodeCore") != null, "core node exists")
	t.ok(
		is_equal_approx(game.camera.position.z, CAMERA_HOME.z + 1.0),
		"camera ends on the pulled-in shot (z=%.2f)" % game.camera.position.z
	)
	t.ok(game.face_info_label.text.contains("CLAIM COMPLETE"), "HUD announces the claim")
	t.ok(game.face_info_label.text.contains("60 gems secured"), "HUD reports secured gems")
	t.no_emoji(game.face_info_label.text, "finale HUD copy")
	t.eq(claim_hits, 2, "finishing does not re-emit the claim")

func _test_reset_after_finish(t) -> void:
	t.group("reset after finish")
	var finale = _finale()
	var helper_id: int = finale.get_instance_id()
	var done_rind: MeshInstance3D = game.inner_core_mesh

	game.reset_game()

	t.ok(done_rind.visible, "reset restores the rind after a completed finale")
	t.ok(not finale.is_running(), "finished helper stays stopped")
	t.ok(not finale.has_finished(), "cancel clears the finished latch")
	t.eq(_finale().get_instance_id(), helper_id, "finale helper is reused after the finish")
	t.ok(game.camera.position.is_equal_approx(CAMERA_HOME), "camera returns home")
	t.ok(not game.game_won, "reset clears the win state")
	t.ok(game.inner_core_mesh.visible, "the new rind is visible")

	await _wait(t, 3)
	t.eq(game.tile_nodes.size(), 488, "reset rebuilds 488 tiles after the finish")
	t.eq(game.elastic_pivot.get_child_count(), PIVOT_CHILDREN, "pivot returns to the base scene")
	t.ok(_finale().get_node_or_null("MotherLodeCore") == null, "core is freed on reset")
	t.ok(not is_instance_valid(done_rind), "old rind is freed after the finish")

func _test_camera_stability(t) -> void:
	t.group("camera stability across victory")
	t.ok(game.camera.position.is_equal_approx(game.camera_home), "board starts at the camera home")
	_populate()

	game._shake_camera()
	await _wait(t, 3)
	t.ok(
		not game.camera.position.is_equal_approx(game.camera_home),
		"the strike shake moves the camera off home"
	)

	_force_win()
	t.ok(
		game.camera.position.is_equal_approx(game.camera_home),
		"claim snaps the camera home immediately (shake tween killed)"
	)
	await _wait(t, 3)
	t.ok(
		game.camera.position.is_equal_approx(game.camera_home),
		"camera stays home before the finale dolly starts"
	)

	var frames := await _wait_until(
		t, func() -> bool: return game.camera.position.z > game.camera_home.z + 0.05, 120
	)
	t.ok(frames < 120, "finale dolly starts after the delay (%d frames)" % frames)

	game.reset_game()
	t.ok(game.camera.position.is_equal_approx(game.camera_home), "reset returns the camera home")
	t.ok(is_equal_approx(game.camera.position.z, 18.0), "camera home z is 18")
	await _wait(t, 3)

func _test_cracked_final_copy(t) -> void:
	t.group("cracked final copy")
	_populate()

	var cracked := 0
	for cell in game.grid.all_cells:
		if not cell.is_gem:
			cell.is_revealed = true
		elif cracked < 2:
			cell.is_detonated = true
			cell.is_marked = true
			cracked += 1
		else:
			cell.is_marked = true
	t.eq(cracked, 2, "setup cracked exactly two gems")
	t.eq(game.grid.get_board_stats()["gems_cracked"], 2, "grid reports two cracked gems")

	var claims_before: int = claim_hits
	game._check_victory()
	t.eq(claim_hits, claims_before + 1, "a board with cracked gems still wins")

	var finale = _finale()
	t.ok(finale != null, "finale helper exists for the cracked board")
	if finale == null:
		return
	var frames := await _wait_until(t, func() -> bool: return finale.has_finished(), FULL_FINALE_FRAMES)
	t.ok(frames < FULL_FINALE_FRAMES, "finale finishes with cracked gems (%d frames)" % frames)

	var hud: String = game.face_info_label.text
	t.ok(hud.contains("CLAIM COMPLETE"), "final HUD announces the claim: %s" % hud)
	t.ok(hud.contains("gems secured"), "final HUD reports secured gems: %s" % hud)
	t.ok(hud.contains("(2 cracked)"), "final HUD reports the cracked count: %s" % hud)
	t.no_emoji(hud, "cracked finale HUD")

	game.reset_game()
	await _wait(t, 3)

func _test_no_leaks(t) -> void:
	t.group("no leaks across cycles")
	# Prime one win + reset so the persistent finale helper is in the baseline.
	_populate()
	_force_win()
	await _wait_until(t, func() -> bool:
		var f = _finale()
		return f != null and f.has_finished(), FULL_FINALE_FRAMES)
	game.reset_game()
	await _wait(t, 5)

	var base_nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var base_objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))

	for cycle in range(2):
		_populate()
		_force_win()
		await _wait(t, 15)  # cancel mid-sweep
		game.reset_game()
		await _wait(t, 5)

		_populate()
		_force_win()
		await _wait_until(t, func() -> bool:
			var f = _finale()
			return f != null and f.has_finished(), FULL_FINALE_FRAMES)
		game.reset_game()
		await _wait(t, 5)

	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	t.ok(nodes - base_nodes <= 2, "node count is stable across cycles (%d -> %d)" % [base_nodes, nodes])
	# OBJECT_COUNT also tracks engine-side caches (Label3D text meshes, tween
	# bookkeeping) that plateau around +10 after the first few finales rather
	# than growing per cycle. The node assertion is the leak gate; this is a
	# coarse backstop that still fails on a per-tile leak (+488 per cycle).
	t.ok(
		objects - base_objects <= 16,
		"object count stays within engine churn (%d -> %d)" % [base_objects, objects]
	)
	t.eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), 0, "no orphan nodes after the cycles")
	t.eq(_finale().get_child_count(), 0, "finale helper owns nothing at rest")
	t.eq(game.tile_nodes.size(), 488, "board is intact after the cycles")

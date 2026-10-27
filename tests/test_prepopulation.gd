extends RefCounted

# Pre-population contract: provisional stats, neutral (anti-oracle) HUD copy,
# no progress signals/victory/finale before gems exist, and the cube-net scene
# wiring. Async because the net polls on `_process` and wires its reset hooks
# with `call_deferred`.

const CENTER := Vector3i(5, 4, 9)
const EXPECTED_ROCK := 428

var game
var claim_hits: int = 0
var surveyed_faces: Array[int] = []

func suite_name() -> String:
	return "prepopulation"

func run(t) -> void:
	if not t.ok(t.tree != null, "runner provided a SceneTree"):
		return

	var packed = load("res://volumetric_minesweeper.tscn")
	game = packed.instantiate()
	t.tree.root.add_child(game)
	game.claim_complete.connect(func() -> void: claim_hits += 1)
	game.face_surveyed.connect(func(f: int) -> void: surveyed_faces.append(f))

	_test_board_stats(t)
	_test_hud(t)
	_test_panel_toggles(t)
	_test_neutral_stake_count(t)
	_test_face_line_hides_rock_ratio(t)
	_test_no_early_progress(t)
	await _test_claim_net_boot(t)
	await _test_claim_net_secured_count(t)

	game.reset_game()
	game.queue_free()
	await _wait(t, 2)
	t.ok(not is_instance_valid(game), "pre-population scene is freed")

func _wait(t, frames: int) -> void:
	for i in range(frames):
		await t.tree.process_frame

func _test_board_stats(t) -> void:
	t.group("pre-population board stats")
	var board: Dictionary = game.grid.get_board_stats()
	t.eq(board["total_cells"], 488, "488 shell cells")
	t.eq(board["rock_total"], 488, "every cell is provisional rock before the first pick")
	t.eq(board["gem_total"], 0, "no gems exist before the first pick")
	t.eq(board["resolved_cells"], 0, "nothing is resolved")
	t.ok(not board["gems_populated"], "gems_populated is false")
	t.ok(not board["is_complete"], "unpopulated board is not complete")
	t.ok(not board["all_rock_excavated"], "all_rock_excavated is gated on population")
	t.ok(not board["all_gems_resolved"], "all_gems_resolved is gated on population")
	t.eq(game.tile_nodes.size(), 488, "488 tile nodes built")

func _test_hud(t) -> void:
	t.group("neutral pre-population HUD")
	var stats: String = game.stats_label.text
	var expected_rock: int = game.grid.all_cells.size() - game.total_gems
	t.eq(expected_rock, EXPECTED_ROCK, "expected rock is total_cells - total_gems")
	t.ok(stats.contains("Stakes placed 0"), "HUD shows zero stakes: %s" % stats)
	t.ok(stats.contains("0/%d" % expected_rock), "HUD shows a provisional rock denominator: %s" % stats)
	t.ok(
		stats.contains("Integrity %d/%d" % [game.max_strikes, game.max_strikes]),
		"HUD shows pick integrity: %s" % stats
	)
	t.ok(not stats.contains("Gems secured"), "HUD does not reveal live gem progress")
	t.ok(not stats.contains("Misplaced stakes"), "HUD does not reveal live stake placement")
	t.no_emoji(stats, "pre-population HUD")
	t.ok(
		game.face_info_label.text.contains("survey the geode to begin"),
		"face line prompts the first pick: %s" % game.face_info_label.text
	)

func _test_panel_toggles(t) -> void:
	t.group("collapsible HUD panels")
	var top_panel: PanelContainer = game.get_node("UI/Panel")
	var top_toggle: Button = game.get_node("UI/Panel/VBoxContainer/TitleRow/TopToggle")
	var top_title: Label = game.get_node("UI/Panel/VBoxContainer/TitleRow/TitleLabel")
	var top_face: Label = game.get_node("UI/Panel/VBoxContainer/FaceInfoLabel")
	var top_stats: Label = game.get_node("UI/Panel/VBoxContainer/StatsLabel")
	var top_actions: HBoxContainer = game.get_node("UI/Panel/VBoxContainer/ActionRow")

	var net_panel: PanelContainer = game.get_node("UI/CubeNetPanel")
	var net_toggle: Button = game.get_node("UI/CubeNetPanel/VBox/TitleRow/NetToggle")
	var net_title: Label = game.get_node("UI/CubeNetPanel/VBox/TitleRow/NetTitleLabel")
	var net_canvas: Control = game.get_node("UI/CubeNetPanel/VBox/NetCanvas")
	var net_footer: Label = game.get_node("UI/CubeNetPanel/VBox/NetFooterLabel")

	t.eq(top_toggle.text, "Hide HUD", "top panel starts expanded")
	t.eq(net_toggle.text, "Hide Survey", "claim survey starts expanded")
	var top_width: float = top_panel.offset_right - top_panel.offset_left
	var net_width: float = net_panel.offset_right - net_panel.offset_left

	top_toggle.pressed.emit()
	t.ok(
		not top_title.visible and not top_face.visible and not top_stats.visible and not top_actions.visible,
		"top panel content collapses"
	)
	t.ok(top_toggle.visible, "top show button stays visible")
	t.ok(
		top_panel.offset_right - top_panel.offset_left < top_width,
		"top panel width shrinks"
	)
	t.eq(top_toggle.text, "Show HUD", "top button switches to show")

	top_toggle.pressed.emit()
	t.ok(
		top_title.visible and top_face.visible and top_stats.visible and top_actions.visible,
		"top panel content restores"
	)
	t.ok(
		is_equal_approx(top_panel.offset_right - top_panel.offset_left, top_width),
		"top panel width restores"
	)
	t.eq(top_toggle.text, "Hide HUD", "top button switches back to hide")

	net_toggle.pressed.emit()
	t.ok(
		not net_title.visible and not net_canvas.visible and not net_footer.visible,
		"claim survey content collapses"
	)
	t.ok(net_toggle.visible, "claim survey show button stays visible")
	t.ok(
		net_panel.offset_right - net_panel.offset_left < net_width,
		"claim survey width shrinks"
	)
	t.eq(net_toggle.text, "Show Survey", "claim survey button switches to show")

	net_toggle.pressed.emit()
	t.ok(
		net_title.visible and net_canvas.visible and net_footer.visible,
		"claim survey content restores"
	)
	t.ok(
		is_equal_approx(net_panel.offset_right - net_panel.offset_left, net_width),
		"claim survey width restores"
	)
	t.eq(net_toggle.text, "Hide Survey", "claim survey button switches back to hide")

func _test_neutral_stake_count(t) -> void:
	t.group("neutral stake count before the first pick")
	game.reset_game()
	var marked := 0
	for cell in game.grid.all_cells:
		if marked >= 30:
			break
		game._on_tile_clicked(cell.coord, MOUSE_BUTTON_RIGHT)
		marked += 1
	t.eq(marked, 30, "right-clicked 30 cells")
	t.eq(game.grid.get_board_stats()["misplaced_marks"], 30, "all 30 stakes are provisional rock stakes")

	var stats: String = game.stats_label.text
	t.ok(stats.contains("Stakes placed 30"), "HUD counts provisional stakes: %s" % stats)
	t.ok(not stats.contains("Gems secured"), "HUD does not reveal gem progress")
	t.ok(not stats.contains("Misplaced stakes"), "HUD does not label provisional stakes as misplaced")
	t.ok(stats.contains("0/%d" % EXPECTED_ROCK), "global stats keep the rock denominator: %s" % stats)
	t.no_emoji(stats, "pre-population stake HUD")
	game.reset_game()

func _test_face_line_hides_rock_ratio(t) -> void:
	t.group("face line hides per-face rock totals")
	game.reset_game()
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)
	t.ok(game.grid.gems_populated, "first pick populates the board")

	var face: Dictionary = game.grid.get_face_stats(game.current_viewed_face)
	var face_text: String = game.face_info_label.text
	t.ok(face["face_rock_excavated"] >= 1, "the viewed face has excavated rock")
	t.ok(
		face_text.contains("Rock %d" % face["face_rock_excavated"]),
		"face line reports the excavated count: %s" % face_text
	)
	t.ok(not face_text.contains("/"), "face line hides the per-face denominator: %s" % face_text)
	t.ok(not face_text.contains("Rock 0/"), "no Rock 0/<total> ratio")
	t.ok(not face_text.contains("Rock 1/"), "no Rock 1/<total> ratio")
	t.ok(
		game.stats_label.text.contains("/%d" % EXPECTED_ROCK),
		"global stats keep the rock denominator: %s" % game.stats_label.text
	)

func _test_no_early_progress(t) -> void:
	t.group("no progress before population")
	game.reset_game()
	var claims_before: int = claim_hits
	var surveyed_before: int = surveyed_faces.size()

	var marked := 0
	for cell in game.grid.all_cells:
		if marked >= 30:
			break
		if cell.coord == CENTER:
			continue
		game._on_tile_clicked(cell.coord, MOUSE_BUTTON_RIGHT)
		marked += 1
	t.eq(game.grid.get_board_stats()["misplaced_marks"], 30, "pre-population stakes are stored")
	t.eq(surveyed_faces.size(), surveyed_before, "staking before population emits no face survey")
	t.eq(claim_hits, claims_before, "staking before population emits no claim")
	t.ok(game.get_node_or_null("ExcavationFinale") == null, "finale helper is not created before victory")

	# Even a fully resolved grid must not win while gems are unplaced.
	for cell in game.grid.all_cells:
		cell.is_revealed = true
		cell.is_marked = true
	game._check_victory()
	t.ok(not game.game_won, "a forced resolved grid cannot win before population")
	t.ok(not game.game_over, "forced state fabricates no loss")
	t.eq(claim_hits, claims_before, "forced completion emits no claim")
	t.eq(surveyed_faces.size(), surveyed_before, "forced completion emits no survey")
	t.ok(game.get_node_or_null("ExcavationFinale") == null, "no finale helper after forced completion")

func _test_claim_net_boot(t) -> void:
	t.group("claim net scene boot")
	game.reset_game()
	await _wait(t, 12)  # one 0.1 s poll at fixed 60 fps plus deferred wiring

	var net = game.get_node_or_null("UI/CubeNetPanel/VBox/NetCanvas")
	t.ok(net != null, "NetCanvas exists")
	if net == null:
		return
	t.ok(net.get_script() == load("res://claim_net.gd"), "NetCanvas runs claim_net.gd")
	t.eq(net.controller_path, NodePath("../../../.."), "controller_path resolves to the scene root")
	t.ok(not net._net_disabled, "cube net is enabled for a 10x10 board")

	var title: Label = game.get_node("UI/CubeNetPanel/VBox/TitleRow/NetTitleLabel")
	var footer: Label = game.get_node("UI/CubeNetPanel/VBox/NetFooterLabel")
	t.eq(title.text, "CLAIM SURVEY · UNSURVEYED", "pre-population title")
	t.eq(
		footer.text,
		"First pick is safe · %d rock · %d gems expected" % [EXPECTED_ROCK, game.total_gems],
		"pre-population footer"
	)
	t.ok(
		game.restart_button.pressed.is_connected(Callable(net, "_on_new_game")),
		"New Claim is wired after the deferred hook runs"
	)
	t.ok(
		game.difficulty_option.item_selected.is_connected(Callable(net, "_on_difficulty_selected")),
		"difficulty selector is wired"
	)

func _test_claim_net_secured_count(t) -> void:
	t.group("claim net win copy reports secured gems")
	game.reset_game()
	await _wait(t, 2)
	game._on_tile_clicked(CENTER, MOUSE_BUTTON_LEFT)

	var staked := 0
	for cell in game.grid.all_cells:
		if cell.is_gem and staked < 5:
			cell.is_marked = true
			staked += 1
	t.eq(staked, 5, "staked five gems")

	game._trigger_claim_complete()
	await _wait(t, 2)

	var title: Label = game.get_node("UI/CubeNetPanel/VBox/TitleRow/NetTitleLabel")
	var footer: Label = game.get_node("UI/CubeNetPanel/VBox/NetFooterLabel")
	t.eq(title.text, "CLAIM COMPLETE", "win title")
	t.ok(footer.text.contains("5 gems secured"), "footer reports actual secured gems: %s" % footer.text)
	t.ok(not footer.text.contains("60 gems secured"), "footer does not fall back to the expected total")
	t.eq(claim_hits, 1, "claim emitted once")

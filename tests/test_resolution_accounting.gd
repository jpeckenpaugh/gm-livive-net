extends RefCounted

# Resolution truth table, staked/cracked/misplaced accounting, face stats,
# and board completion. `is_cell_resolved()` is the single source of truth.

const Grid = preload("res://volumetric_grid.gd")
const SIZE := 10
const CENTER := Vector3i(5, 4, 9)

func suite_name() -> String:
	return "resolution_accounting"

func run(t) -> void:
	_test_truth_table(t)
	_test_population_gate(t)
	_test_stats_keys(t)
	_test_accounting(t)
	_test_edge_gem_two_faces(t)
	_test_cracked_gem(t)
	_test_completion(t)
	_test_zero_gem_completion(t)

func _new_grid():
	var g = Grid.new()
	g.init_grid(SIZE)
	return g

func _clear_cell(cell) -> void:
	cell.is_gem = false
	cell.is_revealed = false
	cell.is_marked = false
	cell.is_detonated = false

func _first_gem(g, min_faces: int = 1):
	for cell in g.all_cells:
		if cell.is_gem and cell.exterior_faces.size() >= min_faces:
			return cell
	return null

func _first_rock(g, unrevealed: bool = false):
	for cell in g.all_cells:
		if cell.is_gem:
			continue
		if unrevealed and cell.is_revealed:
			continue
		return cell
	return null

func _test_truth_table(t) -> void:
	t.group("is_cell_resolved truth table")
	var g = _new_grid()
	var rock = g.get_cell_at(Vector3i(5, 4, 9))
	var gem = g.get_cell_at(Vector3i(5, 4, 0))

	_clear_cell(rock)
	t.ok(not g.is_cell_resolved(rock), "rock unresolved by default")
	rock.is_marked = true
	t.ok(not g.is_cell_resolved(rock), "marked rock is still unresolved")
	rock.is_revealed = true
	t.ok(g.is_cell_resolved(rock), "revealed rock is resolved")
	rock.is_marked = false
	t.ok(g.is_cell_resolved(rock), "revealed rock resolves without a mark")

	_clear_cell(gem)
	gem.is_gem = true
	t.ok(not g.is_cell_resolved(gem), "gem unresolved by default")
	gem.is_revealed = true
	t.ok(not g.is_cell_resolved(gem), "revealed flag never resolves a gem")
	gem.is_revealed = false
	gem.is_marked = true
	t.ok(g.is_cell_resolved(gem), "staked gem is resolved")
	gem.is_marked = false
	gem.is_detonated = true
	t.ok(g.is_cell_resolved(gem), "cracked gem is resolved")
	gem.is_marked = true
	t.ok(g.is_cell_resolved(gem), "cracked and staked gem is resolved")

func _test_population_gate(t) -> void:
	t.group("completion requires population")
	var g = _new_grid()
	for cell in g.all_cells:
		cell.is_revealed = true
		cell.is_marked = true
	t.ok(not g.is_board_complete(), "unpopulated board is never complete")
	var board: Dictionary = g.get_board_stats()
	t.ok(not board["is_complete"], "stats is_complete stays false")
	t.ok(not board["all_rock_excavated"], "all_rock_excavated requires gems_populated")
	t.ok(not board["all_gems_resolved"], "all_gems_resolved requires gems_populated")

func _test_stats_keys(t) -> void:
	t.group("frozen stats key sets")
	var g = _new_grid()

	var face_keys: Array = g.get_face_stats(0).keys()
	face_keys.sort()
	var expected_face := [
		"face",
		"face_name",
		"face_total",
		"face_rock_total",
		"face_gem_total",
		"face_rock_excavated",
		"face_gems_staked",
		"face_gems_cracked",
		"face_gems_resolved",
		"face_resolved",
		"face_unresolved",
		"face_misplaced_marks",
		"is_face_complete",
	]
	expected_face.sort()
	t.eq(face_keys, expected_face, "face stats expose the frozen 13 keys")

	var board_keys: Array = g.get_board_stats().keys()
	board_keys.sort()
	var expected_board := [
		"size",
		"total_cells",
		"rock_total",
		"gem_total",
		"gems_populated",
		"rock_excavated",
		"rock_remaining",
		"gems_staked",
		"gems_cracked",
		"gems_resolved",
		"gems_remaining",
		"misplaced_marks",
		"resolved_cells",
		"unresolved_cells",
		"all_rock_excavated",
		"all_gems_resolved",
		"is_complete",
		"faces_complete",
	]
	expected_board.sort()
	t.eq(board_keys, expected_board, "board stats expose the frozen 18 keys")

func _test_accounting(t) -> void:
	t.group("board and face accounting")
	var g = _new_grid()
	seed(4242)
	g.populate_gems(CENTER, 60)

	var rocks := []
	var gems := []
	for cell in g.all_cells:
		if cell.is_gem:
			gems.append(cell)
		else:
			rocks.append(cell)

	for i in range(10):
		rocks[i].is_revealed = true
	for i in range(10, 13):
		rocks[i].is_marked = true
	for i in range(3):
		gems[i].is_marked = true
	for i in range(3, 5):
		gems[i].is_detonated = true
	gems[5].is_detonated = true
	gems[5].is_marked = true

	var board: Dictionary = g.get_board_stats()
	t.eq(board["rock_excavated"], 10, "excavated rock count")
	t.eq(board["rock_remaining"], 418, "remaining rock count")
	t.eq(board["gems_staked"], 3, "staked gem count")
	t.eq(board["gems_cracked"], 3, "cracked gem count (crack wins over stake)")
	t.eq(board["gems_resolved"], 6, "resolved gem count")
	t.eq(board["gems_remaining"], 54, "remaining gem count")
	t.eq(board["misplaced_marks"], 3, "marked rock counted as misplaced")
	t.eq(board["resolved_cells"], 16, "resolved cell count")
	t.eq(board["unresolved_cells"], 472, "unresolved cell count")
	t.eq(g.get_total_remaining_gems(), 54, "get_total_remaining_gems")
	t.ok(not board["all_rock_excavated"], "not all rock excavated")
	t.ok(not board["all_gems_resolved"], "not all gems resolved")
	t.ok(not board["is_complete"], "board not complete")

	var faces_bad := 0
	var complete_faces := 0
	for f in range(6):
		var fs: Dictionary = g.get_face_stats(f)
		var total := 0
		var rock_total := 0
		var gem_total := 0
		var rock_excavated := 0
		var staked := 0
		var cracked := 0
		var misplaced := 0
		var resolved := 0
		for cell in g.face_cells[f]:
			total += 1
			if cell.is_gem:
				gem_total += 1
				if cell.is_detonated:
					cracked += 1
				elif cell.is_marked:
					staked += 1
			else:
				rock_total += 1
				if cell.is_revealed:
					rock_excavated += 1
				if cell.is_marked:
					misplaced += 1
			if g.is_cell_resolved(cell):
				resolved += 1

		if fs["face_total"] != total:
			faces_bad += 1
		if fs["face_rock_total"] != rock_total:
			faces_bad += 1
		if fs["face_gem_total"] != gem_total:
			faces_bad += 1
		if fs["face_rock_excavated"] != rock_excavated:
			faces_bad += 1
		if fs["face_gems_staked"] != staked:
			faces_bad += 1
		if fs["face_gems_cracked"] != cracked:
			faces_bad += 1
		if fs["face_gems_resolved"] != staked + cracked:
			faces_bad += 1
		if fs["face_resolved"] != resolved:
			faces_bad += 1
		if fs["face_unresolved"] != total - resolved:
			faces_bad += 1
		if fs["face_misplaced_marks"] != misplaced:
			faces_bad += 1
		if fs["is_face_complete"] != (total > 0 and resolved == total):
			faces_bad += 1
		if fs["is_face_complete"]:
			complete_faces += 1

	t.eq(faces_bad, 0, "every face stat matches an independent tally")
	t.eq(board["faces_complete"], complete_faces, "board faces_complete matches face stats")

func _test_edge_gem_two_faces(t) -> void:
	t.group("edge gem resolves two faces")
	var g = _new_grid()
	var gem = null
	for s in [4242, 9001, 777, 2026, 1000]:
		g = _new_grid()
		seed(s)
		g.populate_gems(CENTER, 60)
		gem = _first_gem(g, 2)
		if gem != null:
			break

	t.ok(gem != null, "found a gem on an edge or corner")
	if gem == null:
		return

	var f0: int = gem.exterior_faces[0]
	var f1: int = gem.exterior_faces[1]
	t.ok(f0 != f1, "edge gem belongs to two distinct faces")
	t.ok(g.face_cells[f0].has(gem), "gem listed on its first face")
	t.ok(g.face_cells[f1].has(gem), "gem listed on its second face")

	var before0: Dictionary = g.get_face_stats(f0)
	var before1: Dictionary = g.get_face_stats(f1)
	var before_board: Dictionary = g.get_board_stats()

	gem.is_marked = true
	t.ok(g.is_cell_resolved(gem), "one stake resolves the edge gem")

	var after0: Dictionary = g.get_face_stats(f0)
	var after1: Dictionary = g.get_face_stats(f1)
	var after_board: Dictionary = g.get_board_stats()
	t.eq(after0["face_resolved"], before0["face_resolved"] + 1, "face 0 resolved count +1")
	t.eq(after1["face_resolved"], before1["face_resolved"] + 1, "face 1 resolved count +1")
	t.eq(after0["face_gems_staked"], before0["face_gems_staked"] + 1, "face 0 staked count +1")
	t.eq(after1["face_gems_staked"], before1["face_gems_staked"] + 1, "face 1 staked count +1")
	t.eq(after_board["resolved_cells"], before_board["resolved_cells"] + 1, "board counts the cell once")
	t.eq(after_board["gems_staked"], before_board["gems_staked"] + 1, "board stakes the gem once")

func _test_cracked_gem(t) -> void:
	t.group("cracked gem accounting")
	var g = _new_grid()
	seed(8080)
	g.populate_gems(CENTER, 60)
	var gem = _first_gem(g)
	t.ok(gem != null, "found a gem")
	if gem == null:
		return

	var before: Dictionary = g.get_board_stats()
	gem.is_detonated = true
	t.ok(g.is_cell_resolved(gem), "detonated gem is resolved")
	var after: Dictionary = g.get_board_stats()
	t.eq(after["gems_cracked"], before["gems_cracked"] + 1, "cracked count +1")
	t.eq(after["gems_staked"], before["gems_staked"], "cracked gem is not also staked")
	t.eq(after["gems_resolved"], before["gems_resolved"] + 1, "resolved count +1")

	gem.is_marked = true
	var both: Dictionary = g.get_board_stats()
	t.eq(both["gems_cracked"], after["gems_cracked"], "marked cracked gem stays cracked-only")
	t.eq(both["gems_staked"], after["gems_staked"], "marked cracked gem is not double-counted")

	var rock = _first_rock(g, true)
	t.ok(rock != null, "found an unrevealed rock")
	if rock != null:
		var before_rock: Dictionary = g.get_board_stats()
		rock.is_marked = true
		t.ok(not g.is_cell_resolved(rock), "marked rock remains unresolved")
		var after_rock: Dictionary = g.get_board_stats()
		t.eq(after_rock["misplaced_marks"], before_rock["misplaced_marks"] + 1, "misplaced stake counted")

func _test_completion(t) -> void:
	t.group("board completion predicates")
	var g = _new_grid()
	seed(2026)
	g.populate_gems(CENTER, 60)

	var first_gem = null
	var first_rock = null
	for cell in g.all_cells:
		if cell.is_gem:
			cell.is_marked = true
			if first_gem == null:
				first_gem = cell
		else:
			cell.is_revealed = true
			if first_rock == null:
				first_rock = cell

	t.ok(g.is_board_complete(), "all rock revealed and all gems staked completes the board")
	var board: Dictionary = g.get_board_stats()
	t.ok(board["all_rock_excavated"], "all_rock_excavated true")
	t.ok(board["all_gems_resolved"], "all_gems_resolved true")
	t.eq(board["gems_remaining"], 0, "no gems remaining")
	t.eq(board["rock_remaining"], 0, "no rock remaining")
	t.eq(board["faces_complete"], 6, "all six faces complete")
	for f in range(6):
		t.ok(g.get_face_stats(f)["is_face_complete"], "face %d complete" % f)

	first_gem.is_marked = false
	t.ok(not g.is_board_complete(), "unstaked gem breaks completion")
	t.eq(g.get_board_stats()["gems_remaining"], 1, "one gem remaining")
	first_gem.is_marked = true
	t.ok(g.is_board_complete(), "re-staking restores completion")

	first_rock.is_revealed = false
	first_rock.is_marked = true
	t.ok(not g.is_board_complete(), "unrevealed marked rock breaks completion")
	t.eq(g.get_board_stats()["misplaced_marks"], 1, "misplaced stake reported")
	var unresolved_face_cells := 0
	for f in first_rock.exterior_faces:
		unresolved_face_cells += g.get_face_stats(f)["face_unresolved"]
	t.ok(unresolved_face_cells >= 1, "the blocked rock keeps its faces unresolved")

func _test_zero_gem_completion(t) -> void:
	t.group("zero-gem board completion")
	var g = _new_grid()
	seed(1)
	g.populate_gems(CENTER, 0)
	t.eq(g.get_board_stats()["gem_total"], 0, "zero-gem board has no gems")
	for cell in g.all_cells:
		cell.is_revealed = true
	t.ok(g.is_board_complete(), "fully excavated zero-gem board completes")
	var board: Dictionary = g.get_board_stats()
	t.ok(board["all_rock_excavated"], "all rock excavated")
	t.ok(board["all_gems_resolved"], "zero gems are trivially resolved")
	t.eq(board["gems_resolved"], 0, "zero resolved gems")
	t.eq(g.get_total_remaining_gems(), 0, "zero remaining gems")

extends RefCounted

# Gem placement is lazy and RNG-driven. These tests assert structural
# invariants only; they never pin an exact layout (engine shuffle details are
# not part of the contract). Fixed seeds make failures reproducible.

const Grid = preload("res://volumetric_grid.gd")
const SIZE := 10
const TOTAL_GEMS := 60
const CENTER := Vector3i(5, 4, 9)
const CORNER := Vector3i(0, 9, 9)
const PREMARKS := 20

func suite_name() -> String:
	return "gem_placement"

func run(t) -> void:
	_test_lazy_placement(t)
	_test_counts_and_stats(t)
	_test_first_click_safety_center(t)
	_test_first_click_safety_corner(t)
	_test_premark_neutrality(t)
	_test_repopulate_totality(t)
	_test_seed_determinism(t)
	_test_multi_seed_invariants(t)
	_test_reinit_clears_gems(t)

func _count_gems(g) -> int:
	var count := 0
	for cell in g.all_cells:
		if cell.is_gem:
			count += 1
	return count

func _has_any_gem(g) -> bool:
	for cell in g.all_cells:
		if cell.is_gem:
			return true
	return false

func _gem_coords(g) -> Dictionary:
	var coords := {}
	for cell in g.all_cells:
		if cell.is_gem:
			coords[cell.coord] = true
	return coords

func _new_grid():
	var g = Grid.new()
	g.init_grid(SIZE)
	return g

func _test_lazy_placement(t) -> void:
	t.group("lazy placement")
	var g = _new_grid()
	t.ok(not g.gems_populated, "gems are not populated at init")
	t.ok(not _has_any_gem(g), "no cell is a gem at init")
	t.ok(not g.is_board_complete(), "board is not complete before population")
	t.eq(g.get_total_remaining_gems(), 0, "no remaining gems before population")
	var board: Dictionary = g.get_board_stats()
	t.eq(board["total_cells"], 488, "board total before population")
	t.eq(board["gem_total"], 0, "gem total before population")
	t.eq(board["rock_total"], 488, "rock total before population")
	t.ok(not board["all_rock_excavated"], "all_rock_excavated requires population")

func _test_counts_and_stats(t) -> void:
	t.group("population counts")
	var g = _new_grid()
	seed(4242)
	g.populate_gems(CENTER, TOTAL_GEMS)

	t.ok(g.gems_populated, "gems_populated set after populate")
	t.eq(_count_gems(g), TOTAL_GEMS, "exactly 60 gems placed")
	t.eq(g.get_total_remaining_gems(), TOTAL_GEMS, "all gems remain unresolved")
	var board: Dictionary = g.get_board_stats()
	t.eq(board["total_cells"], 488, "board total")
	t.eq(board["rock_total"], 428, "428 rock cells")
	t.eq(board["gem_total"], 60, "60 gem cells")
	t.eq(board["rock_excavated"], 0, "nothing excavated")
	t.eq(board["gems_remaining"], 60, "60 gems remaining")
	t.ok(not board["all_rock_excavated"], "not all rock excavated")
	t.ok(not board["all_gems_resolved"], "not all gems resolved")
	t.ok(not board["is_complete"], "board not complete")

	var memberships := 0
	for f in range(6):
		memberships += g.get_face_stats(f)["face_total"]
	t.eq(memberships, 600, "face stats still total 600 memberships")

func _test_first_click_safety_center(t) -> void:
	t.group("first-click safety (face interior)")
	var g = _new_grid()
	seed(4242)
	g.populate_gems(CENTER, TOTAL_GEMS)

	t.ok(not g.get_cell_at(CENTER).is_gem, "clicked center cell is safe")
	var neighbors: Array = g.get_neighbors(CENTER)
	t.eq(neighbors.size(), 8, "center has 8 global neighbors")
	var unsafe := 0
	for n in neighbors:
		if n.is_gem:
			unsafe += 1
	t.eq(unsafe, 0, "all 8 first-click neighbors are safe")
	t.eq(_count_gems(g), 60, "safety does not reduce the gem count")

func _test_first_click_safety_corner(t) -> void:
	t.group("first-click safety (cube corner)")
	var g = _new_grid()
	seed(77)
	g.populate_gems(CORNER, TOTAL_GEMS)

	t.ok(not g.get_cell_at(CORNER).is_gem, "clicked corner cell is safe")
	var neighbors: Array = g.get_neighbors(CORNER)
	t.eq(neighbors.size(), 6, "corner has 6 global neighbors")
	var unsafe := 0
	for n in neighbors:
		if n.is_gem:
			unsafe += 1
	t.eq(unsafe, 0, "all 6 first-click neighbors are safe")
	t.eq(_count_gems(g), 60, "safety does not reduce the gem count")

func _test_premark_neutrality(t) -> void:
	t.group("pre-mark neutrality")
	var plain = _new_grid()
	seed(9001)
	plain.populate_gems(CENTER, TOTAL_GEMS)
	var plain_gems := _gem_coords(plain)

	var marked = _new_grid()
	var marks := {}
	var marked_count := 0
	for cell in marked.all_cells:
		if cell.coord == CENTER:
			continue
		if marked_count >= PREMARKS:
			break
		cell.is_marked = true
		marks[cell.coord] = true
		marked_count += 1

	seed(9001)
	marked.populate_gems(CENTER, TOTAL_GEMS)
	var marked_gems := _gem_coords(marked)

	t.eq(marked_count, PREMARKS, "setup marked %d cells" % PREMARKS)
	t.eq(_count_gems(marked), TOTAL_GEMS, "pre-marks do not reduce the gem count")
	t.eq(marked_gems, plain_gems, "pre-marks do not change the gem layout")

	var marks_lost := 0
	var marks_on_gems := 0
	for coord in marks:
		var cell = marked.get_cell_at(coord)
		if not cell.is_marked:
			marks_lost += 1
		if cell.is_gem:
			marks_on_gems += 1
	t.eq(marks_lost, 0, "population preserves existing stakes")
	t.ok(marks_on_gems >= 1, "pre-marks may land on gems")

	var unsafe := 0
	if marked.get_cell_at(CENTER).is_gem:
		unsafe += 1
	for n in marked.get_neighbors(CENTER):
		if n.is_gem:
			unsafe += 1
	t.eq(unsafe, 0, "pre-marks never weaken first-click safety")

func _test_repopulate_totality(t) -> void:
	t.group("populate_gems totality")
	var g = _new_grid()
	seed(4242)
	g.populate_gems(CENTER, TOTAL_GEMS)
	t.eq(_count_gems(g), TOTAL_GEMS, "first populate places %d gems" % TOTAL_GEMS)

	seed(4242)
	g.populate_gems(CORNER, TOTAL_GEMS)
	t.eq(_count_gems(g), TOTAL_GEMS, "second populate does not accumulate gems")
	t.eq(g.get_board_stats()["gem_total"], TOTAL_GEMS, "gem_total stays exact after re-population")

	var unsafe := 0
	if g.get_cell_at(CORNER).is_gem:
		unsafe += 1
	for n in g.get_neighbors(CORNER):
		if n.is_gem:
			unsafe += 1
	t.eq(unsafe, 0, "the second call keeps its own safe set clear")

	var stale := 0
	var mismatch := 0
	for cell in g.all_cells:
		if cell.is_gem:
			if not cell.face_neighbor_gems.is_empty():
				stale += 1
			continue
		for f in cell.exterior_faces:
			var expected := 0
			for n in g.get_face_neighbors(f, cell.coord):
				if n.is_gem:
					expected += 1
			if int(cell.face_neighbor_gems.get(f, -1)) != expected:
				mismatch += 1
	t.eq(stale, 0, "gem cells never carry face numbers")
	t.eq(mismatch, 0, "rock face numbers are recomputed after re-population")

func _test_seed_determinism(t) -> void:
	t.group("seed determinism")
	var a = _new_grid()
	seed(31337)
	a.populate_gems(CENTER, TOTAL_GEMS)
	var b = _new_grid()
	seed(31337)
	b.populate_gems(CENTER, TOTAL_GEMS)

	var differing := 0
	for cell in a.all_cells:
		if cell.is_gem != b.get_cell_at(cell.coord).is_gem:
			differing += 1
	t.eq(differing, 0, "same seed produces the same gem layout")

func _test_multi_seed_invariants(t) -> void:
	t.group("multi-seed structural invariants")
	var failures := 0
	var min_face_gems := 100
	for s in range(20):
		var g = _new_grid()
		var safe: Vector3i = CORNER if s % 2 == 0 else CENTER
		seed(1000 + s)
		g.populate_gems(safe, TOTAL_GEMS)

		if _count_gems(g) != 60:
			failures += 1
		if g.get_cell_at(safe).is_gem:
			failures += 1
		for n in g.get_neighbors(safe):
			if n.is_gem:
				failures += 1

		var per_face := [0, 0, 0, 0, 0, 0]
		var memberships := 0
		for cell in g.all_cells:
			memberships += cell.exterior_faces.size()
			if cell.is_gem:
				for f in cell.exterior_faces:
					per_face[f] += 1
		if memberships != 600:
			failures += 1
		for f in range(6):
			min_face_gems = min(min_face_gems, per_face[f])

	t.eq(failures, 0, "20 seeds keep count, safety, and face membership invariants")
	t.ok(min_face_gems >= 1, "each face receives at least one gem across 20 seeds")

func _test_reinit_clears_gems(t) -> void:
	t.group("re-init clears placement")
	var g = _new_grid()
	seed(5)
	g.populate_gems(CENTER, TOTAL_GEMS)
	t.ok(_has_any_gem(g), "board has gems before re-init")

	g.init_grid(SIZE)
	t.ok(not g.gems_populated, "re-init clears gems_populated")
	t.eq(_count_gems(g), 0, "re-init clears every is_gem flag")
	t.eq(g.cells.size(), 488, "re-init rebuilds 488 cells")
	t.eq(g.face_cells[0].size(), 100, "re-init rebuilds face membership")

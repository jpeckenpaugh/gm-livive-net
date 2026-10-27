extends RefCounted

# Numbers are face-local: every non-gem cell stores one count per exterior
# face, computed only from that face's 8-neighborhood. Edge and corner cells
# therefore carry several independent numbers.

const Grid = preload("res://volumetric_grid.gd")
const SIZE := 10
const CENTER := Vector3i(5, 4, 9)
const CORNER := Vector3i(0, 9, 9)

func suite_name() -> String:
	return "face_numbering"

func run(t) -> void:
	var found_face_vs_global_difference := false
	found_face_vs_global_difference = _test_counts(t, 4242, CENTER) or found_face_vs_global_difference
	found_face_vs_global_difference = _test_counts(t, 9001, CORNER) or found_face_vs_global_difference
	t.group("face-local vs global numbering")
	t.ok(found_face_vs_global_difference, "some edge/corner number differs from its global gem count")
	_test_multiface_cells(t)

func _new_grid():
	var g = Grid.new()
	g.init_grid(SIZE)
	return g

func _count_gem_neighbors(g, coord: Vector3i) -> int:
	var count := 0
	for n in g.get_neighbors(coord):
		if n.is_gem:
			count += 1
	return count

func _expected_face_count(g, face: int, coord: Vector3i) -> int:
	var count := 0
	for n in g.get_face_neighbors(face, coord):
		if n.is_gem:
			count += 1
	return count

func _test_counts(t, s: int, safe: Vector3i) -> bool:
	t.group("face-local counts (seed %d, safe %s)" % [s, str(safe)])
	var g = _new_grid()
	seed(s)
	g.populate_gems(safe, 60)

	var size_mismatch := 0
	var value_mismatch := 0
	var bounds_violations := 0
	var gem_dict_violations := 0
	var single_face_mismatch := 0
	var face_vs_global_difference := false

	for cell in g.all_cells:
		if cell.is_gem:
			# Current Phase 1 behavior: gem cells carry no number dictionary.
			if not cell.face_neighbor_gems.is_empty():
				gem_dict_violations += 1
			continue

		if cell.face_neighbor_gems.size() != cell.exterior_faces.size():
			size_mismatch += 1

		for f in cell.exterior_faces:
			var local: Array = g.get_face_neighbors(f, cell.coord)
			var expected := _expected_face_count(g, f, cell.coord)
			if cell.face_neighbor_gems.get(f, -1) != expected:
				value_mismatch += 1
			if expected > local.size():
				bounds_violations += 1

		if cell.exterior_faces.size() == 1:
			var f: int = cell.exterior_faces[0]
			if cell.face_neighbor_gems.get(f, -1) != _count_gem_neighbors(g, cell.coord):
				single_face_mismatch += 1
		else:
			var global_count := _count_gem_neighbors(g, cell.coord)
			for f in cell.exterior_faces:
				if cell.face_neighbor_gems.get(f, 0) != global_count:
					face_vs_global_difference = true

	t.eq(size_mismatch, 0, "one stored count per exterior face")
	t.eq(value_mismatch, 0, "stored counts match face-local recomputation")
	t.eq(bounds_violations, 0, "no count exceeds its face-local neighbor count")
	t.eq(gem_dict_violations, 0, "gem cells have no face number dictionary")
	t.eq(single_face_mismatch, 0, "single-face numbers equal global gem counts")
	return face_vs_global_difference

func _test_multiface_cells(t) -> void:
	t.group("edge and corner number entries")
	var g = _new_grid()
	var edge = null
	var corner = null
	for s in [4242, 9001, 777, 2026]:
		g = _new_grid()
		seed(s)
		g.populate_gems(CENTER, 60)
		for cell in g.all_cells:
			if cell.is_gem:
				continue
			if edge == null and cell.exterior_faces.size() == 2:
				edge = cell
			if corner == null and cell.exterior_faces.size() == 3:
				corner = cell
		if edge != null and corner != null:
			break

	t.ok(edge != null, "found a non-gem edge cell")
	t.ok(corner != null, "found a non-gem corner cell")
	if edge == null or corner == null:
		return

	t.eq(edge.exterior_faces.size(), 2, "edge cell owns two faces")
	t.eq(edge.face_neighbor_gems.size(), 2, "edge cell stores two numbers")
	for f in edge.exterior_faces:
		t.eq(
			edge.face_neighbor_gems.get(f, -1),
			_expected_face_count(g, f, edge.coord),
			"edge number on face %d is face-local" % f
		)

	t.eq(corner.exterior_faces.size(), 3, "corner cell owns three faces")
	t.eq(corner.face_neighbor_gems.size(), 3, "corner cell stores three numbers")
	for f in corner.exterior_faces:
		t.eq(
			corner.face_neighbor_gems.get(f, -1),
			_expected_face_count(g, f, corner.coord),
			"corner number on face %d is face-local" % f
		)

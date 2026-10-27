extends RefCounted

# Topology of the 10x10x10 shell: cell counts, face membership, face mapping,
# and the two neighbor graphs. No gem placement is involved.

const Grid = preload("res://volumetric_grid.gd")
const SIZE := 10
const CELLS := 488
const MEMBERSHIPS := 600

func suite_name() -> String:
	return "grid_topology"

func run(t) -> void:
	var g = Grid.new()
	g.init_grid(SIZE)
	_test_shell_counts(t, g)
	_test_face_membership(t, g)
	_test_face_mapping(t, g)
	_test_neighbor_graphs(t, g)
	_test_missing_coords(t, g)
	_test_missing_face_keys(t, g)

func _test_shell_counts(t, g) -> void:
	t.group("shell cell counts")
	t.eq(g.size, SIZE, "grid size")
	t.eq(g.cells.size(), CELLS, "unique shell voxels")
	t.eq(g.all_cells.size(), CELLS, "all_cells length")
	t.eq(SIZE * SIZE * SIZE - (SIZE - 2) * (SIZE - 2) * (SIZE - 2), CELLS, "shell count formula")

	var last := SIZE - 1
	var shape_ok := true
	var keyed_ok := true
	for cell in g.all_cells:
		var c: Vector3i = cell.coord
		var in_bounds := c.x >= 0 and c.x <= last and c.y >= 0 and c.y <= last and c.z >= 0 and c.z <= last
		var on_shell := c.x == 0 or c.x == last or c.y == 0 or c.y == last or c.z == 0 or c.z == last
		if not in_bounds or not on_shell:
			shape_ok = false
		if g.cells.get(c) != cell:
			keyed_ok = false
	t.ok(shape_ok, "every coord is an in-bounds shell voxel")
	t.ok(keyed_ok, "cells dictionary maps every coord to its CellData")

func _test_face_membership(t, g) -> void:
	t.group("face membership")
	var total := 0
	var per_face_ok := true
	var ownership_ok := true
	for f in range(6):
		t.eq(g.face_cells[f].size(), 100, "face %d cell count" % f)
		total += g.face_cells[f].size()

		var seen := {}
		for cell in g.face_cells[f]:
			if seen.has(cell.coord):
				per_face_ok = false
			seen[cell.coord] = true
			if not (f in cell.exterior_faces):
				per_face_ok = false
		if seen.size() != 100:
			per_face_ok = false
	t.eq(total, MEMBERSHIPS, "total face memberships")
	t.ok(per_face_ok, "each face lists 100 unique cells and marks itself exterior")

	var hist := {}
	for cell in g.all_cells:
		var n: int = cell.exterior_faces.size()
		hist[n] = hist.get(n, 0) + 1
	t.eq(hist.get(3, 0), 8, "8 cube corners belong to 3 faces")
	t.eq(hist.get(2, 0), 96, "96 edge cells belong to 2 faces")
	t.eq(hist.get(1, 0), 384, "384 face-interior cells belong to 1 face")
	t.eq(hist.size(), 3, "no other face-ownership counts")

	for cell in g.all_cells:
		for f in cell.exterior_faces:
			if not g.face_cells[f].has(cell):
				ownership_ok = false
	t.ok(ownership_ok, "every exterior face lists its cell in face_cells")

func _test_face_mapping(t, g) -> void:
	t.group("face_uv_to_voxel orientation")
	var origins := {
		0: Vector3i(0, 9, 9),
		1: Vector3i(9, 9, 9),
		2: Vector3i(9, 9, 0),
		3: Vector3i(0, 9, 0),
		4: Vector3i(0, 9, 0),
		5: Vector3i(0, 0, 9),
	}
	var rights := {
		0: Vector3i(1, 0, 0),
		1: Vector3i(0, 0, -1),
		2: Vector3i(-1, 0, 0),
		3: Vector3i(0, 0, 1),
		4: Vector3i(1, 0, 0),
		5: Vector3i(1, 0, 0),
	}
	var downs := {
		0: Vector3i(0, -1, 0),
		1: Vector3i(0, -1, 0),
		2: Vector3i(0, -1, 0),
		3: Vector3i(0, -1, 0),
		4: Vector3i(0, 0, 1),
		5: Vector3i(0, 0, -1),
	}

	for f in range(6):
		var origin: Vector3i = Grid.face_uv_to_voxel(f, 0, 0, SIZE)
		t.eq(origin, origins[f], "face %d uv(0,0)" % f)
		t.eq(Grid.face_uv_to_voxel(f, 1, 0, SIZE) - origin, rights[f], "face %d +u direction" % f)
		t.eq(Grid.face_uv_to_voxel(f, 0, 1, SIZE) - origin, downs[f], "face %d +v direction" % f)
		t.eq(
			Grid.face_uv_to_voxel(f, 5, 4, SIZE),
			origin + rights[f] * 5 + downs[f] * 4,
			"face %d affine mapping at uv(5,4)" % f
		)

		var seen := {}
		var face_coords := {}
		for cell in g.face_cells[f]:
			face_coords[cell.coord] = true
		var mapping_ok := true
		for u in range(SIZE):
			for v in range(SIZE):
				var coord: Vector3i = Grid.face_uv_to_voxel(f, u, v, SIZE)
				if seen.has(coord):
					mapping_ok = false
				seen[coord] = true
				var cell = g.get_cell_at(coord)
				if cell == null or not (f in cell.exterior_faces):
					mapping_ok = false
				if not face_coords.has(coord):
					mapping_ok = false
		t.ok(mapping_ok and seen.size() == 100, "face %d uv grid is a bijection onto its 100 cells" % f)

func _test_neighbor_graphs(t, g) -> void:
	t.group("global manifold neighbor graph")
	t.eq(g.neighbor_graph.size(), CELLS, "neighbor_graph has one entry per shell cell")

	var hist := {}
	var self_loops := 0
	var unknown_neighbors := 0
	var asymmetric := 0
	for cell in g.all_cells:
		var neighbors: Array = g.get_neighbors(cell.coord)
		hist[neighbors.size()] = hist.get(neighbors.size(), 0) + 1
		for n in neighbors:
			if n.coord == cell.coord:
				self_loops += 1
			if not g.cells.has(n.coord):
				unknown_neighbors += 1
			if not g.get_neighbors(n.coord).has(cell):
				asymmetric += 1

	t.eq(hist.get(6, 0), 8, "cube corners have 6 global neighbors")
	t.eq(hist.get(8, 0), 480, "all other shell cells have 8 global neighbors")
	t.eq(hist.size(), 2, "no other global neighbor counts")
	t.eq(self_loops, 0, "no self-loop neighbors")
	t.eq(unknown_neighbors, 0, "all global neighbors are shell cells")
	t.eq(asymmetric, 0, "global neighbor graph is symmetric")

	t.group("face-local neighbor graph")
	t.eq(g.face_neighbor_graph.size(), 6, "one face-local graph per face")
	var face_hist := {}
	var subset_bad := 0
	var face_ownership_bad := 0
	for f in range(6):
		t.eq(g.face_neighbor_graph[f].size(), 100, "face %d graph has 100 coords" % f)
		for u in range(SIZE):
			for v in range(SIZE):
				var cell = g.get_cell_uv(f, u, v)
				var local: Array = g.get_face_neighbors(f, cell.coord)
				face_hist[local.size()] = face_hist.get(local.size(), 0) + 1
				var global_neighbors: Array = g.get_neighbors(cell.coord)
				for n in local:
					if not (f in n.exterior_faces):
						face_ownership_bad += 1
					if not global_neighbors.has(n):
						subset_bad += 1
	t.eq(face_hist.get(3, 0), 24, "face corners have 3 face-local neighbors")
	t.eq(face_hist.get(5, 0), 192, "face edges have 5 face-local neighbors")
	t.eq(face_hist.get(8, 0), 384, "face interiors have 8 face-local neighbors")
	t.eq(face_hist.size(), 3, "no other face-local neighbor counts")
	t.eq(subset_bad, 0, "face-local neighbors are global manifold neighbors")
	t.eq(face_ownership_bad, 0, "face-local neighbors share the face")

	t.group("face-local vs global graphs differ")
	var corner: Vector3i = Vector3i(0, 9, 9)
	t.eq(g.get_neighbors(corner).size(), 6, "corner global neighbor count")
	for f in g.get_cell_at(corner).exterior_faces:
		t.eq(g.get_face_neighbors(f, corner).size(), 3, "corner face-local count on face %d" % f)

	var edge := Vector3i(0, 4, 9)
	var edge_cell = g.get_cell_at(edge)
	t.eq(edge_cell.exterior_faces.size(), 2, "edge voxel belongs to two faces")
	t.eq(g.get_neighbors(edge).size(), 8, "edge voxel global neighbor count")
	var face_local: Array = g.get_face_neighbors(Grid.Face.FRONT, edge)
	t.eq(face_local.size(), 5, "edge voxel face-local neighbor count")
	var global_only := 0
	for n in g.get_neighbors(edge):
		if not face_local.has(n):
			global_only += 1
	t.ok(global_only > 0, "an edge voxel has global-only neighbors")

# Missing coordinates must return a typed empty Array[CellData]. An untyped
# fallback raises a runtime SCRIPT ERROR, which `make test` treats as failure.
func _test_missing_coords(t, g) -> void:
	t.group("non-shell coord neighbors")
	var interior: Array = g.get_neighbors(Vector3i(5, 5, 5))
	t.eq(interior.size(), 0, "interior coord has no shell neighbors")
	t.ok(interior.is_typed(), "missing neighbors are a typed array")
	t.eq(interior.get_typed_builtin(), TYPE_OBJECT, "typed element is an object")
	t.ok(interior.get_typed_script() != null, "typed element carries the CellData script")

	t.eq(g.get_neighbors(Vector3i(-1, 5, 5)).size(), 0, "negative coord returns empty")
	t.eq(g.get_neighbors(Vector3i(SIZE, 5, 5)).size(), 0, "out-of-bounds coord returns empty")
	t.eq(g.get_neighbors(Vector3i(1, 1, 1)).size(), 0, "inner corner coord returns empty")
	t.eq(g.get_cell_at(Vector3i(5, 5, 5)), null, "interior coord has no cell")

func _test_missing_face_keys(t, g) -> void:
	t.group("missing face-local keys")
	t.eq(g.get_face_neighbors(99, Vector3i(0, 0, 0)).size(), 0, "unknown face returns empty")
	t.eq(g.get_face_neighbors(-1, Vector3i(0, 0, 0)).size(), 0, "negative face returns empty")
	t.eq(
		g.get_face_neighbors(Grid.Face.FRONT, Vector3i(5, 5, 5)).size(),
		0,
		"real face with a non-shell coord returns empty"
	)
	var missing: Array = g.get_face_neighbors(Grid.Face.FRONT, Vector3i(5, 5, 5))
	t.ok(missing.is_typed(), "missing face-local neighbors are a typed array")
	t.eq(missing.get_typed_builtin(), TYPE_OBJECT, "typed element is an object")

class_name VolumetricGrid
extends RefCounted

# The 6 faces of a 3D Cube
enum Face {
	FRONT = 0,
	RIGHT = 1,
	BACK = 2,
	LEFT = 3,
	TOP = 4,
	BOTTOM = 5
}

const FACE_NAMES = ["Front", "Right", "Back", "Left", "Top", "Bottom"]

const FACE_NORMALS = [
	Vector3i(0, 0, 1),   # FRONT (+Z)
	Vector3i(1, 0, 0),   # RIGHT (+X)
	Vector3i(0, 0, -1),  # BACK (-Z)
	Vector3i(-1, 0, 0),  # LEFT (-X)
	Vector3i(0, 1, 0),   # TOP (+Y)
	Vector3i(0, -1, 0)   # BOTTOM (-Y)
]

# A unified 3D voxel cell on the cube's outer shell
class CellData:
	var coord: Vector3i # (x, y, z) in [0, size - 1]^3
	var is_gem: bool = false
	var is_revealed: bool = false # rock only; gems are never revealed
	var is_marked: bool = false # staked with an X
	var is_detonated: bool = false # cracked gem
	var exterior_faces: Array[int] = [] # list of Face enums this voxel is visible on
	# Map of Face enum -> int (count of gems touching this cell on that specific face)
	var face_neighbor_gems: Dictionary = {}

	func _init(c: Vector3i, ext_faces: Array[int]) -> void:
		coord = c
		exterior_faces = ext_faces

var size: int = 10
# Gems are placed lazily on the first left-click; stats are provisional until then.
var gems_populated: bool = false
# coord Vector3i -> CellData (488 shell voxels)
var cells: Dictionary = {}
# Array of all shell cells
var all_cells: Array[CellData] = []
# Map of face -> Array of CellData on that face (100 cells per face, with shared edges/corners)
var face_cells: Dictionary = {}
# Global cross-face connected neighbor graph (for cascades): coord -> Array[CellData]
var neighbor_graph: Dictionary = {}
# Per-face neighbor graph (Option A: for face-local numbers and chording): [face][coord] -> Array[CellData]
var face_neighbor_graph: Dictionary = {}

func init_grid(grid_size: int = 10) -> void:
	size = grid_size
	gems_populated = false
	cells.clear()
	all_cells.clear()
	face_cells.clear()
	neighbor_graph.clear()

	for f in range(6):
		face_cells[f] = []

	var last = size - 1

	for x in range(size):
		for y in range(size):
			for z in range(size):
				# Only include outer shell voxels
				if x == 0 or x == last or y == 0 or y == last or z == 0 or z == last:
					var ext_faces: Array[int] = []
					if z == last: ext_faces.append(Face.FRONT)
					if x == last: ext_faces.append(Face.RIGHT)
					if z == 0:    ext_faces.append(Face.BACK)
					if x == 0:    ext_faces.append(Face.LEFT)
					if y == last: ext_faces.append(Face.TOP)
					if y == 0:    ext_faces.append(Face.BOTTOM)

					var c = Vector3i(x, y, z)
					var cell = CellData.new(c, ext_faces)
					cells[c] = cell
					all_cells.append(cell)
					neighbor_graph[c] = []

					for f in ext_faces:
						face_cells[f].append(cell)

	# Build true 2D Manifold Surface Neighbor Graph (global cross-face cascade)
	# AND Per-Face Neighbor Graph (Option A: for face-local numbers and chording)
	var neighbor_sets: Dictionary = {}
	for cell in all_cells:
		neighbor_sets[cell.coord] = {}

	face_neighbor_graph.clear()
	for f in range(6):
		face_neighbor_graph[f] = {}
		# Pre-map (u, v) on this face to voxel coordinate
		var face_map = {}
		for u in range(size):
			for v in range(size):
				var coord = face_uv_to_voxel(f, u, v, size)
				face_map[Vector2i(u, v)] = coord
				if not face_neighbor_graph[f].has(coord):
					face_neighbor_graph[f][coord] = []

		for u in range(size):
			for v in range(size):
				var c1 = face_map[Vector2i(u, v)]
				var local_neighbors: Array[CellData] = []
				for du in [-1, 0, 1]:
					for dv in [-1, 0, 1]:
						if du == 0 and dv == 0:
							continue
						var nu = u + du
						var nv = v + dv
						if nu >= 0 and nu < size and nv >= 0 and nv < size:
							var c2 = face_map[Vector2i(nu, nv)]
							if c1 != c2:
								# Global manifold connection
								neighbor_sets[c1][c2] = true
								neighbor_sets[c2][c1] = true
								# Face-local connection
								if cells.has(c2) and not local_neighbors.has(cells[c2]):
									local_neighbors.append(cells[c2])
				face_neighbor_graph[f][c1] = local_neighbors

	for c in neighbor_sets:
		var arr: Array[CellData] = []
		for nc in neighbor_sets[c]:
			if cells.has(nc):
				arr.append(cells[nc])
		neighbor_graph[c] = arr

# Convert Face (f, u, v) coordinate into 3D voxel coordinate (x, y, z)
static func face_uv_to_voxel(face: int, u: int, v: int, sz: int) -> Vector3i:
	var last = sz - 1
	match face:
		Face.FRONT:  # +Z: u goes left->right (x: 0..last), v goes top->bottom (y: last..0)
			return Vector3i(u, last - v, last)
		Face.RIGHT:  # +X: u goes left->right front->back (z: last..0), v goes top->bottom (y: last..0)
			return Vector3i(last, last - v, last - u)
		Face.BACK:   # -Z: u goes left->right right->left (x: last..0), v goes top->bottom (y: last..0)
			return Vector3i(last - u, last - v, 0)
		Face.LEFT:   # -X: u goes left->right back->front (z: 0..last), v goes top->bottom (y: last..0)
			return Vector3i(0, last - v, u)
		Face.TOP:    # +Y: u goes left->right (x: 0..last), v goes top->bottom back->front (z: 0..last)
			return Vector3i(u, last, v)
		Face.BOTTOM: # -Y: u goes left->right (x: 0..last), v goes top->bottom front->back (z: last..0)
			return Vector3i(u, 0, last - v)
	return Vector3i.ZERO

func get_cell_at(coord: Vector3i) -> CellData:
	return cells.get(coord, null)

func get_cell_uv(face: int, u: int, v: int) -> CellData:
	var coord = face_uv_to_voxel(face, u, v, size)
	return get_cell_at(coord)

# 2D Manifold surface neighborhood on the shell (exact 8 neighbors on edges/interiors, 6 on corners)
func get_neighbors(coord: Vector3i) -> Array[CellData]:
	if neighbor_graph.has(coord):
		return neighbor_graph[coord]
	var empty: Array[CellData] = []
	return empty

# Get neighbors of a cell strictly on a specific face (for Option A)
func get_face_neighbors(face: int, coord: Vector3i) -> Array[CellData]:
	if face_neighbor_graph.has(face) and face_neighbor_graph[face].has(coord):
		return face_neighbor_graph[face][coord]
	var empty: Array[CellData] = []
	return empty

# Places gems lazily for the first click. Stake state never influences placement.
# Re-entry is only supported on a fresh grid: cell play flags
# (is_revealed/is_marked/is_detonated) are preserved, only gem state is reset.
func populate_gems(safe_coord: Vector3i, total_gems: int) -> void:
	for cell in all_cells:
		cell.is_gem = false
		cell.face_neighbor_gems.clear()

	var safe_neighbors = get_neighbors(safe_coord)
	var safe_set = {}
	safe_set[safe_coord] = true
	for n in safe_neighbors:
		safe_set[n.coord] = true

	var potential_cells: Array[CellData] = []
	for cell in all_cells:
		if not safe_set.has(cell.coord):
			potential_cells.append(cell)

	potential_cells.shuffle()
	var count = min(total_gems, potential_cells.size())
	for i in range(count):
		potential_cells[i].is_gem = true

	# Compute face-local neighbor gem counts for each cell
	for cell in all_cells:
		cell.face_neighbor_gems.clear()
		if not cell.is_gem:
			for f in cell.exterior_faces:
				var gem_count = 0
				for neighbor in get_face_neighbors(f, cell.coord):
					if neighbor.is_gem:
						gem_count += 1
				cell.face_neighbor_gems[f] = gem_count

	gems_populated = true

# Single source of truth for whether a cell is finished.
func is_cell_resolved(cell: CellData) -> bool:
	if cell.is_gem:
		return cell.is_marked or cell.is_detonated
	return cell.is_revealed

func is_board_complete() -> bool:
	if not gems_populated:
		return false
	for cell in all_cells:
		if not is_cell_resolved(cell):
			return false
	return true

# Stats for one face of the cube net. Edge/corner cells belong to several faces.
func get_face_stats(face: int) -> Dictionary:
	var f_cells: Array = face_cells.get(face, [])
	var face_total: int = f_cells.size()
	var face_rock_total: int = 0
	var face_gem_total: int = 0
	var face_rock_excavated: int = 0
	var face_gems_staked: int = 0
	var face_gems_cracked: int = 0
	var face_misplaced_marks: int = 0
	var face_resolved: int = 0

	for cell in f_cells:
		if is_cell_resolved(cell):
			face_resolved += 1
		if cell.is_gem:
			face_gem_total += 1
			if cell.is_detonated:
				face_gems_cracked += 1
			elif cell.is_marked:
				face_gems_staked += 1
		else:
			face_rock_total += 1
			if cell.is_revealed:
				face_rock_excavated += 1
			if cell.is_marked:
				face_misplaced_marks += 1

	var face_gems_resolved: int = face_gems_staked + face_gems_cracked
	var is_face_complete: bool = face_total > 0 and face_resolved == face_total

	return {
		"face": face,
		"face_name": FACE_NAMES[face] if face >= 0 and face < FACE_NAMES.size() else "Unknown",
		"face_total": face_total,
		"face_rock_total": face_rock_total,
		"face_gem_total": face_gem_total,
		"face_rock_excavated": face_rock_excavated,
		"face_gems_staked": face_gems_staked,
		"face_gems_cracked": face_gems_cracked,
		"face_gems_resolved": face_gems_resolved,
		"face_resolved": face_resolved,
		"face_unresolved": face_total - face_resolved,
		"face_misplaced_marks": face_misplaced_marks,
		"is_face_complete": is_face_complete
	}

func get_board_stats() -> Dictionary:
	var total_cells: int = all_cells.size()
	var rock_total: int = 0
	var gem_total: int = 0
	var rock_excavated: int = 0
	var gems_staked: int = 0
	var gems_cracked: int = 0
	var misplaced_marks: int = 0
	var resolved_cells: int = 0

	for cell in all_cells:
		if is_cell_resolved(cell):
			resolved_cells += 1
		if cell.is_gem:
			gem_total += 1
			if cell.is_detonated:
				gems_cracked += 1
			elif cell.is_marked:
				gems_staked += 1
		else:
			rock_total += 1
			if cell.is_revealed:
				rock_excavated += 1
			if cell.is_marked:
				misplaced_marks += 1

	var gems_resolved: int = gems_staked + gems_cracked
	var faces_complete: int = 0
	for f in range(6):
		if get_face_stats(f)["is_face_complete"]:
			faces_complete += 1

	return {
		"size": size,
		"total_cells": total_cells,
		"rock_total": rock_total,
		"gem_total": gem_total,
		"gems_populated": gems_populated,
		"rock_excavated": rock_excavated,
		"rock_remaining": rock_total - rock_excavated,
		"gems_staked": gems_staked,
		"gems_cracked": gems_cracked,
		"gems_resolved": gems_resolved,
		"gems_remaining": max(gem_total - gems_resolved, 0),
		"misplaced_marks": misplaced_marks,
		"resolved_cells": resolved_cells,
		"unresolved_cells": total_cells - resolved_cells,
		"all_rock_excavated": gems_populated and rock_excavated == rock_total,
		"all_gems_resolved": gems_populated and gems_resolved == gem_total,
		"is_complete": is_board_complete(),
		"faces_complete": faces_complete
	}

func get_total_remaining_gems() -> int:
	var remaining: int = 0
	for cell in all_cells:
		if cell.is_gem and not is_cell_resolved(cell):
			remaining += 1
	return remaining

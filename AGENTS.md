# AGENTS.md

Guidance for coding agents working in this repository. Read this before making
changes.

## Project in one paragraph

Gem Miner is a Godot 4 GDScript puzzle on the outer voxel shell of a
10×10×10 geode. The grid is pure data (`VolumetricGrid`, a `RefCounted`); each
shell voxel is also an `Area3D` view node (`VolumetricTile3D`) that handles mouse
input, labels, stakes, and crystals. `VolumetricCubeController` owns the game
state and wires the two together. `claim_net.gd` draws a read-only cube-net
survey panel, and `ExcavationFinale` runs the whole-cube extraction sequence.
Everything is procedural: no imported meshes, textures, or other art assets.

The main scene is `res://volumetric_minesweeper.tscn`. Files named
`minesweeper_3d.*`, `minesweeper_tile_3d.gd`, `main.tscn`, `player.*`,
`dodecahedron_planet.gd`, and `face_camera_controller.gd` are legacy prototypes
and are not loaded by the main scene. The scene file and `Volumetric*` class
names are historical; do not rename them without an explicit migration task.

## First commands

```sh
make import   # once per fresh checkout — required for global class_name resolution
make check    # headless smoke test (depends on import)
make test     # headless rules/topology suite at fixed 60 fps (depends on import)
make run      # play (blocks until the window is closed)
make editor   # open the editor
make all      # check + test
```

`make import` matters in a fresh worktree: without
`.godot/global_script_class_cache.cfg`, scripts fail with
`Could not find type "VolumetricGrid"`. Run it first when `make check` or
`make test` reports parse errors about missing types.

If Godot is not at the default macOS path, pass `GODOT=/path/to/godot`.

## Working agreement

- Use GDScript and match the existing style: tabs for indentation, typed local
  variables where the file already uses them, `snake_case` functions, one blank
  line between functions.
- Keep changes scoped to the volumetric system unless the task explicitly
  involves a legacy file or the test harness.
- Do not import binary assets or add dependencies. The project is fully
  procedural. `icon.svg` is the only static asset.
- Do not revive the retired 4×4 gem-excavation experiment or per-face removal
  without an explicit request.
- Update `README.md` / `docs/ARCHITECTURE.md` when behavior, configuration, or
  the scene tree changes.
- Prefer fixing data/topology bugs in `volumetric_grid.gd` and presentation
  bugs in `volumetric_tile_3d.gd`. Do not duplicate game rules in the view or
  in `claim_net.gd`.
- Do not add live stake-correctness feedback. The HUD and cube net are
  deliberately anti-oracle.

## Where things are

| Concern | File |
| --- | --- |
| Scene tree, HUD, cube-net panel, camera, lights, exported board config | `volumetric_minesweeper.tscn` |
| Reset/build, rotation, input, excavation, staking, chording, cracks, HUD, victory | `volumetric_cube_controller.gd` |
| Shell cells, face mapping, neighbor graphs, gem placement, stats | `volumetric_grid.gd` |
| Per-voxel mesh, labels, lazy stakes/crystals, hover/long-press, extraction hook | `volumetric_tile_3d.gd` |
| Unfolded cube-net progress panel | `claim_net.gd` |
| Collapsible HUD/net panels | `ui_panels.gd` |
| Whole-cube extraction finale | `excavation_finale.gd` |
| Headless suites, assertion helper, runner | `tests/**` |
| Build/gate targets | `Makefile` |

## Critical invariants

1. **Coordinates are integer voxel coordinates**, `Vector3i(0..size-1)` per axis.
   Only shell cells exist in `grid.cells`. World position is
   `coord * tile_spacing - (size - 1) * 0.5 * tile_spacing` on each axis.
2. **`Face` enum order is fixed**: FRONT(+Z), RIGHT(+X), BACK(-Z), LEFT(-X),
   TOP(+Y), BOTTOM(-Y). `current_viewed_face` indexes this enum.
3. **`face_uv_to_voxel()` is the single source of face orientation.** UI label
   orientation, chording, the cube net, and the global manifold graph all depend
   on it. Changing a face's `u`/`v` direction breaks picking and edge sharing.
4. **There are two neighbor graphs.** `neighbor_graph` is the global 2D manifold
   union (used by cascades and first-click safety); the
   `face_neighbor_graph` is strictly per-face (used by numbers and chording). Do
   not swap them.
5. **Numbers are face-local.** An edge/corner cell has one entry in
   `face_neighbor_gems` per exterior face. Only the current face's number is
   displayed. Gem cells carry no numbers.
6. **Gems are placed lazily on the first left-click**, in
   `grid.populate_gems(safe_coord, total_gems)`. The safe set is the clicked
   cell plus its global neighbors (up to 8; 6 at cube corners). Do not place
   gems at reset. Pre-marks do not affect placement, and `populate_gems()` is
   total on re-entry: it clears existing gems before placing.
7. **`is_cell_resolved()` is the completion source of truth.** Rock resolves when
   revealed; a gem resolves when staked or cracked. `is_board_complete()` also
   requires `gems_populated`. Never express completion as a sum of counters.
8. **Staked rock remains unresolved.** A stake blocks excavation, face
   completion, board completion, and auto-stake until it is pulled. A cracked
   gem is both `is_detonated` and `is_marked`, is permanently staked, and is
   never `is_revealed`.
9. **Loss has precedence over victory.** A run is lost when `strikes` reaches
   the limit (Easy 9, Medium 3, Hard 0); loss suppresses surveys, auto-stake, and
   victory.
10. **Auto-stake, victory, and finale are one-shot.** `_after_mutation()` is the
    single post-action pipeline. On `all_rock_excavated`, remaining gems
    auto-stake, then victory is checked. `_trigger_claim_complete()` is
    idempotent, sets `game_won`, emits `claim_complete()`, and starts the finale
    once.
11. **There is no per-face dissolve.** A face survey is a milestone only; tiles
    never shrink or disappear during play. The whole cube runs to the finale.
12. **The live UI never confirms stake correctness.** It shows stakes placed,
    not a confirmed-gem or misplaced-stake count; staked gems and staked rock
    render identically. Wrong stakes are recoverable by un-staking.
13. **`claim_net.gd` is read-only.** It polls grid stats, never mutates gameplay
    state, and requires a 10×10 board.
14. **Reset must cancel presentation state.** `reset_game()` cancels the finale,
    kills navigation/elastic/shake tweens, restores `camera_home`, disables old
    tile input, and rebuilds the board.
15. **Panel collapse is presentation-only.** `ui_panels.gd` hides panel content
    and shrinks offsets, but the toggle button must remain visible. Do not move
    `FaceInfoLabel`, `StatsLabel`, `ActionRow`, or `NetCanvas` out of their
    controller/claim-net paths.

## Verification

`make check` imports the project, boots the main scene headless for 120 frames,
and fails on `SCRIPT ERROR` / `Parse Error` in the log. It does not assert
gameplay.

`make test` imports the project, runs `tests/run_tests.gd` headless with
`--fixed-fps 60`, and fails on a non-zero exit, a script error, or a missing
`TEST RESULT: PASS` marker. It prints the per-suite check counts. The seven
suites are `grid_topology`, `gem_placement`, `face_numbering`,
`resolution_accounting`, `controller_flow`, `prepopulation`, and
`finale_lifecycle`. Do not hard-code a total check count in docs or scripts; the
suite set can grow.

Manual checklist for any gameplay change:

1. Rotate all six faces and confirm numbers stay upright and only show on the
   forward face.
2. First left-click never cracks a gem; blank cells cascade across edges and
   corners.
3. Right-click stakes and un-stakes; a staked cell cannot be excavated, and
   un-staking reopens it.
4. A satisfied number chords only its face-local neighbors.
5. Strikes decrement correctly on Easy/Medium/Hard; Hard ends on the first
   crack; a lost run cannot win.
6. Surveying a face pulses/checks the cube net without removing tiles.
7. Revealing all rock auto-stakes remaining gems, then completes the claim once.
8. The finale runs once; New Claim during and after the finale resets cleanly.
9. Counts: 488 cells, 428 rock, 60 gems; each face lists 100 cells; the six
   faces total 600 memberships.
10. New Claim rebuilds a clean 488-tile board and resets the HUD, net, camera,
    and latches.

Headless success only proves scripts parse, `_ready()` runs, and the data/flow
assertions hold. It cannot verify rendering, mouse picking, or touch behavior,
so state what still needs manual testing.

## Known traps

- `reset_game()` calls `queue_free()` on old `ElasticPivot` children and then
  immediately adds new tiles. The free is deferred; do not rely on
  `get_child_count()` being zero right away, and never assert pivot child counts
  in the same frame as the reset.
- `reset_game()` must call `_finale.cancel()` before freeing or rebuilding the
  pivot. `cancel()` restores the inner core rind; the controller restores the
  camera and pivot transform.
- The finale helper is reused across wins on the same controller instance. Do
  not free it on reset; cancel it and leave it idle.
- `_after_mutation()` is the only place that runs auto-stake, surveys, and
  victory. Do not call those from individual handlers or they can double-fire.
- `surveyed_faces` is a one-shot latch. The cube-net check is recomputed from
  current stats, so pulling a stake can clear the check without re-pulsing.
- Chording treats every marked cell as accounted for. A wrong stake can satisfy
  the number and crack the real gem. This is characterized by
  `controller_flow`, not fixed.
- `_flood_excavate()` cascades from a cell that is zero on *any* exterior face,
  then expands over the global manifold. It can reveal a cell on a face where
  its number is nonzero. Also characterized, not fixed.
- A cracked gem never sets `is_revealed`; stats count it as cracked, not staked,
  using the `is_detonated` check before `is_marked`.
- Staked rock blocks auto-stake forever until un-staked. The cube net shows a
  "no further rock can be excavated" stuck hint, but the HUD must not identify
  which stake is wrong.
- `VolumetricTile3D.set_process(false)` must be enforced again in `_ready()`:
  the engine re-enables idle processing when a node enters the tree. Processing
  should run only while a left press is held.
- The difficulty selector changes strikes only; `total_gems` is a scene export.
  Gem-count scaling is future work.
- `claim_net.gd` is hard-coded for 10×10. Expanding `initial_cube_size`
  disables the net with a warning.
- Pre-population stats are provisional: 488 rock, 0 gems, expected rock
  `488 - total_gems`. Stakes placed before the first pick are stored and must
  stay neutral.
- `populate_gems()` preserves play flags on re-entry, so it is only safe on a
  fresh grid. Do not call it while a real game is in progress.
- `project.godot` references `res://icon.svg`; keep it present or the game logs
  a load error at startup.

## Sensible next steps

1. Decide whether cascades should require zero on all exterior faces instead of
   any face.
2. Decide whether chording should ignore unconfirmed stakes or keep the
   wrong-stake quirk.
3. Scale the gem count with difficulty and/or board size.
4. Generalize the cube net to other board sizes.
5. Add touch-specific input affordances and verify long-press on a device.
6. Add automated input/visual coverage; current tests are data and controller
   flow only.

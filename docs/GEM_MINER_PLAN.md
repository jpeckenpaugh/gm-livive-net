# Gem Miner — Delegation Plan

Status: **Complete — ready for live test** · Owner: PM (main session) · Last updated: 2026-10-26

## 1. Goal

Reframe the 10×10×10 volumetric Minesweeper baseline as **Gem Miner** without
changing the underlying puzzle rules:

- Mines become **gems**; defusing becomes **staking an `X`**.
- Numbers remain face-local counts of adjacent gems.
- Cascades, chording, first-click safety, and strike limits are unchanged.
- Per-face dissolve/removal is removed; the board plays to a whole-cube finish.
- Victory requires every rock cell excavated and every gem staked or cracked.
- The finale is a whole-block extraction sequence, not six separate face clears.

## 2. Approved decisions

These were confirmed before planning and are not open for reinterpretation
without a PM decision-log entry.

| Topic | Decision |
| --- | --- |
| Fiction | Surveyor staking a claim on a giant geode. `X` is an extraction stake; numbers are gem-scanner readings. Hitting a gem with the pick cracks it. |
| Struck gem | Automatically staked, counts as resolved, still costs a strike. Easy/Medium runs remain winnable. |
| Victory | All rock cells revealed **and** all gems staked or cracked. |
| Final marks | Once every rock cell is revealed, auto-stake all remaining unrevealed gems, then check victory. |
| Density | Keep 10×10×10: 488 shell cells, 60 gems, 428 rock. |
| Face completion | Pulse/checkmark milestone only. Never remove tiles during play. |
| Per-face dissolve | Deleted entirely. |
| Difficulty | Keep Easy 9 / Medium 3 / Hard 0 strikes; reframe copy only. |
| Code naming | Mechanical rename to gem/mark/excavate terminology. |

## 3. Operating model

- **PM (this session)** owns scope, the interface contract, branch/worktree
  management, merges, triage, and final acceptance. PM is the only role allowed
  to change the contract or touch `project.godot`.
- **Implementation roles** are staffed by `general` subagents.
- **Audit** is staffed by an `explore` subagent and is read-only.
- **One writer per file at a time.** Parallel agents must work in separate
  worktrees and must not edit a file owned by another active agent.
- **No agent commits to `main`.** Agents commit to their own branch/worktree and
  report the hash. PM reviews, merges, and runs the merge gates.
- **No new dependencies or binary assets.** Art remains procedural.
- **Out-of-scope bugs are logged, not drive-by fixed.** Known cascade/chord
  quirks stay as-is during the reframe unless the PM explicitly schedules them.
- Agents must run `make check` before handoff. Once available, `make test` is
  also required.
- Every handoff uses the report template in section 9.

## 4. Sub-agent roster

| Agent | Type | Phase | Owns | Primary deliverable |
| --- | --- | --- | --- | --- |
| `pm` | main session | 0, 4, 5 | Contract, branches, merges, final QA, `project.godot` | Integrated, verified build |
| `core-rules` | `general` | 1 | `volumetric_grid.gd`, `volumetric_cube_controller.gd`, mechanical API renames in `volumetric_tile_3d.gd` | Playable Gem Miner loop with placeholder visuals |
| `tile-view` | `general` | 2A | `volumetric_tile_3d.gd` | X stakes, gem crystals, palette, lazy visuals |
| `hud-ui` | `general` | 2B | `volumetric_minesweeper.tscn`, new `claim_net.gd` | HUD, cube-net progress, face milestones, warnings |
| `rules-verifier` | `general` | 2C, 4 | `tests/**`, `Makefile` test target | Headless rule/topology test suite |
| `finale` | `general` | 3 | `volumetric_cube_controller.gd` (victory sequence), new `excavation_finale.gd` | Whole-cube extraction finale |
| `auditor` | `explore` | 4 | None (read-only) | Independent regression and contract audit |
| `scribe` | `general` | 5 | `README.md`, `docs/ARCHITECTURE.md`, `AGENTS.md` | Accurate docs and release notes |

The roster is a maximum, not a quota. PM may fold a role into another if the
handoff cost exceeds the task size, but file ownership still applies.

## 5. File ownership matrix

| Path | Owner | Notes |
| --- | --- | --- |
| `volumetric_grid.gd` | `core-rules` | Frozen after Phase 1; later fixes only via PM triage |
| `volumetric_cube_controller.gd` | `core-rules` (P1), `finale` (P3) | Strictly serial; never concurrent |
| `volumetric_tile_3d.gd` | `core-rules` (P1 API only), `tile-view` (P2A) | P1 may rename API; P2 owns visuals |
| `volumetric_minesweeper.tscn` | `hud-ui` | Sole writer in P2B |
| `claim_net.gd` (new) | `hud-ui` | Flat project layout, consistent with existing scripts |
| `excavation_finale.gd` (new) | `finale` | Instantiated from controller; no scene edit needed |
| `tests/**`, `Makefile` | `rules-verifier` | No gameplay edits |
| `README.md`, `docs/ARCHITECTURE.md`, `AGENTS.md` | `scribe` | After code freeze |
| `docs/GEM_MINER_PLAN.md` | `pm` | Living plan and status |
| `project.godot`, `icon.svg` | `pm` | Do not touch without PM approval |

## 6. Frozen interface contract

Phase 0 freezes these names so parallel agents do not drift. Additive changes
are allowed with PM approval; renames require a PM decision-log entry.

### `VolumetricGrid.CellData`

```gdscript
var coord: Vector3i
var is_gem: bool             # was is_mine
var is_revealed: bool
var is_marked: bool          # was is_defused; means staked with X
var is_detonated: bool       # now used: cracked gem
var exterior_faces: Array[int]
var face_neighbor_gems: Dictionary   # Face -> int; was face_neighbor_mines
```

### `VolumetricGrid`

```gdscript
func init_grid(grid_size: int = 10) -> void
func populate_gems(safe_coord: Vector3i, total_gems: int) -> void
func get_cell_at(coord: Vector3i) -> CellData
func get_neighbors(coord: Vector3i) -> Array[CellData]
func get_face_neighbors(face: int, coord: Vector3i) -> Array[CellData]

func is_cell_resolved(cell: CellData) -> bool
func is_board_complete() -> bool
func get_face_stats(face: int) -> Dictionary
func get_board_stats() -> Dictionary
func get_total_remaining_gems() -> int
```

`is_cell_resolved()` is the single source of truth:

```gdscript
func is_cell_resolved(cell: CellData) -> bool:
    if cell.is_gem:
        return cell.is_marked or cell.is_detonated
    return cell.is_revealed
```

Do not express completion as a sum of counters. The old
`face_revealed + face_mines == face_total` predicate double-counts cracked gems
and is deleted.

### `VolumetricTile3D`

```gdscript
func setup(c: Vector3i, ext_faces: Array[int]) -> void
func set_gem(value: bool) -> void
func set_face_counts(counts: Dictionary) -> void
func excavate() -> void                 # was reveal()
func set_marked(value: bool) -> void    # was toggle_defused()
func strike() -> void                   # cracked gem visual
func play_extraction(delay: float) -> void
func update_label_display(active_face: int, camera_up_world: Vector3) -> void
```

Signals stay `tile_clicked(coord, button_index)` and `tile_pressed(coord)`.

### Controller hooks

```gdscript
func reset_game() -> void
func _on_tile_clicked(coord: Vector3i, button_index: int) -> void
func _on_gem_struck(coord: Vector3i) -> void
func _check_victory() -> void
func _trigger_claim_complete() -> void
```

`_check_victory()` runs after every state mutation: excavate, mark/unmark,
chord, and strike. `_trigger_claim_complete()` is the only entry point to the
finale and must be idempotent.

## 7. Phases

### Phase 0 — Contract and guardrails (PM)

**Depends on:** nothing. **Parallel with:** none.

- Create the `gem-miner` integration branch from `main`.
- Confirm the baseline: `make check` on the 10×10 scene.
- Freeze this contract and the approved decisions above.
- Prepare the Phase 1 task brief with the rename map and acceptance criteria.
- Record the worktree layout in section 8.

**Exit criteria:** clean baseline, contract frozen, Phase 1 brief ready.

### Phase 1 — Core rules and loop (`core-rules`)

**Depends on:** Phase 0. **Parallel with:** none (critical path).

Files: `volumetric_grid.gd`, `volumetric_cube_controller.gd`, and API-only
mechanical renames in `volumetric_tile_3d.gd`.

Tasks:

1. Rename domain symbols: mine → gem, defuse → mark, detonate → strike/crack,
   reveal → excavate. Keep the two neighbor graphs intact.
2. Rename `is_defused` to `is_marked`; use `is_detonated` for cracks.
3. Add `is_cell_resolved()`, `is_board_complete()`, `get_board_stats()`, and
   per-face progress. Remove the old completion sum.
4. Delete `dissolved_faces`, `_dissolve_face_slice()`, and
   `_check_all_faces_completion()`.
5. On gem strike: increment strikes, set `is_detonated`, auto-mark, play the
   placeholder cracked/gem visual, and re-check victory.
6. Add `_check_victory()` after every mutation. On completion, auto-stake
   remaining gems only if no unrevealed rock remains, then fire
   `_trigger_claim_complete()` once.
7. Keep a placeholder finale: HUD message and input lock only. Real finale is
   Phase 3.
8. Update HUD text to Gem Miner terminology with temporary labels: rock
   excavated, stakes placed, integrity. (The final neutral wording and the
   removal of live stake-correctness feedback land in Phase 4.)
9. Keep `game_won` reachable and idempotent; reset must clear it and restore
   input.

**Exit criteria:** the full loop is playable with placeholder visuals; no face
removal; victory and hard-mode loss both work; reset works; `make check` clean.

### Phase 2 — Presentation and verification (parallel)

**Depends on:** Phase 1. **Parallel with:** all three tracks below.

Run each track in its own worktree. Merge order: `tile-view` → `hud-ui` →
`rules-verifier`.

#### Phase 2A — Tile presentation (`tile-view`)

File: `volumetric_tile_3d.gd` only.

1. Replace the hidden 12-beam cage with an `X` stake visual. Keep the rock cube
   visible when marked; the stake is an overlay, not a replacement.
2. Build mark visuals lazily. Do not construct hidden multi-mesh cages for all
   488 tiles.
3. Add a faceted gem crystal for struck cells and a cracked/dim variant.
4. Establish the palette: dark basalt rock, lighter excavated rock, cyan/emerald
   gems, amber stakes, red cracks.
5. Preserve label behavior: only the active face shows numbers; labels stay
   upright and readable.
6. Implement `set_gem`, `set_marked`, `strike`, and `play_extraction(delay)` to
   the contract. `play_extraction` is a hook; the finale orchestrates it.

**Exit criteria:** stakes read clearly from any angle; gems are distinct from
rock; no per-tile hidden mesh waste; no label regressions.

#### Phase 2B — HUD and cube net (`hud-ui`)

Files: `volumetric_minesweeper.tscn`, new `claim_net.gd`.

1. Retitle the experience and replace mine/defuse copy with Gem Miner copy.
2. HUD fields: current face, rock excavated `N/428`, stakes placed, and pick
   integrity. Do not confirm whether a stake is correct (see Phase 4).
3. Build an unfolded cube-net progress panel: six 10×10 mini-grids with rock,
   excavated, stake, cracked-gem, current-face, and surveyed states. Staked gems
   and staked rock render identically.
4. Add a brief gold pulse/checkmark when a face becomes surveyed. Checks reflect
   current completion, not a historical latch. Do not remove or hide tiles.
5. Keep the difficulty selector and New Game button working. Update controls
   hint for excavate / stake / chord.
6. Do not change gameplay rules in the scene; UI reads grid stats through the
   controller.

**Exit criteria:** all counts match the grid; the six-face goal is legible;
face milestones do not remove tiles; input is not blocked by UI; the live UI
never reveals whether an individual stake is correct.

#### Phase 2C — Verification harness (`rules-verifier`)

Files: `tests/**`, `Makefile`.

1. Add a dependency-free headless test entry point and a `make test` target.
2. Cover: 488 shell cells, 100 cells per face / 600 memberships, face mapping,
   interior/corner neighbor counts, first-click safety, face-local numbering,
   cascade behavior, chord behavior, mark/unmark, edge-gem resolving two faces,
   cracked-gem resolution, marked-rock blocking, auto-stake, and board
   completion. Phase 4 adds pre-mark neutrality, populate re-entry, non-shell
   neighbor guards, pre-population HUD, and finale lifecycle/reset coverage.
3. Add a headless scene boot contract check if practical; do not require a
   rendered viewport.
4. Report failures to the PM; do not edit gameplay files to make tests pass.

**Exit criteria:** `make test` runs headlessly and fails meaningfully; all tests
green against the integrated Phase 1 code.

### Phase 3 — Whole-cube finale (`finale`)

**Depends on:** Phase 2A tile hook and Phase 1 controller hook.
**Parallel with:** none after Phase 2.

Files: `volumetric_cube_controller.gd` (victory sequence only), new
`excavation_finale.gd`. No scene edits; instantiate the helper from code.

1. Implement a single whole-cube extraction sequence: rock tiles peel/sink in a
   sweep, staked gems rise or glow, and a large faceted mother-lode core is
   revealed.
2. Reuse the retired 4×4 gem concept from history, scaled to the 10×10 core.
3. Ensure the sequence runs exactly once, blocks input, and is safe to interrupt
   with New Game.
4. No infinite `Tween` loops; use `_process` or a finite loop with a clean kill
   path.
5. Update the final HUD message: claim complete, all six faces surveyed, and
   the actual number of gems secured (including cracked gems).

**Exit criteria:** finale runs once with no Tween errors; restart during and
after the finale works; no orphaned nodes.

### Phase 4 — Verification and audit (PM, `rules-verifier`, `auditor`)

**Depends on:** Phases 2 and 3.

1. Run `make check` and `make test` on the integrated branch.
2. Manually run the checklist in section 10.
3. `auditor` performs a read-only review: rule regressions, shared-edge
   ownership, completion edge cases, stale mine/defuse terminology, performance
   hotspots, and docs drift.
4. PM triages findings into: fix now, defer, or reject. Original owners fix
   their files; re-run gates after each fix.
5. Required hardening fixes from the Phase 4 audit:
   - remove the live stake-correctness oracle from the HUD and cube net; show
     stakes placed, not confirmed gems or misplaced stakes;
   - make pre-marks neutral for placement and make `populate_gems()` total;
   - guard non-shell neighbor queries;
   - cancel rotation/elastic/shake tweens and disable old-tile input on reset;
   - suppress survey/auto-stake on a loss;
   - add the async finale lifecycle suite, pre-population suite, and
     `check: import` / fixed-fps test target.

**Exit criteria:** all gates green; audit findings resolved or explicitly
deferred with a note; `make test` covers the finale lifecycle and reset.

### Phase 5 — Documentation and release (scribe, PM)

**Depends on:** Phase 4.

1. Rewrite `README.md` for Gem Miner: fiction, rules, controls, victory.
2. Update `docs/ARCHITECTURE.md`: new cell states, completion predicate, remove
   the dissolve section, document the finale and cube net.
3. Update `AGENTS.md`: invariants, traps, verification checklist, and remove
   obsolete mine/defuse guidance.
4. PM updates this plan's status table and decision log, runs final gates, and
   prepares the release commit.

**Exit criteria:** docs match behavior; `make check` and `make test` green; no
stale references to face dissolve or mandatory mine marking.

## 8. Branch and worktree strategy

- `main` stays the stable baseline. Integration happens on `gem-miner`.
- Phase 1 runs in the integration worktree.
- Phase 2 runs in three worktrees created from the Phase 1 tip:
  `gem-miner-view`, `gem-miner-ui`, `gem-miner-tests`.
- Each worktree runs `make import` once before `make check`; `.godot/` is
  per-worktree and ignored.
- Merge order: `tile-view` → `hud-ui` → `rules-verifier`, running `make check`
  after each merge.
- Phase 3 runs on the integration branch after the Phase 2 merges.
- No force-pushes, no direct-to-`main` agent commits, no rebasing shared
  branches.

## 9. Handoff protocol

Every agent reports:

```text
Agent:
Phase:
Branch/worktree:
Commit:
Files changed:
What works:
Tests run:
Manual checks:
Known issues / follow-ups:
Contract changes requested:
```

Definition of done: scoped changes only, `make check` clean, tests run where
available, no unrelated formatting churn, and an explicit statement of what
could not be verified headlessly.

## 10. Acceptance and manual checklist

- [ ] Six faces rotate correctly; numbers stay upright and appear only on the
      forward face.
- [ ] First left-click never strikes a gem; blank cascades cross shared edges
      and corners.
- [ ] Left-click excavates rock; left-click on a gem cracks it, costs a strike,
      and auto-stakes it.
- [ ] Right-click stakes/unstakes an unrevealed cell; marked rock blocks
      completion. The live UI shows a neutral stakes-placed count and never
      identifies which stake is wrong.
- [ ] Right-click on a satisfied number chords only face-local neighbors.
- [ ] Easy/Medium continue after a crack; Hard ends on the first crack.
- [ ] Surveying a face pulses/checks in without removing tiles.
- [ ] All-rock-revealed auto-stakes the remaining gems.
- [ ] Board completion runs the finale once; New Game during and after the
      finale resets cleanly.
- [ ] Counts: 488 cells, 428 rock, 60 gems; per-face totals are 100 each.
- [ ] No script/parse errors; no Tween infinite-loop errors; no orphaned nodes.
- [ ] Performance is comparable to the pre-reframe 10×10 build.

## 11. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Two agents edit `volumetric_minesweeper.tscn` | `hud-ui` is sole writer; finale instantiates from code |
| Grid/controller/view interface drift | Frozen contract in Phase 0; PM approves additive changes |
| Cracked-gem win deadlock | `is_cell_resolved` treats cracks as resolved; test it |
| Stakes on rock make completion impossible | Neutral stakes-placed count plus a “pull a stake” stuck hint; unmark is allowed; no live correctness oracle |
| Live UI confirms stake correctness | All stakes render identically; confirmed-gem and misplaced counts are never shown live |
| Pre-marks reduce the gem pool | Pre-marks do not affect placement; they may land on gems |
| Mandatory marking is tedious | Auto-stake remaining gems once all rock is revealed |
| Cascade on *any* zero face remains inconsistent | Explicitly out of scope; log for a later rules pass |
| Wrong-mark chording quirk | Explicitly out of scope; covered by a characterization test |
| Headless cannot verify visuals/input | Manual checklist plus read-only audit |
| Parallel Godot runs corrupt `.godot` | One worktree per parallel agent |
| Hidden cage mesh bloat | Lazy mark visuals; no per-tile cage construction |
| Deferred `queue_free` on reset | Keep reset rebuild pattern; verify old tiles do not receive input |
| 4×4 experiment is accidentally revived | Do not touch retired code; docs note it is retired |

## 12. Out of scope for this reframe

- Changing number, cascade, or chording rules.
- Difficulty-based gem counts.
- Free-orbit or drag-to-rotate camera.
- Audio, textures, imported models, or third-party dependencies.
- Mobile/touch-specific UI beyond the existing long-press path.
- Reviving the 4×4 gem experiment or per-face dissolve.
- Automated rendering/visual regression tests.

## 13. Status tracker

| Phase | Owner | Status | Commit | Notes |
| --- | --- | --- | --- | --- |
| 0 — Contract | `pm` | Done | `21b62bb` | Branch `gem-miner`; baseline `make check` green |
| 1 — Core rules/loop | `core-rules` | Done | `05cb14d` | Frozen stats keys and signals; `make check` green |
| 2A — Tile view | `tile-view` | Done | `7189dff` | X stakes, crystals, lazy overlays, extraction hooks |
| 2B — HUD/net | `hud-ui` | Done | `c3cf59f` | HUD, cube net, face pulses |
| 2C — Tests | `rules-verifier` | Done | `59c2ae8` | 289-check suite |
| 3 — Finale | `finale` | Done | `76d0238` | Whole-cube sweep, mother lode, restart-safe |
| 4 — Audit/hardening | `auditor`, PM, all owners | Done | `da162f2` | Anti-oracle UI, pre-mark neutrality, reset/perf fixes; final suite 474 checks |
| 5 — Docs | `scribe` | Done | `ac6b776` | README/architecture/agent guide rewritten for Gem Miner |

**Final gates:** `make import`, `make check`, and `make test` green on the
integrated tree; `TEST RESULT: PASS (474 checks)`. Live test with:
`make import && make run`.

## 14. Decision log

| Date | Decision | By |
| --- | --- | --- |
| 2026-10-26 | 10×10 baseline restored on `main`; 4×4 experiment retired | PM |
| 2026-10-26 | Claim-staking fiction; X stakes; numbers are gem scans | User |
| 2026-10-26 | Cracked gems auto-stake and remain winnable | User |
| 2026-10-26 | Victory = all rock revealed + all gems staked/cracked | User |
| 2026-10-26 | Auto-stake remaining gems when all rock is revealed | User |
| 2026-10-26 | Keep 60 gems on 10×10 | User |
| 2026-10-26 | Face milestone pulses only; no tile removal | User |
| 2026-10-26 | Mechanical code rename to gem/mark/excavate | User |
| 2026-10-26 | P1 renames `total_gems` and updates the one scene line; P2B retains it | PM |
| 2026-10-26 | Add `face_surveyed(face)` and `claim_complete()` controller signals | PM |
| 2026-10-26 | Put `gems_populated` on the grid; completion requires it | PM |
| 2026-10-26 | ~~Pre-marked cells are excluded from gem placement~~ superseded 2026-10-26 by Phase 4 neutrality | PM |
| 2026-10-26 | Cracked gems never set `is_revealed`; loss has precedence over victory | PM |
| 2026-10-26 | Face milestones emit once; auto-stake emits each newly surveyed face | PM |
| 2026-10-26 | Remove live stake-correctness feedback; show stakes placed, not confirmed gems/misplaced | PM |
| 2026-10-26 | Pre-marks do not affect gem placement; populate_gems clears prior gems | PM |
| 2026-10-26 | Face checks reflect current completion; suppress checks on loss | PM |
| 2026-10-26 | `make check` depends on `make import`; tests run at fixed 60 fps | PM |
| 2026-10-26 | Final copy reports actual gems secured, including cracked | PM |
| 2026-10-26 | Remove per-face rock denominators and pre-pop stake-count mismatch | PM |
| 2026-10-26 | Stabilize camera home across interrupted shakes/finale | PM |
| 2026-10-26 | Final suite covers anti-oracle UI, camera stability, cracked copy (474 checks) | PM |
| 2026-10-26 | Promote the finished Gem Miner build to `main` for live testing | PM |

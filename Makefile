GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot
SCENE ?= res://volumetric_minesweeper.tscn
FRAMES ?= 120
TEST_SCRIPT ?= res://tests/run_tests.gd
TEST_FRAMES ?= 9000
# Deterministic frame delta for awaited suites; also makes the run much faster.
TEST_FLAGS ?= --fixed-fps 60

.PHONY: all run editor import check test web web-debug serve-web

all: check test

run:
	$(GODOT) --path . $(SCENE)

editor:
	$(GODOT) -e --path .

# Web export. Requires the Web export templates (Editor > Manage Export Templates).
web:
	@mkdir -p build/web
	$(GODOT) --headless --path . --export-release "Web" build/web/index.html

web-debug:
	@mkdir -p build/web
	$(GODOT) --headless --path . --export-debug "Web" build/web/index.html

# Serve the exported build locally. Do not open index.html via file://.
serve-web:
	@test -f build/web/index.html || (echo "Run 'make web' first."; exit 1)
	cd build/web && python3 -m http.server 8000

# Generates .godot/ and the global class cache. Required in a fresh checkout and
# after any new class_name merges, so check/test depend on it.
import:
	$(GODOT) --headless --path . --import

# Boot the scene headless and fail on script/parse errors.
check: import
	@out=$$(mktemp); \
	$(GODOT) --headless --path . --quit-after $(FRAMES) $(SCENE) > "$$out" 2>&1; \
	cat "$$out"; \
	if grep -qE "SCRIPT ERROR|Parse Error" "$$out"; then \
		rm -f "$$out"; \
		echo "check failed: script errors above"; \
		exit 1; \
	fi; \
	rm -f "$$out"

# Run the headless rule/topology suite. Fails on a non-zero exit, any script
# error, or a missing PASS marker (an aborted suite must not look successful).
test: import
	@out=$$(mktemp); \
	$(GODOT) --headless --path . $(TEST_FLAGS) --quit-after $(TEST_FRAMES) --script $(TEST_SCRIPT) > "$$out" 2>&1; \
	status=$$?; \
	cat "$$out"; \
	if [ $$status -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error" "$$out" || ! grep -q "^TEST RESULT: PASS" "$$out"; then \
		rm -f "$$out"; \
		echo "test failed: see output above"; \
		exit 1; \
	fi; \
	rm -f "$$out"

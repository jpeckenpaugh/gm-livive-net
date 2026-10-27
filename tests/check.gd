extends RefCounted

# Tiny assertion collector shared by the headless test suites.
# No class_name, so the project's global class cache stays untouched.

var tree: SceneTree = null
var checks: int = 0
var failures: int = 0
var current_group: String = ""

func group(name: String) -> void:
	current_group = name
	print("  [%s]" % name)

func ok(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL [%s] %s" % [current_group, label])
	return condition

func eq(actual, expected, label: String) -> bool:
	return ok(actual == expected, "%s: expected %s, got %s" % [label, str(expected), str(actual)])

func ne(actual, unexpected, label: String) -> bool:
	return ok(actual != unexpected, "%s: did not expect %s" % [label, str(unexpected)])

## Fails when HUD/status copy contains pictographic emoji or their variation
## selectors. Plain typography (em dash, middle dot) is allowed.
func no_emoji(text: String, label: String) -> bool:
	var found := false
	for i in range(text.length()):
		var code: int = text.unicode_at(i)
		if (code >= 0x1F000 and code <= 0x1FAFF) \
				or (code >= 0x2600 and code <= 0x27BF) \
				or code == 0xFE0F:
			found = true
			break
	return ok(not found, "%s: emoji found in \"%s\"" % [label, text])

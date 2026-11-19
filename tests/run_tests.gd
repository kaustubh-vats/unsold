extends SceneTree
## Minimal headless test runner.
## Usage: godot --headless --path . -s res://tests/run_tests.gd

var failures := 0
var passed := 0


func _initialize() -> void:
	var dir := DirAccess.open("res://tests")
	var files := []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			failures += 1
			print("  FAIL  %s could not be loaded (parse error)" % f)
			continue
		var inst = script.new()
		inst.set("runner", self)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var before := failures
			var t0 := Time.get_ticks_msec()
			inst.call(name)
			var ms := Time.get_ticks_msec() - t0
			if failures == before:
				passed += 1
				print("  PASS  %s.%s (%d ms)" % [f.get_basename(), name, ms])
			else:
				print("  FAIL  %s.%s" % [f.get_basename(), name])
	print("\n%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("ASSERT: " + msg)
		print("        ✗ " + msg)

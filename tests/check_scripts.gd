extends SceneTree
## Loads every script in the project to surface parse/compile errors.
## Usage: godot --headless --path . -s res://tests/check_scripts.gd


func _initialize() -> void:
	var bad := 0
	var files := []
	_collect("res://scripts", files)
	for f in files:
		var s = load(f)
		if s == null or (s is GDScript and not s.can_instantiate()):
			print("  BROKEN  ", f)
			bad += 1
	print("%d scripts checked, %d broken" % [files.size(), bad])
	quit(1 if bad > 0 else 0)


func _collect(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	for sub in d.get_directories():
		_collect(dir_path + "/" + sub, out)

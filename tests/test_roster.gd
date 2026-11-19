extends RefCounted
## Roster editor: rename, export/import round trip, reset. Preserves any
## real user roster file that exists before the test runs.

var runner


func ok(cond: bool, msg: String) -> void:
	runner.check(cond, msg)


func test_roster_roundtrip() -> void:
	var backup := ""
	var had := FileAccess.file_exists(DB.ROSTER_FILE)
	if had:
		backup = FileAccess.get_file_as_string(DB.ROSTER_FILE)
	DB.reset_roster()
	var id: String = DB.all_ids()[0]
	var default_name := DB.default_player_name(id)
	DB.set_player_name(id, "Real Name Here")
	ok(DB.player(id)["name"] == "Real Name Here", "rename applies")
	DB.set_team_names("MUM", "My Custom Team", "mct")
	ok(DB.team("MUM")["name"] == "My Custom Team" and DB.team_short("MUM") == "MCT", "team rename + upper-case code")
	var exported := DB.export_roster()
	DB.reset_roster()
	ok(DB.player(id)["name"] == default_name, "reset restores default")
	ok(DB.team_short("MUM") == "MUM", "reset restores team code")
	var res := DB.import_roster(exported)
	ok(res["ok"] and res["count"] == 2, "import applies 2 overrides (%s)" % str(res))
	ok(DB.player(id)["name"] == "Real Name Here", "imported name")
	ok(not DB.import_roster("{\"hello\": 1}")["ok"], "rejects non-roster JSON")
	DB.set_player_name(id, "")
	ok(DB.player(id)["name"] == default_name, "empty name restores default")
	# Restore the user's own roster.
	DB.reset_roster()
	if had:
		DB.import_roster(backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DB.ROSTER_FILE))

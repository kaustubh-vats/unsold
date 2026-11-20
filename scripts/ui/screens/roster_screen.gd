extends VBoxContainer
## Roster editor: rename any player or team on this device, and export/import
## roster files so fans can share name packs. Names are display-only; online
## rooms sync ids, so each device shows its own roster.

const PAGE := 40

var tab := "players"
var role_filter := "ALL"
var query := ""
var list: VBoxContainer
var filters: HBoxContainer
var search: LineEdit
var count_label: Label
var import_panel: PanelContainer
var import_text: TextEdit
var reset_armed := false
var shown := PAGE


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var top := UI.hbox()
	top.add_child(UI.button("◀", func(): Game.goto("home"), "icon"))
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.caption("Make it yours", UI.GOLD))
	tv.add_child(UI.display("Roster editor", 34))
	top.add_child(tv)
	add_child(top)
	add_child(UI.segmented(["Players", "Teams"], ["players", "teams"], tab, func(v):
		tab = v
		shown = PAGE
		_render()))
	var srow := UI.hbox(8)
	search = LineEdit.new()
	search.placeholder_text = "Search players…"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = 46
	search.clear_button_enabled = true
	search.text_changed.connect(func(t):
		query = t.strip_edges().to_lower()
		shown = PAGE
		_render())
	srow.add_child(search)
	add_child(srow)
	filters = UI.segmented(["All", "BAT", "WK", "AR", "PACE", "SPIN"], ["ALL", "BAT", "WK", "AR", "PACE", "SPIN"],
		role_filter, func(v):
			role_filter = v
			shown = PAGE
			_render())
	add_child(filters)
	count_label = UI.caption("", UI.DIM, 10)
	add_child(count_label)
	list = UI.vbox(6)
	add_child(UI.scroll(list))
	_build_import_panel()
	var row := UI.hbox(8)
	row.add_child(UI.expand(UI.button("Export", _export, "normal", 15)))
	row.add_child(UI.expand(UI.button("Import", _toggle_import, "normal", 15)))
	var reset := UI.button("Reset all", Callable(), "danger", 15)
	reset.pressed.connect(func(): _reset(reset))
	row.add_child(UI.expand(reset))
	add_child(row)
	_render()


func _render() -> void:
	UI.clear(list)
	search.visible = tab == "players"
	filters.visible = tab == "players"
	if tab == "teams":
		count_label.text = "Tap a name or code to edit  •  changes save automatically"
		for t in DB.teams():
			list.add_child(_team_row(t["id"]))
		return
	var ids := []
	for id in DB.all_ids():
		var p := DB.player(id)
		if role_filter != "ALL" and p["role"] != role_filter:
			continue
		if query != "" and not (p["name"].to_lower().contains(query) or DB.default_player_name(id).to_lower().contains(query)):
			continue
		ids.append(id)
	count_label.text = "%d players  •  %d renamed  •  changes save automatically" % [ids.size(), DB.override_count()]
	for id in ids.slice(0, shown):
		list.add_child(_player_row(id))
	if ids.size() > shown:
		var more := UI.button("Show more (%d left)" % (ids.size() - shown), func():
			shown += PAGE
			_render(), "ghost", 14)
		list.add_child(more)


func _player_row(id: String) -> Control:
	var p := DB.player(id)
	var panel := UI.panel(UI.GLASS, 14, 10, Color(UI.GOLD, 0.45) if DB.is_renamed(id) else UI.LINE)
	var h := UI.hbox(10)
	panel.add_child(h)
	h.add_child(UI.role_icon(p["role"], 34))
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var e := LineEdit.new()
	e.text = p["name"]
	e.max_length = 32
	e.custom_minimum_size.y = 40
	e.select_all_on_focus = true
	var commit := func(_t = ""):
		if e.text.strip_edges() != DB.player(id)["name"]:
			DB.set_player_name(id, e.text)
			e.text = DB.player(id)["name"]
	e.text_submitted.connect(commit)
	e.focus_exited.connect(commit)
	v.add_child(e)
	var info := "%s  •  %s  •  OVR %d" % [p["country"], p["role"], p["ovr"]]
	if DB.is_renamed(id):
		info += "  •  DEFAULT: " + DB.default_player_name(id).to_upper()
	v.add_child(UI.caption(info, UI.DIM, 10))
	h.add_child(v)
	if DB.is_renamed(id):
		var r := UI.small_button("Reset", func():
			DB.set_player_name(id, "")
			_render())
		r.tooltip_text = "Restore default name"
		h.add_child(r)
	return panel


func _team_row(id: String) -> Control:
	var t := DB.team(id)
	var panel := UI.panel(UI.GLASS, 14, 10, Color(UI.GOLD, 0.45) if DB.is_renamed(id) else UI.LINE)
	var h := UI.hbox(10)
	panel.add_child(h)
	h.add_child(UI.crest(id, 44))
	var name_e := LineEdit.new()
	name_e.text = t["name"]
	name_e.max_length = 32
	name_e.custom_minimum_size.y = 42
	name_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var code_e := LineEdit.new()
	code_e.text = t["short"]
	code_e.max_length = 4
	code_e.custom_minimum_size = Vector2(76, 42)
	code_e.add_theme_font_override("font", UI.display_font())
	code_e.add_theme_font_size_override("font_size", 22)
	var commit := func(_x = ""):
		var cur := DB.team(id)
		if name_e.text.strip_edges() != cur["name"] or code_e.text.strip_edges().to_upper() != cur["short"]:
			DB.set_team_names(id, name_e.text, code_e.text)
			_render.call_deferred()
	for e in [name_e, code_e]:
		e.select_all_on_focus = true
		e.text_submitted.connect(commit)
		e.focus_exited.connect(commit)
	h.add_child(name_e)
	h.add_child(code_e)
	if DB.is_renamed(id):
		h.add_child(UI.small_button("Reset", func():
			DB.set_team_names(id, "", "")
			_render()))
	return panel


func _build_import_panel() -> void:
	import_panel = UI.glass(14)
	import_panel.visible = false
	var v := UI.vbox(8)
	import_panel.add_child(v)
	v.add_child(UI.caption("Paste a roster file below", UI.GOLD))
	import_text = TextEdit.new()
	import_text.custom_minimum_size.y = 120
	import_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	import_text.placeholder_text = "{ \"format\": \"unsold-roster-1\", ... }"
	import_text.add_theme_stylebox_override("normal", UI.box(UI.FIELD, 10, 10, UI.LINE))
	import_text.add_theme_font_size_override("font_size", 13)
	v.add_child(import_text)
	var r := UI.hbox(8)
	r.add_child(UI.expand(UI.button("Paste from clipboard", func():
		import_text.text = DisplayServer.clipboard_get(), "ghost", 14)))
	r.add_child(UI.expand(UI.button("APPLY", _apply_import, "primary", 14)))
	v.add_child(r)
	add_child(import_panel)


func _toggle_import() -> void:
	import_panel.visible = not import_panel.visible


func _apply_import() -> void:
	var res := DB.import_roster(import_text.text)
	if res["ok"]:
		UI.toast(self, "Imported %d names" % res["count"], UI.GREEN)
		import_panel.visible = false
		import_text.text = ""
		_render()
	else:
		UI.toast(self, res["error"])


func _export() -> void:
	var text := DB.export_roster()
	DisplayServer.clipboard_set(text)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "unsold-roster.json", "application/json")
		UI.toast(self, "Roster downloaded and copied", UI.GREEN)
	else:
		var path := "user://unsold-roster.json"
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(text)
		UI.toast(self, "Roster copied to clipboard", UI.GREEN)


func _reset(btn: Button) -> void:
	if not reset_armed:
		reset_armed = true
		btn.text = "Tap again to reset"
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(btn):
				reset_armed = false
				btn.text = "Reset all")
		return
	reset_armed = false
	btn.text = "Reset all"
	DB.reset_roster()
	UI.toast(self, "All names restored", UI.GREEN)
	_render()

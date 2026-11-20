extends VBoxContainer
## Title screen: logo, name, single player, and online room create/join.

var name_edit: LineEdit
var code_edit: LineEdit
var status_label: Label
var busy := false
var logo: Control
var mp_card: PanelContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var top := UI.hbox()
	top.add_child(UI.spacer(0, 1))
	top.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(UI.theme_button())
	top.add_child(UI.sound_button())
	add_child(top)

	if ResourceLoader.exists("res://assets/logo.png"):
		logo = UI.texture_rect("res://assets/logo.png", Vector2(0, 150))
	else:
		logo = UI.center(UI.display("UNSOLD", 84, UI.GOLD))
	add_child(logo)
	add_child(UI.center(UI.caption("The cricket league auction simulator", UI.MUTED, 13)))
	if DB.is_friends_edition():
		var tag := UI.chip("FRIENDS EDITION", Color(UI.GOLD, 0.18), UI.GOLD, 11)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(tag)

	# Profile + single player.
	var card := UI.glass(18)
	var v := UI.vbox(12)
	card.add_child(v)
	v.add_child(UI.caption("Your name"))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "e.g. Kaustubh"
	name_edit.max_length = 16
	name_edit.text = Game.player_name
	name_edit.custom_minimum_size.y = 52
	name_edit.add_theme_font_size_override("font_size", 18)
	v.add_child(name_edit)
	var sp := UI.button("PLAY SOLO", _single, "primary", 20)
	sp.custom_minimum_size.y = 60
	v.add_child(sp)
	v.add_child(UI.center(UI.label("You vs 9 AI franchises  •  works offline", 13, UI.MUTED)))
	add_child(card)

	# Multiplayer (needs an account).
	mp_card = UI.glass(18)
	add_child(mp_card)
	_build_online()
	Firebase.auth_changed.connect(_build_online)
	var rb := UI.button("Roster editor  •  rename players & teams", func(): Game.goto("roster"), "ghost", 14)
	rb.custom_minimum_size.y = 44
	add_child(rb)

	status_label = UI.center(UI.wrap(UI.label("", 14, UI.RED)))
	add_child(status_label)
	add_child(UI.spacer())
	var rules := UI.hbox(18)
	rules.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair in [["₹120 CR", "purse"], ["18–25", "squad"], ["8", "overseas"], ["10", "franchises"]]:
		var col := UI.vbox(0)
		col.add_child(UI.center(UI.display(pair[0], 24, UI.GOLD)))
		col.add_child(UI.center(UI.caption(pair[1], UI.DIM, 10)))
		rules.add_child(col)
	add_child(rules)

	# Gentle breathing on the logo.
	await get_tree().process_frame
	if is_instance_valid(logo):
		logo.pivot_offset = logo.size / 2.0
		var tw := logo.create_tween().set_loops()
		tw.tween_property(logo, "scale", Vector2(1.025, 1.025), 2.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(logo, "scale", Vector2.ONE, 2.2).set_trans(Tween.TRANS_SINE)


func _say(text: String, color := UI.RED) -> void:
	status_label.add_theme_color_override("font_color", color)
	status_label.text = text


func _check_name() -> bool:
	var n := name_edit.text.strip_edges()
	if n.length() < 2:
		_say("Please enter your name")
		UI.pop(name_edit)
		return false
	Game.save_name(n)
	return true


func _single() -> void:
	if _check_name():
		Game.start_single()


func _create() -> void:
	if busy or not _check_name():
		return
	busy = true
	_say("Creating room…", UI.MUTED)
	var err := await Game.create_room()
	busy = false
	if err != "" and is_instance_valid(status_label):
		_say(err)


func _join() -> void:
	if busy or not _check_name():
		return
	if code_edit.text.strip_edges().length() != 6:
		_say("Enter the 6-character room code")
		return
	busy = true
	_say("Joining…", UI.MUTED)
	var err := await Game.join_room(code_edit.text)
	busy = false
	if err != "" and is_instance_valid(status_label):
		_say(err)


## Online card: account status + room controls when signed in, sign-in button otherwise.
func _build_online() -> void:
	if not is_instance_valid(mp_card):
		return
	UI.clear(mp_card)
	var mv := UI.vbox(12)
	mp_card.add_child(mv)
	var mh := UI.hbox(8)
	var cap := UI.caption("Play with friends", UI.GOLD)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(cap)
	mv.add_child(mh)
	if not Firebase.is_configured():
		mv.add_child(UI.wrap(UI.label("Online play needs Firebase settings — see README.", 13, UI.DIM)))
		return
	if not Firebase.is_signed_in():
		mv.add_child(UI.wrap(UI.label("Sign in to create or join rooms with friends.", 14, UI.MUTED)))
		mv.add_child(UI.button("Sign in / Create account", func(): Game.goto("auth")))
		return
	var who := UI.hbox(8)
	var wl := UI.vbox(0)
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wl.add_child(UI.label(Firebase.display_name, 15, UI.TEXT, true))
	var mail := UI.caption(Firebase.email, UI.DIM, 10)
	mail.clip_text = true
	wl.add_child(mail)
	who.add_child(wl)
	who.add_child(UI.small_button("Sign out", func(): Firebase.sign_out()))
	mv.add_child(who)
	var row := UI.hbox(10)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ROOM CODE"
	code_edit.max_length = 6
	code_edit.custom_minimum_size.y = 52
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.add_theme_font_override("font", UI.display_font())
	code_edit.add_theme_font_size_override("font_size", 28)
	code_edit.text_changed.connect(func(t):
		var up: String = t.to_upper()
		if up != t:
			var c := code_edit.caret_column
			code_edit.text = up
			code_edit.caret_column = c)
	row.add_child(code_edit)
	var jb := UI.button("JOIN", _join)
	jb.custom_minimum_size.x = 110
	row.add_child(jb)
	mv.add_child(row)
	mv.add_child(UI.button("Create a room", _create))
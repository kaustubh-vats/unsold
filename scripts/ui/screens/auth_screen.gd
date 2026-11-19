extends VBoxContainer
## Sign in / create account (email + password, or Google). Required for online
## rooms; solo play works without an account.

var mode := "signin"   # signin | signup
var name_row: Control
var name_edit: LineEdit
var email_edit: LineEdit
var pass_edit: LineEdit
var submit_btn: Button
var forgot_btn: Button
var google_btn: Button
var status_label: Label
var busy := false


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var top := UI.hbox()
	top.add_child(UI.button("◀", func(): Game.goto("home"), "icon"))
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.caption("Online play", UI.GOLD))
	tv.add_child(UI.display("Your account", 36))
	top.add_child(tv)
	add_child(top)
	add_child(UI.segmented(["Sign in", "Create account"], ["signin", "signup"], mode, func(v):
		mode = v
		_refresh()))

	var card := UI.glass(18)
	var v := UI.vbox(10)
	card.add_child(v)
	name_row = UI.vbox(6)
	name_row.add_child(UI.caption("Display name"))
	name_edit = _field("Shown to other players", false)
	name_edit.max_length = 16
	name_edit.text = Game.player_name
	name_row.add_child(name_edit)
	v.add_child(name_row)
	v.add_child(UI.caption("Email"))
	email_edit = _field("you@example.com", false)
	email_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	v.add_child(email_edit)
	v.add_child(UI.caption("Password"))
	pass_edit = _field("At least 6 characters", true)
	pass_edit.text_submitted.connect(func(_t): _submit())
	v.add_child(pass_edit)
	submit_btn = UI.button("SIGN IN", _submit, "primary", 18)
	submit_btn.custom_minimum_size.y = 58
	v.add_child(submit_btn)
	forgot_btn = UI.button("Forgot password?", _forgot, "ghost", 13)
	forgot_btn.custom_minimum_size.y = 38
	v.add_child(forgot_btn)
	add_child(card)

	var orow := UI.hbox(10)
	var l1 := UI.hline()
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l2 := UI.hline()
	l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	orow.add_child(l1)
	orow.add_child(UI.caption("or", UI.DIM))
	orow.add_child(l2)
	add_child(orow)

	google_btn = _google_button()
	add_child(google_btn)
	if not Firebase.google_available():
		google_btn.disabled = true
		add_child(UI.center(UI.wrap(UI.label("Google sign-in works in the Android app and on the web.", 12, UI.DIM))))

	status_label = UI.center(UI.wrap(UI.label("", 14, UI.RED, true)))
	add_child(status_label)
	add_child(UI.spacer())
	add_child(UI.center(UI.wrap(UI.label("Solo play doesn't need an account.", 12, UI.DIM))))
	_refresh()


func _field(placeholder: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size.y = 50
	e.add_theme_font_size_override("font_size", 17)
	return e


func _google_button() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 56
	b.add_theme_stylebox_override("normal", UI.box(Color("f8f9fb"), 14, 14))
	b.add_theme_stylebox_override("hover", UI.box(Color.WHITE, 14, 14, UI.GOLD))
	b.add_theme_stylebox_override("pressed", UI.box(Color("e4e7ee"), 14, 14))
	b.add_theme_stylebox_override("disabled", UI.box(Color(1, 1, 1, 0.25), 14, 14))
	var h := UI.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var g := UI.label("G", 22, Color("4285f4"), true)
	h.add_child(g)
	h.add_child(UI.label("Continue with Google", 16, Color("1f1f1f"), true))
	UI.ignore_mouse(h)
	b.add_child(h)
	b.pressed.connect(func():
		UI._click()
		_google())
	return b


func _refresh() -> void:
	name_row.visible = mode == "signup"
	forgot_btn.visible = mode == "signin"
	submit_btn.text = "SIGN IN" if mode == "signin" else "CREATE ACCOUNT"
	status_label.text = ""


func _say(t: String, col := UI.RED) -> void:
	status_label.add_theme_color_override("font_color", col)
	status_label.text = t


func _set_busy(b: bool) -> void:
	busy = b
	submit_btn.disabled = b
	google_btn.disabled = b or not Firebase.google_available()


func _done() -> void:
	UI.toast(get_parent(), "Signed in as " + Firebase.display_name, UI.GREEN)
	Game.goto("home")


func _submit() -> void:
	if busy:
		return
	var mail := email_edit.text.strip_edges()
	var pw := pass_edit.text
	if not mail.contains("@"):
		_say("Enter a valid email address.")
		return
	if pw.length() < 6:
		_say("Password must be at least 6 characters.")
		return
	var err := ""
	_set_busy(true)
	if mode == "signup":
		var nm := name_edit.text.strip_edges()
		if nm.length() < 2:
			_set_busy(false)
			_say("Enter a display name.")
			return
		_say("Creating your account…", UI.MUTED)
		err = await Firebase.sign_up_email(mail, pw, nm)
		if err == "":
			Game.save_name(nm)
	else:
		_say("Signing in…", UI.MUTED)
		err = await Firebase.sign_in_email(mail, pw)
	if not is_instance_valid(self):
		return
	_set_busy(false)
	if err == "":
		_done()
	else:
		_say(err)


func _google() -> void:
	if busy:
		return
	_set_busy(true)
	_say("Opening Google…", UI.MUTED)
	var err := await Firebase.sign_in_google()
	if not is_instance_valid(self):
		return
	_set_busy(false)
	if err == "":
		_done()
	elif err == "cancelled":
		_say("")
	else:
		_say(err)


func _forgot() -> void:
	var mail := email_edit.text.strip_edges()
	if not mail.contains("@"):
		_say("Type your email above, then tap “Forgot password?”.")
		return
	_set_busy(true)
	var err := await Firebase.reset_password(mail)
	if not is_instance_valid(self):
		return
	_set_busy(false)
	if err == "":
		_say("Password reset email sent to " + mail, UI.GREEN)
	else:
		_say(err)

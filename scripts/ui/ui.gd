class_name UI
extends RefCounted
## Design system: "auction night" broadcast look. Glass panels over a floodlit
## stadium, condensed display type for names and money, gold for value, team
## colours for identity. Screens are built in code from these helpers.

# Palette. Two themes share the same token names; `set_light()` swaps them and
# the app rebuilds the current screen. Colours are static vars (not consts) so
# they can change at runtime.
static var DARK := {
	"BG": Color("070a14"), "GLASS": Color(0.075, 0.09, 0.16, 0.84), "GLASS_HI": Color(0.12, 0.145, 0.25, 0.92),
	"LINE": Color(1, 1, 1, 0.09), "TEXT": Color("f2f4fa"), "MUTED": Color("97a0bd"), "DIM": Color("5d6684"),
	"GOLD": Color("ffc53d"), "GOLD_DEEP": Color("f59e0b"), "RED": Color("ff4d6d"), "GREEN": Color("22d38a"),
	"BLUE": Color("4f8cff"), "FIELD": Color(0.04, 0.05, 0.1, 0.85), "INK": Color(1, 1, 1),
}
static var LIGHT := {
	"BG": Color("eef0f5"), "GLASS": Color(1, 1, 1, 0.9), "GLASS_HI": Color(1, 1, 1, 0.97),
	"LINE": Color(0.08, 0.1, 0.2, 0.12), "TEXT": Color("141a2b"), "MUTED": Color("586078"), "DIM": Color("8a92a8"),
	"GOLD": Color("c98a00"), "GOLD_DEEP": Color("a86f00"), "RED": Color("d6284b"), "GREEN": Color("0e9a62"),
	"BLUE": Color("2563eb"), "FIELD": Color(1, 1, 1, 0.95), "INK": Color(0.05, 0.07, 0.15),
}
const SETTINGS := "user://ui.cfg"

static var light := false
static var BG: Color = DARK["BG"]
static var GLASS: Color = DARK["GLASS"]
static var GLASS_HI: Color = DARK["GLASS_HI"]
static var LINE: Color = DARK["LINE"]
static var TEXT: Color = DARK["TEXT"]
static var MUTED: Color = DARK["MUTED"]
static var DIM: Color = DARK["DIM"]
static var GOLD: Color = DARK["GOLD"]
static var GOLD_DEEP: Color = DARK["GOLD_DEEP"]
static var RED: Color = DARK["RED"]
static var GREEN: Color = DARK["GREEN"]
static var BLUE: Color = DARK["BLUE"]
static var FIELD: Color = DARK["FIELD"]
static var INK: Color = DARK["INK"]
# Kept for compatibility with older code paths.
static var PANEL: Color = DARK["GLASS"]
static var PANEL2: Color = DARK["GLASS_HI"]

static var _regular: Font
static var _bold: Font
static var _display: Font
static var _caps: Font


# ------------------------------------------------------------------ theme

## Loads the saved theme choice (call once at startup).
static func load_theme_choice() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		set_light(bool(cfg.get_value("ui", "light", false)), false)


static func set_light(on: bool, save := true) -> void:
	light = on
	var p: Dictionary = LIGHT if on else DARK
	BG = p["BG"]; GLASS = p["GLASS"]; GLASS_HI = p["GLASS_HI"]; LINE = p["LINE"]
	TEXT = p["TEXT"]; MUTED = p["MUTED"]; DIM = p["DIM"]; GOLD = p["GOLD"]
	GOLD_DEEP = p["GOLD_DEEP"]; RED = p["RED"]; GREEN = p["GREEN"]; BLUE = p["BLUE"]
	FIELD = p["FIELD"]; INK = p["INK"]; PANEL = GLASS; PANEL2 = GLASS_HI
	if save:
		var cfg := ConfigFile.new()
		cfg.set_value("ui", "light", on)
		cfg.save(SETTINGS)


## Foreground "ink" at a given opacity: white on dark, near-black on light.
## Used for hairlines, hover washes and subtle row backgrounds.
static func ink(a: float) -> Color:
	return Color(INK, a)


## A panel tint of a team colour: deep on dark, pale on light.
static func shade(col: Color, amount := 0.45, alpha := 0.9) -> Color:
	if light:
		return Color(col.lightened(clampf(0.95 - amount * 0.5, 0.6, 0.85)), alpha)
	return Color(col.darkened(amount), alpha)


## A status colour softened for text: lighter on dark, a touch deeper on light.
static func soft(col: Color, amount := 0.3) -> Color:
	return col.darkened(0.1) if light else col.lightened(amount)


# ------------------------------------------------------------------ fonts

static func _font(path: String, fallbacks: Array) -> Font:
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var f: FontFile = load(path)
	var fb: Array[Font] = []
	for p in fallbacks:
		if ResourceLoader.exists(p):
			fb.append(load(p))
	f.fallbacks = fb
	return f


static func regular_font() -> Font:
	if _regular == null:
		_regular = _font("res://assets/fonts/NotoSans-Regular.ttf", ["res://assets/fonts/NotoSansSymbols2-Regular.ttf"])
	return _regular


static func bold_font() -> Font:
	if _bold == null:
		_bold = _font("res://assets/fonts/NotoSans-Bold.ttf", ["res://assets/fonts/NotoSansSymbols2-Regular.ttf"])
	return _bold


## Condensed display face (Bebas Neue) for names, money and headings.
static func display_font() -> Font:
	if _display == null:
		_display = _font("res://assets/fonts/BebasNeue-Regular.ttf", [
			"res://assets/fonts/NotoSans-Bold.ttf", "res://assets/fonts/NotoSansSymbols2-Regular.ttf"])
	return _display


## Small tracked-out caps for section labels.
static func caps_font() -> Font:
	if _caps == null:
		var v := FontVariation.new()
		v.base_font = bold_font()
		v.spacing_glyph = 2
		_caps = v
	return _caps


# ------------------------------------------------------------------ styles

static func box(color: Color, radius := 14, pad := 14, border := Color(0, 0, 0, 0), border_w := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.8
	s.content_margin_bottom = pad * 0.8
	s.anti_aliasing = true
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	return s


static func glow(s: StyleBoxFlat, color: Color, size := 14) -> StyleBoxFlat:
	s.shadow_color = color
	s.shadow_size = size
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = regular_font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "Button", box(GLASS_HI, 14, 14, LINE))
	t.set_stylebox("hover", "Button", box(GLASS_HI.lightened(0.06), 14, 14, GOLD.darkened(0.35)))
	t.set_stylebox("pressed", "Button", box(GLASS_HI.darkened(0.15), 14, 14, GOLD))
	t.set_stylebox("disabled", "Button", box(ink(0.04), 14, 14))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_font("font", "Button", bold_font())
	t.set_stylebox("normal", "LineEdit", box(FIELD, 12, 14, LINE))
	t.set_stylebox("focus", "LineEdit", box(FIELD, 12, 14, GOLD, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", DIM)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_stylebox("panel", "PanelContainer", box(GLASS, 18, 14, LINE))
	t.set_stylebox("background", "ProgressBar", box(ink(0.07), 6, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOLD, 6, 0))
	t.set_stylebox("panel", "TabContainer", box(GLASS, 16, 10, LINE))
	t.set_stylebox("tab_selected", "TabContainer", box(GLASS, 12, 14))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0, 0, 0, 0), 12, 14))
	t.set_stylebox("tab_hovered", "TabContainer", box(ink(0.04), 12, 14))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font("font", "TabContainer", bold_font())
	t.set_font_size("font_size", "TabContainer", 15)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, box(Color(0, 0, 0, 0), 4, 0))
		t.set_stylebox("grabber", sb, box(ink(0.12), 4, 0))
		t.set_stylebox("grabber_highlight", sb, box(ink(0.25), 4, 0))
		t.set_stylebox("grabber_pressed", sb, box(GOLD, 4, 0))
	return t


# ------------------------------------------------------------------ text

static func label(text: String, size := 17, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", bold_font())
	return l


## Big condensed headline / money text.
static func display(text: String, size := 40, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Small tracked uppercase label for sections and captions.
static func caption(text: String, color := MUTED, size := 12) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", caps_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func center(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# ------------------------------------------------------------------ buttons

static func button(text: String, cb: Callable, kind := "normal", size := 17) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size.y = 52
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	match kind:
		"primary":
			b.add_theme_stylebox_override("normal", glow(box(GOLD, 14, 16), Color(GOLD, 0.28), 12))
			b.add_theme_stylebox_override("hover", glow(box(GOLD.lightened(0.12), 14, 16), Color(GOLD, 0.45), 16))
			b.add_theme_stylebox_override("pressed", glow(box(GOLD_DEEP, 14, 16), Color(GOLD, 0.2), 6))
			b.add_theme_stylebox_override("disabled", box(ink(0.08), 14, 16))
			for c in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(c, Color("1a1405"))
			b.add_theme_color_override("font_disabled_color", ink(0.3))
			b.add_theme_font_override("font", display_font())
			b.add_theme_font_size_override("font_size", size + 8)
		"danger":
			b.add_theme_stylebox_override("normal", box(Color(RED, 0.18), 14, 14, Color(RED, 0.6)))
			b.add_theme_stylebox_override("hover", box(Color(RED, 0.3), 14, 14, RED))
			b.add_theme_color_override("font_color", RED.lightened(0.3))
		"ghost":
			b.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), 12, 12, LINE))
			b.add_theme_stylebox_override("hover", box(ink(0.05), 12, 12, ink(0.2)))
			b.add_theme_color_override("font_color", MUTED)
		"icon":
			b.custom_minimum_size = Vector2(46, 46)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.add_theme_stylebox_override("normal", box(ink(0.05), 23, 8, LINE))
			b.add_theme_stylebox_override("hover", box(ink(0.1), 23, 8, ink(0.2)))
			b.add_theme_stylebox_override("pressed", box(ink(0.15), 23, 8, GOLD))
	b.pressed.connect(func(): _click())
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Compact outlined text button for inline row actions.
static func small_button(text: String, cb: Callable) -> Button:
	var b := button(text, cb, "ghost", 12)
	b.custom_minimum_size = Vector2(64, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


static func _click() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root.has_node("Sfx"):
		tree.root.get_node("Sfx").play("click", -8.0)


## A row of toggle buttons acting as a single choice control.
static func segmented(labels: Array, values: Array, current, cb: Callable, enabled := true) -> HBoxContainer:
	var h := hbox(6)
	var group := ButtonGroup.new()
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not enabled
		b.custom_minimum_size.y = 42
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("normal", box(ink(0.04), 11, 10, LINE))
		b.add_theme_stylebox_override("hover", box(ink(0.08), 11, 10, ink(0.2)))
		b.add_theme_stylebox_override("pressed", box(Color(GOLD, 0.16), 11, 10, GOLD))
		b.add_theme_stylebox_override("hover_pressed", box(Color(GOLD, 0.22), 11, 10, GOLD))
		b.add_theme_stylebox_override("disabled", box(ink(0.02), 11, 10))
		b.add_theme_color_override("font_pressed_color", GOLD)
		b.add_theme_color_override("font_hover_pressed_color", GOLD)
		b.add_theme_color_override("font_color", MUTED)
		b.button_pressed = values[i] == current
		if b.button_pressed:
			b.add_theme_stylebox_override("disabled", box(Color(GOLD, 0.1), 11, 10, Color(GOLD, 0.5)))
			b.add_theme_color_override("font_disabled_color", Color(GOLD, 0.8))
		var v = values[i]
		b.pressed.connect(func():
			_click()
			cb.call(v))
		h.add_child(b)
	return h


# ------------------------------------------------------------------ layout

static func panel(color := GLASS, radius := 18, pad := 14, border := LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius, pad, border))
	return p


static func glass(pad := 16, radius := 20) -> PanelContainer:
	return panel(GLASS, radius, pad, LINE)


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(h := 0, w := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if h == 0 and w == 0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


static func hline() -> Control:
	var c := ColorRect.new()
	c.color = LINE
	c.custom_minimum_size.y = 1
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		ignore_mouse(c)


# ------------------------------------------------------------------ game visuals

static func team_color(tid: String) -> Color:
	var t := DB.team(tid)
	return Color(t.get("primary", "#555")) if not t.is_empty() else MUTED


static func team_color2(tid: String) -> Color:
	var t := DB.team(tid)
	return Color(t.get("secondary", "#999")) if not t.is_empty() else MUTED


## Brighter version of a team colour that stays readable on dark glass.
static func team_accent(tid: String) -> Color:
	var c := team_color(tid)
	if light:
		# On light panels pick the deeper of the two team colours.
		var c2 := team_color2(tid)
		if c2.get_luminance() < c.get_luminance():
			c = c2
		return c.darkened(0.25) if c.get_luminance() > 0.5 else c
	if c.get_luminance() < 0.25:
		c = team_color2(tid)
	if c.get_luminance() < 0.3:
		c = c.lightened(0.35)
	return c


static func texture_rect(path: String, size: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Team crest image (generated art), falling back to a drawn badge.
static func crest(tid: String, size := 40) -> Control:
	var path := "res://assets/crests/%s.png" % tid.to_lower()
	# The art has the default code on its ribbon; if the user renamed the code,
	# fall back to the drawn badge so it shows their code.
	if tid != "" and ResourceLoader.exists(path) and DB.team_short(tid) == tid:
		return texture_rect(path, Vector2(size, size))
	var c := preload("res://scripts/ui/crest.gd").new()
	c.tid = tid
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func role_icon(role: String, size := 48) -> Control:
	var path := "res://assets/roles/%s.png" % role.to_lower()
	if ResourceLoader.exists(path):
		return texture_rect(path, Vector2(size, size))
	return label(role, 14, GOLD, true)


static func chip(text: String, color: Color, text_color := Color.WHITE, size := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color, 8, 8)
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	var l := label(text, size, text_color, true)
	p.add_child(l)
	return p


static func rating_bar(name: String, value: int, color: Color) -> Control:
	var h := hbox(10)
	var l := caption(name, MUTED, 11)
	l.custom_minimum_size.x = 40
	h.add_child(l)
	var pb := ProgressBar.new()
	pb.max_value = 100
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 8)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("fill", glow(box(color, 4, 0), Color(color, 0.35), 4))
	pb.add_theme_stylebox_override("background", box(ink(0.07), 4, 0))
	h.add_child(pb)
	var v := display(str(value), 22, TEXT)
	v.custom_minimum_size.x = 30
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


static func toast(parent: Node, text: String, color := RED) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", glow(box(Color(GLASS_HI, 0.98), 14, 16, color, 2), Color(color, 0.3), 10))
	var l := label(text, 15, TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.z_index = 100
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	p.top_level = true
	await p.get_tree().process_frame
	if not is_instance_valid(p):
		return
	var vp := p.get_viewport_rect().size
	p.position = Vector2((vp.x - p.size.x) / 2.0, vp.y - p.size.y - 110)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)


## Little pop animation for feedback.
static func pop(c: Control, scale_to := 1.08) -> void:
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(scale_to, scale_to), 0.08)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Light/dark theme toggle for headers.
static func theme_button() -> Button:
	var b := button("", Callable(), "icon", 18)
	b.tooltip_text = "Light / dark theme"
	var icon := preload("res://scripts/ui/theme_icon.gd").new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	b.pressed.connect(func():
		var tree := Engine.get_main_loop() as SceneTree
		tree.root.get_node("Game").toggle_theme())
	return b


## Audio/music toggle for headers.
static func sound_button() -> Button:
	var tree := Engine.get_main_loop() as SceneTree
	var sfx = tree.root.get_node_or_null("Sfx")
	var b := button("", Callable(), "icon", 18)
	b.tooltip_text = "Music on/off"
	var icon := preload("res://scripts/ui/sound_icon.gd").new()
	icon.on = sfx == null or sfx.music_on
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	b.pressed.connect(func():
		if sfx == null:
			return
		sfx.set_music(not sfx.music_on)
		icon.on = sfx.music_on
		icon.queue_redraw())
	return b

extends Control
## Root of the app: owns the theme, the floodlit stadium backdrop and the active
## screen, and follows the room status (lobby, auction, review, results).

const SCREENS := {
	"home": preload("res://scripts/ui/screens/home_screen.gd"),
	"lobby": preload("res://scripts/ui/screens/lobby_screen.gd"),
	"auction": preload("res://scripts/ui/screens/auction_screen.gd"),
	"review": preload("res://scripts/ui/screens/review_screen.gd"),
	"results": preload("res://scripts/ui/screens/results_screen.gd"),
	"roster": preload("res://scripts/ui/screens/roster_screen.gd"),
	"auth": preload("res://scripts/ui/screens/auth_screen.gd"),
}
const MAX_CONTENT_WIDTH := 600.0

var current := ""
var holder: MarginContainer
var screen: Control
var bg_tex: TextureRect
var backdrop: Control


func _ready() -> void:
	_build_backdrop()
	holder = MarginContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_theme_constant_override("margin_left", 16)
	holder.add_theme_constant_override("margin_right", 16)
	holder.add_theme_constant_override("margin_top", 18)
	holder.add_theme_constant_override("margin_bottom", 14)
	add_child(holder)
	Game.screen_requested.connect(show_screen)
	Game.theme_changed.connect(_on_theme_changed)
	show_screen("home")


## Swap palettes: rebuild the theme, the backdrop and the current screen.
func _on_theme_changed() -> void:
	_build_backdrop()
	var name := current
	current = ""
	show_screen(name)


func _build_backdrop() -> void:
	theme = UI.make_theme()
	RenderingServer.set_default_clear_color(UI.BG)
	if backdrop != null:
		backdrop.queue_free()
	backdrop = Control.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	move_child(backdrop, 0)
	var base := ColorRect.new()
	base.color = UI.BG
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(base)
	if ResourceLoader.exists("res://assets/bg.jpg"):
		bg_tex = TextureRect.new()
		bg_tex.texture = load("res://assets/bg.jpg")
		bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.add_child(bg_tex)
	# Gradient wash so text stays readable over the floodlights: dark in the
	# dark theme, a bright daylight wash in the light theme.
	var shade := TextureRect.new()
	var g := Gradient.new()
	var w := Color(UI.BG, 1.0)
	g.set_color(0, Color(w, 0.62 if UI.light else 0.35))
	g.set_color(1, Color(w, 0.97 if UI.light else 0.92))
	g.add_point(0.45, Color(w, 0.88 if UI.light else 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(shade)
	_add_dust()


## Slow drifting specks of floodlight dust for atmosphere.
func _add_dust() -> void:
	var p := CPUParticles2D.new()
	p.amount = 28
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(700, 900)
	p.direction = Vector2(0, -1)
	p.spread = 25
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 6
	p.initial_velocity_max = 18
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = Color(0.85, 0.6, 0.1, 0.18) if UI.light else Color(1.0, 0.85, 0.45, 0.22)
	p.position = Vector2(270, 480)
	backdrop.add_child(p)


func show_screen(name: String) -> void:
	if name == current and screen != null:
		return
	current = name
	if screen != null:
		screen.queue_free()
	screen = SCREENS[name].new()
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(screen)
	screen.modulate.a = 0.0
	screen.position.y += 12
	var tw := create_tween().set_parallel(true)
	tw.tween_property(screen, "modulate:a", 1.0, 0.25)
	if bg_tex:
		# Slight zoom on the stadium between screens for a sense of motion.
		bg_tex.pivot_offset = size / 2.0
		bg_tex.scale = Vector2(1.06, 1.06)
		tw.tween_property(bg_tex, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(_dt: float) -> void:
	# On wide screens (desktop browsers) keep a phone-like centred column.
	var side := int(maxf(16.0, (size.x - MAX_CONTENT_WIDTH) / 2.0))
	if holder.get_theme_constant("margin_left") != side:
		holder.add_theme_constant_override("margin_left", side)
		holder.add_theme_constant_override("margin_right", side)
	var s := Game.store
	if s == null or not is_instance_valid(s):
		if not current in ["home", "roster", "auth"]:
			show_screen("home")
		return
	if s.state.is_empty():
		return
	var st := s.status()
	if st in ["lobby", "auction", "review", "results"] and st != current:
		show_screen(st)

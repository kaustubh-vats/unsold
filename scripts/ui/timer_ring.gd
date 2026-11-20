extends Control
## Circular countdown. Set `fraction` (0..1) and `text` each frame.

var fraction := 1.0
var text := ""


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 7.0
	draw_circle(c, r + 4.0, Color(0, 0, 0, 0.35))
	draw_arc(c, r, 0, TAU, 72, UI.ink(0.08), 9.0, true)
	var col := UI.GREEN
	if fraction < 0.5:
		col = UI.GOLD
	if fraction < 0.25:
		col = UI.RED
	if fraction > 0.0:
		var a0 := -PI / 2.0
		var a1 := a0 + TAU * fraction
		# Soft glow under the progress arc.
		draw_arc(c, r, a0, a1, 72, Color(col, 0.22), 18.0, true)
		draw_arc(c, r, a0, a1, 72, col, 9.0, true)
		draw_circle(c + Vector2(cos(a1), sin(a1)) * r, 6.0, col.lightened(0.3))
	var font := UI.display_font()
	var fs := int(r * 1.05)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w / 2.0, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		col.lightened(0.2) if fraction < 0.25 else UI.TEXT)

extends Control
## Drawn speaker icon: sound waves when on, a slash when muted.

var on := true


func _draw() -> void:
	var c := size / 2.0
	var s := minf(size.x, size.y) / 24.0
	var col := UI.TEXT if on else UI.DIM
	var body := PackedVector2Array([
		c + Vector2(-8, -3) * s, c + Vector2(-4, -3) * s, c + Vector2(1, -8) * s,
		c + Vector2(1, 8) * s, c + Vector2(-4, 3) * s, c + Vector2(-8, 3) * s])
	draw_colored_polygon(body, col)
	if on:
		draw_arc(c + Vector2(1, 0) * s, 4.5 * s, -0.9, 0.9, 12, col, 1.8 * s, true)
		draw_arc(c + Vector2(1, 0) * s, 8.0 * s, -0.9, 0.9, 16, col, 1.8 * s, true)
	else:
		draw_line(c + Vector2(4, -4) * s, c + Vector2(10, 4) * s, UI.RED, 2.0 * s, true)
		draw_line(c + Vector2(10, -4) * s, c + Vector2(4, 4) * s, UI.RED, 2.0 * s, true)

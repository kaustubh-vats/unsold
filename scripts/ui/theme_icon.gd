extends Control
## Drawn theme icon: a sun in light mode, a crescent moon in dark mode.


func _draw() -> void:
	var c := size / 2.0
	var s := minf(size.x, size.y) / 24.0
	var col := UI.TEXT
	if UI.light:
		draw_circle(c, 4.5 * s, col)
		for i in 8:
			var a := TAU * i / 8.0
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * 7.0 * s, c + d * 9.5 * s, col, 1.8 * s, true)
	else:
		# Crescent: a disc with an offset disc of the button colour cut out.
		draw_circle(c, 7.5 * s, col)
		draw_circle(c + Vector2(3.6, -3.0) * s, 6.6 * s, UI.GLASS_HI.blend(UI.ink(0.05)))

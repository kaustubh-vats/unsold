extends Control
## Drawn franchise badge (no official logos): a shield in team colours with the short code.

var tid := ""


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var r := s / 2.0
	var p := UI.team_color(tid)
	var q := UI.team_color2(tid)
	draw_circle(c, r, q)
	draw_circle(c, r * 0.86, p)
	# Diagonal stripe.
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.6, r * 0.35), c + Vector2(r * 0.35, -r * 0.6),
		c + Vector2(r * 0.5, -r * 0.45), c + Vector2(-r * 0.45, r * 0.5)])
	draw_colored_polygon(pts, Color(q, 0.45))
	var font := UI.bold_font()
	var fs := int(s * (0.34 if DB.team_short(tid).length() <= 3 else 0.27))
	var txt := DB.team_short(tid)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lum := p.get_luminance()
	var col := Color("111111") if lum > 0.6 else Color.WHITE
	draw_string(font, Vector2(c.x - w / 2.0, c.y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

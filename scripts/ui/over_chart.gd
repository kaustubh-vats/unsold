class_name OverChart
extends Control
## Runs per over (a "Manhattan") for one or two innings; red dots mark wickets.

var series := []   # [{runs: [int], wkts: [int], color: Color}]


func _init() -> void:
	custom_minimum_size = Vector2(0, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(s: Array) -> OverChart:
	series = s
	queue_redraw()
	return self


func _draw() -> void:
	var n := 20
	var maxr := 12
	for s in series:
		n = maxi(n, (s["runs"] as Array).size())
		for r in s["runs"]:
			maxr = maxi(maxr, int(r))
	var font := UI.regular_font()
	var bottom := 16.0
	var w := size.x
	var h := size.y - bottom
	var slot := w / n
	# Grid every 6 runs.
	var g := 6
	while g <= maxr:
		var y := h - float(g) / maxr * (h - 8)
		draw_line(Vector2(0, y), Vector2(w, y), UI.ink(0.07), 1.0)
		g += 6
	var k := maxi(1, series.size())
	var bw := slot * 0.8 / k
	for si in series.size():
		var s: Dictionary = series[si]
		var runs: Array = s["runs"]
		var wk: Array = s.get("wkts", [])
		for i in runs.size():
			var x := i * slot + slot * 0.1 + si * bw
			var bh := float(runs[i]) / maxr * (h - 8)
			draw_rect(Rect2(x, h - bh, maxf(1.0, bw - 1.0), bh), s["color"])
			var nw := int(wk[i]) if i < wk.size() else 0
			for j in nw:
				draw_circle(Vector2(x + bw / 2.0, h - bh - 5.0 - j * 7.0), 2.8, UI.RED)
	draw_line(Vector2(0, h), Vector2(w, h), UI.ink(0.2), 1.0)
	for o in [1, 5, 10, 15, 20]:
		if o > n:
			continue
		var cx: float = (o - 0.5) * slot
		draw_string(font, Vector2(cx - 10, size.y - 2), str(o), HORIZONTAL_ALIGNMENT_CENTER, 20, 10, UI.MUTED)

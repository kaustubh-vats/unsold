extends SceneTree
## Verifies every non-ASCII glyph used by the UI exists in the bundled fonts.

func _initialize() -> void:
	var reg: FontFile = load("res://assets/fonts/NotoSans-Regular.ttf")
	var bold: FontFile = load("res://assets/fonts/NotoSans-Bold.ttf")
	var sym: FontFile = load("res://assets/fonts/NotoSansSymbols2-Regular.ttf")
	var missing := 0
	for ch in "–—₹▶▾○…★✈✔✕⚠•◀":
		var code := ch.unicode_at(0)
		var in_reg := reg.has_char(code) and bold.has_char(code)
		var in_sym := sym.has_char(code)
		if not in_reg and not in_sym:
			missing += 1
		print("%s U+%04X  noto:%s  symbols2:%s" % [ch, code, in_reg, in_sym])
	print("missing: %d" % missing)
	quit(0)

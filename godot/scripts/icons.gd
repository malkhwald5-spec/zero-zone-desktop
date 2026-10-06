class_name Icons
## Small vector icons drawn with lines and polygons (no emoji fonts needed).
## draw(ci, name, centre, radius, colour) on any CanvasItem's draw callback.

static func _poly(ci: CanvasItem, pts: Array, c: Vector2, r: float, col: Color) -> void:
	var p := PackedVector2Array()
	for v in pts: p.append(c + v * r)
	ci.draw_colored_polygon(p, col)

static func _line(ci: CanvasItem, pts: Array, c: Vector2, r: float, col: Color, w := 2.0) -> void:
	var p := PackedVector2Array()
	for v in pts: p.append(c + v * r)
	ci.draw_polyline(p, col, w, true)

static func draw(ci: CanvasItem, name: String, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(1.5, r * 0.14)
	match name:
		"shirt":      # inventory
			_poly(ci, [Vector2(-0.35, -0.8), Vector2(-1, -0.45), Vector2(-0.75, 0.0), Vector2(-0.5, -0.15), Vector2(-0.5, 0.85), Vector2(0.5, 0.85), Vector2(0.5, -0.15), Vector2(0.75, 0.0), Vector2(1, -0.45), Vector2(0.35, -0.8), Vector2(0, -0.55)], c, r, col)
		"card":       # player card
			ci.draw_rect(Rect2(c + Vector2(-1, -0.7) * r, Vector2(2, 1.4) * r), col, false, w)
			ci.draw_circle(c + Vector2(-0.45, -0.1) * r, r * 0.25, col)
			ci.draw_rect(Rect2(c + Vector2(0.05, -0.3) * r, Vector2(0.7, 0.15) * r), col)
			ci.draw_rect(Rect2(c + Vector2(0.05, 0.05) * r, Vector2(0.55, 0.15) * r), col)
		"wrench":     # workshop
			ci.draw_line(c + Vector2(-0.7, 0.7) * r, c + Vector2(0.25, -0.25) * r, col, w * 1.6)
			ci.draw_arc(c + Vector2(0.45, -0.45) * r, r * 0.38, -0.6, 3.6, 16, col, w * 1.4)
		"trophy":     # season
			_poly(ci, [Vector2(-0.6, -0.8), Vector2(0.6, -0.8), Vector2(0.5, -0.1), Vector2(0, 0.25), Vector2(-0.5, -0.1)], c, r, col)
			ci.draw_arc(c + Vector2(-0.6, -0.45) * r, r * 0.3, PI * 0.5, PI * 1.5, 10, col, w)
			ci.draw_arc(c + Vector2(0.6, -0.45) * r, r * 0.3, -PI * 0.5, PI * 0.5, 10, col, w)
			ci.draw_rect(Rect2(c + Vector2(-0.1, 0.2) * r, Vector2(0.2, 0.4) * r), col)
			ci.draw_rect(Rect2(c + Vector2(-0.45, 0.6) * r, Vector2(0.9, 0.22) * r), col)
		"mail":
			ci.draw_rect(Rect2(c + Vector2(-1, -0.65) * r, Vector2(2, 1.3) * r), col, false, w)
			_line(ci, [Vector2(-1, -0.65), Vector2(0, 0.1), Vector2(1, -0.65)], c, r, col, w)
		"clan":       # shield with a star
			_poly(ci, [Vector2(0, -0.95), Vector2(0.8, -0.6), Vector2(0.7, 0.25), Vector2(0, 0.95), Vector2(-0.7, 0.25), Vector2(-0.8, -0.6)], c, r, col)
			star(ci, c + Vector2(0, -0.05) * r, r * 0.38, Color(0, 0, 0, 0.55))
		"tasks":      # checklist
			for i in 3:
				var y := -0.6 + i * 0.6
				ci.draw_rect(Rect2(c + Vector2(-0.9, y - 0.18) * r, Vector2(0.36, 0.36) * r), col, false, w * 0.8)
				ci.draw_rect(Rect2(c + Vector2(-0.3, y - 0.07) * r, Vector2(1.2, 0.14) * r), col)
		"crate":
			_poly(ci, [Vector2(-0.95, -0.25), Vector2(0.95, -0.25), Vector2(0.85, 0.85), Vector2(-0.85, 0.85)], c, r, col)
			_poly(ci, [Vector2(-1.05, -0.65), Vector2(1.05, -0.65), Vector2(1.05, -0.3), Vector2(-1.05, -0.3)], c, r, col)
			ci.draw_rect(Rect2(c + Vector2(-0.12, -0.65) * r, Vector2(0.24, 1.5) * r), Color(0, 0, 0, 0.35))
		"cart":
			_line(ci, [Vector2(-1, -0.7), Vector2(-0.65, -0.7), Vector2(-0.4, 0.35), Vector2(0.75, 0.35), Vector2(0.95, -0.4), Vector2(-0.55, -0.4)], c, r, col, w)
			ci.draw_circle(c + Vector2(-0.3, 0.7) * r, r * 0.15, col)
			ci.draw_circle(c + Vector2(0.6, 0.7) * r, r * 0.15, col)
		"gear":
			for k in 8:
				var a := k * TAU / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.55, c + Vector2(cos(a), sin(a)) * r * 0.98, col, w * 1.8)
			ci.draw_circle(c, r * 0.62, col)
			ci.draw_circle(c, r * 0.25, Color(0, 0, 0, 0.6))
		"bell":
			_poly(ci, [Vector2(-0.7, 0.45), Vector2(-0.55, -0.3), Vector2(-0.25, -0.7), Vector2(0.25, -0.7), Vector2(0.55, -0.3), Vector2(0.7, 0.45), Vector2(0.9, 0.6), Vector2(-0.9, 0.6)], c, r, col)
			ci.draw_circle(c + Vector2(0, 0.78) * r, r * 0.16, col)
		"friends":
			ci.draw_circle(c + Vector2(-0.35, -0.35) * r, r * 0.28, col)
			_poly(ci, [Vector2(-0.85, 0.7), Vector2(-0.75, 0.05), Vector2(0.05, 0.05), Vector2(0.15, 0.7)], c, r, col)
			ci.draw_circle(c + Vector2(0.45, -0.25) * r, r * 0.24, col.darkened(0.2))
			_poly(ci, [Vector2(0.25, 0.7), Vector2(0.25, 0.1), Vector2(0.9, 0.1), Vector2(0.95, 0.7)], c, r, col.darkened(0.2))
		"home":
			_poly(ci, [Vector2(0, -0.9), Vector2(0.95, -0.05), Vector2(0.7, -0.05), Vector2(0.7, 0.8), Vector2(-0.7, 0.8), Vector2(-0.7, -0.05), Vector2(-0.95, -0.05)], c, r, col)
			ci.draw_rect(Rect2(c + Vector2(-0.18, 0.25) * r, Vector2(0.36, 0.55) * r), Color(0, 0, 0, 0.45))
		"gift":
			ci.draw_rect(Rect2(c + Vector2(-0.85, -0.2) * r, Vector2(1.7, 1.0) * r), col)
			ci.draw_rect(Rect2(c + Vector2(-0.95, -0.5) * r, Vector2(1.9, 0.35) * r), col)
			ci.draw_rect(Rect2(c + Vector2(-0.1, -0.5) * r, Vector2(0.2, 1.3) * r), Color(0, 0, 0, 0.35))
			ci.draw_arc(c + Vector2(-0.3, -0.6) * r, r * 0.25, 0, TAU, 12, col, w)
			ci.draw_arc(c + Vector2(0.3, -0.6) * r, r * 0.25, 0, TAU, 12, col, w)
		"calendar":   # events
			ci.draw_rect(Rect2(c + Vector2(-0.9, -0.65) * r, Vector2(1.8, 1.5) * r), col, false, w)
			ci.draw_rect(Rect2(c + Vector2(-0.9, -0.65) * r, Vector2(1.8, 0.4) * r), col)
			star(ci, c + Vector2(0, 0.3) * r, r * 0.38, col)
		"question":
			ci.draw_arc(c + Vector2(0, -0.3) * r, r * 0.42, PI, TAU + 0.6, 16, col, w * 1.3)
			ci.draw_line(c + Vector2(0.3, 0.0) * r, c + Vector2(0, 0.3) * r, col, w * 1.3)
			ci.draw_circle(c + Vector2(0, 0.7) * r, r * 0.13, col)
		"hand":       # wave emote
			for k in 4:
				var x := -0.45 + k * 0.3
				ci.draw_line(c + Vector2(x, 0.1) * r, c + Vector2(x, -0.75 + absf(k - 1.5) * 0.12) * r, col, w * 1.6)
			ci.draw_line(c + Vector2(-0.6, 0.3) * r, c + Vector2(-0.95, -0.1) * r, col, w * 1.6)
			ci.draw_circle(c + Vector2(0, 0.35) * r, r * 0.5, col)
		"expand":     # fullscreen
			for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				_line(ci, [s * 0.8 + Vector2(-s.x * 0.45, 0), s * 0.8, s * 0.8 + Vector2(0, -s.y * 0.45)], c, r, col, w * 1.2)
		"coin":       # gold
			ci.draw_circle(c, r, Color("e0a42a"))
			ci.draw_circle(c, r * 0.75, Color("ffd34d"))
			ci.draw_string(UiKit.bold(), c + Vector2(-r * 0.42, r * 0.42), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 1.2), Color("8a5a10"))
		"gem":        # ZC
			_poly(ci, [Vector2(-0.9, -0.35), Vector2(-0.45, -0.85), Vector2(0.45, -0.85), Vector2(0.9, -0.35), Vector2(0, 0.95)], c, r, Color("4fc3f7"))
			_poly(ci, [Vector2(-0.45, -0.35), Vector2(0.45, -0.35), Vector2(0, 0.6)], c, r, Color("b3e5fc"))
		"crown":
			_poly(ci, [Vector2(-0.95, 0.6), Vector2(-0.95, -0.55), Vector2(-0.45, -0.05), Vector2(0, -0.8), Vector2(0.45, -0.05), Vector2(0.95, -0.55), Vector2(0.95, 0.6)], c, r, col)
		"globe":
			ci.draw_arc(c, r * 0.9, 0, TAU, 24, col, w)
			ci.draw_line(c + Vector2(-0.9, 0) * r, c + Vector2(0.9, 0) * r, col, w * 0.8)
			ci.draw_arc(c, r * 0.9, -PI * 0.5, PI * 0.5, 16, col, w * 0.8)
			var pts := PackedVector2Array()
			for k in 17:
				var a := -PI * 0.5 + PI * k / 16.0
				pts.append(c + Vector2(cos(a) * 0.4, sin(a) * 0.9) * r)
			ci.draw_polyline(pts, col, w * 0.8)
		"plus":
			ci.draw_line(c + Vector2(-0.7, 0) * r, c + Vector2(0.7, 0) * r, col, w * 1.6)
			ci.draw_line(c + Vector2(0, -0.7) * r, c + Vector2(0, 0.7) * r, col, w * 1.6)

static func star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var p := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		var rr := r if k % 2 == 0 else r * 0.45
		p.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(p, col)

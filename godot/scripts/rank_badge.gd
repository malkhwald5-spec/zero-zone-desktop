class_name RankBadge
extends Control
## A rank emblem drawn in code: a shield in the tier colour with stars for the step,
## wings for Ace and a crown for Conqueror.

var rp := 1000:
	set(v):
		rp = v
		queue_redraw()

func _init(points := 1000, size_px := 64.0) -> void:
	rp = points
	custom_minimum_size = Vector2(size_px, size_px * 1.1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var info: Dictionary = Game.rank_info(rp)
	var col: Color = info.color
	var w := size.x
	var h := size.y
	var c := Vector2(w * 0.5, h * 0.5)
	var tier: int = info.tier
	# Wings behind the shield from Ace up.
	if tier >= 6:
		for s in [-1.0, 1.0]:
			var wing := PackedVector2Array([c + Vector2(s * w * 0.18, -h * 0.18), c + Vector2(s * w * 0.5, -h * 0.3),
				c + Vector2(s * w * 0.42, h * 0.02), c + Vector2(s * w * 0.48, h * 0.08), c + Vector2(s * w * 0.2, h * 0.2)])
			draw_colored_polygon(wing, col.darkened(0.25))
	var sw := w * (0.36 if tier >= 6 else 0.44)
	var shield := PackedVector2Array([
		c + Vector2(-sw, -h * 0.38), c + Vector2(0, -h * 0.47), c + Vector2(sw, -h * 0.38),
		c + Vector2(sw, h * 0.05), c + Vector2(0, h * 0.46), c + Vector2(-sw, h * 0.05)])
	draw_colored_polygon(shield, col.darkened(0.45))
	var inner := PackedVector2Array()
	for p in shield: inner.append(c + (p - c) * 0.8)
	draw_colored_polygon(inner, col)
	var outline := shield.duplicate()
	outline.append(shield[0])
	draw_polyline(outline, col.lightened(0.5), maxf(1.5, w * 0.03), true)
	# Highlight on the upper half.
	draw_colored_polygon(PackedVector2Array([inner[0], inner[1], inner[2], c + Vector2(inner[2].x - c.x, -h * 0.08), c + Vector2(inner[0].x - c.x, -h * 0.08)]), Color(1, 1, 1, 0.18))
	if tier == 7:
		var cr := PackedVector2Array([c + Vector2(-w * 0.2, h * 0.08), c + Vector2(-w * 0.22, -h * 0.16), c + Vector2(-w * 0.1, -h * 0.04),
			c + Vector2(0, -h * 0.22), c + Vector2(w * 0.1, -h * 0.04), c + Vector2(w * 0.22, -h * 0.16), c + Vector2(w * 0.2, h * 0.08)])
		draw_colored_polygon(cr, Color("fff6c8"))
		return
	# Stars: one per tier step reached (1 for Bronze … 6 for Crown, 3 big ones for Ace).
	var n := 3 if tier == 6 else mini(tier + 1, 6)
	var r := w * (0.075 if n > 3 else 0.1)
	for i in n:
		var row := i / 3
		var in_row := mini(3, n - row * 3)
		var x := (float(i % 3) - (in_row - 1) * 0.5) * r * 2.4
		_star(c + Vector2(x, -h * 0.04 + row * r * 2.4), r)

func _star(p: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0
		pts.append(p + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, Color(1, 1, 1, 0.95))

class_name Bot
extends CharacterBody3D
## An AI player. Rides the plane, jumps and parachutes to a landing spot, loots
## a weapon and ammo, fights anyone it sees (the player or other bots), and
## moves into the safe zone in time. Far from the player it thinks less often.

const GRAVITY := 18.0
const TIER := {"p92": 1, "ump": 2, "s1897": 2, "m416": 3, "akm": 3, "kar98": 3}

var world: Node
var display_name := "خصم"
var health := 100.0
var dead := false
var skill := 0.5
var kills := 0
var model: SoldierModel
var shape: CollisionShape3D

var weapon_id := ""          # "" = unarmed (has to loot a gun first)
var mag := 0
var reserve := 0             # spare rounds for the current gun

var state := "plane"         # plane | fall | chute | ground | dead
var dest := Vector3.ZERO     # landing spot
var jump_at := 0.5           # fraction of the plane route where it jumps
var chute_alt := 150.0

var mode := "loot"           # loot | fight | zone | roam | flee
var target: Node3D = null    # enemy being fought
var goal := Vector3.ZERO     # where it is walking
var path: Array = []         # waypoints before the goal (doors, bridges)
var loot_item: Node3D = null
var home := Vector3.ZERO

var fire_cd := 0.0
var reload_t := 0.0
var think_t := 0.0
var react_t := 0.0
var engage_t := 0.0
var burst := 0
var yaw := 0.0
var stuck_t := 0.0
var stuck_n := 0
var last_pos := Vector3.ZERO
var far := false
var hurt_t := 99.0           # seconds since it was last shot
var _frame := 0

func _ready() -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape = CollisionShape3D.new()
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_max_angle = deg_to_rad(50)
	model = SoldierModel.new(Color.from_hsv(randf(), 0.35, 0.45), Color.from_hsv(randf(), 0.6, 0.85), Color.from_hsv(randf(), 0.2, 0.25))
	add_child(model)
	model.set_gear(randi_range(0, 1), randi_range(0, 1), randi_range(0, 1))
	_frame = randi() % 4
	if state == "plane":
		visible = false
		shape.disabled = true
	home = global_position
	goal = global_position

## Things the HUD and player code query.
func on_ground() -> bool:
	return state == "ground"

func armed() -> bool:
	return weapon_id != ""

func take_damage(amount: float, attacker: Node, _head := false) -> bool:
	if dead: return false
	health -= amount
	hurt_t = 0.0
	if attacker is Node3D and attacker != self and state == "ground":
		if target == null or not is_instance_valid(target) or randf() < 0.5:
			target = attacker
			react_t = minf(react_t, 0.25)
		yaw = atan2(-(attacker.global_position.x - global_position.x), -(attacker.global_position.z - global_position.z))
	if health <= 0.0:
		_die(attacker)
		return true
	return false

func _die(attacker: Node) -> void:
	dead = true
	state = "dead"
	collision_layer = 0
	velocity = Vector3.ZERO
	model.set_pose("dead", 0.0, false, 0.016, 0.0)
	world.on_actor_killed(self, attacker)

# ---------------------------------------------------------------- per frame
func _physics_process(delta: float) -> void:
	_frame += 1
	match state:
		"plane":
			global_position = world.plane_position() + Vector3(0, -3, 0)
			if world.plane_t >= jump_at or not world.plane_active:
				_jump()
		"fall", "chute":
			_air(delta)
		"ground":
			_ground(delta)
		"dead":
			if not is_on_floor():
				velocity.y -= GRAVITY * delta
				move_and_slide()
			else:
				set_physics_process(false)

func _jump() -> void:
	state = "fall"
	visible = true
	var to := dest - global_position
	yaw = atan2(-to.x, -to.z)

func _air(delta: float) -> void:
	var alt: float = global_position.y - world.ground_height(global_position)
	var to := dest - global_position
	to.y = 0.0
	var dist := to.length()
	if state == "fall" and alt < chute_alt:
		state = "chute"
	var hs := 30.0 if state == "fall" else 11.0
	var vs := 45.0 if state == "fall" else 6.5
	# Glide only as fast as needed to arrive about when touching down.
	var need := dist / maxf(alt / vs, 0.5)
	var v := to.normalized() * minf(hs, need) if dist > 1.0 else Vector3.ZERO
	global_position += Vector3(v.x, -vs, v.z) * delta
	if dist > 1.0:
		yaw = lerp_angle(yaw, atan2(-to.x, -to.z), minf(1.0, delta * 2.0))
	model.rotation.y = yaw
	if not far or _frame % 4 == 0:
		model.set_pose(state, 0.0, false, delta, world.time)
	if alt <= 0.4:
		_land()

func _land() -> void:
	global_position = world.safe_landing(global_position)
	state = "ground"
	shape.disabled = false
	home = global_position
	goal = global_position
	last_pos = global_position
	think_t = randf_range(0.0, 0.3)

func _ground(delta: float) -> void:
	var player: Node3D = world.player
	var d_player := global_position.distance_to(player.global_position)
	far = d_player > 280.0
	model.visible = d_player < 650.0
	fire_cd = maxf(0.0, fire_cd - delta)
	hurt_t += delta
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			var need: int = Game.WEAPONS[weapon_id].mag - mag
			var take := mini(need, reserve)
			mag += take
			reserve -= take
	think_t -= delta
	if think_t <= 0.0:
		think_t = randf_range(0.8, 1.3) if far else randf_range(0.2, 0.35)
		_think()
	_move(delta)
	_combat(delta)
	model.rotation.y = yaw
	if not far or _frame % 4 == 0:
		model.set_pose("stand", Vector2(velocity.x, velocity.z).length(), armed(), delta, world.time)

# ---------------------------------------------------------------- decisions
func _think() -> void:
	if target and (not is_instance_valid(target) or _is_dead(target) or global_position.distance_to(target.global_position) > 160.0):
		target = null
	var seen := _look_for_enemy()
	if seen:
		if target != seen:
			react_t = randf_range(0.45, 1.0) - skill * 0.3
			engage_t = 0.0
		target = seen
	var zone: Zone = world.zone
	var outside_now: bool = zone.state != "idle" and zone.is_outside(global_position)
	var must_move: bool = zone.state != "idle" and zone.distance_to_safe(global_position) > 0.0 and (zone.state == "shrink" or zone.time_left / zone.speed < zone.distance_to_safe(global_position) / 4.0 + 25.0)
	if target and armed() and not (outside_now and global_position.distance_to(target.global_position) > 35.0):
		mode = "fight"
		return
	# Unarmed: only run when actually under fire, otherwise keep looking for a gun.
	if target and not armed() and hurt_t < 4.0 and _enemy_armed(target):
		if mode != "flee" or global_position.distance_to(goal) < 3.0:
			mode = "flee"
			var away: Vector3 = global_position - target.global_position
			away.y = 0.0
			_go(global_position + away.normalized() * 30.0)
		return
	if must_move or outside_now:
		if mode != "zone" or global_position.distance_to(goal) < 3.0:
			mode = "zone"
			var c := zone.next_center + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * zone.next_radius * 0.5
			_go(Vector3(c.x, 0.0, c.y))
		return
	if _wants_loot():
		if loot_item and (not is_instance_valid(loot_item) or not world.pickups.has(loot_item) or global_position.distance_to(loot_item.global_position) > 90.0):
			loot_item = null
		if loot_item == null:
			loot_item = world.find_pickup(global_position, 70.0 if armed() else 120.0, _useful)
		if loot_item:
			# Keep walking to the item (also after fleeing or a detour).
			if mode != "loot" or goal.distance_to(loot_item.global_position) > 1.0:
				_go(loot_item.global_position)
			mode = "loot"
			if global_position.distance_to(loot_item.global_position) < 1.8:
				world.bot_take(self, loot_item)
				loot_item = null
			return
	if mode != "roam" or global_position.distance_to(goal) < 3.0:
		mode = "roam"
		var a := randf() * TAU
		var p := home + Vector3(cos(a), 0, sin(a)) * randf_range(15.0, 70.0)
		if zone.state != "idle":
			var c2 := zone.next_center
			var to_c := Vector3(c2.x, 0, c2.y) - global_position
			to_c.y = 0.0
			p = global_position + to_c.normalized() * randf_range(10.0, 40.0) + Vector3(cos(a), 0, sin(a)) * 15.0
			if zone.distance_to_safe(p) > 0.0 and zone.distance_to_safe(global_position) == 0.0:
				p = global_position + Vector3(cos(a), 0, sin(a)) * 15.0
		if world.island.is_land(p.x, p.z):
			_go(p)

func _wants_loot() -> bool:
	return not armed() or reserve < 30 or TIER.get(weapon_id, 0) < 3

func _useful(it: Node3D) -> bool:
	var data: Dictionary = it.get_meta("data")
	if data.kind == "weapon":
		return not armed() or TIER.get(data.id, 0) > TIER.get(weapon_id, 0)
	if data.kind == "ammo":
		return armed() and Game.WEAPONS[weapon_id].ammo == data.type and reserve < 90
	return false

func _enemy_armed(e: Node) -> bool:
	if e is Bot: return e.armed()
	if "active" in e: return e.active >= 0
	return true

func _is_dead(n: Node) -> bool:
	return ("dead" in n and n.dead) or ("state" in n and n.state == "dead")

## Nearest enemy (player or bot) that is in view and not behind cover.
func _look_for_enemy() -> Node3D:
	var view := 70.0 + skill * 50.0
	var facing := Vector3(-sin(yaw), 0, -cos(yaw))
	var best: Node3D = null
	var bd := view
	for e in world.actors():
		if e == self or not e.on_ground(): continue
		var to: Vector3 = e.global_position - global_position
		var d := to.length()
		var v := view
		if "stance" in e:
			v *= {"stand": 1.0, "crouch": 0.8, "prone": 0.5}[e.stance]
		if d > v or d > bd: continue
		if facing.dot(to / maxf(d, 0.01)) < 0.3 and d > 10.0: continue
		if _clear_line(e):
			best = e
			bd = d
	return best

func _eye() -> Vector3:
	return global_position + Vector3(0, 1.5, 0)

func _aim_height(e: Node3D) -> float:
	if "capsule" in e and e.capsule: return e.capsule.height
	return 1.8

func _clear_line(e: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_eye(), e.global_position + Vector3(0, _aim_height(e) * 0.7, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# ---------------------------------------------------------------- movement
func _go(p: Vector3) -> void:
	goal = p
	path = world.route(global_position, p)

func _move(delta: float) -> void:
	var wish := Vector3.ZERO
	var speed := 4.6
	if mode == "fight" and target:
		var to_t: Vector3 = target.global_position - global_position
		to_t.y = 0.0
		var d := to_t.length()
		var side := Vector3(cos(yaw), 0, -sin(yaw)) * (1.0 if int((Time.get_ticks_msec() + get_instance_id()) / 1400) % 2 == 0 else -1.0)
		wish = side * 0.6 + to_t.normalized() * (0.6 if d > 45.0 else (-0.3 if d < 12.0 else 0.0))
		speed = 3.2
	else:
		var wp: Vector3 = path[0] if not path.is_empty() else goal
		var to := wp - global_position
		to.y = 0.0
		if to.length() < 1.2 and not path.is_empty():
			path.pop_front()
		elif to.length() > 0.8:
			wish = to.normalized()
			yaw = lerp_angle(yaw, atan2(-wish.x, -wish.z), minf(1.0, delta * 6.0))
		if mode == "zone" or mode == "flee": speed = 5.6
	velocity.x = move_toward(velocity.x, wish.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, 30.0 * delta)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	move_and_slide()
	# Never walk into deep water (bridges are fine).
	if global_position.y < Island.WATER - 0.3 and world.is_deep(global_position):
		global_position = Vector3(before.x, global_position.y, before.z)
		path = world.route(global_position, goal)
	# Stuck on something: hop, then try another way.
	stuck_t += delta
	if stuck_t > 1.0:
		var moved := global_position.distance_to(last_pos)
		if moved < 0.4 and wish.length() > 0.1:
			stuck_n += 1
			if is_on_floor(): velocity.y = 5.0
			if stuck_n >= 3:
				stuck_n = 0
				loot_item = null
				var a := randf() * TAU
				_go(global_position + Vector3(cos(a), 0, sin(a)) * 12.0)
		else:
			stuck_n = 0
		last_pos = global_position
		stuck_t = 0.0

# ---------------------------------------------------------------- combat
func _combat(delta: float) -> void:
	if mode != "fight" or target == null or not is_instance_valid(target): return
	react_t -= delta
	engage_t += delta
	var to_t: Vector3 = target.global_position - global_position
	var want := atan2(-to_t.x, -to_t.z)
	yaw = lerp_angle(yaw, want, minf(1.0, delta * (3.0 + skill * 6.0)))
	if react_t <= 0.0 and absf(angle_difference(yaw, want)) < 0.15:
		_shoot(target)

func _shoot(e: Node3D) -> void:
	if fire_cd > 0.0 or reload_t > 0.0 or not armed(): return
	var w: Dictionary = Game.WEAPONS[weapon_id]
	if mag <= 0:
		if reserve > 0:
			reload_t = w.reload
		return
	mag -= 1
	if burst <= 0:
		burst = randi_range(3, 6) if w.auto else 1
	burst -= 1
	fire_cd = w.rate * randf_range(1.0, 1.6) if burst > 0 else randf_range(0.9, 1.8)
	var origin := _eye()
	var aim: Vector3 = e.global_position + Vector3(0, randf_range(0.35, 0.9) * _aim_height(e), 0)
	var dist := origin.distance_to(aim)
	var settle := clampf(1.6 - engage_t * 0.35, 1.0, 1.6)
	var ev: Vector3 = e.velocity if "velocity" in e else Vector3.ZERO
	var moving := Vector2(ev.x, ev.z).length() > 2.0
	var err := (0.25 + dist * (0.012 + (1.0 - skill) * 0.02)) * settle * (1.4 if moving else 1.0)
	if e == world.player: err *= 1.6   # be fair to the human
	var pellets: int = w.get("pellets", 1)
	var range_m: float = w.range
	for i in pellets:
		var a := aim + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * err * (1.0 if pellets == 1 else 1.8)
		var dir := (a - origin).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * range_m, 1 | 2 | 4)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var end: Vector3 = hit.position if hit else origin + dir * range_m
		if i == 0 and not far:
			world.effects.tracer(origin + Vector3(0, -0.15, 0), end)
		if hit and hit.collider and hit.collider.has_method("take_damage"):
			var head: bool = end.y > hit.collider.global_position.y + _aim_height(hit.collider) * 0.8
			var dmg: float = float(w.dmg) * (0.5 if hit.collider == world.player else 0.8) * (1.8 if head else 1.0)
			if hit.collider.take_damage(dmg, self, head):
				kills += 1
				if target == hit.collider: target = null
		elif hit and not far and i == 0:
			world.effects.impact(end, hit.normal, false)
	if global_position.distance_to(world.player.global_position) < 700.0:
		world.sound_shot(w.cls, global_position, false)
	if mag == 0 and reserve > 0:
		reload_t = w.reload

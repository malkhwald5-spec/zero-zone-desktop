class_name Bot
extends CharacterBody3D
## An AI player. Rides the plane, jumps and parachutes to a landing spot, loots
## a weapon and ammo, fights anyone it sees (the player or other bots), and
## moves into the safe zone in time. Far from the player it thinks less often.

const GRAVITY := 18.0
const TIER := {"p92": 1, "ump": 2, "s1897": 2, "m416": 3, "akm": 3, "mp44": 3, "kar98": 3, "awm": 4, "m249": 4, "groza": 4,
	"uzi": 2, "vector": 2, "scar": 3, "beryl": 3, "sks": 3, "mini14": 3}     # no pan or crossbow for bots

var world: Node
var display_name := "خصم"
var health := 100.0
var dead := false
var skill := 0.5
var kills := 0
var model: HumanModel
var shape: CollisionShape3D

var weapon_id := ""          # "" = unarmed (has to loot a gun first)
var mag := 0
var reserve := 0             # spare rounds for the current gun
var gear := {"vest": 0, "vest_dur": 0.0, "helmet": 0, "helmet_dur": 0.0, "pack": 0}
var meds := 0                # generic healing items
var frags := 0               # frag grenades
var throw_cd := 0.0
var heal_t := 0.0

var state := "plane"         # plane | fall | chute | ground | dead
var dest := Vector3.ZERO     # landing spot
var jump_at := 0.5           # fraction of the plane route where it jumps
var chute_alt := 150.0
var chute_t := 0.0

var mode := "loot"           # loot | fight | cover | flank | alert | zone | roam | flee | heal
var cover_t := 0.0           # seconds spent at the current cover / flank move
var unseen_t := 0.0          # seconds the target has been out of sight in a fight
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
var _pose_dt := 0.0
var hurt_t := 99.0           # seconds since it was last shot
var blind_t := 0.0           # seconds left blinded by a flashbang
var team := 0                # same team = no friendly fire, revive each other
var slot := 0                # number in its team (colour)
var buddy := false           # your teammate: drops with you, follows you
var knocked := false         # down in a team match: crawls and bleeds out
var knocked_by: Node = null
var revive_mate: Node3D = null   # knocked teammate this bot is picking up
var revive_t := 0.0
var _buddy_off := Vector3.ZERO
var _buddy_jump_t := -1.0
var _last_pp := Vector3.ZERO     # your position last frame (to match your speed in the air)
var _face := 0.0             # quick turn towards a shot or a hit
var _face_t := 0.0

## Turn round quickly but not in one frame (a hit, a heard shot).
func _turn_to(y: float) -> void:
	_face = y
	_face_t = 0.5
var _frame := 0
var _step_dist := 0.0
var _far_dt := 0.0

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
	model = HumanModel.new(Color.from_hsv(randf(), 0.35, 0.45), Color.from_hsv(randf(), 0.6, 0.85), Color.from_hsv(randf(), 0.2, 0.25))
	add_child(model)
	model.set_gear(0, 0, 0)
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

func take_damage(amount: float, attacker: Node, head := false) -> bool:
	if dead: return false
	if attacker != null and attacker != self and world.same_team(self, attacker): return false   # no friendly fire
	if attacker != null and not knocked:
		var kind := "helmet" if head else "vest"
		var lvl: int = gear[kind]
		if lvl > 0:
			var absorbed: float = amount * (Items.HELMET if head else Items.VEST)[lvl].reduce
			gear[kind + "_dur"] = float(gear[kind + "_dur"]) - amount
			if gear[kind + "_dur"] <= 0.0:
				gear[kind] = 0
				model.set_gear(gear.vest, gear.helmet, gear.pack)
			amount -= absorbed
	heal_t = 0.0
	if attacker != null and attacker == world.player: world.player.dmg_dealt += minf(amount, maxf(health, 0.0))
	health -= amount
	hurt_t = 0.0
	if model.visible: model.hit(amount / 40.0)
	if attacker is Node3D and attacker != self and state == "ground":
		if target == null or not is_instance_valid(target) or randf() < 0.5:
			target = attacker
			react_t = minf(react_t, 0.25)
		_turn_to(atan2(-(attacker.global_position.x - global_position.x), -(attacker.global_position.z - global_position.z)))
	if health <= 0.0 and not knocked and world.can_knock(self):
		_knock(attacker)
		return false
	if health <= 0.0:
		_die(attacker if attacker != null or not knocked else knocked_by)
		return true
	return false

## Down in a team match: drops the fight, crawls to its team, bleeds out.
func _knock(attacker: Node) -> void:
	knocked = true
	knocked_by = attacker
	health = 100.0
	target = null
	reload_t = 0.0
	heal_t = 0.0
	revive_mate = null
	mode = "knocked"
	world.on_actor_knocked(self, attacker)

func revive_done() -> void:
	if not knocked or dead: return
	knocked = false
	health = 25.0
	hurt_t = 0.0
	mode = "roam"

var bled := false            # died of bleeding / team wiped (the knocker gets the kill)

func bleed_out() -> void:
	if dead: return
	bled = true
	_die(knocked_by)

func _die(attacker: Node) -> void:
	knocked = false
	dead = true
	state = "dead"
	collision_layer = 0
	if Vector2(velocity.x, velocity.z).length() > 3.0: model.death_anim = "death_walk"
	velocity = Vector3.ZERO
	model.set_pose("dead", 0.0, false, 0.016, 0.0)
	world.on_actor_killed(self, attacker)

# ---------------------------------------------------------------- per frame
func _physics_process(delta: float) -> void:
	_frame += 1
	match state:
		"plane":
			global_position = world.plane_position() + Vector3(0, -3, 0)
			if buddy:
				# Your teammates jump right after you.
				if world.player.state != "plane":
					if _buddy_jump_t < 0.0: _buddy_jump_t = 0.4 + slot * 0.35
					_buddy_jump_t -= delta
					if _buddy_jump_t <= 0.0:
						_buddy_off = Vector3(cos(slot * 2.1), 0, sin(slot * 2.1)) * (6.0 + slot * 3.0)
						_jump()
				elif not world.plane_active:
					_jump()
			elif world.plane_t >= jump_at or not world.plane_active:
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
	if buddy and world.player.state in ["fall", "chute", "ground"]:
		# Follow you down and land next to you.
		var pp: Vector3 = world.player.global_position + _buddy_off
		dest = Vector3(pp.x, world.ground_height(pp), pp.z)
	var alt: float = global_position.y - world.ground_height(global_position)
	var to := dest - global_position
	to.y = 0.0
	var dist := to.length()
	if state == "fall" and alt < chute_alt:
		state = "chute"
		chute_t = 0.0
	if state == "chute":
		chute_t += delta
		model.chute_open = clampf(chute_t / 1.6, 0.0, 1.0)
	else:
		model.dive = 0.8
	var hs := (30.0 if state == "fall" else 11.0) * (1.6 if buddy else 1.0)   # teammates keep up with you
	var vs := 45.0 if state == "fall" else 6.5
	if buddy and world.player.state in ["fall", "chute"]:
		# Stay with you all the way down: as fast as you dive or glide, at
		# about your height, and the canopy opens when yours does.
		var ppos: Vector3 = world.player.global_position
		var pv := (ppos - _last_pp) / maxf(delta, 0.001) if _last_pp != Vector3.ZERO else Vector3.ZERO
		_last_pp = ppos
		hs = maxf(hs, Vector2(pv.x, pv.z).length() * 1.3 + 6.0)
		vs = clampf(-pv.y + (global_position.y - ppos.y - 4.0) * 0.8, 2.0, 95.0)
		if world.player.state == "chute" and state == "fall":
			state = "chute"
			chute_t = 0.0
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
	if state == "chute" and not far:
		world.drop_canopy(model, Vector3(-sin(yaw), 0, -cos(yaw)) * 8.0)
	global_position = world.safe_landing(global_position)
	state = "ground"
	shape.disabled = false
	home = global_position
	goal = global_position
	last_pos = global_position
	think_t = randf_range(0.0, 0.3)

func _ground(delta: float) -> void:
	var d_player := global_position.distance_to(world.view_position())
	far = d_player > 280.0 * Game.view_k()
	model.visible = d_player < 650.0 * Game.view_k()
	fire_cd = maxf(0.0, fire_cd - delta)
	hurt_t += delta
	if knocked:
		health -= delta * 100.0 / 45.0
		if health <= 0.0:
			bleed_out()
			return
	_tick_revive(delta)
	throw_cd = maxf(0.0, throw_cd - delta)
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
	# Away from the player and not fighting: move every other frame in double
	# steps (100 players cost a lot of physics otherwise).
	if d_player > 120.0 and target == null:
		_far_dt += delta
		if (_frame + get_instance_id()) % 2 == 0:
			_move(_far_dt)
			_far_dt = 0.0
	else:
		_far_dt = 0.0
		_move(delta)
	_combat(delta)
	if _face_t > 0.0:
		_face_t -= delta
		yaw = lerp_angle(yaw, _face, minf(1.0, delta * 9.0))
	model.rotation.y = lerp_angle(model.rotation.y, yaw, minf(1.0, delta * 14.0))
	# Animation level of detail: every frame up close, less often further away.
	var every := 1 if d_player < 35.0 else (2 if d_player < 90.0 else (3 if d_player < 180.0 else 5))
	_pose_dt += delta
	if _frame % every == 0 and model.visible:
		var sp := Vector2(velocity.x, velocity.z).length()
		model.move_local = Vector2(velocity.dot(Vector3(cos(yaw), 0, -sin(yaw))), velocity.dot(Vector3(-sin(yaw), 0, -cos(yaw))))
		var t: Node3D = target if is_instance_valid(target) else null
		model.aiming = t != null and mode == "fight"
		model.sprinting = sp > 5.0 and not model.aiming
		model.aim_pitch = 0.0
		if model.aiming:
			var to := t.global_position - global_position
			model.aim_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.8, 0.8)
		model.reload_p = 1.0 - reload_t / float(Game.WEAPONS[weapon_id].reload) if reload_t > 0.0 and armed() else -1.0
		# Down low behind cover (reloading, healing) and while patching up.
		var low := (mode == "cover" and global_position.distance_to(goal) < 1.8) or mode == "heal" or revive_mate != null
		model.downed = knocked
		model.reviving = revive_mate != null and is_instance_valid(revive_mate) and global_position.distance_to(revive_mate.global_position) < 2.2
		model.foot_ik = model.visible and is_on_floor() and global_position.distance_squared_to(world.view_position()) < 3600.0
		model.set_pose("prone" if knocked else ("crouch" if low else "stand"), Vector2(velocity.x, velocity.z).length(), armed() and not knocked, _pose_dt, world.time)
		_pose_dt = 0.0

# ---------------------------------------------------------------- decisions
func _think() -> void:
	if knocked:
		# Crawl to the nearest teammate still standing.
		var best: Node3D = null
		for m in world.teammates(self):
			if not world.is_gone(m) and not world.is_down(m) and (best == null or m.global_position.distance_to(global_position) < best.global_position.distance_to(global_position)):
				best = m
		if best and best.global_position.distance_to(global_position) > 1.5:
			_go(best.global_position)
		else:
			goal = global_position
			path = []
		return
	if _team_think():
		return
	# Standing in a molotov's fire: get out first.
	var burn: Vector3 = world.fire_at(global_position, 0.8)
	if burn != Vector3.INF:
		var away := global_position - burn
		away.y = 0.0
		if away.length() < 0.1: away = Vector3(1, 0, 0)
		mode = "flee"
		_go(burn + away.normalized() * (world.FIRE_RADIUS + 4.0))
		return
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
		if _tactics(seen != null):
			return
		mode = "fight"
		_maybe_throw()
		return
	# Unarmed: only run when actually under fire, otherwise keep looking for a gun.
	if target and not armed() and hurt_t < 4.0 and _enemy_armed(target):
		if mode != "flee" or global_position.distance_to(goal) < 3.0:
			mode = "flee"
			var away: Vector3 = global_position - target.global_position
			away.y = 0.0
			_go(global_position + away.normalized() * 30.0)
		return
	# Patch up when hurt and nobody is shooting.
	if health < 65.0 and meds > 0 and hurt_t > 5.0 and not outside_now:
		mode = "heal"
		heal_t += 0.3 if not far else 1.0
		if heal_t >= 5.0:
			meds -= 1
			health = minf(100.0, health + 45.0)
			heal_t = 0.0
		return
	if must_move or outside_now:
		if mode != "zone" or global_position.distance_to(goal) < 3.0:
			mode = "zone"
			var c := zone.next_center + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * zone.next_radius * 0.5
			_go(Vector3(c.x, 0.0, c.y))
		return
	if mode == "alert" and global_position.distance_to(goal) > 3.0:
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
			# Flat distance: items on top of a supply crate sit a metre up and the
			# crate itself stops the bot about a metre from them.
			var to_item: Vector3 = loot_item.global_position - global_position
			if Vector2(to_item.x, to_item.z).length() < 2.2 and absf(to_item.y) < 2.0:
				world.bot_take(self, loot_item)
				loot_item = null
			return
	# A supply crate nearby: go and take its loot.
	var ad: Node3D = world.nearest_airdrop(global_position, 260.0 if armed() else 0.0, _useful)
	if ad:
		if mode != "crate" or goal.distance_to(ad.global_position) > 2.0:
			mode = "crate"
			_go(ad.global_position + Vector3(1.2, 0, 0))
		if global_position.distance_to(ad.global_position) < 2.5:
			for it in world.pickups_near(ad.global_position + Vector3(0, 0.95, 0), 1.5):
				if _useful(it): world.bot_take(self, it)
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
	return not armed() or reserve < 30 or TIER.get(weapon_id, 0) < 3 or gear.vest < 3 or gear.helmet < 3 or meds < 3

func _useful(it: Node3D) -> bool:
	if buddy and world.player.state != "dead" and it.global_position.distance_to(world.player.global_position) > 40.0: return false
	var data: Dictionary = it.get_meta("data")
	# Bots do not climb stairs: skip loot on upper floors.
	var ip := it.global_position
	if ip.y - world.island.height_at(ip.x, ip.z) > 2.5:
		return false
	if data.kind == "weapon":
		if not TIER.has(data.id): return false
		return not armed() or TIER.get(data.id, 0) > TIER.get(weapon_id, 0)
	if data.kind == "ammo":
		return armed() and Game.WEAPONS[weapon_id].ammo == data.type and reserve < 90
	if data.kind == "gear":
		return int(data.lvl) > int(gear[data.gear])
	if data.kind == "heal":
		return meds < 4
	if data.kind == "throw":
		return data.id == "frag" and frags < 2
	return false

func _enemy_armed(e: Node) -> bool:
	if e is Bot: return e.armed()
	if "active" in e: return e.active >= 0
	return true

func _is_dead(n: Node) -> bool:
	return ("dead" in n and n.dead) or ("state" in n and n.state == "dead")

## Nearest enemy (player or bot) that is in view and not behind cover.
func _look_for_enemy() -> Node3D:
	if blind_t > 0.0 or knocked: return null
	var view := (70.0 + skill * 50.0) * (0.75 if world.weather == "rain" else 1.0)
	var facing := Vector3(-sin(yaw), 0, -cos(yaw))
	var best: Node3D = null
	var bd := view
	for e in world.actors():
		if e == self or not e.on_ground() or world.same_team(self, e): continue
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
	var to := e.global_position + Vector3(0, _aim_height(e) * 0.7, 0)
	if world.smoke_blocks(_eye(), to): return false
	var q := PhysicsRayQueryParameters3D.create(_eye(), to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Fighting smarter than standing in the open: run to cover when hit, low on
## health or reloading (heal and reload there, then peek out again), and go
## round the side when the enemy hides. True while busy with that.
func _tactics(can_see: bool) -> bool:
	var tpos: Vector3 = target.global_position
	var d := global_position.distance_to(tpos)
	unseen_t = 0.0 if can_see else unseen_t + 0.3
	if mode == "cover":
		cover_t += 0.3
		var there := global_position.distance_to(goal) < 1.6
		if there:
			if mag < Game.WEAPONS[weapon_id].mag and reserve > 0 and reload_t <= 0.0:
				reload_t = Game.WEAPONS[weapon_id].reload
			if health < 75.0 and meds > 0:
				heal_t += 0.3
				if heal_t >= 4.0:
					meds -= 1
					health = minf(100.0, health + 45.0)
					heal_t = 0.0
		var done := reload_t <= 0.0 and (health >= 75.0 or meds <= 0)
		if (there and done and cover_t > 1.5) or cover_t > 9.0:
			mode = "fight"
			cover_t = 0.0
			return false
		return true
	if mode == "flank":
		cover_t += 0.3
		if can_see or cover_t > 7.0 or global_position.distance_to(goal) < 2.0:
			mode = "fight"
			cover_t = 0.0
			return false
		return true
	# Hit and hurting, out of bullets, or badly hurt: get behind something.
	var need := (hurt_t < 0.8 and health < 70.0) or (mag <= 0 and reserve > 0 and d < 70.0) or (health < 40.0 and hurt_t < 3.0)
	if need and randf() < 0.55 + skill * 0.4:
		var spot: Vector3 = world.find_cover(global_position, tpos, 28.0)
		if spot != Vector3.INF:
			mode = "cover"
			cover_t = 0.0
			heal_t = 0.0
			_go(spot)
			return true
	# The enemy went behind cover: come round the side.
	if unseen_t > 3.0 and d < 80.0 and randf() < 0.3 + skill * 0.5:
		var to := tpos - global_position
		to.y = 0.0
		var side := Vector3(-to.z, 0, to.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
		var p := tpos - to.normalized() * minf(d * 0.6, 25.0) + side * randf_range(14.0, 22.0)
		if world.island.is_land(p.x, p.z):
			mode = "flank"
			cover_t = 0.0
			_go(p)
			return true
	return false

## Heard a shot: look that way and, if idle, go and see (stopping short).
func hear(pos: Vector3, shooter: Node) -> void:
	if knocked or target != null or mode in ["fight", "cover", "flank", "zone", "flee", "revive"]: return
	if world.same_team(self, shooter): return
	if randf() > 0.4 + skill * 0.5: return
	var to := pos - global_position
	to.y = 0.0
	_turn_to(atan2(-to.x, -to.z))
	if armed() and to.length() > 25.0:
		mode = "alert"
		_go(global_position + to * (1.0 - 22.0 / to.length()))
	if shooter is Node3D and _clear_line(shooter):
		target = shooter
		react_t = randf_range(0.5, 1.1) - skill * 0.3

# ---------------------------------------------------------------- team play
## Team decisions before the usual ones: pick up a knocked teammate when no
## enemy is on us, and (your teammates) stay with you. True when busy.
func _team_think() -> bool:
	if world.team_size <= 1: return false
	var engaged: bool = target != null and is_instance_valid(target) and hurt_t < 3.0
	# A knocked teammate nearby: go and pick them up.
	if not engaged:
		var best: Node3D = null
		var bd := 80.0
		for m in world.teammates(self):
			if world.is_down(m) and not world.is_gone(m):
				var d: float = m.global_position.distance_to(global_position)
				if d < bd:
					bd = d
					best = m
		if best:
			mode = "revive"
			target = null
			if bd > 1.6:
				revive_mate = null
				if goal.distance_to(best.global_position) > 1.0: _go(best.global_position)
			else:
				goal = global_position
				path = []
				if revive_mate != best:
					revive_mate = best
					revive_t = 0.0
			return true
	revive_mate = null
	if not buddy or world.player.state == "dead": return false
	var pp: Vector3 = world.player.global_position
	var d_me := global_position.distance_to(pp)
	# Left far behind (you drove off): catch up out of sight.
	var behind_cam: bool = world.player.camera.global_basis.z.dot(global_position - pp) > 0.0
	if (d_me > 160.0 or (d_me > 80.0 and behind_cam)) and world.player.state in ["ground", "vehicle"]:
		var cz: Vector3 = world.player.camera.global_basis.z
		var behind: Vector3 = pp + Vector3(cz.x, 0, cz.z).normalized() * 25.0 + _buddy_off
		var g: float = world.ground_height(behind)
		if not world.is_deep(behind):
			global_position = Vector3(behind.x, g + 0.3, behind.z)
			reset_physics_interpolation()
			path = []
			goal = global_position
			return true
	if engaged and armed(): return false
	home = pp
	# Too far from you: come back (looting only near you).
	if d_me > 35.0 or (d_me > 14.0 and mode == "follow"):
		mode = "follow"
		var want := pp + _buddy_off
		if goal.distance_to(want) > 4.0: _go(want)
		return true
	return false

## Kneeling by a knocked teammate: six seconds to get them up.
func _tick_revive(delta: float) -> void:
	if revive_mate == null: return
	if not is_instance_valid(revive_mate) or not world.is_down(revive_mate) or world.is_gone(revive_mate) or knocked \
			or revive_mate.global_position.distance_to(global_position) > 2.2:
		revive_mate = null
		revive_t = 0.0
		return
	revive_t += delta
	var to: Vector3 = revive_mate.global_position - global_position
	yaw = lerp_angle(yaw, atan2(-to.x, -to.z), minf(1.0, delta * 6.0))
	if revive_mate == world.player: world.player.revived_by_t = revive_t / Player.REVIVE_TIME
	if revive_t >= Player.REVIVE_TIME:
		var m := revive_mate
		revive_mate = null
		revive_t = 0.0
		m.revive_done()

# ---------------------------------------------------------------- movement
func _go(p: Vector3) -> void:
	goal = p
	path = world.route(global_position, p)

func _move(delta: float) -> void:
	var g: float = world.ground_height(global_position)
	if global_position.y < g - 0.8 and not world.is_deep(global_position):
		global_position.y = g + 0.1
		velocity.y = 0.0
	var wish := Vector3.ZERO
	var speed := 4.6
	if mode == "heal":
		pass
	elif mode == "fight" and target:
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
		# The foot of a staircase has to be reached properly, not cut past.
		var near := 0.45 if path.size() > 1 and path[1].y - wp.y > 2.0 else 1.2
		if to.length() < near and not path.is_empty():
			path.pop_front()
		elif to.length() > minf(0.8, near * 0.5):
			wish = to.normalized()
			yaw = lerp_angle(yaw, atan2(-wish.x, -wish.z), minf(1.0, delta * 6.0))
		if mode in ["zone", "flee", "cover", "flank", "revive"]: speed = 5.8
		elif mode == "alert": speed = 3.6
		elif mode == "follow": speed = 5.6 if global_position.distance_to(goal) > 12.0 else 3.8
		if knocked: speed = 0.9
		if revive_mate != null: speed = 0.0
	velocity.x = move_toward(velocity.x, wish.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, 30.0 * delta)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	# move_and_slide() always steps one physics frame; scale for longer steps.
	var k := delta / maxf(get_physics_process_delta_time(), 0.0001)
	if k > 1.01:
		velocity *= k
		move_and_slide()
		velocity /= k
	else:
		move_and_slide()
	if is_on_floor():
		var sp := Vector2(velocity.x, velocity.z).length()
		_step_dist += sp * delta
		if _step_dist > (1.9 if sp > 5.0 else 1.35):
			_step_dist = 0.0
			world.footstep(global_position, false, 0.9 if sp > 5.0 else 0.5)
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
	if knocked or revive_mate != null: return
	if blind_t > 0.0:
		blind_t -= delta
		return
	if mode != "fight" or target == null or not is_instance_valid(target): return
	react_t -= delta
	engage_t += delta
	var to_t: Vector3 = target.global_position - global_position
	var want := atan2(-to_t.x, -to_t.z)
	yaw = lerp_angle(yaw, want, minf(1.0, delta * (3.0 + skill * 6.0)))
	if react_t <= 0.0 and absf(angle_difference(yaw, want)) < 0.15:
		_shoot(target)

## Throw a frag at an enemy hiding behind cover (or now and then in a fight).
func _maybe_throw() -> void:
	if frags <= 0 or throw_cd > 0.0 or target == null: return
	var d := global_position.distance_to(target.global_position)
	if d < 10.0 or d > 32.0: return
	if _clear_line(target) and randf() > 0.12: return
	var from := _eye()
	var v := Grenade.aim_velocity(from, target.global_position + Vector3(0, 0.3, 0))
	if v == Vector3.ZERO: return
	frags -= 1
	throw_cd = randf_range(8.0, 14.0)
	var g := Grenade.new()
	g.world = world
	g.kind = "frag"
	g.thrower = self
	world.add_child(g)
	if not far: model.play_action("toss", 1.1)
	g.global_position = from
	g.linear_velocity = v

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
		if i == 0 and hit.get("collider") != world.player and world.player.state != "dead":
			# Bullet passing within a few metres of the player's head: whizz.
			var head: Vector3 = world.player.global_position + Vector3(0, 1.5, 0)
			var close := Geometry3D.get_closest_point_to_segment(head, origin, end)
			if close.distance_to(head) < 3.0 and close.distance_to(origin) > 8.0:
				world.sound_flyby(close)
		if i == 0 and not far:
			model.recoil = 1.0
			world.effects.tracer(model.muzzle_position() if model.visible and model.weapon_node else origin + Vector3(0, -0.15, 0), end)
		if hit and hit.collider and hit.collider.has_method("take_damage"):
			var head: bool = end.y > hit.collider.global_position.y + _aim_height(hit.collider) * 0.8
			var dmg: float = float(w.dmg) * (0.5 if hit.collider == world.player else 0.8) * (1.8 if head else 1.0)
			if hit.collider.take_damage(dmg, self, head):
				kills += 1
				if target == hit.collider: target = null
		elif hit and not far and i == 0:
			world.effects.impact(end, hit.normal, false)
	if global_position.distance_to(world.view_position()) < 700.0:
		world.sound_shot(w.cls, global_position, false)
	world.notify_shot(global_position, self)
	if mag == 0 and reserve > 0:
		reload_t = w.reload

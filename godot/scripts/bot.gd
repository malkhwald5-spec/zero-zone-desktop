class_name Bot
extends CharacterBody3D
## A basic opponent for the first Godot milestone: patrols around its town and
## shoots at the player when it can see them. (Full BR AI comes next.)

const GRAVITY := 18.0

var world: Node
var display_name := "خصم"
var health := 100.0
var dead := false
var skill := 0.5
var model: SoldierModel
var weapon_id := "m416"
var mag := 30
var fire_cd := 0.0
var reload_t := 0.0
var target_pos := Vector3.ZERO
var home := Vector3.ZERO
var think_t := 0.0
var sees_player := false
var react_t := 0.0
var yaw := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var burst := 0                 # shots left in the current burst
var engage_t := 0.0            # seconds since the bot spotted the player (aim settles)

func _ready() -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	model = SoldierModel.new(Color.from_hsv(randf(), 0.35, 0.45))
	add_child(model)
	model.set_weapon(Game.WEAPONS[weapon_id].cls)
	model.set_gear(randi_range(0, 2), randi_range(0, 2), randi_range(0, 2))
	home = global_position
	target_pos = global_position

func take_damage(amount: float, attacker: Node) -> bool:
	if dead: return false
	health -= amount
	react_t = minf(react_t, 0.3)
	if attacker is Node3D:
		yaw = atan2(-(attacker.global_position.x - global_position.x), -(attacker.global_position.z - global_position.z))
	if health <= 0.0:
		dead = true
		collision_layer = 0
		world.on_bot_killed(self, attacker)
		return true
	return false

func _physics_process(delta: float) -> void:
	if dead:
		model.set_pose("dead", 0.0, false, delta, 0.0)
		return
	var player: Player = world.player
	think_t -= delta
	fire_cd = maxf(0.0, fire_cd - delta)
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0: mag = Game.WEAPONS[weapon_id].mag
	if think_t <= 0.0:
		think_t = randf_range(0.2, 0.35)
		_think(player)
	var to_target := target_pos - global_position
	to_target.y = 0
	var wish := Vector3.ZERO
	if sees_player:
		var d := global_position.distance_to(player.global_position)
		var side := Vector3(cos(yaw), 0, -sin(yaw)) * (1.0 if int(Time.get_ticks_msec() / 1500) % 2 == 0 else -1.0)
		wish = side * 0.6 + (to_target.normalized() * (0.6 if d > 40.0 else -0.3))
	elif to_target.length() > 1.5:
		wish = to_target.normalized()
		yaw = lerp_angle(yaw, atan2(-wish.x, -wish.z), minf(1.0, delta * 5.0))
	var speed := 4.2 if not sees_player else 3.2
	velocity.x = move_toward(velocity.x, wish.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, 30.0 * delta)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if world.is_deep(global_position):
		target_pos = home
	# Stuck on a wall: pick a new patrol point.
	stuck_t += delta
	if stuck_t > 1.0:
		if global_position.distance_to(last_pos) < 0.5 and not sees_player:
			_new_patrol()
		last_pos = global_position
		stuck_t = 0.0
	if sees_player:
		react_t -= delta
		engage_t += delta
		var to_p := player.global_position - global_position
		var want := atan2(-to_p.x, -to_p.z)
		yaw = lerp_angle(yaw, want, minf(1.0, delta * (3.0 + skill * 6.0)))
		if react_t <= 0.0 and absf(angle_difference(yaw, want)) < 0.15:
			_shoot(player)
	model.rotation.y = yaw
	model.set_pose("stand", Vector2(velocity.x, velocity.z).length(), true, delta, 0.0)

func _new_patrol() -> void:
	var a := randf() * TAU
	var r := randf_range(10.0, 60.0)
	var p := home + Vector3(cos(a) * r, 0, sin(a) * r)
	if world.island.is_land(p.x, p.z):
		target_pos = p

func _think(player: Player) -> void:
	var was := sees_player
	sees_player = false
	if player.state == "ground":
		var to_p := player.global_position - global_position
		var d := to_p.length()
		var view := 70.0 + skill * 40.0
		if player.stance == "crouch": view *= 0.8
		elif player.stance == "prone": view *= 0.5
		var facing := Vector3(-sin(yaw), 0, -cos(yaw))
		var in_cone := facing.dot(to_p.normalized()) > 0.4 or d < 8.0
		if d < view and in_cone and _clear_line(player):
			sees_player = true
			target_pos = player.global_position
	if sees_player and not was:
		react_t = randf_range(0.5, 1.1) - skill * 0.3
		engage_t = 0.0
	if not sees_player and global_position.distance_to(target_pos) < 2.0:
		_new_patrol()

func _eye() -> Vector3:
	return global_position + Vector3(0, 1.5, 0)

func _clear_line(player: Player) -> bool:
	var top: float = player.capsule.height if player.capsule else 1.8
	var q := PhysicsRayQueryParameters3D.create(_eye(), player.global_position + Vector3(0, top * 0.7, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _shoot(player: Player) -> void:
	if fire_cd > 0.0 or reload_t > 0.0: return
	if mag <= 0:
		reload_t = Game.WEAPONS[weapon_id].reload
		return
	var w: Dictionary = Game.WEAPONS[weapon_id]
	mag -= 1
	# Short bursts with pauses, like a person, instead of a laser beam.
	if burst <= 0:
		burst = randi_range(3, 6) if w.auto else 1
	burst -= 1
	fire_cd = w.rate * randf_range(1.0, 1.6) if burst > 0 else randf_range(0.9, 1.8)
	var origin := _eye()
	var top: float = player.capsule.height if player.capsule else 1.8
	var aim := player.global_position + Vector3(0, randf_range(0.35, 0.9) * top, 0)
	# Miss distance grows with range, drops with skill, and the first shots after
	# spotting you are the least accurate; moving targets are harder to hit.
	var dist := origin.distance_to(aim)
	var settle := clampf(1.6 - engage_t * 0.35, 1.0, 1.6)
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 2.0
	var err := (0.3 + dist * (0.03 + (1.0 - skill) * 0.04)) * settle * (1.4 if moving else 1.0)
	aim += Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * err
	var q := PhysicsRayQueryParameters3D.create(origin, origin + (aim - origin).normalized() * float(w.range), 1 | 2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit.position if hit else origin + (aim - origin).normalized() * float(w.range)
	world.effects.tracer(origin + Vector3(0, -0.15, 0), end)
	world.sound_shot(w.cls, global_position, false)
	if hit and hit.collider == player:
		player.take_damage(float(w.dmg) * 0.5, self)
	elif hit:
		world.effects.impact(end, hit.normal, false)

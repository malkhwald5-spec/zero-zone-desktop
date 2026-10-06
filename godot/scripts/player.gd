class_name Player
extends CharacterBody3D
## The player: third-person movement, stances, skydiving, shooting and inventory.

signal hit_confirmed(headshot: bool, killed: bool, pos: Vector3)
signal damaged(from_dir: Vector3)
signal died(killer_name: String)
signal message(text: String)

const GRAVITY := 18.0
const PLANE_ALT := 600.0
const CHUTE_AUTO := 140.0
# Skydive speeds in m/s (PUBG-like: 126 km/h belly-down, up to 234 km/h diving).
const FALL_V := 35.0
const DIVE_V := 65.0
const GLIDE_H := 30.0
const CHUTE_OPEN_TIME := 1.6

var world: Node
var state := "plane"          # plane | fall | chute | ground | vehicle | dead
var vehicle: Vehicle = null
var stance := "stand"         # stand | crouch | prone
var health := 100.0
var kills := 0
var display_name := "لاعب"

# Look / camera
var yaw := 0.0
var pitch := -0.15
var aiming := false
var sens := 1.0
var cam_rig: Node3D
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var model: HumanModel
var shape_node: CollisionShape3D
var capsule: CapsuleShape3D

# Input state (keyboard or the touch UI)
var move_input := Vector2.ZERO    # x = right, y = forward
var touch_move := Vector2.ZERO
var sprinting := false
var firing := false
var jump_queued := false
var air_speed := 0.0              # km/h shown on the HUD
var dive := 0.0                   # smoothed 0..1 head-down amount while skydiving
var chute_t := 0.0                # seconds since the parachute was pulled
var chute_heading := 0.0          # direction the canopy flies
var chute_bank := 0.0             # roll from turning (radians)
var chute_swing := 0.0            # pitch swing under the canopy (radians)
var land_t := 0.0                 # short landing crouch
var is_sprinting := false
var _wind: AudioStreamPlayer

# Weapons: two primaries + pistol. Each slot: {id, mag}
var slots := [null, null, null]
var active := -1
var ammo := {"9mm": 0, "556": 0, "762": 0, "12g": 0, "300": 0}
var fire_cd := 0.0
var reload_t := 0.0
var recoil_kick := 0.0

# Gear and meds
var gear := {"vest": 0, "vest_dur": 0.0, "helmet": 0, "helmet_dur": 0.0, "pack": 0}
var heals := {"bandage": 0, "firstaid": 0, "medkit": 0, "drink": 0, "pills": 0}
var boost := 0.0                  # 0..100, slowly heals and (when high) speeds you up
var heal_id := ""                 # item being used
var heal_t := 0.0                 # seconds left

# Grenades
var throwables := {"frag": 0, "smoke": 0}
var throw_kind := "frag"
var throw_ready := false          # holding G: aiming a throw (arc shown)
var shake := 0.0                  # camera shake from nearby explosions

func _ready() -> void:
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape_node = CollisionShape3D.new()
	shape_node.shape = capsule
	shape_node.position.y = 0.9
	add_child(shape_node)
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)

	model = HumanModel.new(Game.outfit_color(), Color("f2a900"), Game.pants_color(), Game.outfit_character())
	model.set_style(Game.outfit_style())
	add_child(model)
	_refresh_gear()

	cam_rig = Node3D.new()
	cam_rig.top_level = true
	add_child(cam_rig)
	cam_pivot = Node3D.new()
	cam_rig.add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 3.2
	spring.margin = 0.25
	spring.collision_mask = 1 | WorldBuilder.CAMERA_LAYER
	spring.position = Vector3(0.6, 0, 0)
	spring.add_excluded_object(get_rid())
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 4000.0
	camera.current = true
	spring.add_child(camera)
	sens = float(Game.settings.sensitivity)
	display_name = Game.player_name()

# ---------- Input ----------
func add_look(dx: float, dy: float) -> void:
	var k := 0.0032 * sens * (0.45 if aiming else 1.0)
	yaw -= dx * k
	pitch = clampf(pitch - dy * k, -1.35, 1.0)

func action(act: String, pressed: bool) -> void:
	match act:
		"fire":
			if throw_ready:
				if pressed: release_throw()
			else:
				firing = pressed
		"aim": if pressed: aiming = not aiming
		"reload": if pressed: start_reload()
		"jump": if pressed: jump_queued = true
		"crouch": if pressed: set_stance("crouch")
		"prone": if pressed: set_stance("prone")
		"interact": if pressed: interact()
		"heal": if pressed: use_heal(best_heal())
		"boost": if pressed: use_heal(best_boost())
		"throw":
			if pressed: start_throw()
			else: release_throw()
		"throw_kind": if pressed: switch_throw()
		"slot1": if pressed: switch_slot(0)
		"slot2": if pressed: switch_slot(1)
		"slot3": if pressed: switch_slot(2)

func _unhandled_input(event: InputEvent) -> void:
	if Game.settings.controls != "kbm" or state == "dead" or world.match_over:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look(event.relative.x, event.relative.y)
	elif event is InputEventMouseButton and throw_ready and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.pressed: release_throw()
	elif event is InputEventMouseButton:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# Cursor shown with Ctrl: clicks don't shoot. Otherwise a click grabs the mouse again.
			if event.pressed and not Game.cursor_free:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			firing = false
			aiming = false
			return
		if event.button_index == MOUSE_BUTTON_LEFT: firing = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT: aiming = event.pressed
	elif event is InputEventKey and not event.pressed and event.physical_keycode == KEY_G:
		release_throw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F: interact()
			KEY_R: start_reload()
			KEY_SPACE:
				if state == "plane":
					interact()
				else:
					jump_queued = true
			KEY_C: set_stance("crouch")
			KEY_Z: set_stance("prone")
			KEY_H: use_heal(best_heal())
			KEY_Y: use_heal(best_boost())
			KEY_G: start_throw()
			KEY_T: switch_throw()
			KEY_4: use_heal("bandage")
			KEY_5: use_heal("firstaid")
			KEY_6: use_heal("medkit")
			KEY_7: use_heal("drink")
			KEY_8: use_heal("pills")
			KEY_1: switch_slot(0)
			KEY_2: switch_slot(1)
			KEY_3: switch_slot(2)

func _read_move() -> void:
	var v := touch_move
	if Game.settings.controls == "kbm":
		v = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
		sprinting = Input.is_physical_key_pressed(KEY_SHIFT)
	move_input = v.limit_length(1.0)

# ---------- Actions ----------
func interact() -> void:
	match state:
		"plane":
			if world.plane_over_land():
				jump_from_plane()
			else:
				message.emit("انتظر حتى تصل الطائرة فوق الجزيرة")
		"fall":
			open_chute()
		"ground":
			var car: Vehicle = world.nearest_vehicle(global_position, 3.5)
			var it = world.nearest_pickup(global_position, 2.4)
			if it and (car == null or car.global_position.distance_to(global_position) > 2.8):
				world.pickup(self, it)
			elif car:
				enter_vehicle(car)
		"vehicle":
			exit_vehicle()

func jump_from_plane() -> void:
	state = "fall"
	velocity = world.plane_velocity() * 0.5
	dive = 0.0
	message.emit("W مع النظر لتحت = غوص أسرع (234 كم/س) — W مع النظر لقدام = طيران لبعيد")

func open_chute() -> void:
	if state == "fall" and global_position.y < PLANE_ALT - 40.0:
		state = "chute"
		chute_t = 0.0
		chute_heading = model.rotation.y
		chute_swing = 0.35          # the opening shock swings you forward
		shake = maxf(shake, 0.6)

func set_stance(s: String) -> void:
	if state != "ground": return
	stance = "stand" if stance == s else s
	var h := {"stand": 1.8, "crouch": 1.25, "prone": 0.7}[stance] as float
	capsule.height = maxf(h, capsule.radius * 2.0)
	shape_node.position.y = capsule.height * 0.5

func switch_slot(i: int) -> void:
	if i < 0 or i > 2 or slots[i] == null or active == i: return
	active = i
	reload_t = 0.0
	fire_cd = maxf(fire_cd, 0.35)
	model.set_weapon(slots[i].id)
	_refresh_back()

## The primary you are not holding hangs on your back.
func _refresh_back() -> void:
	var other = slots[1 - active] if active in [0, 1] else (slots[0] if active == 2 else null)
	model.set_back_weapon(other.id if other != null else "")

func weapon() -> Dictionary:
	return Game.WEAPONS[slots[active].id] if active >= 0 and slots[active] != null else {}

func start_reload() -> void:
	var w := weapon()
	if w.is_empty() or reload_t > 0.0: return
	var s: Dictionary = slots[active]
	if s.mag >= w.mag or ammo[w.ammo] <= 0: return
	reload_t = w.reload
	# Reload sound stretched a little to fit this gun's reload time.
	var snd := "reload_bolt" if w.cls in ["sr", "shotgun"] else "reload_rifle"
	var length: float = world.sound_length(snd)
	if length > 0.0:
		world.sound_local(snd, 0.0, clampf(length / float(w.reload), 0.85, 1.35))

func give_weapon(id: String, mag: int) -> void:
	var cls: String = Game.WEAPONS[id].cls
	var slot := 2 if cls == "pistol" else (0 if slots[0] == null else (1 if slots[1] == null else (active if active in [0, 1] else 0)))
	if slots[slot] != null:
		world.drop_weapon(slots[slot].id, slots[slot].mag, global_position)
	slots[slot] = {"id": id, "mag": mag}
	active = -1
	switch_slot(slot)

# ---------- Physics ----------
func _physics_process(delta: float) -> void:
	_read_move()
	match state:
		"plane":
			global_position = world.plane_position() + Vector3(0, -3, 0)
			velocity = Vector3.ZERO
		"fall", "chute":
			_air(delta)
		"ground":
			_ground(delta)
		"vehicle":
			_drive(delta)
		"dead":
			velocity.y -= GRAVITY * delta
			velocity.x = 0
			velocity.z = 0
			move_and_slide()
	_update_camera(delta)
	_update_model(delta)

func _wish_dir() -> Vector3:
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	return (fwd * move_input.y + right * move_input.x)

func _air(delta: float) -> void:
	if state == "fall":
		_freefall(delta)
	else:
		_canopy_flight(delta)
	air_speed = velocity.length() * 3.6
	move_and_slide()
	if is_on_floor() or global_position.y <= world.ground_height(global_position) + 0.05:
		_land()

## Freefall: W + looking down dives head-first, W + looking ahead glides far,
## S spreads out to slow down, A/D slide sideways. Speeds change gradually.
func _freefall(delta: float) -> void:
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var push := maxf(move_input.y, 0.0)
	var back := maxf(-move_input.y, 0.0)
	var steep := clampf(inverse_lerp(-0.15, -1.0, pitch), 0.0, 1.0)
	dive = move_toward(dive, push * lerpf(0.35, 1.0, steep), delta * 0.8)
	var v_target := lerpf(FALL_V, DIVE_V, dive) - back * 5.0
	var h_target := fwd * (push * lerpf(GLIDE_H, 7.0, steep) - back * 6.0) + right * move_input.x * 9.0
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(h_target, 9.0 * delta)
	velocity = Vector3(h.x, move_toward(velocity.y, -v_target, (9.8 if velocity.y > -v_target else 6.0) * delta), h.z)
	if global_position.y - world.ground_height(global_position) < CHUTE_AUTO:
		open_chute()

## Under the canopy: it always flies forward. Steering turns it at a limited
## rate (banking into the turn), W speeds up and sinks faster, S flares.
func _canopy_flight(delta: float) -> void:
	chute_t += delta
	var opening := clampf(chute_t / CHUTE_OPEN_TIME, 0.0, 1.0)
	var brake := maxf(-move_input.y, 0.0) if absf(move_input.x) < 0.3 else 0.0
	var push := maxf(move_input.y, 0.0)
	var turn := 0.0
	if move_input.length() > 0.1 and brake == 0.0:
		var d := _wish_dir()
		var want := atan2(-d.x, -d.z)
		turn = clampf(wrapf(want - chute_heading, -PI, PI) * 2.0, -1.0, 1.0)
	chute_heading = wrapf(chute_heading + turn * 1.1 * delta * opening, -PI, PI)
	var h_speed := lerpf(9.0, 14.0, push) - brake * 5.0 - absf(turn) * 1.5
	var v_speed := lerpf(5.5, 7.5, push) - brake * 1.8 + absf(turn) * 1.2
	var dir := Vector3(-sin(chute_heading), 0, -cos(chute_heading))
	var h_target := dir * h_speed * opening
	# The opening shock: big deceleration while the canopy inflates.
	var rate := lerpf(45.0, 6.0, opening)
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(h_target, rate * delta)
	velocity = Vector3(h.x, move_toward(velocity.y, -v_speed, rate * delta), h.z)
	chute_bank = lerpf(chute_bank, -turn * 0.42, minf(1.0, delta * 2.5))
	# Pendulum swing: pushed by speed changes, damped, with a slow sway.
	chute_swing = lerpf(chute_swing, (push - brake) * -0.12 + sin(chute_t * 1.4) * 0.03, minf(1.0, delta * 1.2))
	model.steer = -turn
	model.brake = brake
	model.chute_open = opening

func _land() -> void:
	if state == "chute":
		world.drop_canopy(model, velocity)
		land_t = 0.45
	state = "ground"
	jump_queued = false
	stance = "stand"
	velocity = Vector3.ZERO
	var p: Vector3 = world.safe_landing(global_position)
	global_position = p
	message.emit("اجمع الأسلحة بسرعة!")

func _ground(delta: float) -> void:
	# Safety net: never stay below the terrain surface.
	var g: float = world.ground_height(global_position)
	if global_position.y < g - 0.8 and not world.is_deep(global_position):
		global_position.y = g + 0.1
		velocity.y = 0.0
	fire_cd = maxf(0.0, fire_cd - delta)
	recoil_kick = move_toward(recoil_kick, 0.0, delta * 6.0)
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			reload_t = 0.0
			var w := weapon()
			if not w.is_empty():
				var s: Dictionary = slots[active]
				var take := mini(w.mag - s.mag, ammo[w.ammo])
				s.mag += take
				ammo[w.ammo] -= take
	var wish := _wish_dir()
	var speed := 5.2
	var sprint := sprinting and not aiming and move_input.y > 0.3 and stance != "prone"
	is_sprinting = sprint and not firing
	if sprint:
		speed = 7.2
		if stance == "crouch": set_stance("crouch")
	if stance == "crouch": speed = 2.8
	elif stance == "prone": speed = 1.2
	if aiming: speed = minf(speed, 2.8)
	if heal_id != "": speed = minf(speed, 2.0)
	elif boost >= 60.0: speed *= 1.06
	# Wading through water is slow.
	if global_position.y < Island.WATER - 0.3:
		speed *= 0.55
	var target := wish * speed
	var accel := 40.0 if is_on_floor() else 8.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if is_on_floor():
		if jump_queued:
			if stance != "stand":
				set_stance(stance)
			else:
				velocity.y = 5.4
		velocity.y = maxf(velocity.y, -1.0) if not jump_queued else velocity.y
	else:
		velocity.y -= GRAVITY * delta
	jump_queued = false
	var before := global_position
	move_and_slide()
	# Deep water: you cannot swim out to sea (bridges and piers are fine).
	if global_position.y < Island.WATER - 0.3 and world.is_deep(global_position):
		global_position = Vector3(before.x, global_position.y, before.z)
		velocity.x = 0
		velocity.z = 0
	_tick_heal(delta)
	if firing and not throw_ready:
		if heal_id != "": cancel_heal()
		_try_fire()

# ---------- Shooting ----------
func _try_fire() -> void:
	var w := weapon()
	if w.is_empty() or reload_t > 0.0 or fire_cd > 0.0 or state != "ground":
		return
	var s: Dictionary = slots[active]
	if s.mag <= 0:
		if ammo[w.ammo] <= 0:
			# Out of ammo: the trigger just clicks.
			world.sound_local("dry_click")
			fire_cd = 0.35
			firing = false
			return
		start_reload()
		return
	s.mag -= 1
	fire_cd = w.rate
	if not w.auto:
		firing = false
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	var spread_deg: float = w.spread * (0.4 if aiming else 1.0) * (1.6 if moving else 1.0) * (0.75 if stance == "crouch" else (0.55 if stance == "prone" else 1.0))
	var pellets: int = w.get("pellets", 1)
	for i in pellets:
		_fire_ray(w, deg_to_rad(spread_deg))
	recoil_kick += w.recoil
	pitch = clampf(pitch + deg_to_rad(w.recoil) * 0.5, -1.35, 1.0)
	yaw += deg_to_rad(randf_range(-w.recoil, w.recoil)) * 0.15
	model.recoil = 1.0
	world.effects.muzzle_flash(model.muzzle_position())
	world.sound_shot(w.cls, global_position, true)
	if s.mag == 0:
		start_reload()

func _fire_ray(w: Dictionary, spread: float) -> void:
	var origin := camera.global_position
	var dir := -camera.global_basis.z
	dir = dir.rotated(camera.global_basis.x, randf_range(-spread, spread)).rotated(camera.global_basis.y, randf_range(-spread, spread))
	# The third-person camera sits behind the character: start the ray level with
	# the player so enemies or cover behind us are never hit.
	var muzzle0 := model.gun.global_position
	origin += dir * maxf(0.0, dir.dot(muzzle0 - origin))
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * float(w.range), 1 | 4)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end: Vector3 = hit.position if hit else origin + dir * float(w.range)
	# The bullet leaves the muzzle; make sure nothing blocks it on the way.
	var muzzle := model.muzzle_position()
	var q2 := PhysicsRayQueryParameters3D.create(muzzle, end + (end - muzzle).normalized() * 0.1, 1 | 4)
	q2.exclude = [get_rid()]
	var hit2 := space.intersect_ray(q2)
	if hit2:
		hit = hit2
		end = hit2.position
	world.effects.tracer(muzzle, end)
	if hit:
		var col: Object = hit.collider
		if col and col.has_method("take_damage"):
			var head: bool = end.y > col.global_position.y + 1.45
			var killed: bool = col.take_damage(float(w.dmg) * (2.0 if head else 1.0), self)
			hit_confirmed.emit(head, killed, end)
			if killed: kills += 1
			world.effects.impact(end, hit.normal, true)
		else:
			world.effects.impact(end, hit.normal, false)

## Which way to fall: by stance, movement and where the shot came from.
func _death_anim(attacker: Node, head: bool) -> String:
	if stance == "crouch": return "death_crouch"
	if stance == "prone": return "death_front"
	if Vector2(velocity.x, velocity.z).length() > 3.0: return "death_walk"
	if attacker is Node3D:
		var to: Vector3 = (attacker.global_position - global_position)
		var fwd := -model.global_basis.z
		var front := to.dot(fwd) > 0.0
		if head: return "death_head" if front else "death_back_head"
		if absf(to.normalized().dot(model.global_basis.x)) > 0.75: return "death_right"
		return "death_front" if front else "death_back"
	return ""

func on_ground() -> bool:
	return state == "ground" or state == "vehicle"

## attacker is null for blue-zone damage.
func take_damage(amount: float, attacker: Node, _head := false) -> bool:
	if state == "dead" or world.match_over: return false
	if attacker != null:
		amount = _armour(amount, _head)
	health -= amount
	if attacker is Node3D:
		damaged.emit((attacker.global_position - global_position).normalized())
	if health <= 0.0:
		health = 0.0
		model.death_anim = _death_anim(attacker, _head)
		state = "dead"
		firing = false
		world.on_actor_killed(self, attacker)
		died.emit(attacker.display_name if attacker and "display_name" in attacker else "")
		return true
	return false

# ---------- Camera and model ----------
func _update_camera(delta: float) -> void:
	var head := global_position + Vector3(0, {"stand": 1.6, "crouch": 1.15, "prone": 0.45}[stance] as float, 0)
	# Wading: keep the camera above the water surface.
	head.y = maxf(head.y, Island.WATER + 0.6)
	var w := weapon()
	var zoom: float = w.get("zoom", 1.0) if aiming and state == "ground" else 1.0
	var length := 3.2
	var shoulder := 0.6
	match state:
		"plane":
			length = 26.0
			shoulder = 0.0
		"fall":
			length = 6.5 + dive * 1.5
			shoulder = 0.0
		"chute":
			length = 10.0
			shoulder = 0.0
			head.y += 2.6
		"vehicle":
			head = vehicle.global_position + Vector3(0, 2.2, 0)
			length = 7.5
			shoulder = 0.0
	if aiming and state == "ground":
		length = 0.0 if zoom >= 3.0 else 1.5
		shoulder = 0.0 if zoom >= 3.0 else 0.45
	cam_rig.global_position = cam_rig.global_position.lerp(head, minf(1.0, delta * 20.0)) if state == "ground" else head
	cam_rig.rotation = Vector3(0, yaw, 0)
	shake = move_toward(shake, 0.0, delta * 1.5)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.03
	cam_pivot.rotation = Vector3(pitch + recoil_kick * 0.004, 0, 0) + sh
	spring.spring_length = lerpf(spring.spring_length, length, minf(1.0, delta * 12.0))
	if state == "ground" and head.y < Island.WATER + 1.5:
		cam_pivot.rotation.x = maxf(cam_pivot.rotation.x, -0.25)   # don't look down into the water
	# The over-the-shoulder offset must not poke through a wall next to you
	# (the camera arm cannot see a wall it starts inside of).
	if shoulder > 0.0 and state == "ground":
		var side := cam_rig.global_transform.basis.x
		var q := PhysicsRayQueryParameters3D.create(head, head + side * (shoulder + 0.3), 1 | WorldBuilder.CAMERA_LAYER, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			shoulder = maxf(0.0, head.distance_to(hit.position) - 0.3)
	spring.position.x = lerpf(spring.position.x, shoulder, minf(1.0, delta * 12.0))
	if spring.position.x > shoulder: spring.position.x = shoulder
	var fov := 70.0 / zoom
	if state == "fall":
		fov += clampf((air_speed - 120.0) / 115.0, 0.0, 1.0) * 10.0      # speed rush
		shake = maxf(shake, clampf((air_speed - 150.0) / 85.0, 0.0, 1.0) * 0.12)
	camera.fov = lerpf(camera.fov, fov, minf(1.0, delta * 6.0))
	_update_wind()
	model.visible = not (aiming and zoom >= 3.0 and state == "ground") and state != "plane"

func scoped() -> bool:
	return aiming and state == "ground" and float(weapon().get("zoom", 1.0)) >= 3.0

func _update_model(delta: float) -> void:
	# Face where the camera looks (or the travel direction while skydiving).
	var target_yaw := yaw
	if state == "fall" and move_input.length() > 0.1 and move_input.y < 0.0:
		target_yaw = yaw    # backing up: keep facing forward
	var ry := lerp_angle(model.rotation.y, target_yaw, minf(1.0, delta * (4.0 if state == "fall" else 12.0)))
	if state == "vehicle" and vehicle:
		# Sitting in the driver's seat (left side), facing the car's front (+Z).
		var seat := Vector3(0.38, 0.42 if vehicle.kind == "sedan" else 0.62, -0.18)
		model.global_transform = vehicle.global_transform * Transform3D(Basis(Vector3.UP, PI), seat)
		model.steer = vehicle.steer_in
	elif state == "chute":
		ry = chute_heading
		# Swing and bank around the canopy, not the feet.
		var b := Basis(Vector3.UP, ry) * Basis(Vector3.BACK, chute_bank) * Basis(Vector3.RIGHT, chute_swing)
		var pivot := Vector3(0, HumanModel.CANOPY_Y - 0.4, 0)
		model.transform = Transform3D(b, pivot - b * pivot)
	else:
		model.transform = Transform3D(Basis(Vector3.UP, ry), Vector3.ZERO)
	model.dive = dive
	model.vel_y = velocity.y
	model.aiming = aiming and state == "ground"
	model.sprinting = is_sprinting and state == "ground"
	model.aim_pitch = pitch + 0.1
	var w := weapon()
	model.reload_p = 1.0 - reload_t / float(w.reload) if reload_t > 0.0 and not w.is_empty() else -1.0
	model.lean = move_input.x if state == "fall" else 0.0
	land_t = maxf(land_t - delta, 0.0)
	var pose := "stand"
	match state:
		"fall": pose = "fall"
		"chute": pose = "chute"
		"dead": pose = "dead"
		"vehicle": pose = "drive"
		"ground":
			pose = "crouch" if land_t > 0.0 and stance == "stand" else stance
			# Falling off a roof or a cliff: arms and legs flail.
			if not is_on_floor() and (velocity.y < -5.0 or velocity.y > 1.5): pose = "airborne"
	var sp := Vector2(velocity.x, velocity.z).length()
	var fwd := Vector3(-sin(ry), 0, -cos(ry))
	var rgt := Vector3(cos(ry), 0, -sin(ry))
	model.move_local = Vector2(velocity.dot(rgt), velocity.dot(fwd))
	model.set_pose(pose, sp, active >= 0, delta, Time.get_ticks_msec() / 1000.0)

## Rushing wind while skydiving, softer flapping under the canopy, engine drone in the plane.
func _update_wind() -> void:
	if not Game.settings.sound or DisplayServer.get_name() == "headless": return
	if _wind == null:
		_wind = AudioStreamPlayer.new()
		_wind.stream = world.wind_stream()
		_wind.volume_db = -60.0
		add_child(_wind)
		_wind.play()
	var vol := -60.0
	var pitch_s := 1.0
	match state:
		"plane":
			vol = -10.0
			pitch_s = 0.45
		"fall":
			vol = lerpf(-14.0, -2.0, clampf((air_speed - 80.0) / 150.0, 0.0, 1.0))
			pitch_s = lerpf(0.8, 1.4, clampf(air_speed / 234.0, 0.0, 1.0))
		"chute":
			vol = -20.0 + (1.0 - model.chute_open) * 14.0
			pitch_s = 0.7
	_wind.volume_db = lerpf(_wind.volume_db, vol, 0.08)
	_wind.pitch_scale = lerpf(_wind.pitch_scale, pitch_s, 0.08)

# ---------- Gear and meds ----------
func capacity() -> float:
	return Items.PACK[int(gear.pack)].cap

func used_space() -> float:
	var u := 0.0
	for t in throwables: u += throwables[t] * Items.THROW_SIZE
	for a in ammo: u += ammo[a] * Items.AMMO_SIZE
	for h in heals: u += heals[h] * Items.HEALS[h].size
	return u

func free_space() -> float:
	return capacity() - used_space()

## Damage left after the helmet (head shots) or vest (body) absorbs its share.
## The armour piece loses durability and breaks at 0.
func _armour(amount: float, head: bool) -> float:
	var kind := "helmet" if head else "vest"
	var lvl: int = gear[kind]
	if lvl <= 0: return amount
	var table: Array = Items.HELMET if head else Items.VEST
	var absorbed: float = amount * table[lvl].reduce
	gear[kind + "_dur"] = float(gear[kind + "_dur"]) - amount
	if gear[kind + "_dur"] <= 0.0:
		gear[kind] = 0
		gear[kind + "_dur"] = 0.0
		message.emit("انكسرت " + ("الخوذة" if head else "السترة") + "!")
		_refresh_gear()
	return amount - absorbed

func _refresh_gear() -> void:
	model.set_gear(int(gear.vest), int(gear.helmet), int(gear.pack))

## Wear a vest/helmet/backpack. Returns the old piece as {lvl, dur} (lvl 0 = none).
func equip(kind: String, lvl: int, dur: float) -> Dictionary:
	var old := {"lvl": int(gear[kind]), "dur": float(gear.get(kind + "_dur", 0.0))}
	gear[kind] = lvl
	if kind != "pack": gear[kind + "_dur"] = dur
	_refresh_gear()
	return old

func best_heal() -> String:
	if health < 60.0 and heals.firstaid > 0: return "firstaid"
	if health < 75.0 and heals.bandage > 0: return "bandage"
	if health < 90.0 and heals.medkit > 0: return "medkit"
	if health < 75.0 and heals.firstaid > 0: return "firstaid"
	return ""

func best_boost() -> String:
	if heals.drink > 0 and boost < 85.0: return "drink"
	if heals.pills > 0 and boost < 85.0: return "pills"
	return ""

func use_heal(id: String) -> void:
	if id == "" or state != "ground" or heal_id != "": 
		if id == "" and state == "ground": message.emit("ما عندك أدوية مناسبة هلق")
		return
	if heals.get(id, 0) <= 0:
		message.emit("ما عندك " + Items.HEALS[id].name)
		return
	var h: Dictionary = Items.HEALS[id]
	if h.heal > 0.0 and health >= h.max:
		message.emit("صحتك ما بتحتاج " + h.name)
		return
	heal_id = id
	heal_t = h.time
	firing = false
	reload_t = 0.0

func cancel_heal() -> void:
	heal_id = ""
	heal_t = 0.0

func _tick_heal(delta: float) -> void:
	# Boost: slow regeneration, wears off over a few minutes.
	if boost > 0.0:
		boost = maxf(0.0, boost - delta * 0.55)
		health = minf(100.0, health + delta * (0.15 + boost * 0.006))
	if heal_id == "": return
	if jump_queued or stance == "prone" and Vector2(velocity.x, velocity.z).length() > 0.5:
		cancel_heal()
		return
	heal_t -= delta
	if heal_t <= 0.0:
		var h: Dictionary = Items.HEALS[heal_id]
		heals[heal_id] -= 1
		if h.heal > 0.0:
			health = minf(h.max, health + h.heal) if heal_id == "bandage" else maxf(health, h.max)
		boost = minf(100.0, boost + h.boost)
		heal_id = ""

# ---------- Grenades ----------
func switch_throw() -> void:
	throw_kind = "smoke" if throw_kind == "frag" else "frag"
	message.emit(Items.THROWS[throw_kind])

func start_throw() -> void:
	if state != "ground" or throw_ready: return
	if throwables[throw_kind] <= 0:
		var other := "smoke" if throw_kind == "frag" else "frag"
		if throwables[other] <= 0:
			message.emit("ما معك قنابل")
			return
		throw_kind = other
	cancel_heal()
	firing = false
	throw_ready = true

func throw_origin() -> Vector3:
	return global_position + Vector3(0, 1.6, 0) + (-camera.global_basis.z) * 0.6

func throw_velocity() -> Vector3:
	return (-camera.global_basis.z) * 17.0 + Vector3.UP * 3.5 + Vector3(velocity.x, 0, velocity.z) * 0.5

## Points of the throw arc for the HUD preview (until it reaches the ground).
func throw_arc() -> PackedVector3Array:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var pts := PackedVector3Array()
	var p := throw_origin()
	var v := throw_velocity()
	for i in 60:
		pts.append(p)
		v.y -= g * 0.05
		p += v * 0.05
		if p.y < world.ground_height(p):
			pts.append(p)
			break
	return pts

func release_throw() -> void:
	if not throw_ready: return
	throw_ready = false
	if state != "ground" or throwables[throw_kind] <= 0: return
	throwables[throw_kind] -= 1
	var g := Grenade.new()
	g.world = world
	g.kind = throw_kind
	g.thrower = self
	world.add_child(g)
	g.global_position = throw_origin()
	g.linear_velocity = throw_velocity()
	g.angular_velocity = Vector3(randf(), randf(), randf()) * 6.0
	model.play_action("toss", 1.1)

# ---------- Vehicles ----------
func enter_vehicle(v: Vehicle) -> void:
	if v.dead or v.driver != null: return
	vehicle = v
	v.driver = self
	state = "vehicle"
	stance = "stand"
	shape_node.disabled = true
	firing = false
	aiming = false
	throw_ready = false
	cancel_heal()
	message.emit("WASD للقيادة • Space فرامل • F للنزول")

func exit_vehicle() -> void:
	if vehicle == null: return
	var v := vehicle
	v.driver = null
	v.throttle = 0.0
	v.steer_in = 0.0
	vehicle = null
	# Step out on the left side (or the right if that side is blocked by water).
	var side: Vector3 = v.global_transform.basis.x
	var out := v.global_position - side * 1.9
	if world.is_deep(out): out = v.global_position + side * 1.9
	out.y = maxf(world.ground_height(out), v.global_position.y - 0.5) + 0.3
	global_position = out
	velocity = Vector3.ZERO
	shape_node.disabled = false
	if state != "dead": state = "ground"

func _drive(_delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.dead:
		exit_vehicle()
		return
	global_position = vehicle.global_position + Vector3(0, 0.6, 0)
	velocity = vehicle.linear_velocity
	vehicle.throttle = move_input.y
	vehicle.steer_in = move_input.x
	vehicle.handbrake = jump_queued or (Game.settings.controls == "kbm" and Input.is_physical_key_pressed(KEY_SPACE))
	jump_queued = false

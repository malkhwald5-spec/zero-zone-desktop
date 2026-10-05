class_name Player
extends CharacterBody3D
## The player: third-person movement, stances, skydiving, shooting and inventory.

signal hit_confirmed(headshot: bool, killed: bool, pos: Vector3)
signal damaged(from_dir: Vector3)
signal died(killer_name: String)
signal message(text: String)

const GRAVITY := 18.0
const PLANE_ALT := 600.0
const CHUTE_AUTO := 120.0

var world: Node
var state := "plane"          # plane | fall | chute | ground | dead
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
var model: SoldierModel
var shape_node: CollisionShape3D
var capsule: CapsuleShape3D

# Input state (keyboard or the touch UI)
var move_input := Vector2.ZERO    # x = right, y = forward
var touch_move := Vector2.ZERO
var sprinting := false
var firing := false
var jump_queued := false
var air_speed := 0.0              # km/h shown on the HUD

# Weapons: two primaries + pistol. Each slot: {id, mag}
var slots := [null, null, null]
var active := -1
var ammo := {"9mm": 0, "556": 0, "762": 0, "12g": 0}
var fire_cd := 0.0
var reload_t := 0.0
var recoil_kick := 0.0

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

	model = SoldierModel.new(Game.outfit_color(), Color("f2a900"), Game.pants_color())
	add_child(model)

	cam_rig = Node3D.new()
	cam_rig.top_level = true
	add_child(cam_rig)
	cam_pivot = Node3D.new()
	cam_rig.add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 3.2
	spring.margin = 0.25
	spring.collision_mask = 1
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
		"fire": firing = pressed
		"aim": if pressed: aiming = not aiming
		"reload": if pressed: start_reload()
		"jump": if pressed: jump_queued = true
		"crouch": if pressed: set_stance("crouch")
		"prone": if pressed: set_stance("prone")
		"interact": if pressed: interact()
		"slot1": if pressed: switch_slot(0)
		"slot2": if pressed: switch_slot(1)
		"slot3": if pressed: switch_slot(2)

func _unhandled_input(event: InputEvent) -> void:
	if Game.settings.controls != "kbm" or state == "dead" or world.match_over:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look(event.relative.x, event.relative.y)
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
			var it = world.nearest_pickup(global_position, 2.4)
			if it: world.pickup(self, it)

func jump_from_plane() -> void:
	state = "fall"
	velocity = world.plane_velocity() * 0.3
	message.emit("اسحب للأمام للغوص أسرع — افتح المظلة متى شئت")

func open_chute() -> void:
	if state == "fall" and global_position.y < PLANE_ALT - 40.0:
		state = "chute"

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
	model.set_weapon(Game.WEAPONS[slots[i].id].cls)

func weapon() -> Dictionary:
	return Game.WEAPONS[slots[active].id] if active >= 0 and slots[active] != null else {}

func start_reload() -> void:
	var w := weapon()
	if w.is_empty() or reload_t > 0.0: return
	var s: Dictionary = slots[active]
	if s.mag >= w.mag or ammo[w.ammo] <= 0: return
	reload_t = w.reload

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
	var wish := _wish_dir()
	var dive := maxf(0.0, move_input.y)
	var h_speed: float
	var v_speed: float
	if state == "fall":
		h_speed = 12.0 + 26.0 * dive
		v_speed = 48.0 + 18.0 * dive
		if global_position.y - world.ground_height(global_position) < CHUTE_AUTO:
			open_chute()
	else:
		h_speed = 11.0 + 4.0 * dive
		v_speed = 7.5
	var target := wish * h_speed
	velocity.x = move_toward(velocity.x, target.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 30.0 * delta)
	velocity.y = move_toward(velocity.y, -v_speed, 40.0 * delta)
	air_speed = Vector3(velocity.x, velocity.y, velocity.z).length() * 3.6
	move_and_slide()
	if is_on_floor() or global_position.y <= world.ground_height(global_position) + 0.05:
		_land()

func _land() -> void:
	state = "ground"
	jump_queued = false
	stance = "stand"
	velocity = Vector3.ZERO
	var p: Vector3 = world.safe_landing(global_position)
	global_position = p
	message.emit("اجمع الأسلحة بسرعة!")

func _ground(delta: float) -> void:
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
	if sprint:
		speed = 7.2
		if stance == "crouch": set_stance("crouch")
	if stance == "crouch": speed = 2.8
	elif stance == "prone": speed = 1.2
	if aiming: speed = minf(speed, 2.8)
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
	if firing:
		_try_fire()

# ---------- Shooting ----------
func _try_fire() -> void:
	var w := weapon()
	if w.is_empty() or reload_t > 0.0 or fire_cd > 0.0 or state != "ground":
		return
	var s: Dictionary = slots[active]
	if s.mag <= 0:
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
	world.effects.muzzle_flash(model.gun.global_position + (-model.global_basis.z) * 0.6)
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
	var muzzle := model.gun.global_position + (-model.global_basis.z) * 0.6
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

func on_ground() -> bool:
	return state == "ground"

## attacker is null for blue-zone damage.
func take_damage(amount: float, attacker: Node, _head := false) -> bool:
	if state == "dead" or world.match_over: return false
	health -= amount
	if attacker is Node3D:
		damaged.emit((attacker.global_position - global_position).normalized())
	if health <= 0.0:
		health = 0.0
		state = "dead"
		firing = false
		world.on_actor_killed(self, attacker)
		died.emit(attacker.display_name if attacker and "display_name" in attacker else "")
		return true
	return false

# ---------- Camera and model ----------
func _update_camera(delta: float) -> void:
	var head := global_position + Vector3(0, {"stand": 1.6, "crouch": 1.15, "prone": 0.45}[stance] as float, 0)
	var w := weapon()
	var zoom: float = w.get("zoom", 1.0) if aiming and state == "ground" else 1.0
	var length := 3.2
	var shoulder := 0.6
	match state:
		"plane":
			length = 26.0
			shoulder = 0.0
		"fall":
			length = 6.0
			shoulder = 0.0
		"chute":
			length = 9.0
			shoulder = 0.0
			head.y += 3.0
	if aiming and state == "ground":
		length = 0.0 if zoom >= 3.0 else 1.5
		shoulder = 0.0 if zoom >= 3.0 else 0.45
	cam_rig.global_position = cam_rig.global_position.lerp(head, minf(1.0, delta * 20.0)) if state == "ground" else head
	cam_rig.rotation = Vector3(0, yaw, 0)
	cam_pivot.rotation = Vector3(pitch + recoil_kick * 0.004, 0, 0)
	spring.spring_length = lerpf(spring.spring_length, length, minf(1.0, delta * 12.0))
	spring.position.x = lerpf(spring.position.x, shoulder, minf(1.0, delta * 12.0))
	camera.fov = lerpf(camera.fov, 70.0 / zoom, minf(1.0, delta * 14.0))
	model.visible = not (aiming and zoom >= 3.0 and state == "ground") and state != "plane"

func scoped() -> bool:
	return aiming and state == "ground" and float(weapon().get("zoom", 1.0)) >= 3.0

func _update_model(delta: float) -> void:
	# Face where the camera looks (or the travel direction while skydiving).
	var target_yaw := yaw
	if state in ["fall", "chute"] and move_input.length() > 0.1:
		var d := _wish_dir()
		target_yaw = atan2(-d.x, -d.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, minf(1.0, delta * 12.0))
	var pose := "stand"
	match state:
		"fall": pose = "fall"
		"chute": pose = "chute"
		"dead": pose = "dead"
		"ground": pose = stance
	var sp := Vector2(velocity.x, velocity.z).length()
	model.set_pose(pose, sp, active >= 0, delta, Time.get_ticks_msec() / 1000.0)

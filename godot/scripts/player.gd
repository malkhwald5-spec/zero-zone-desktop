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
var dmg_dealt := 0.0      # career stats for this match
var head_kills := 0
var longest_kill := 0.0
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
var ammo := {"9mm": 0, "556": 0, "762": 0, "12g": 0, "300": 0, "bolt": 0}
var fire_cd := 0.0
var reload_t := 0.0
var recoil_kick := 0.0

# Gear and meds
var gear := {"vest": 0, "vest_dur": 0.0, "helmet": 0, "helmet_dur": 0.0, "pack": 0}
var heals := {"bandage": 0, "firstaid": 0, "medkit": 0, "drink": 0, "pills": 0}
var spares: Array = []            # attachments carried in the bag (not on a gun)
const SPARE_SIZE := 3.0
var boost := 0.0                  # 0..100, slowly heals and (when high) speeds you up
var heal_id := ""                 # item being used
var heal_t := 0.0                 # seconds left

# Grenades
var throwables := {"frag": 0, "smoke": 0, "molotov": 0, "flash": 0}
var throw_kind := "frag"
var throw_ready := false          # holding G: aiming a throw (arc shown)
var shake := 0.0                  # camera shake from nearby explosions
var peek := 0.0                   # leaning round cover: -1 left .. 1 right (Q / E)
var peek_toggle := 0.0            # touch buttons: lean stays on until pressed again
var team := 0                     # your team (bot teammates share it)
var slot := 0                     # your number in the team (colour on the HUD)
var knocked := false              # down in a team match: crawl, bleed, wait for a revive
var knocked_by: Node = null
var revive_target: Node3D = null  # knocked teammate you are picking up (hold F)
var revive_t := 0.0
var revived_by_t := 0.0           # a teammate picking you up: their progress 0..1
const REVIVE_TIME := 6.0
const BLEED_TIME := 45.0          # seconds from knocked to dead with nobody helping
var killer: Node3D = null         # who killed you (the killcam looks at them)
var spectate: Node3D = null       # player you are watching after dying
var dead_t := 0.0                 # seconds since you died
var vault_t := -1.0               # 0..1 while climbing over something (Space)
var _vault_from := Vector3.ZERO
var _vault_to := Vector3.ZERO
var _vault_top := 0.0
var _vault_time := 0.5

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
	# Moved every rendered frame from the interpolated body position instead.
	cam_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	camera.far = 4000.0 if not Game.laptop() else 2600.0
	camera.current = true
	spring.add_child(camera)
	sens = float(Game.settings.sensitivity)
	display_name = Game.player_name()

# ---------- Input ----------
func add_look(dx: float, dy: float) -> void:
	var k := 0.0032 * sens * (float(Game.settings.get("aim_sens", 0.45)) if aiming else 1.0)
	if aiming and scoped():
		# Through a scope: slower the more it magnifies.
		k /= sqrt(maxf(1.0, float(weapon().get("zoom", 1.0))))
	yaw -= dx * k
	if Game.settings.get("invert_y", false): dy = -dy
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
		"interact":
			if pressed: interact()
			else: revive_target = null
		"heal": if pressed: use_heal(best_heal())
		"boost": if pressed: use_heal(best_boost())
		"throw":
			if pressed: start_throw()
			else: release_throw()
		"throw_kind": if pressed: switch_throw()
		"peek_l": if pressed: peek_toggle = 0.0 if peek_toggle < 0.0 else -1.0
		"peek_r": if pressed: peek_toggle = 0.0 if peek_toggle > 0.0 else 1.0
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
	elif event is InputEventKey and not event.pressed and event.physical_keycode == Game.key("throw"):
		release_throw()
	elif event is InputEventKey and not event.pressed and event.physical_keycode == Game.key("interact"):
		revive_target = null
	elif event is InputEventKey and event.pressed and not event.echo:
		match Game.action_for(event.physical_keycode):
			"interact": interact()
			"reload": start_reload()
			"jump":
				if state == "plane":
					interact()
				else:
					jump_queued = true
			"crouch": set_stance("crouch")
			"prone": set_stance("prone")
			"heal": use_heal(best_heal())
			"boost": use_heal(best_boost())
			"throw": start_throw()
			"throw_kind": switch_throw()
			"slot1": switch_slot(0)
			"slot2": switch_slot(1)
			"slot3": switch_slot(2)
		match event.physical_keycode:
			KEY_4: use_heal("bandage")
			KEY_5: use_heal("firstaid")
			KEY_6: use_heal("medkit")
			KEY_7: use_heal("drink")
			KEY_8: use_heal("pills")

func _read_move() -> void:
	var v := touch_move
	if Game.settings.controls == "kbm":
		v = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
		sprinting = Input.is_physical_key_pressed(Game.key("sprint"))
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
			if knocked: return
			# A knocked teammate next to you: hold to pick them up.
			var mate := downed_mate_near()
			if mate:
				revive_target = mate
				revive_t = 0.0
				firing = false
				cancel_heal()
				return
			var car: Vehicle = world.nearest_vehicle(global_position, 3.5)
			var it = world.nearest_pickup(global_position, 2.4)
			if it and (car == null or car.global_position.distance_to(global_position) > 2.8):
				if it.has_meta("crate"):
					# A loot box: look inside (the bag screen lists what it holds).
					if not world.hud.bag_open: world.hud.toggle_bag()
				else:
					world.pickup(self, it)
			elif car:
				enter_vehicle(car)
		"vehicle":
			exit_vehicle()

## Nearest knocked teammate within reach (or null).
func downed_mate_near() -> Node3D:
	for m in world.teammates(self):
		if world.is_down(m) and not world.is_gone(m) and m.global_position.distance_to(global_position) < 2.3:
			return m
	return null

## Holding F next to a knocked teammate: six seconds standing still.
func _tick_revive(delta: float) -> void:
	if revive_target == null: return
	var m := revive_target
	if not is_instance_valid(m) or not world.is_down(m) or world.is_gone(m) or knocked \
			or m.global_position.distance_to(global_position) > 2.6 or move_input.length() > 0.3:
		revive_target = null
		return
	revive_t += delta
	if revive_t >= REVIVE_TIME:
		revive_target = null
		m.revive_done()

func jump_from_plane() -> void:
	state = "fall"
	reset_physics_interpolation()
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
	if state != "ground" or knocked: return
	_force_stance("stand" if stance == s else s)

func _force_stance(s: String) -> void:
	stance = s
	var h := {"stand": 1.8, "crouch": 1.25, "prone": 0.7}[stance] as float
	capsule.height = maxf(h, capsule.radius * 2.0)
	shape_node.position.y = capsule.height * 0.5

func switch_slot(i: int) -> void:
	if knocked: return
	if i < 0 or i > 2 or slots[i] == null or active == i: return
	active = i
	reload_t = 0.0
	fire_cd = maxf(fire_cd, 0.35)
	model.set_weapon(slots[i].id)
	model.set_attachments(slots[i].get("att", {}))
	_refresh_back()

## The primary you are not holding hangs on your back.
func _refresh_back() -> void:
	var other = slots[1 - active] if active in [0, 1] else (slots[0] if active == 2 else null)
	model.set_back_weapon(other.id if other != null else "")

var _wkey := ""
var _wcache := {}

## The held gun's stats, with its attachments applied (cached).
func weapon() -> Dictionary:
	if active < 0 or slots[active] == null: return {}
	var s: Dictionary = slots[active]
	var att: Dictionary = s.get("att", {})
	if att.is_empty(): return Game.WEAPONS[s.id]
	var key := "%s%s" % [s.id, att]
	if key != _wkey:
		_wkey = key
		_wcache = Items.apply_attachments(Game.WEAPONS[s.id], att)
	return _wcache

## Fits a picked-up attachment: first to a gun with that slot free (the one in
## your hands first), else swaps it onto the first gun it fits (the old part
## drops at your feet). False if no gun takes it.
func add_attachment(id: String, swap_to_bag := false) -> bool:
	var a: Dictionary = Items.ATTACH[id]
	var order := [active, 0, 1, 2]
	for pass_n in 2:
		for i in order:
			if i < 0 or slots[i] == null: continue
			if not Items.attach_fits(id, Game.WEAPONS[slots[i].id].cls): continue
			var att: Dictionary = slots[i].get("att", {})
			if pass_n == 0 and att.has(a.slot): continue
			if att.has(a.slot):
				if swap_to_bag: spares.append(att[a.slot])
				else: world._add_pickup({"kind": "attach", "id": att[a.slot]}, global_position + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)))
			att[a.slot] = id
			slots[i].att = att
			_after_attach_change(i)
			message.emit("تم تركيب %s على %s" % [a.name, Game.WEAPONS[slots[i].id].name])
			return true
	# Nothing to fit it on yet: keep it in the bag.
	if free_space() >= SPARE_SIZE:
		spares.append(id)
		message.emit("%s في الحقيبة" % a.name)
		return true
	message.emit("الحقيبة ممتلئة")
	return false

# ---------- Inventory actions (bag screen) ----------
func _drop_at() -> Vector3:
	return global_position + Vector3(randf_range(-0.7, 0.7), 0, randf_range(-0.7, 0.7))

## Takes an attachment off a gun into the bag (or to the ground if full).
func detach(slot_i: int, att_slot: String) -> void:
	if slots[slot_i] == null or not slots[slot_i].get("att", {}).has(att_slot): return
	var id: String = slots[slot_i].att[att_slot]
	slots[slot_i].att.erase(att_slot)
	_after_attach_change(slot_i)
	if slot_i == active:
		model.set_attachments(slots[slot_i].att)
	if free_space() >= SPARE_SIZE: spares.append(id)
	else: world._add_pickup({"kind": "attach", "id": id}, _drop_at())

## Fits a spare from the bag onto a specific gun (or the best one if -1).
func fit_spare(spare_i: int, slot_i := -1) -> bool:
	if spare_i < 0 or spare_i >= spares.size(): return false
	var id: String = spares[spare_i]
	var a: Dictionary = Items.ATTACH[id]
	if slot_i >= 0:
		if slots[slot_i] == null or not Items.attach_fits(id, Game.WEAPONS[slots[slot_i].id].cls): return false
		spares.remove_at(spare_i)
		var att: Dictionary = slots[slot_i].get("att", {})
		if att.has(a.slot): spares.append(att[a.slot])
		att[a.slot] = id
		slots[slot_i].att = att
		_after_attach_change(slot_i)
		return true
	spares.remove_at(spare_i)
	for i in [active, 0, 1, 2]:
		if i >= 0 and slots[i] != null and Items.attach_fits(id, Game.WEAPONS[slots[i].id].cls):
			return fit_spare_on(id, i)
	spares.insert(spare_i, id)
	message.emit("%s ما بيركب على أسلحتك" % a.name)
	return false

func fit_spare_on(id: String, i: int) -> bool:
	var att: Dictionary = slots[i].get("att", {})
	var slot_name: String = Items.ATTACH[id].slot
	if att.has(slot_name): spares.append(att[slot_name])
	att[slot_name] = id
	slots[i].att = att
	_after_attach_change(i)
	return true

func drop_spare(spare_i: int) -> void:
	if spare_i < 0 or spare_i >= spares.size(): return
	world._add_pickup({"kind": "attach", "id": spares[spare_i]}, _drop_at())
	spares.remove_at(spare_i)

func drop_slot(i: int) -> void:
	if slots[i] == null: return
	world.drop_weapon(slots[i].id, slots[i].mag, global_position, slots[i].get("att", {}))
	slots[i] = null
	if active == i:
		var next := -1
		for k in [0, 1, 2]:
			if slots[k] != null:
				next = k
				break
		active = -1
		reload_t = 0.0
		if next >= 0: switch_slot(next)
		else: model.set_weapon("")
	_refresh_back()

func drop_ammo(type: String, amount := -1) -> void:
	var n: int = ammo[type] if amount < 0 else mini(amount, ammo[type])
	if n <= 0: return
	ammo[type] -= n
	world._add_pickup({"kind": "ammo", "type": type, "amount": n}, _drop_at())

func drop_heal(id: String) -> void:
	if heals[id] <= 0: return
	heals[id] -= 1
	world._add_pickup({"kind": "heal", "id": id, "n": 1}, _drop_at())

func drop_throw(id: String) -> void:
	if throwables[id] <= 0: return
	throwables[id] -= 1
	world._add_pickup({"kind": "throw", "id": id, "n": 1}, _drop_at())

func drop_gear(kind: String) -> void:
	if int(gear[kind]) <= 0: return
	if kind == "pack" and used_space() > Items.PACK[0].cap:
		message.emit("فضّي الحقيبة أول قبل ما ترميها")
		return
	var old := equip(kind, 0, 0.0)
	world._add_gear(kind, old.lvl, old.dur, _drop_at())

func _after_attach_change(i: int) -> void:
	# A smaller magazine than the rounds loaded: put the extra back in the bag.
	var w := Items.apply_attachments(Game.WEAPONS[slots[i].id], slots[i].get("att", {}))
	if slots[i].mag > w.mag:
		ammo[w.ammo] += slots[i].mag - w.mag
		slots[i].mag = w.mag
	if i == active:
		model.set_attachments(slots[i].att)

func start_reload() -> void:
	if knocked: return
	var w := weapon()
	if w.is_empty() or reload_t > 0.0 or w.get("melee", false): return
	var s: Dictionary = slots[active]
	if s.mag >= w.mag or ammo[w.ammo] <= 0: return
	reload_t = w.reload
	# Reload sound stretched a little to fit this gun's reload time.
	var snd := "reload_bolt" if w.cls in ["sr", "shotgun", "crossbow", "dmr"] else "reload_rifle"
	var length: float = world.sound_length(snd)
	if length > 0.0:
		world.sound_local(snd, 0.0, clampf(length / float(w.reload), 0.85, 1.35))

func give_weapon(id: String, mag: int, att := {}) -> void:
	var cls: String = Game.WEAPONS[id].cls
	var slot := 2 if cls in ["pistol", "melee"] else (0 if slots[0] == null else (1 if slots[1] == null else (active if active in [0, 1] else 0)))
	if slots[slot] != null:
		world.drop_weapon(slots[slot].id, slots[slot].mag, global_position, slots[slot].get("att", {}))
	slots[slot] = {"id": id, "mag": mag, "att": att.duplicate()}
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
			dead_t += delta
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
	reset_physics_interpolation()
	message.emit("اجمع الأسلحة بسرعة!")

func _ground(delta: float) -> void:
	if vault_t >= 0.0:
		_vault_step(delta)
		return
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
	if knocked:
		speed = 0.9
		is_sprinting = false
	if revive_target: speed = 0.0
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
	_update_peek(delta)
	if is_on_floor():
		if jump_queued:
			if stance != "stand":
				set_stance(stance)
			elif try_vault():
				jump_queued = false
				return
			else:
				velocity.y = 5.4
		velocity.y = maxf(velocity.y, -1.0) if not jump_queued else velocity.y
	else:
		velocity.y -= GRAVITY * delta
	jump_queued = false
	var before := global_position
	move_and_slide()
	_step_up(wish)
	# Deep water: you cannot swim out to sea (bridges and piers are fine).
	if global_position.y < Island.WATER - 0.3 and world.is_deep(global_position):
		global_position = Vector3(before.x, global_position.y, before.z)
		velocity.x = 0
		velocity.z = 0
	_tick_heal(delta)
	_tick_revive(delta)
	if knocked:
		# Bleeding out.
		health -= delta * 100.0 / BLEED_TIME
		if health <= 0.0:
			bleed_out()
			return
	_footsteps(delta)
	if firing and not throw_ready:
		if heal_id != "": cancel_heal()
		_try_fire()

## Q / E (held) or the touch buttons: lean out to the side. Not while
## prone, sprinting or running.
func _update_peek(delta: float) -> void:
	var want := peek_toggle
	if Game.settings.controls == "kbm" and not Game.cursor_free:
		want = (1.0 if Input.is_physical_key_pressed(Game.key("peek_r")) else 0.0) - (1.0 if Input.is_physical_key_pressed(Game.key("peek_l")) else 0.0)
	if stance == "prone" or is_sprinting or vault_t >= 0.0:
		want = 0.0
		peek_toggle = 0.0
	peek = move_toward(peek, want, delta * 5.0)

## Walking into a kerb, a step or a low ledge (under 40 cm): step up onto it
## instead of stopping.
func _step_up(wish: Vector3) -> void:
	if not is_on_floor() or not is_on_wall() or wish.length() < 0.1: return
	var dir := Vector3(wish.x, 0, wish.z).normalized()
	var space := get_world_3d().direct_space_state
	var p := global_position
	var low := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.12, 0), p + Vector3(0, 0.12, 0) + dir * 0.7, 1, [get_rid()]))
	if low.is_empty(): return
	var high := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.45, 0), p + Vector3(0, 0.45, 0) + dir * 0.9, 1, [get_rid()]))
	if not high.is_empty(): return
	var at: Vector3 = low.position + dir * 0.2
	var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, p.y + 0.5, at.z), Vector3(at.x, p.y, at.z), 1, [get_rid()]))
	if top.is_empty(): return
	var rise: float = top.position.y - p.y
	if rise > 0.02 and rise < 0.42:
		global_position = Vector3(p.x, top.position.y + 0.02, p.z) + dir * 0.06

## Space in front of a low wall, fence, crate or window: climb over it (or
## up onto it when it is deep). True when a vault started.
func try_vault() -> bool:
	if knocked: return false
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var base := global_position
	var space := get_world_3d().direct_space_state
	var ray := func(a: Vector3, b: Vector3) -> Dictionary:
		var q := PhysicsRayQueryParameters3D.create(a, b, 1, [get_rid()])
		return space.intersect_ray(q)
	# Something knee-high right in front?
	var front: Dictionary = ray.call(base + Vector3(0, 0.45, 0), base + Vector3(0, 0.45, 0) + fwd * 1.2)
	if front.is_empty(): return false
	var d: float = Vector2(front.position.x - base.x, front.position.z - base.z).length()
	# Its top: look down just past the front face (inside a wall's thickness).
	var probe := base + fwd * (d + 0.1)
	var top_hit: Dictionary = ray.call(probe + Vector3(0, 2.3, 0), probe + Vector3(0, 0.3, 0))
	if top_hit.is_empty(): return false
	var h: float = top_hit.position.y - base.y
	if h < 0.35 or h > 1.75: return false
	# Room above it to get over (a window opening is enough).
	if not ray.call(base + Vector3(0, h + 0.55, 0), base + Vector3(0, h + 0.55, 0) + fwd * (d + 1.2)).is_empty():
		return false
	# How deep is it? Look back from the far side.
	var far_p := base + fwd * (d + 1.6) + Vector3(0, h - 0.15, 0)
	var back: Dictionary = ray.call(far_p, far_p - fwd * 1.6)
	var to: Vector3
	if not back.is_empty() and Vector2(back.position.x - base.x, back.position.z - base.z).length() > d + 0.05:
		# Thin: over it, down on the other side.
		var beyond: Vector3 = Vector3(back.position.x, base.y, back.position.z) + fwd * 0.55
		var down: Dictionary = ray.call(beyond + Vector3(0, h + 0.5, 0), beyond + Vector3(0, -3.0, 0))
		if down.is_empty(): return false
		to = down.position
	else:
		# Deep (a crate stack, a ledge): up on top of it.
		to = base + fwd * (d + 0.45)
		to.y = top_hit.position.y
	# The landing spot must be free.
	var shp := PhysicsShapeQueryParameters3D.new()
	shp.shape = capsule
	shp.transform = Transform3D(Basis.IDENTITY, to + Vector3(0, capsule.height * 0.5 + 0.05, 0))
	shp.collision_mask = 1 | 4
	shp.exclude = [get_rid()]
	if not space.intersect_shape(shp, 1).is_empty(): return false
	_vault_from = base
	_vault_to = to
	_vault_top = base.y + h + 0.25
	_vault_time = 0.38 + h * 0.18
	vault_t = 0.0
	shape_node.disabled = true
	velocity = Vector3.ZERO
	firing = false
	aiming = false
	if heal_id != "": cancel_heal()
	world.footstep(base, true, 0.7)
	return true

func _vault_step(delta: float) -> void:
	vault_t = minf(1.0, vault_t + delta / _vault_time)
	var t := vault_t
	var p := _vault_from.lerp(_vault_to, smoothstep(0.0, 1.0, t))
	# Up to the top first, over, then down.
	var up := smoothstep(0.0, 0.45, t)
	var y := lerpf(_vault_from.y, _vault_top, up)
	if t > 0.55:
		y = lerpf(_vault_top, _vault_to.y, smoothstep(0.55, 1.0, t))
	p.y = maxf(y, lerpf(_vault_from.y, _vault_to.y, t))
	global_position = p
	if vault_t >= 1.0:
		vault_t = -1.0
		shape_node.disabled = false
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		velocity = fwd * 2.5
		land_t = 0.2
		world.footstep(global_position, true, 0.8)

var _step_dist := 0.0

## A footstep sound every stride (none while prone).
func _footsteps(delta: float) -> void:
	world._update_auto_tail()
	if not is_on_floor() or stance == "prone":
		_step_dist = 0.0
		return
	_step_dist += Vector2(velocity.x, velocity.z).length() * delta
	var stride := 1.9 if is_sprinting else (0.95 if stance == "crouch" else 1.35)
	if _step_dist > stride:
		_step_dist = 0.0
		world.footstep(global_position, true, 0.9 if is_sprinting else (0.15 if stance == "crouch" else 0.5))

# ---------- Shooting ----------
func _try_fire() -> void:
	var w := weapon()
	if w.is_empty() or reload_t > 0.0 or fire_cd > 0.0 or state != "ground" or knocked:
		return
	if w.get("melee", false):
		_swing(w)
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
	var quiet: bool = w.get("suppressed", false) or w.get("silent", false)
	if not quiet: world.effects.muzzle_flash(model.muzzle_position())
	world.sound_shot(w.cls, global_position, true, quiet)
	world.notify_shot(global_position, self, quiet)
	if s.mag == 0:
		start_reload()

## Pan (melee): a swing that hits whoever is right in front of you.
func _swing(w: Dictionary) -> void:
	fire_cd = w.rate
	firing = false
	model.play_action("toss", 0.45)
	var fwd := -camera.global_basis.z
	fwd = Vector3(fwd.x, clampf(fwd.y, -0.4, 0.4), fwd.z).normalized()
	var space := get_world_3d().direct_space_state
	var shp := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.55
	shp.shape = ball
	shp.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 1.2, 0) + fwd * 1.3)
	shp.collision_mask = 2 | 4
	shp.exclude = [get_rid()]
	var hit_someone := false
	for r in space.intersect_shape(shp, 4):
		var col: Object = r.collider
		if col and col != self and col.has_method("take_damage") and not world.is_gone(col):
			var killed: bool = col.take_damage(float(w.dmg), self, false)
			hit_confirmed.emit(false, killed, col.global_position + Vector3(0, 1.2, 0))
			if killed: kills += 1
			hit_someone = true
			break
	world.sound_local("bolt_cycle", 0.08, 0.55 if hit_someone else 1.4, -2.0 if hit_someone else -10.0)
	world.notify_shot(global_position, self, true)

## The pan on your hip stops bullets from behind (when you are not holding it).
func _pan_blocks(attacker: Node) -> bool:
	if slots[2] == null or slots[2].id != "pan" or active == 2 or not (attacker is Node3D): return false
	var to: Vector3 = attacker.global_position - global_position
	to.y = 0.0
	var fwd := Vector3(-sin(model.rotation.y), 0, -cos(model.rotation.y))
	return to.length() > 0.5 and fwd.dot(to.normalized()) < -0.7

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
			if killed:
				kills += 1
				if head: head_kills += 1
			world.effects.impact(end, hit.normal, not (col is Vehicle))     # cars get holes, not blood
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
	if attacker != null and attacker != self and world.same_team(self, attacker): return false   # no friendly fire
	if not knocked and _pan_blocks(attacker):
		# Clang: the round hits the pan on your back.
		world.sound_local("bolt_cycle", 0.0, 0.5, -4.0)
		world.effects.impact(global_position + Vector3(0, 1.1, 0) - Vector3(-sin(model.rotation.y), 0, -cos(model.rotation.y)) * 0.3, Vector3.UP, false)
		return false
	if attacker != null and not knocked:
		amount = _armour(amount, _head)
	health -= amount
	if attacker != null: model.hit(amount / 40.0)
	if attacker is Node3D:
		damaged.emit((attacker.global_position - global_position).normalized())
	if health <= 0.0 and not knocked and world.can_knock(self):
		_knock(attacker)
		return false
	if health <= 0.0:
		_die(attacker if attacker != null or not knocked else knocked_by, _head)
		return true
	return false

## Knocked down (team match): on the ground, crawling, bleeding out unless a
## teammate picks you up.
func _knock(attacker: Node) -> void:
	if state == "vehicle": exit_vehicle(true)
	knocked = true
	knocked_by = attacker
	health = 100.0
	firing = false
	aiming = false
	throw_ready = false
	peek_toggle = 0.0
	revive_target = null
	cancel_heal()
	_force_stance("prone")
	world.on_actor_knocked(self, attacker)

## Picked up by a teammate.
func revive_done() -> void:
	if not knocked or state == "dead": return
	knocked = false
	health = 25.0
	revived_by_t = 0.0
	_force_stance("stand")
	message.emit("زميلك رفعك!")

## Nobody left to help, or bled out.
func bleed_out() -> void:
	if state != "dead": _die(knocked_by, false)

func _die(attacker: Node, _head: bool) -> void:
	knocked = false
	revive_target = null
	health = 0.0
	model.death_anim = _death_anim(attacker, _head)
	state = "dead"
	killer = attacker if attacker is Node3D and attacker != self else null
	dead_t = 0.0
	firing = false
	world.on_actor_killed(self, attacker)
	died.emit(attacker.display_name if attacker and "display_name" in attacker else "")

# ---------- Camera and model ----------
func _update_camera(delta: float) -> void:
	if state == "dead" and (is_instance_valid(spectate) or is_instance_valid(killer)):
		model.visible = true
		return
	var head := global_position + Vector3(0, {"stand": 1.6, "crouch": 1.15, "prone": 0.45}[stance] as float, 0)
	# Wading: keep the camera above the water surface.
	head.y = maxf(head.y, Island.WATER + 0.6)
	var w := weapon()
	var zoom: float = w.get("zoom", 1.0) if aiming and state == "ground" else 1.0
	view_zoom = zoom
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
		length = 0.0 if scoped() else 1.5
		shoulder = 0.0 if scoped() else 0.45
	if state == "ground" and absf(peek) > 0.01:
		# Lean: the eyes move out to the side (not into a wall) and drop a little.
		var side := cam_rig.global_transform.basis.x * signf(peek)
		var want := absf(peek) * 0.55
		var qp := PhysicsRayQueryParameters3D.create(head, head + side * (want + 0.25), 1 | WorldBuilder.CAMERA_LAYER, [get_rid()])
		var hp := get_world_3d().direct_space_state.intersect_ray(qp)
		if not hp.is_empty():
			want = minf(want, maxf(0.0, head.distance_to(hp.position) - 0.25))
		head += side * want + Vector3(0, -0.08 * absf(peek), 0)
	# Where the camera looks from, relative to the body (applied every rendered
	# frame in _process, so it is smooth at any frame rate and the mouse reacts
	# at once).
	_cam_offset = head - (vehicle.global_position if state == "vehicle" else global_position)
	shake = move_toward(shake, 0.0, delta * 1.5)
	spring.spring_length = lerpf(spring.spring_length, length, minf(1.0, delta * 12.0))
	_cam_low_water = state == "ground" and head.y < Island.WATER + 1.5
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
	model.visible = not scoped() and state != "plane"

var _cam_offset := Vector3(0, 1.6, 0)
## Breathing sway through a magnified scope; Shift holds the breath for a few seconds.
var breath := 1.0               # 1 = rested, 0 = out of breath (held too long)
var holding_breath := false
var view_zoom := 1.0            # magnification of the current view (scopes)
var _sway := Vector2.ZERO
var _sway_t := 0.0
var _cam_low_water := false

func _process(delta: float) -> void:
	if cam_rig == null: return
	if state == "dead" and _dead_camera(delta): return
	var body: Node3D = vehicle if state == "vehicle" and is_instance_valid(vehicle) else self
	var head := body.get_global_transform_interpolated().origin + _cam_offset
	head.y = maxf(head.y, Island.WATER + 0.6)
	cam_rig.global_position = cam_rig.global_position.lerp(head, minf(1.0, delta * 20.0)) if state == "ground" else head
	cam_rig.rotation = Vector3(0, yaw, 0)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.03
	_update_sway(delta)
	cam_pivot.rotation = Vector3(pitch + recoil_kick * 0.004 + _sway.y, _sway.x, -peek * 0.12) + sh
	if _cam_low_water:
		cam_pivot.rotation.x = maxf(cam_pivot.rotation.x, -0.25)   # don't look down into the water

func _update_sway(delta: float) -> void:
	var want := Vector2.ZERO
	holding_breath = false
	if scoped() and view_zoom >= 1.9:
		_sway_t += delta
		holding_breath = Game.settings.controls == "kbm" and Input.is_physical_key_pressed(Game.key("sprint")) and breath > 0.02
		if holding_breath: breath = maxf(0.0, breath - delta / 4.0)
		else: breath = minf(1.0, breath + delta / 3.0)
		var amp: float = 0.0055 * float({"prone": 0.35, "crouch": 0.65}.get(stance, 1.0))
		amp *= 0.12 if holding_breath else 1.0 + (1.0 - breath) * 1.5
		want = Vector2(sin(_sway_t * 0.9) + 0.4 * sin(_sway_t * 2.3), 0.6 * sin(_sway_t * 1.7) + 0.3 * sin(_sway_t * 0.55)) * amp
	else:
		breath = minf(1.0, breath + delta / 3.0)
	_sway = _sway.lerp(want, minf(1.0, delta * 6.0))

## After dying: first the camera turns to whoever killed you (killcam), then
## it can follow another player from behind (spectating). True when handled.
func _dead_camera(delta: float) -> bool:
	if is_instance_valid(spectate):
		var hd := spectate.get_global_transform_interpolated().origin + Vector3(0, 1.6, 0)
		var jump := cam_rig.global_position.distance_to(hd) > 30.0
		cam_rig.global_position = hd if jump else cam_rig.global_position.lerp(hd, minf(1.0, delta * 10.0))
		var ty: float = spectate.yaw if "yaw" in spectate else yaw
		yaw = ty if jump else lerp_angle(yaw, ty, minf(1.0, delta * 4.0))
		cam_rig.rotation = Vector3(0, yaw, 0)
		cam_pivot.rotation = Vector3(-0.15, 0, 0)
		spring.spring_length = lerpf(spring.spring_length, 3.6, minf(1.0, delta * 6.0))
		spring.position.x = 0.5
		camera.fov = lerpf(camera.fov, 70.0, minf(1.0, delta * 6.0))
		return true
	if is_instance_valid(killer):
		# Killcam: stay by your body and turn to face the killer.
		var to := killer.global_position + Vector3(0, 1.2, 0) - cam_rig.global_position
		var ty := atan2(-to.x, -to.z)
		var tp := atan2(to.y, Vector2(to.x, to.z).length())
		yaw = lerp_angle(yaw, ty, minf(1.0, delta * 3.0))
		pitch = lerpf(pitch, clampf(tp, -0.6, 0.5), minf(1.0, delta * 3.0))
		cam_rig.rotation = Vector3(0, yaw, 0)
		cam_pivot.rotation = Vector3(pitch, 0, 0)
		# Zoom in on them if they are far.
		var zoom := clampf(to.length() / 25.0, 1.0, 4.0)
		camera.fov = lerpf(camera.fov, 70.0 / zoom, minf(1.0, delta * 2.0))
		return true
	return false

## Looking through a sight or scope (first person, reticle on screen).
func scoped() -> bool:
	if not aiming or state != "ground": return false
	var w := weapon()
	return w.get("sight", "") != "" or float(w.get("zoom", 1.0)) >= 3.0

func _update_model(delta: float) -> void:
	# Face where the camera looks (or the travel direction while skydiving).
	var target_yaw := yaw
	if state == "fall" and move_input.length() > 0.1 and move_input.y < 0.0:
		target_yaw = yaw    # backing up: keep facing forward
	var ry := lerp_angle(model.rotation.y, target_yaw, minf(1.0, delta * (4.0 if state == "fall" else 12.0)))
	if state == "vehicle" and vehicle:
		# On the driver's seat, facing the front (+Z).
		model.global_transform = vehicle.global_transform * vehicle.seat_xform()
		model.ride = vehicle.kind
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
	model.peek = peek if state == "ground" else 0.0
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
			if vault_t >= 0.0: pose = "crouch"
	var sp := Vector2(velocity.x, velocity.z).length()
	var fwd := Vector3(-sin(ry), 0, -cos(ry))
	var rgt := Vector3(cos(ry), 0, -sin(ry))
	model.move_local = Vector2(velocity.dot(rgt), velocity.dot(fwd))
	model.foot_ik = is_on_floor() and state == "ground"
	model.set_pose(pose, sp, active >= 0 and not knocked, delta, Time.get_ticks_msec() / 1000.0)

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
	u += spares.size() * SPARE_SIZE
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
	if knocked: return
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
## T: the next kind of grenade you carry.
func switch_throw() -> void:
	var order: Array = Items.THROW_ORDER
	var i := order.find(throw_kind)
	for k in range(1, order.size() + 1):
		var nk: String = order[(i + k) % order.size()]
		if throwables[nk] > 0 or k == order.size():
			throw_kind = nk
			break
	message.emit(Items.THROWS[throw_kind])

func start_throw() -> void:
	if state != "ground" or throw_ready or knocked: return
	if throwables[throw_kind] <= 0:
		var other := ""
		for k in Items.THROW_ORDER:
			if throwables[k] > 0:
				other = k
				break
		if other == "":
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
	if v.dead or v.driver != null or knocked: return
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

## Get out (F). From a boat only where you can stand: next to the shore or
## in shallow water. `force` (the vehicle blew up): out anyway, on the
## nearest dry spot.
func exit_vehicle(force := false) -> void:
	if vehicle == null: return
	var v := vehicle
	if v.kind == "boat":
		var spot := _boat_exit_spot(v, force)
		if spot == Vector3.INF:
			message.emit("ما بتقدر تنزل بالمي العميقة — قرّب على الشط")
			return
		v.driver = null
		v.throttle = 0.0
		v.steer_in = 0.0
		vehicle = null
		global_position = spot
		reset_physics_interpolation()
		velocity = Vector3.ZERO
		shape_node.disabled = false
		if state != "dead": state = "ground"
		return
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
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	shape_node.disabled = false
	if state != "dead": state = "ground"

func _boat_exit_spot(v: Vehicle, force: bool) -> Vector3:
	var b := v.global_transform.basis
	for off in [-b.x * 1.6, b.x * 1.6, b.z * 3.0, -b.z * 3.0, -b.x * 2.6, b.x * 2.6, b.z * 4.2]:
		var p: Vector3 = v.global_position + off
		if not world.is_deep(p):
			return Vector3(p.x, maxf(world.ground_height(p), Island.WATER - 1.0) + 0.3, p.z)
	if not force: return Vector3.INF
	for r in range(4, 80, 4):
		for k in 12:
			var p2: Vector3 = v.global_position + Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0)) * r
			if not world.is_deep(p2):
				return Vector3(p2.x, world.ground_height(p2) + 0.3, p2.z)
	return v.global_position

func _drive(_delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.dead:
		exit_vehicle(true)
		return
	global_position = vehicle.global_position + Vector3(0, 0.6, 0)
	velocity = vehicle.linear_velocity
	vehicle.throttle = move_input.y
	vehicle.steer_in = move_input.x
	vehicle.handbrake = jump_queued or (Game.settings.controls == "kbm" and Input.is_physical_key_pressed(Game.key("jump")))
	jump_queued = false

class_name RemotePlayer
extends Bot
## Another person in an online match, as seen here: a body that follows what
## their game reports (where they are, how they stand, what they hold) and
## does no thinking of its own. Hitting it tells their game, which takes the
## damage off (armour, health) and says if they died.

var peer := 0
var _st := {}                     # the last state their game sent
var _to := Vector3.ZERO           # where they are (we ease towards it)
var _to_yaw := 0.0
var _ride: Vehicle = null
var _gear_key := ""
var hit_by_me_t := -100000        # when you last hit them (ms), for kill credit

func setup(w: Node, id: int, info: Dictionary) -> void:
	world = w
	peer = id
	display_name = String(info.get("name", "لاعب"))
	team = 1000 + id
	var outfit := int(info.get("outfit", 0))
	_outfit = outfit

var _outfit := 0

func _ready() -> void:
	super._ready()
	# Their own outfit instead of a random bot's.
	model.queue_free()
	var w: Array = Game.WARDROBE[clampi(_outfit, 0, Game.WARDROBE.size() - 1)]
	var style: String = w[4] if w.size() > 4 else ""
	var who: String = style if HumanModel.CHARACTERS.has(style) else HumanModel.DYE_BASE
	model = HumanModel.new(w[1], Color("f2a900"), w[2], who, not HumanModel.CHARACTERS.has(style))
	add_child(model)
	model.set_gear(0, 0, 0)
	skill = 0.0

## Their game's report (see World.net_my_state).
func apply(st: Dictionary) -> void:
	if dead: return
	_st = st
	_to = st.get("p", global_position)
	_to_yaw = float(st.get("y", yaw))
	if global_position.distance_to(_to) > 25.0 or state == "plane":
		global_position = _to      # a jump (boarding, landing far away): no gliding across the map
	var w: String = st.get("w", "")
	if w != weapon_id:
		weapon_id = w
		model.set_weapon(w)
	var gk := "%d%d%d" % [int(st.get("gv", 0)), int(st.get("gh", 0)), int(st.get("gp", 0))]
	if gk != _gear_key:
		_gear_key = gk
		gear.vest = int(st.get("gv", 0))
		gear.helmet = int(st.get("gh", 0))
		gear.pack = int(st.get("gp", 0))
		model.set_gear(gear.vest, gear.helmet, gear.pack)
	health = float(st.get("h", health))
	knocked = bool(st.get("k", false))

## Hit by you: their game decides what it does to them.
func take_damage(amount: float, attacker: Node, head := false) -> bool:
	if dead: return false
	if attacker != null and attacker == world.player:
		Net.send_hit(peer, amount, head)
		hit_by_me_t = Time.get_ticks_msec()
		world.player.dmg_dealt += minf(amount, maxf(health, 0.0))
		if model.visible: model.hit(amount / 40.0)
	return false

func _physics_process(delta: float) -> void:
	_frame += 1
	if dead:
		if not is_on_floor() and state != "vehicle":
			velocity.y -= GRAVITY * delta
			move_and_slide()
		return
	var s: String = _st.get("s", "plane")
	if s != state:
		if state == "vehicle" and _ride: _leave_ride()
		state = s
		visible = s != "plane"
		shape.disabled = s in ["plane", "fall", "chute"]
	if s == "plane":
		global_position = world.plane_position() + Vector3(0, -3, 0)
		return
	global_position = global_position.lerp(_to, minf(1.0, delta * 12.0))
	velocity = _st.get("v", Vector3.ZERO)
	yaw = lerp_angle(yaw, _to_yaw, minf(1.0, delta * 14.0))
	model.rotation.y = yaw
	if s == "vehicle":
		_ride_step()
		model.set_pose("drive", 0.0, false, delta, world.time)
		return
	if s in ["fall", "chute"]:
		model.dive = float(_st.get("dv", 0.5))
		model.chute_open = 1.0
		model.set_pose(s, 0.0, false, delta, world.time)
		return
	var sp := Vector2(velocity.x, velocity.z).length()
	model.move_local = Vector2(velocity.dot(Vector3(cos(yaw), 0, -sin(yaw))), velocity.dot(Vector3(-sin(yaw), 0, -cos(yaw))))
	model.aiming = bool(_st.get("a", false))
	model.sprinting = bool(_st.get("sp", false))
	model.aim_pitch = float(_st.get("pi", 0.0))
	model.reload_p = float(_st.get("rl", -1.0))
	model.downed = knocked
	model.swimming = bool(_st.get("sw", false))
	model.foot_ik = false
	var stance: String = _st.get("st", "stand")
	if knocked: stance = "prone"
	if not bool(_st.get("fl", true)): stance = "airborne"
	model.vel_y = velocity.y
	model.set_pose(stance, sp, armed() and not knocked, delta, world.time)

## Driving: the car they are in goes where their game says.
func _ride_step() -> void:
	var nid := int(_st.get("vn", -1))
	if _ride == null or not is_instance_valid(_ride) or int(_ride.get_meta("nid", -2)) != nid:
		if _ride: _leave_ride()
		_ride = world.vehicle_by_nid(nid)
		# Never the car you are in yourself, nor one far from where they are.
		if _ride and (_ride == world.player.vehicle or _ride.get_meta("net_driven", false) or _ride.global_position.distance_to(_to) > 12.0): _ride = null
		if _ride:
			_ride.freeze = true
			_ride.set_meta("net_driven", true)
	if _ride:
		var xf: Transform3D = _st.get("vx", _ride.global_transform)
		_ride.global_transform = _ride.global_transform.interpolate_with(xf, 0.35)
		model.global_transform = _ride.global_transform * _ride.seat_xform()
		model.ride = _ride.kind

func _leave_ride() -> void:
	if _ride and is_instance_valid(_ride):
		_ride.freeze = false
		_ride.remove_meta("net_driven")
	_ride = null
	model.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)

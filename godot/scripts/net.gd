extends Node
## Playing with friends (autoload "Net"): one phone or PC hosts a room, the
## others on the same Wi-Fi find it (or type the host's address) and join.
## In the match every player runs their own character and tells the others
## where it is 15 times a second; shots, hits, deaths and picked-up loot are
## sent as they happen. The island, the loot and the safe zone come out the
## same everywhere from the shared seed. The person shot decides the damage
## (their armour, their health), so nobody's game argues with anyone else's.

signal roster_changed
signal rooms_changed
signal failed(text: String)
signal left_room

const PORT := 24680
const FIND_PORT := 24681
const MAX_PLAYERS := 8
const SEND_HZ := 15.0

var active := false               # in a room (lobby or match)
var in_match := false
var is_host := false
var roster := {}                  # peer id -> {name, outfit}
var rooms := {}                   # host address -> {name, players, t}
var match_seed := 0
var weather := "clear"
var map_id := "seasons"
var world: Node = null            # the match, while one is running
var _udp: PacketPeerUDP
var _find: PacketPeerUDP
var _beacon_t := 0.0
var _send_t := 0.0
var _loaded := {}
var _budget := {}                 # peer id -> [shots, hits, since] they may still send this second
const MAX_ROOMS := 16

func me() -> int:
	return multiplayer.get_unique_id() if active else 1

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _close(); failed.emit("ما قدرنا نوصل للغرفة"))
	multiplayer.server_disconnected.connect(func():
		var was_match := in_match
		_close()
		failed.emit("صاحب الغرفة طلع" if not was_match else "انقطع الاتصال مع صاحب الغرفة"))

func _my_info() -> Dictionary:
	return {"name": Game.player_name(), "outfit": int(Game.profile.outfit)}

# ---------------------------------------------------------------- rooms
func host() -> bool:
	_close()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		failed.emit("ما قدرنا نفتح غرفة (البورت %d مشغول؟)" % PORT)
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	roster = {1: _my_info()}
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", FIND_PORT)
	roster_changed.emit()
	return true

func join(address: String) -> bool:
	_close()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address.strip_edges(), PORT) != OK:
		failed.emit("العنوان مش صحيح")
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	return true

func leave() -> void:
	_close()
	left_room.emit()

func _close() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	in_match = false
	is_host = false
	roster = {}
	_loaded = {}
	_budget = {}
	if _udp: _udp.close()
	_udp = null

## Listening for rooms on this network (call while the friends page is open).
func start_finding() -> void:
	if _find: return
	_find = PacketPeerUDP.new()
	if _find.bind(FIND_PORT) != OK: _find = null

func stop_finding() -> void:
	if _find: _find.close()
	_find = null
	rooms.clear()

## This machine's addresses on the local network (to tell friends).
func local_addresses() -> Array:
	var res := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"): res.append(a)
	return res

func _process(delta: float) -> void:
	if is_host and _udp and not in_match:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			_udp.put_packet(JSON.stringify({"zz": 1, "name": clean_name(Game.player_name()), "n": roster.size()}).to_utf8_buffer())
	if _find:
		# Anyone on the network can send these: only a few a frame, only small
		# ones, only so many rooms (a flood must not freeze the friends page).
		var got := 0
		var changed := false
		while _find.get_available_packet_count() > 0 and got < 16:
			got += 1
			var pkt := _find.get_packet().get_string_from_utf8()
			var ip := _find.get_packet_ip()
			if pkt.length() > 512: continue
			var d = JSON.parse_string(pkt)
			if typeof(d) != TYPE_DICTIONARY or not d.has("zz"): continue
			if not rooms.has(ip) and rooms.size() >= MAX_ROOMS: continue
			var n = d.get("n", 1)
			rooms[ip] = {"name": clean_name(d.get("name", "?")), "players": clampi(int(n) if typeof(n) in [TYPE_INT, TYPE_FLOAT] else 1, 0, MAX_PLAYERS), "t": Time.get_ticks_msec()}
			changed = true
		for ip in rooms.keys():
			if Time.get_ticks_msec() - int(rooms[ip].t) > 4000:
				rooms.erase(ip)
				changed = true
		if changed: rooms_changed.emit()
	if in_match and world and is_instance_valid(world) and world.ready_done:
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / SEND_HZ
			var st: Dictionary = world.net_my_state()
			if not st.is_empty(): _state.rpc(st)

func _on_connected() -> void:
	_hello.rpc_id(1, _my_info())

## A connection that never says hello (or is turned away) is dropped, so it
## can't sit in the room taking a seat or send anything into a match.
func _on_peer_connected(id: int) -> void:
	if is_host: get_tree().create_timer(5.0).timeout.connect(_drop_stranger.bind(id))

func _drop_stranger(id: int) -> void:
	if is_host and active and not roster.has(id) and id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)

## A known player in this room (not a stranger who connected without joining).
func known(id: int) -> bool:
	return roster.has(id) and id != me()

## Names come from other people's games: no control or direction marks
## (which could scramble the lists), and short.
static func clean_name(v: Variant) -> String:
	var out := ""
	for ch in str(v).strip_edges():
		var c := ch.unicode_at(0)
		if c < 32 or c == 127 or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069): continue
		out += ch
		if out.length() >= 16: break
	return out if out != "" else "لاعب"

## Each player may send only so many shots and hits a second (the fastest
## gun with every shotgun pellet landing stays well under it).
func _spend(id: int, kind: int) -> bool:
	if not known(id): return false
	var b: Array = _budget.get(id, [])
	if b.is_empty() or Time.get_ticks_msec() - int(b[2]) > 1000:
		b = [40, 60, Time.get_ticks_msec()]
		_budget[id] = b
	if int(b[kind]) <= 0: return false
	b[kind] = int(b[kind]) - 1
	return true

func _on_peer_disconnected(id: int) -> void:
	roster.erase(id)
	_loaded.erase(id)
	_budget.erase(id)
	roster_changed.emit()
	if is_host and not in_match: _roster.rpc(roster)
	if in_match and world and is_instance_valid(world): world.net_peer_left(id)
	if is_host and in_match: _check_all_loaded()

@rpc("any_peer", "reliable")
func _hello(info: Dictionary) -> void:
	if not is_host: return
	var id := multiplayer.get_remote_sender_id()
	if in_match or roster.size() >= MAX_PLAYERS:
		_refuse.rpc_id(id, "الغرفة بلّشت أو مليانة")
		get_tree().create_timer(1.0).timeout.connect(_drop_stranger.bind(id))
		return
	if roster.has(id): return
	var o = info.get("outfit", 0)
	roster[id] = {"name": clean_name(info.get("name", "لاعب")), "outfit": clampi(int(o) if typeof(o) in [TYPE_INT, TYPE_FLOAT] else 0, 0, Game.WARDROBE.size() - 1)}
	_roster.rpc(roster)
	roster_changed.emit()

@rpc("authority", "reliable")
func _refuse(text: String) -> void:
	_close()
	failed.emit(text)

@rpc("authority", "reliable")
func _roster(r: Dictionary) -> void:
	roster = {}
	for k in r:
		if roster.size() >= MAX_PLAYERS: break
		var v = r[k]
		if typeof(k) not in [TYPE_INT, TYPE_FLOAT] or typeof(v) != TYPE_DICTIONARY: continue
		var o = v.get("outfit", 0)
		roster[int(k)] = {"name": clean_name(v.get("name", "لاعب")), "outfit": clampi(int(o) if typeof(o) in [TYPE_INT, TYPE_FLOAT] else 0, 0, Game.WARDROBE.size() - 1)}
	roster_changed.emit()

# ---------------------------------------------------------------- match
## Host: everyone into the match, on the same island.
func start_match() -> void:
	if not is_host: return
	_begin.rpc(randi(), Game.pick_weather(), Game.pick_map())

@rpc("authority", "call_local", "reliable")
func _begin(s: int, w: String, m := "seasons") -> void:
	match_seed = s
	weather = w
	map_id = m if Game.MAPS.has(m) else "seasons"
	in_match = true
	_loaded = {}
	Game.training = false
	Game.spawn_island = true
	Game.settings.mode = "solo"
	get_tree().change_scene_to_file("res://scenes/world.tscn")

## The match finished loading here; the host starts the countdown once
## everyone has.
func loaded() -> void:
	if is_host:
		_loaded[1] = true
		_check_all_loaded()
	else:
		_im_loaded.rpc_id(1)

@rpc("any_peer", "reliable")
func _im_loaded() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host or not in_match or not roster.has(id) or _loaded.has(id): return
	_loaded[id] = true
	_check_all_loaded()

func _check_all_loaded() -> void:
	if _loaded.has(-1): return       # already started
	for id in roster:
		if not _loaded.has(id): return
	_loaded[-1] = true
	_go.rpc()

@rpc("authority", "call_local", "reliable")
func _go() -> void:
	if world and is_instance_valid(world): world.net_go()

@rpc("any_peer", "unreliable_ordered")
func _state(st: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if known(id) and world and is_instance_valid(world): world.net_state(id, st)

func send_shot(from: Vector3, to: Vector3, cls: String, gun: String) -> void:
	if in_match: _shot.rpc(from, to, cls, gun)

@rpc("any_peer", "unreliable")
func _shot(from: Vector3, to: Vector3, cls: String, gun: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _spend(id, 0) and world and is_instance_valid(world): world.net_shot(id, from, to, cls, gun)

## You hit someone: their game takes off the damage.
func send_hit(victim: int, amount: float, head: bool) -> void:
	if in_match: _hit.rpc_id(victim, amount, head)

@rpc("any_peer", "reliable")
func _hit(amount: float, head: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _spend(id, 1) and world and is_instance_valid(world): world.net_hit(id, amount, head)

func send_died(killer: int) -> void:
	if in_match: _died.rpc(killer)

@rpc("any_peer", "reliable")
func _died(killer: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if known(id) and world and is_instance_valid(world): world.net_died(id, killer)

func send_taken(nid: int) -> void:
	if in_match: _taken.rpc(nid)

@rpc("any_peer", "reliable")
func _taken(nid: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if known(id) and world and is_instance_valid(world): world.net_taken(id, nid)

## Back to the lobby after a match: the room stays open for the next one.
func match_over() -> void:
	in_match = false
	world = null
	_loaded = {}
	_budget = {}

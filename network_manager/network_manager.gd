extends Node

# SCENES
const MAIN_MENU_SCENE : String = "res://menu_ui/menu_ui_script/main_menu.tscn"
const LOBBY_SCENE     : String = "res://lobby_ui/lobby.tscn"
const TEMPLE_SCENE    : String = "res://TempleScene/metal_temple.tscn"

# NETWORK
var peer: ENetMultiplayerPeer
const DEFAULT_PORT: int = 8888
const DEFAULT_MAX_CLIENTS: int = 32
const DEFAULT_IP: String = "127.0.0.1"

var game_scene_initialized := false


func _ready() -> void:
	get_tree().tree_changed.connect(_on_scene_changed)

	# MULTIPLAYER SIGNALS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnect)

# # # # # # # # 
# HOST / JOIN #
# # # # # # # # 
func host_game(port: int = DEFAULT_PORT, max_clients: int = DEFAULT_MAX_CLIENTS) -> bool:
	if not _initialize_peer():
		return false
	var err: Error = peer.create_server(port, max_clients)
	if err != OK:
		push_error("Failed to create server on port %d. Error %d" % [port, err])
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	print("Server hosted on port %d (peer ID: %d)" % [port, multiplayer.get_unique_id()])
	return await _load_lobby_scene()

func join_game(ip: String = DEFAULT_IP, port: int = DEFAULT_PORT) -> bool:
	if not _initialize_peer():
		return false
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to connect to %s:%d. Error: %d" % [ip, port, err])
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s:%d" % [ip, port])
	return await _load_lobby_scene()

func _initialize_peer() -> bool:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	peer = ENetMultiplayerPeer.new()
	return true

# # # # # # # # # # # # #
# Scene change handling #
# # # # # # # # # # # # #
func _on_scene_changed() -> void:
	# tree_changed can fire when there's no current_scene yet
	var scene = get_tree().current_scene
	if scene == null:
		return

	# Try to attach signals from main menu if they exist on the scene root
	_connect_main_menu_signals(scene)

	# If the game scene loaded, perform game-scene specific setup
	# (compare name to whatever root node you gave MetalTemple)
	if scene.name == "MetalTemple":
		_on_game_scene_loaded(scene)

func _connect_main_menu_signals(scene: Node) -> void:
	# HOST PRESSED
	if scene.has_signal("host_pressed"):
		if not scene.is_connected("host_pressed", Callable(self, "_on_host_pressed")):
			scene.connect("host_pressed", Callable(self, "_on_host_pressed"))

	# JOIN REQUESTED (String ip)
	if scene.has_signal("join_game_requested"):
		if not scene.is_connected("join_game_requested", Callable(self, "_on_join_game_requested")):
			scene.connect("join_game_requested", Callable(self, "_on_join_game_requested"))

	# START GAME REQUESTED (NOT FUNCTIONAL YET, WIP, MIGHT CHANGE THAT BUTTON COMPLETLY)
	if scene.has_signal("start_game_requested"):
		if not scene.is_connected("start_game_requested", Callable(self, "_on_start_game_requested")):
			scene.connect("start_game_requested", Callable(self, "_on_start_game_requested"))


# Handlers that get called from main menu scene
func _on_start_game_requested() -> void:
	# Optional: if your main_menu emits start_game_requested meaning singleplayer/test,
	# decide what to do here. I'll just log.
	print("Start requested from main menu")

func _on_host_pressed() -> void:
	print("Host pressed — starting host flow")
	host_game()

func _on_join_game_requested(ip: String) -> void:
	print("Join requested to ", ip)
	join_game(ip)

# ----------------
# Lobby / game loading
# ----------------
func _change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
	await get_tree().tree_changed

func _load_lobby_scene() -> bool:
	await _change_scene(LOBBY_SCENE)
	if multiplayer.is_server():
		print("Lobby loaded on server")
	else:
		print("Lobby loaded on client")
	return true

@rpc("authority")
func start_match() -> void:
	# Called by host to start the match. Broadcast to clients and locally load.
	rpc("load_game_map")
	load_game_map()

@rpc("any_peer")
func load_game_map() -> void:
	# All peers will execute this and change to the game map
	get_tree().change_scene_to_file(TEMPLE_SCENE)

# # # # # # # # # # # # # # # # #
# Game scene setup and spawning #
# # # # # # # # # # # # # # # # #
func _on_game_scene_loaded(scene: Node) -> void:
	if game_scene_initialized:
		return
	game_scene_initialized = true
	var spawner := scene.get_node_or_null("MultiplayerSpawner")
	if not spawner:
		push_error("MultiplayerSpawner not found in MetalTemple")
		return
	# Tell the spawner which function to call (Callable to this script)
	spawner.spawn_function = Callable(self, "spawn_player")

	# If server, spawn connected peers + host
	
	if multiplayer.is_server():
		var host_id := multiplayer.get_unique_id()
		# spawn host
		spawner.spawn({"id": host_id, "position": _get_spawn_point(scene, host_id)})
		print(scene, host_id)
		# spawn already connected clients
		for id in multiplayer.get_peers():
			if id == host_id:
				continue
			spawner.spawn({"id": id, "position": _get_spawn_point(scene, id)})
			print(scene, id)

func spawn_player(spawn_data) -> Node:
	# typeof seems to be not rly necessary now, idk xd
	var data: Dictionary
	if typeof(spawn_data) == TYPE_DICTIONARY:
		data = spawn_data

	else:
		push_error("spawn_player: unexpected arg type: %s" % typeof(spawn_data))
		return null

	# Validate
	var id := int(data.get("id", -1))
	var pos = data.get("position", Vector3.ZERO)
	if id == -1:
		push_error("spawn_player: id missing")
		return null

	# Ensure MetalTemple & spawner exist
	var scene := get_tree().current_scene
	if scene == null or scene.name != "MetalTemple":
		push_error("spawn_player: MetalTemple not loaded")
		return null
	var spawner := scene.get_node_or_null("MultiplayerSpawner")
	if not spawner:
		push_error("spawn_player: MultiplayerSpawner not found")
		return null

	# If node already exists in the scene tree, return it
	var node_name := "player_%d" % id
	if scene.has_node(node_name):
		return scene.get_node(node_name)

	# Instantiate player scene (DO NOT add_child here - spawner will add it)
	var player_scene := preload("res://player/player_scene/player.tscn")
	var player := player_scene.instantiate()

	# Configure player BEFORE returning:
	player.name = node_name

	# Set local transform without using get_global_transform() (works while not in tree)
	# Use a fresh transform with identity rotation and desired position:
	player.transform = Transform3D(Basis(), pos)

	# Set network authority
	player.set_multiplayer_authority(id)

	# Try to enable local input if the player exposes a method for it
	# Prefer method to avoid checking properties that may not exist
	if player.has_method("set_input_enabled"):
		player.call("set_input_enabled", id == multiplayer.get_unique_id())
	# If your player uses a boolean property named `input_enabled`, you can set it via set():
	elif player.has_meta("input_enabled") or player.has_method("input_enabled"):
		# best-effort: try setting property (silently fail if not present)
		# Using `set()` avoids checking for non-existent property functions
		var _ok = true
		# wrap in pcall-style try/catch: GDScript has no try, but we can use `Object.set` which will still error if property missing.
		# So we only attempt if the script likely defines it:
		if player.get_script() and player.get_script().has_property("input_enabled"):
			player.set("input_enabled", id == multiplayer.get_unique_id())

	# Return node; MultiplayerSpawner will add it to the scene tree
	return player



# ----------------
# Peer connection/disconnection
# ----------------
func _on_peer_connected(id: int) -> void:
	print("Peer connected:", id)
	# We no longer spawn immediately here; spawning occurs after MetalTemple loads.
	# If you want to notify lobby UI about new peer, rpc or call lobby node here.

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected:", id)
	var scene = get_tree().current_scene
	if scene and scene.name == "MetalTemple":
		var spawner := scene.get_node_or_null("MultiplayerSpawner")
		if spawner:
			var player = spawner.get_node_or_null("player_%d" % id)
			if player:
				player.queue_free()

func _on_connected_to_server() -> void:
	print("Connected to server. My id:", multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	print("Connection failed")

func _on_server_disconnect(id: int) -> void:
	print("Disconnected from server (id %s)" % str(id))

@rpc("authority")
func spawn_existing_player(data: Dictionary) -> void:
	# Called by server to tell clients to spawn already existing players.
	# Implement client-side spawn if necessary (e.g. call spawner.spawn locally).
	var scene = get_tree().current_scene
	if scene == null or scene.name != "MetalTemple":
		push_error("spawn_existing_player called but MetalTemple not loaded")
		return
	var spawner := scene.get_node_or_null("MultiplayerSpawner")
	if not spawner:
		push_error("spawn_existing_player: spawner not found")
		return
	if spawner.get_node_or_null("player_%d" % data.id):
		# already exists: update position
		var existing = spawner.get_node("player_%d" % data.id)
		existing.position = data.position
		return
	spawner.spawn(data)

# # # # # # # # # # # # #
# Spawn point selection #
# # # # # # # # # # # # #
func _get_spawn_point(scene: Node, id: int) -> Vector3:
	# Use HostPlayerSpawn / ClientPlayerSpawn nodes inside MetalTemple
	var host_spawn_node := scene.get_node_or_null("HostPlayerSpawn")
	var client_spawn_node := scene.get_node_or_null("ClientPlayerSpawn")
	if host_spawn_node == null or client_spawn_node == null:
		# fallback to a random-ish position if nodes missing
		return Vector3(randf_range(-3, 3), 3, randf_range(-3, 3))

	# Use server unique id to determine host vs client spawn (simple 1 vs others)
	if id == 1:
		return host_spawn_node.global_position
	else:
		return client_spawn_node.global_position

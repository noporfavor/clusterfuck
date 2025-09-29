extends Node

var peer: ENetMultiplayerPeer
const MAIN_SCENE = preload("res://Main.tscn")
const DEFAULT_PORT: int = 8888
const DEFAULT_MAX_CLIENTS: int = 32
const DEFAULT_IP: String = "127.0.0.1"
func _ready():
	# MULTIPLAYER SIGNALS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnect)
## -----------
## HOST / JOIN
## ------------
func host_game(port: int = DEFAULT_PORT, max_clients:  int = DEFAULT_MAX_CLIENTS) -> bool:
	if not _initialize_peer():
		return false
	var err: Error = peer.create_server(port, max_clients)
	if err != OK:
		push_error("Failed to create server on port %d. Error %d" % [port, err])
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	print("Server hosted on port %d (peer ID: %d)" % [port, multiplayer.get_unique_id()])
	return await _load_main_scene_and_spawn()

func join_game(ip: String = DEFAULT_IP, port : int = DEFAULT_PORT) -> bool:
	if not _initialize_peer():
		return false
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to connect to %s:%d. Error: %d" % [ip, port, err])
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s:%d" % [ip, port])
	return await _load_main_scene_and_spawn()

func _initialize_peer() -> bool:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	peer = ENetMultiplayerPeer.new()
	return true

func _load_main_scene_and_spawn() -> bool:
	var main: Node = await _ensure_main_scene()
	if not main:
		return false
	var spawner: MultiplayerSpawner = await _await_spawner(main)
	if not spawner:
		return false
	if multiplayer.is_server():
		spawn_player(multiplayer.get_unique_id())
	return true

func _ensure_main_scene() -> Node:
	var current_scene: Node = get_tree().current_scene
	if current_scene and current_scene.name != "Main":
		current_scene.queue_free()
		await get_tree().tree_changed
	var main: Node = get_tree().current_scene
	if main == null or main.name != "Main":
		main = MAIN_SCENE.instantiate()
		get_tree().root.add_child(main)
		while get_tree().current_scene == null or get_tree().current_scene.name != "Main":
			await get_tree().process_frame
	return main

func _await_spawner(main: Node) -> MultiplayerSpawner:
	var spawner: MultiplayerSpawner = main.get_node_or_null("MultiplayerSpawner")
	while not spawner:
		print("Waiting for MultiplayerSpawner")
		await get_tree().process_frame
		spawner = main.get_node_or_null("MultiplayerSpawner")
	return spawner

func spawn_player(id: int) -> void:
	if not multiplayer.is_server():
		return
	var main := _get_main_scene()
	if main == null:
		push_error("Main scene not found")
		return
	var spawner = main.get_node("MultiplayerSpawner")
	if not spawner:
		push_error("MultiplayerSpawner not found")
		return
	if spawner.get_node_or_null("player_" + str(id)):
		print("Player_%d already exists, skipping spawn" % id)
		return
	var spawn_data = {"id": id, "position": _get_spawn_point(main)}
	spawner.spawn(spawn_data)
	print("Spawned player_%d at %s on peer %d" % [id, spawn_data.position, multiplayer.get_unique_id()])

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Server: peer connected", id)
	spawn_player(id)
	var main := _get_main_scene()
	if main:
		for node in main.get_children():
			if node.name.begins_with("player_"):
				var pid = int(node.name.replace("player_", ""))
				if pid != id:
					var spawn_data = {"id": pid, "position": node.position}
					rpc_id(id, "spawn_existing_player", spawn_data)

func _on_peer_disconnected(id: int):
	print("Peer disconnected", id)
	var main := _get_main_scene()
	if main == null:
		return
	var player: Node = main.get_node_or_null("player_%d" % id)
	if player:
		player.queue_free()

func _on_connected_to_server():
	print("Client connected to host. My id:", multiplayer.get_unique_id())
	await  get_tree().create_timer(0.3).timeout
	var main = _get_main_scene()
	if main:
		var spawner = main.get_node("MultiplayerSpawner")
		while not spawner:
			print("Client waiting for MultiplayerSpawner")
			await get_tree().process_frame
			spawner = main.get_node("MultiplayerSpawner")

func _on_connection_failed():
	print("Connection failed")
	var main := _get_main_scene()
	if main:
		get_tree().change_scene_to_file("res://Main.tscn")

func _on_server_disconnect(id: int):
	print("Disconnected from server")
	var main := _get_main_scene()
	if main == null:
		return
	var player: Node = main.get_node_or_null("player_%d" % id)
	if player:
		player.queue_free()

@rpc("authority")
func spawn_existing_player(data: Dictionary):
	var main := _get_main_scene()
	if main == null:
		push_error("Main scene not found on client")
		return
	var spawner = main.get_node("MultiplayerSpawner")
	if not spawner:
		push_error("MultiplayerSpawner not found on client")
		return
	if spawner.get_node_or_null("player_" + str(data.id)):
		print("Client: player_%d already exists, skipping spawn" % data.id)
		var player = spawner.get_node("player_" + str(data.id))
		player.position = data.position
		return
	print("Client spawning existing player_%d at %s on peer %d" % [data.id, data.position, multiplayer.get_unique_id()])

func _get_main_scene() -> Node:
	var main = get_tree().current_scene
	print("Current scene on peer %d: %s" % [multiplayer.get_unique_id(), main.name if main else null])
	if main == null or main.name != "Main":
		push_error("Main scene not found or incorrect", main.name if main else null)
	print("Current scene: ", main.name if main else null)
	return main

func _get_spawn_point(_main: Node) -> Vector3:
	return Vector3(randf_range(-3, 3), 3, randf_range(-3, 3))

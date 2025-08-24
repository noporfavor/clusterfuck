extends Node

var peer: ENetMultiplayerPeer
const MAIN_SCENE = preload("res://Main.tscn")
func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnect)
## -----------
## HOST / JOIN
## ------------
func host_game(port := 8888, max_clients := 32) -> void:
	if multiplayer == null:
		return
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, max_clients)
	if err != OK:
		push_error("Failed to create ENet server on port %d. create_server returned: %d" % [port, err])
		peer = null
		return
	multiplayer.multiplayer_peer = peer
	var my_id := multiplayer.get_unique_id()
	print("Server hosted on port %d (peer id = %d)" % [port, my_id])
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.name != "Main":
		current_scene.queue_free()
		await get_tree().tree_changed
	var main = get_tree().current_scene
	if main == null or main.name != "Main":
		main = MAIN_SCENE.instantiate()
		get_tree().root.add_child(main)
		get_tree().current_scene = main
	while get_tree().current_scene == null or get_tree().current_scene.name != "Main":
		@warning_ignore("incompatible_ternary")
		print("Waiting for Main scene, current: %s" % (get_tree().current_scene.name if get_tree().current_scene else null))
		await get_tree().process_frame
	print("Main scene set on peer %d" % my_id)
	var spawner = main.get_node("MultiplayerSpawner")
	while not spawner:
		print("Waiting for MultiplayerSpawner")
		await get_tree().process_frame
		spawner = main.get_node("MultiplayerSpawner")
	spawn_player(my_id)
func join_game(ip:= "127.0.0.1", port := 8888) -> void:
	var main = get_tree().current_scene
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, port)
	print("error:", err)
	if err != OK:
		push_error("Fail to create ENet client to %s:%d. create_client returned: %d" % [ip, port, err])
		peer = null
		return 
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s port %d" % [ip, port])
	if main == null or main.name != "Main":
		if main:
			main.queue_free()
			await get_tree().tree_changed
		main = MAIN_SCENE.instantiate()
		get_tree().root.add_child(main)
		get_tree().current_scene = main
	while get_tree().current_scene == null or get_tree().current_scene.name != "Main":
		@warning_ignore("incompatible_ternary")
		print("Client waiting for Main scene, current: %s" % (get_tree().current_scene.name if get_tree().current_scene else null))
		await get_tree().process_frame
	var spawner = main.get_node("MultiplayerSpawner")
	while not spawner:
		print("Client waiting for MultiplayerSpawner")
		await get_tree().process_frame
		spawner = main.get_node("MultiplayerSpawner")
func spawn_player(id: int) -> void:
	if not multiplayer.is_server():
		return
	var main := _get_main()
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
	var main := _get_main()
	if main:
		for node in main.get_children():
			if node.name.begins_with("player_"):
				var pid = int(node.name.replace("player_", ""))
				if pid != id:
					var spawn_data = {"id": pid, "position": node.position}
					rpc_id(id, "spawn_existing_player", spawn_data)
func _on_peer_disconnected(id: int):
	print("Peer disconnected", id)
	var main := _get_main()
	if main == null:
		return
	var n := main.get_node_or_null("player_%d" % id)
	if n:
		n.queue_free()
func _on_connected_to_server():
	print("Client connected to host. My id:", multiplayer.get_unique_id())
	await  get_tree().create_timer(0.3).timeout
	var main = _get_main()
	if main:
		var spawner = main.get_node("MultiplayerSpawner")
		while not spawner:
			print("Client waiting for MultiplayerSpawner")
			await get_tree().process_frame
			spawner = main.get_node("multiplayerSpawner")
func _on_connection_failed():
	print("Connection failed")
	var main := _get_main()
	if main:
		get_tree().change_scene_to_file("res://Main.tscn")
func _on_server_disconnect(id: int):
	print("Disconnected from server")
	var main := _get_main()
	if main == null:
		return
	var n := main.get_node_or_null("player_%d" % id)
	if n:
		n.queue_free()
@rpc("authority")
func spawn_existing_player(data: Dictionary):
	var main := _get_main()
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
	#var parent = spawner.get_node(spawner.get_spawn_path())
	#var node = spawner.get_spawn_function().call(data)
	#if node:
		#parent.add_child(node)
	print("Client spawning existing player_%d at %s on peer %d" % [data.id, data.position, multiplayer.get_unique_id()])
func _get_main() -> Node:
	var main = get_tree().current_scene
	print("Current scene on peer %d: %s" % [multiplayer.get_unique_id(), main.name if main else null])
	if main == null or main.name != "Main":
		push_error("Main scene not found or incorrect", main.name if main else null)
	print("Current scene: ", main.name if main else null)
	return main
func _get_spawn_point(_main: Node) -> Vector3:
	return Vector3(randf_range(-5, 5), 5, randf_range(-5, 5))

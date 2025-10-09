extends Node3D
@onready var menu_ui: CanvasLayer = $MainMenu
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
var menu_visible := true
func _ready() -> void:
	for node in get_children():
		if node.name.begins_with("player_"):
			node.queue_free()
	print("Main scene initialized on peer: %d" % multiplayer.get_unique_id())
	multiplayer_spawner.spawn_function = _spawn_player
	multiplayer_spawner.spawned.connect(_on_spawner_spawned)
	menu_ui.start_game_requested.connect(_on_start_game_pressed)
	menu_ui.join_game_requested.connect(_on_join_game_pressed)
	menu_ui.host_pressed.connect(_on_host_presssed)
	_show_menu(true)
func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		_toggle_menu()
func _toggle_menu():
	_show_menu(!menu_visible)
@warning_ignore("shadowed_variable_base_class")
func _show_menu(visible: bool):
	menu_visible = visible
	menu_ui.visible = visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	_update_player_input(!visible)
func _update_player_input(enabled: bool) -> void:
	var local_player := get_node_or_null("player_%d" % multiplayer.get_unique_id())
	if local_player and "input_enabled" in local_player:
		local_player.input_enabled = enabled
func _spawn_player(data: Dictionary) -> Node:
	var id = data.id
	var pos = data.position
	print("Spawning player for id: %d at %s on peer: %d" % [id, pos, multiplayer.get_unique_id()])
	if has_node("player_" + str(id)):
		var existing = get_node("player_" + str(id))
		print("Player %d already exists at %s" % [id, existing.position])
		return existing
	var player = preload("res://player/player_scene/player.tscn").instantiate()
	player.name = "player_" + str(id)
	player.position = pos
	player.set_multiplayer_authority(id)
	if "input_enabled" in player:
		player.input_enabled = (id == multiplayer.get_unique_id())
	return player
func _on_spawner_spawned(node: Node):
	print("Spawner created node %s on peer %d" % [node.name, multiplayer.get_unique_id()])
# --- CLIENT ---
func _on_start_game_pressed():
	_show_menu(false)
func _on_host_presssed():
	NetworkManager.host_game()
	_show_menu(false)
func _on_join_game_pressed(ip: String):
	NetworkManager.join_game(ip)
	_show_menu(false)
	print("Join requested to ", ip)
func _on_void_fall_body_entered(body: Node3D) -> void:
	if multiplayer.is_server() and body.is_in_group("player"):
		body.rpc("apply_damage", 200)

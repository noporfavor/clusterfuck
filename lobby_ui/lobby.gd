extends Node

@onready var player_list: VBoxContainer = $UI/PlayerList
@onready var ready_button: Button = $UI/ReadyButton
@onready var start_button: Button = $UI/StartMatch

var players_ready := {}
var local_ready := false

func _ready():
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	
	# list for connected peers
	_refresh_player_list()

	# connect multiplayer events
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _refresh_player_list():
	# remove old UI entries
	for child in player_list.get_children():
		child.queue_free()

	# add local player
	_add_player(multiplayer.get_unique_id(), local_ready)

	# add connected peers
	for peer_id in multiplayer.get_peers():
		_add_player(peer_id, players_ready.get(peer_id, false))

func _add_player(id: int, is_ready: bool):
	var label = Label.new()
	label.name = "player_%d" % id
	label.text = "Player %d — %s" % [id, ("READY" if is_ready else "NOT READY")]
	player_list.add_child(label)

func _on_peer_connected(id: int):
	players_ready[id] = false
	_refresh_player_list()

func _on_peer_disconnected(id: int):
	players_ready.erase(id)
	_refresh_player_list()

func _on_ready_pressed():
	local_ready = true
	ready_button.disabled = true

	# notify all peers
	rpc("rpc_set_ready", multiplayer.get_unique_id())

	_update_own_label()

func _update_own_label():
	var my_id := multiplayer.get_unique_id() if multiplayer else 1
	var node_name := "player_%d" % my_id
	var label = player_list.get_node_or_null(node_name)
	if label:
		label.text = "You  -  READY" if local_ready else "You  -  Not ready"
	else:
		push_warning("Own player label not found: %s" % node_name)

@rpc("any_peer", "call_local")
func rpc_set_ready(id: int):
	players_ready[id] = true
	_refresh_player_list()

	if multiplayer.is_server():
		_check_all_ready()
func _check_all_ready():
	if not local_ready:
		return

	# every connected peer check
	for peer_id in multiplayer.get_peers():
		if not players_ready.get(peer_id, false):
			return  # weones still not ready

	start_button.disabled = false

func _on_start_pressed():
	NetworkManager.start_match()

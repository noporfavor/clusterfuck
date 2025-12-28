extends Node

signal scores_updated(scores)
signal kill_event(killer_id: int, victim_id: int)
signal player_list_changed
signal match_started(duration: float)
signal match_time_updated(time_left: float)
signal match_ended(winner_peer_id: int)

var match_running := false
var match_duration := 180
var match_time_left := 0.0
var kill_limit := 2
var scores := {} # Dictionary: peer_id -> {kills: 0, deaths: 0, name: ""}
var player_names := {}

func _ready():
	if multiplayer.is_server():
		print("[MatchManager] Server ready")
	else:
		print("[MatchManager] Client ready")

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not match_running:
		return

	match_time_left -= delta

	if match_time_left <= 0.0:
		match_time_left = 0.0
		end_match()
	else:
		rpc("client_sync_time", match_time_left)

func start_match():
	if not multiplayer.is_server():
		return
	match_running = true
	match_time_left = match_duration
	print("[MatchManager] Match started")
	rpc("client_match_started", match_duration)

@rpc("authority", "call_local", "reliable")
func client_match_started(duration: float):
	match_running = true
	match_time_left = duration
	emit_signal("match_started", duration)

@rpc("authority", "call_local", "unreliable")
func client_sync_time(time_left: float):
	match_time_left = time_left
	emit_signal("match_time_updated", time_left)

func register_player(peer_id: int, _name: String = ""):
	if _name != "":
		player_names[peer_id] = _name
		print("[MatchManager] Registered ", peer_id, " → ", _name)

	if not scores.has(peer_id):
		scores[peer_id] = {
			"kills": 0,
			"deaths": 0
		}

	player_list_changed.emit()

@rpc("authority" ,"reliable")
func sync_player_names(names: Dictionary):
	player_names = names.duplicate(true)
	player_list_changed.emit()

func ensure_player_exists(peer_id: int):
	if not scores.has(peer_id):
		scores[peer_id] = {
			"kills": 0,
			"deaths": 0
		}
		emit_signal("scores_updated", scores)
		player_list_changed.emit()

func get_player_name(peer_id: int) -> String:
	return player_names.get(peer_id, "Player %d" % peer_id)

@rpc("authority", "reliable")
func report_death(victim_id: int, killer_id: int) -> void:
	if not scores.has(victim_id):
		return
	if killer_id != 0 and not scores.has(killer_id):
		return

	scores[victim_id]["deaths"] += 1

	# KILL only if not SUICIDE
	if killer_id != 0 and killer_id != victim_id:
		scores[killer_id]["kills"] += 1
		broadcast_kill.rpc(killer_id, victim_id)

		if scores[killer_id]["kills"] >= kill_limit:
			end_match()
			return
	else:
		# suicide or unknown
		broadcast_kill.rpc(0, victim_id)

	rpc("client_sync_scores", scores)
	print("[MatchManager] Scores updated:", scores)

@rpc("authority", "call_local", "reliable")
func broadcast_kill(killer_id: int, victim_id: int):
	emit_signal("kill_event", killer_id, victim_id)

@rpc("any_peer", "call_local", "reliable")
func client_sync_scores(new_scores: Dictionary) -> void:
	scores = new_scores.duplicate(true)
	emit_signal("scores_updated", scores)

func _get_winner_peer_id() -> int:
	var best_id := -1
	var best_kills := -1

	for peer_id in scores.keys():
		var kills = scores[peer_id].get("kills", 0)
		if kills > best_kills:
			best_kills = kills
			best_id = peer_id

	return best_id

@rpc("authority", "call_local", "reliable")
func client_match_ended(winner_peer_id: int):
	match_running = false
	emit_signal("match_ended", winner_peer_id)

func end_match():
	if not multiplayer.is_server():
		return

	match_running = false

# this should be name of player instead of id, at least later, for showing on screen.
	var winner_id := _get_winner_peer_id()

	print("[MatchManager] Match ended. Winner:", winner_id)

	rpc("client_match_ended", winner_id)

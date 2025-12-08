extends Node

signal scores_updated(scores)

var scores := {} # Dictionary: peer_id -> {kills: 0, deaths: 0, name: ""}

# optional~ initialize from connected peers
func _ready():
	pass

# called by player when they die (CLIENTS call this on SERVER)
@rpc("any_peer", "reliable")
func report_death(victim_id: int, killer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if not scores.has(victim_id):
		scores[victim_id] = { "kills": 0, "deaths": 0, "name": "player_%d" % victim_id }
	if killer_id != 0 and not scores.has(killer_id):
		scores[killer_id] = { "kills": 0, "deaths": 0, "name": "player_%d" % killer_id }

# decide SUICIDE or normal KILL
	if killer_id == 0 or killer_id == victim_id:
		scores[victim_id]["deaths"] += 1
	else:
		scores[victim_id]["deaths"] += 1
		scores[killer_id]["kills"] += 1

	rpc("client_sync_scores", scores)

# called on clients (and server too) to update local copies
@rpc("any_peer", "call_local", "reliable")
func client_sync_scores(new_scores: Dictionary) -> void:
	scores = new_scores.duplicate(true)
	emit_signal("scores_updated", scores)

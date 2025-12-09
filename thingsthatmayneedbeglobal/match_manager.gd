extends Node

signal scores_updated(scores)

var scores := {} # Dictionary: peer_id -> {kills: 0, deaths: 0, name: ""}


func register_player(peer_id: int):
	if not scores.has(peer_id):
		scores[peer_id] = {
			"kills": 0,
			"deaths": 0
		}

@rpc("authority", "reliable")
func report_death(victim_id: int, killer_id: int) -> void:
	register_player(victim_id)
	if killer_id != 0:
		register_player(killer_id)

# decide SUICIDE or KILL
	if killer_id == 0 or killer_id == victim_id:
		scores[victim_id]["deaths"] += 1
	else:
		scores[victim_id]["deaths"] += 1
		scores[killer_id]["kills"] += 1

	rpc("client_sync_scores", scores)

@rpc("any_peer", "call_local", "reliable")
func client_sync_scores(new_scores: Dictionary) -> void:
	scores = new_scores.duplicate(true)
	emit_signal("scores_updated", scores)

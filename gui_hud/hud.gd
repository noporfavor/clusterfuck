extends CanvasLayer

const MAX_KILL_FEED_ENTRIES := 3

@onready var control: Control = $Control
@onready var mini_score_vbox: VBoxContainer = $Control/MiniScore
@onready var top_players: VBoxContainer = $Control/TopPlayers
@onready var full_score_panel: Panel = $Control/FullScoreBoard
@onready var full_score_list: VBoxContainer = $Control/FullScoreBoard/ScoreList
@onready var health_label: Label = $Control/HealthLabel
@onready var ammo_label: Label = $Control/AmmoLabel
@onready var match_timer_label: Label = $Control/MatchTimerLabel

var local_peer_id: int = -1

func _ready() -> void:
	full_score_panel.visible = false
	MatchManager.kill_event.connect(_on_kill_event)
	MatchManager.scores_updated.connect(update_scoreboard)
	MatchManager.match_time_updated.connect(_on_match_time_updated)
	MatchManager.match_ended.connect(_on_match_ended)
	setup_local(multiplayer.get_unique_id())

func _on_kill_event(killer_id: int, victim_id: int) -> void:
	var kill_feed := $Control/MiniScore
	var victim_name = MatchManager.get_player_name(victim_id)
	var text := ""
	if killer_id == 0 or killer_id == victim_id:
		text = "%s DIED" % victim_name
	else:
		var killer_name = MatchManager.get_player_name(killer_id) 
		text = "%s KILLED %s" % [killer_name, victim_name]

	var label := Label.new()
	label.text = text
	kill_feed.add_child(label)

	while kill_feed.get_child_count() > MAX_KILL_FEED_ENTRIES:
		kill_feed.get_child(0).queue_free()

	_remove_kill_entry(label, 5.0)

func _remove_kill_entry(label: Label, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(label):
		label.queue_free()

func setup_local(_peer_id: int) -> void:
	local_peer_id = _peer_id
	name = "HUD"  # get_node("HUD") for later usage~
	_apply_local_highlight()

func set_health(new_health: int) -> void:
	health_label.text = "HP: %d" % new_health

func set_ammo(new_ammo: int, max_ammo: int) -> void:
	ammo_label.text = "%d / %d" % [new_ammo, max_ammo]

func update_scoreboard(scores: Dictionary) -> void:
	_update_full(scores)
	_apply_local_highlight()
	_update_top_players(scores)

func _update_top_players(scores: Dictionary) -> void:
	_clear(top_players)

	var arr := []
	for peer_id in scores.keys():
		var entry = scores[peer_id]
		arr.append({
			"peer_id": peer_id,
			"kills": entry.get("kills", 0)
		})

	arr.sort_custom(func(a,b):
		return a.kills > b.kills
		)

	if arr.size() == 0:
		return

	var left = arr[0]
	var right
	if arr.size() > 1: right = arr[1] 
	else: right = null

	var text := ""

	if right:
		text = "%d %s | %s %d" % [
			left.kills,
			MatchManager.get_player_name(left.peer_id),
			MatchManager.get_player_name(right.peer_id),
			right.kills
		]
	else:
		text = "%d %s" % [
			left.kills,
			MatchManager.get_player_name(left.peer_id)
		]

	var label := Label.new()
	label.text = text
	top_players.add_child(label)

func _update_full(scores: Dictionary) -> void:
	_clear(full_score_list)
	var arr := []
	for peer_id in scores.keys():
		var entry = scores[peer_id]
		arr.append({
	"peer_id": peer_id,
	"kills": entry.get("kills", 0),
	"deaths": entry.get("deaths", 0)
	})

# sort by kills, then deaths
	arr.sort_custom(Callable(self, "_sort_scores_desc"))
	for e in arr:
		var h = HBoxContainer.new()
		h.set_meta("peer_id", e.peer_id)
		var label = Label.new()
		var player_name = MatchManager.get_player_name(e.peer_id)
		label.text = "%s — Kills: %d  Deaths: %d" % [player_name, e.kills, e.deaths]
		h.add_child(label)
		full_score_list.add_child(h)

func _apply_local_highlight() -> void:
	if local_peer_id == -1:
		return

	for row in full_score_list.get_children():
		if not row.has_meta("peer_id"):
			continue

		var label := row.get_child(0) as Label
		if not label:
			continue

		if row.get_meta("peer_id") == local_peer_id:
			label.add_theme_color_override(
				"font_color",
				Color(1.0, 0.9, 0.0)
			)
		else:
			label.remove_theme_color_override("font_color")

func _on_match_time_updated(time_left: float) -> void:
	var seconds := int(time_left)
	@warning_ignore("integer_division")
	var minutes := seconds / 60
	var rem := seconds % 60
	match_timer_label.text = "%02d:%02d" % [minutes, rem]

func _on_match_ended(winner_peer_id: int) -> void:
	var winner_name = MatchManager.get_player_name(winner_peer_id)
	match_timer_label.text = "WINNER: %s" % winner_name


func _sort_scores_desc(a: Dictionary, b: Dictionary) -> bool:
	# most kills top leaderboard
	if a.kills != b.kills:
		return a.kills > b.kills
	# even kills show less deaths on top
	if a.deaths != b.deaths:
		return a.deaths < b.deaths

	return a.peer_id < b.peer_id

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func toggle_scoreboard():
	full_score_panel.visible = true
func troggle_scoreboard():
	full_score_panel.visible = false

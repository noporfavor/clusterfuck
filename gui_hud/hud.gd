extends CanvasLayer

@onready var control: Control = $Control
@onready var mini_score_vbox: VBoxContainer = $Control/MiniScore
@onready var top_players: VBoxContainer = $Control/MiniScore/TopPlayers
@onready var full_score_panel: Panel = $Control/FullScoreBoard
@onready var full_score_list: VBoxContainer = $Control/FullScoreBoard/ScoreList
@onready var health_label: Label = $Control/HealthLabel
@onready var ammo_label: Label = $Control/AmmoLabel

var local_peer_id: int = 0

func _ready() -> void:
	full_score_panel.visible = false

func setup_local(_peer_id: int) -> void:
	local_peer_id = _peer_id
	name = "HUD"  # get_node("HUD") for later usage~

func set_health(new_health: int) -> void:
	health_label.text = "HP: %d" % new_health

func set_ammo(new_ammo: int, max_ammo: int) -> void:
	ammo_label.text = "%d / %d" % [new_ammo, max_ammo]

func update_scoreboard(scores: Dictionary) -> void:
	_update_full(scores)
	_update_mini(scores)

func _update_full(scores: Dictionary) -> void:
	_clear(full_score_list)
	var arr := []
	for peer_id in scores.keys():
		var entry = scores[peer_id]
		arr.append({ "peer_id": peer_id, "kills": entry.get("kills", 0), "deaths": entry.get("deaths", 0), "name": entry.get("name", "player_%d" % peer_id) })
# sort by kills, then deaths
	arr.sort_custom(Callable(self, "_sort_scores_desc"))
	for e in arr:
		var h = HBoxContainer.new()
		var label = Label.new()
		var text = "%s — K: %d  D: %d" % [e.name, e.kills, e.deaths]
		label.text = text
# highlight local player
		if e.peer_id == local_peer_id:
			label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0)) # golden highlight
		h.add_child(label)
		full_score_list.add_child(h)

func _sort_scores_desc(a: Dictionary, b: Dictionary) -> bool:
	if a.kills == b.kills:
		return int(a.deaths - b.deaths) # fewer deaths first
	return int(b.kills - a.kills)

# this prob not really needed~(?)
func _update_mini(scores: Dictionary) -> void:
	_clear(mini_score_vbox) 
	var arr := []
	for peer_id in scores.keys():
		var entry = scores[peer_id]
		arr.append({ "peer_id": peer_id, "kills": entry.get("kills", 0), "deaths": entry.get("deaths", 0), "name": entry.get("name", "player_%d" % peer_id) })
	arr.sort_custom(Callable(self, "_sort_scores_desc"))
	var max_show = min(3, arr.size())
	for i in range(max_show):
		var e = arr[i]
		var l = Label.new()
		l.text = "%d. %s — %d" % [i + 1, e.name, e.kills]
		if e.peer_id == local_peer_id:
			l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
		mini_score_vbox.add_child(l)

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func toggle_scoreboard():
	full_score_panel.visible = true
func troggle_scoreboard():
	full_score_panel.visible = false

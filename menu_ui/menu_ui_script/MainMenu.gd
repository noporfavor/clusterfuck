extends CanvasLayer

signal start_game_requested
signal join_game_requested(ip_address: String)
signal host_pressed
@onready var start_button: Button = $Panel/Control/BoxContainer/StartGame
@onready var host_button: Button = $Panel/Control/BoxContainer/HostGame
@onready var exit_button: Button = $Panel/Control/BoxContainer/ExitGame
@onready var join_button: Button = $Panel/Control/BoxContainer/JoinGame
@onready var ip_input: LineEdit = $Panel/Control/BoxContainer/IPAddress

func _ready():
	start_button.pressed.connect(_on_start_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
func _on_start_pressed():
	start_game_requested.emit()
func _on_host_pressed():
	host_pressed.emit()
func _on_join_pressed():
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		print("Enter valid IP")
		return
	join_game_requested.emit(ip)
func _on_exit_pressed():
	get_tree().quit()

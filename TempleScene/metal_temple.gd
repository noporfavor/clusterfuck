extends Node3D

var player_scene = preload("res://player/player_scene/player.tscn") 
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var client_player_spawn: Node3D = $ClientPlayerSpawn
@onready var host_player_spawn: Node3D = $HostPlayerSpawn

#func _ready():
	#pass
#func _spawn_all_players():
	#pass
#func _spawn_player(id):
	#pass

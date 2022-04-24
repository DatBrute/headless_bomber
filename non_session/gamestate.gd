extends Node

# Default game server port. Can be any number between 1024 and 49151.
# Not on the list of registered or common ports as of November 2020:
# https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
const DEFAULT_PORT = 10567

# Max number of players.
const MAX_PEERS = 12



var peer = null

# Name for my player.
var player_name = "The Warrior"


class Player:
	var id: int
	var name: String
# List of players indexed by side
var players = []
var players_ready = []
var maps = []
var map = 0

# Signals to let lobby GUI know what's going on.
signal player_list_changed()
signal map_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what)

# Callback from SceneTree.
func _player_connected(id):
	# Registration of a client beings here, tell the connected player that we are here.
	rpc_id(id, StringName("register_player"), player_name)


# Callback from SceneTree.
func _player_disconnected(id):
	if has_node("/root/World"): # Game is in progress.
		if multiplayer.is_server():
			game_error.emit("Player " + find_player_by_id(id).name + " disconnected")
			end_game()
		else:
			game_error.emit("Player " + find_player_by_id(id).name + " disconnected")
			end_game()
	else: # Game is not in progress.
		# Unregister this player.
		unregister_player(id)


# Callback from SceneTree, only for clients (not server).
func _connected_ok():
	# We just connected to a server
	connection_succeeded.emit()


# Callback from SceneTree, only for clients (not server).
func _server_disconnected():
	game_error.emit("Server disconnected")
	end_game()


# Callback from SceneTree, only for clients (not server).
func _connected_fail():
	multiplayer.set_multiplayer_peer(null) # Remove peer
	connection_failed.emit()


# Lobby management functions.
@rpc(any_peer)
func register_player(new_player_name):
	var id = multiplayer.get_remote_sender_id()
	# if it's the server, do not add it, but the list has still changed by us existing
	if(id != 1):
		var player = Player.new()
		player.id = id
		player.name = new_player_name
		players += [player]
	player_list_changed.emit()


func unregister_player(id):
	players.erase(find_player_by_id(id))
	player_list_changed.emit()


@rpc(call_local)
func load_world():
	# Change scene.
	var map_path = maps[0] if map == -1 else maps[map]
	var world = load(map_path).instantiate()
	get_tree().get_root().add_child(world)
	get_tree().get_root().get_node("Lobby").hide()

	# Set up score.
	world.get_node("Score").add_player(multiplayer.get_unique_id(), player_name)
	for player in players:
		world.get_node("Score").add_player(player.id, player.name)
	get_tree().set_pause(false) # Unpause and unleash the game!


func host_game(new_player_name):
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	peer.create_server(DEFAULT_PORT, MAX_PEERS)
	multiplayer.set_multiplayer_peer(peer)


func join_game(ip, new_player_name):
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, DEFAULT_PORT)
	multiplayer.set_multiplayer_peer(peer)


func get_player_list():
	var ret = []
	for player in players:
		ret += [player.name]
	return ret


func get_player_name():
	return player_name

@rpc(any_peer)
func set_map(index):
	map = index
	map_changed.emit(index)

@rpc(any_peer)
func begin_game():
	if(not multiplayer.is_server()):
		return
	rpc("load_world")

	var world = get_tree().get_root().get_node("World")
	# BEGIN GAME-SPECIFIC CODE
	var player_scene = load("res://player.tscn")

	# Create a dictionary with peer id and respective spawn points, could be improved by randomizing.
	var spawn_points = {}
#	spawn_points[1] = 0 # Server in spawn point 0.
	var spawn_point_idx = 0
	for p in players:
		spawn_points[p.id] = spawn_point_idx
		spawn_point_idx += 1

	for p_id in spawn_points:
		var spawn_pos = world.get_node("SpawnPoints/" + str(spawn_points[p_id])).position
		var player = player_scene.instantiate()
		player.synced_position = spawn_pos
		player.name = str(p_id)
		player.set_player_name(player_name if p_id == multiplayer.get_unique_id() 
			else find_player_by_id(p_id).name)
		world.get_node("Players").add_child(player)
	# END GAME-SPECIFIC-CODE

func find_player_by_id(id):
	for player in players:
		if player.id == id:
			return player
	push_error("Player not found!")


func end_game():
	if has_node("/root/World"): # Game is in progress.
		# End it
		get_node("/root/World").queue_free()

	game_ended.emit()
	players.clear()


func _ready():
	multiplayer.peer_connected.connect(_player_connected)
	multiplayer.peer_disconnected.connect(_player_disconnected)
	multiplayer.connected_to_server.connect(_connected_ok)
	multiplayer.connection_failed.connect(_connected_fail)
	multiplayer.server_disconnected.connect(_server_disconnected)
	maps = dir_contents("res://maps/current")

func dir_contents(path):
	var dir = Directory.new()
	if dir.open(path) == OK:
		dir.list_dir_begin()
		var ret = []
		var file_name = dir.get_next()
		while file_name != "":
			ret += [path + "/" + file_name]
			file_name = dir.get_next()
		return ret
	else:
		push_error("directory not found")

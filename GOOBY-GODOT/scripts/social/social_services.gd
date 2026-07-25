class_name SocialServices
extends Node
## Sammel-Knoten für die W3c-Social-Services (Besuche, Brettspiel, GoobyPal).
## Gewünscht als Autoload "Social" (project-godot-requests.md); bis der
## Orchestrator ihn einträgt, hängt get_or_create() den Knoten lazy unter
## /root — beide Wege liefern DENSELBEN Zustand. Verkabelt sich in _ready()
## selbst mit /root/Net (W2d) und /root/GameState (W1d); ohne die Autoloads
## (Unit-Tests) bleibt alles passiv und setup() wird von Hand gerufen.

const NODE_NAME := "SocialServices"

var visit: VisitService
var board: BoardSession
var pal: GoobyPalService

var _wired := false


static func get_or_create(root: Node) -> SocialServices:
	var autoload := root.get_node_or_null("/root/Social")
	if autoload is SocialServices:
		return autoload
	var existing := root.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is SocialServices:
		return existing
	var node := SocialServices.new()
	node.name = NODE_NAME
	root.get_tree().root.add_child.call_deferred(node)
	return node


func _init() -> void:
	visit = VisitService.new()
	visit.name = "Visit"
	add_child(visit)
	board = BoardSession.new()
	board.name = "Board"
	add_child(board)
	pal = GoobyPalService.new()
	pal.name = "Pal"
	add_child(pal)


func _ready() -> void:
	var net := get_node_or_null("/root/Net")
	var gs := get_node_or_null("/root/GameState")
	if net != null:
		setup(net, gs)


## Manuelle Verkabelung (Tests / Integration mit eigenem NetClient).
func setup(net_client: Node, game_state: Object) -> void:
	if _wired:
		return
	_wired = true
	visit.setup(net_client)
	board.setup(net_client)
	pal.setup(net_client, game_state)


func is_online() -> bool:
	return visit.is_online()

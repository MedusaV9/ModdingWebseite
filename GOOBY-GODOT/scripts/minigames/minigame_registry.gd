class_name MinigameRegistry
extends RefCounted
## Meta-Registry der Arcade-Spiele (Godot-Pendant zu GOOBY/src/data/
## minigames.js + difficultyTargets.js — nur die georteten Spiele + die
## „Bald!“-Kacheln). coin_table/target sind mit den Web-Zeilen zahlengleich
## (teaParty §V5.1: /4, 4..26, Ziel 85; carrotCatch §C6.1: /3, 4..25, Ziel 70).
## Cover-Konvention: res://assets/covers/<id>.png (1:1 aus dem Web kopiert);
## neue Spiele (W3b GvZ) hängen hier eine Zeile an + legen ihr Cover ab.

const COVER_DIR := "res://assets/covers"

const GAMES: Array[Dictionary] = [
	{
		"id": "teaParty",
		"title_key": "mg.teaParty.title",
		"scene": "res://scripts/minigames/games/tea_party/tea_party.tscn",
		"coin_table": {"divisor": 4, "min": 4, "max": 26},
		"target": 85,
		"orientation": "portrait",
		"supports_endless": true,
	},
	{
		"id": "carrotCatch",
		"title_key": "mg.carrotCatch.title",
		"scene": "res://scripts/minigames/games/carrot_catch/carrot_catch.tscn",
		"coin_table": {"divisor": 3, "min": 4, "max": 25},
		"target": 70,
		"orientation": "portrait",
		"supports_endless": true,
	},
	{"id": "gvz", "title_key": "mg.gvz.title", "coming_soon": true},
	{"id": "gobnom", "title_key": "mg.gobnom.title", "coming_soon": true},
]


static func get_game(id: String) -> Dictionary:
	for game in GAMES:
		if game["id"] == id:
			return game
	return {}


## Nur die spielbaren Einträge (mit Szene, ohne coming_soon).
static func playable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for game in GAMES:
		if not game.get("coming_soon", false):
			out.append(game)
	return out


static func cover_path(id: String) -> String:
	return "%s/%s.png" % [COVER_DIR, id]

class_name MinigameRegistry
extends RefCounted
## Meta-Registry der Arcade-Spiele (Godot-Pendant zu GOOBY/src/data/
## minigames.js + difficultyTargets.js — nur die georteten Spiele + die
## „Bald!“-Kacheln). coin_table/target sind mit den Web-Zeilen zahlengleich
## (teaParty §V5.1: /4, 4..26, Ziel 85; carrotCatch §C6.1: /3, 4..25, Ziel 70).
## Cover-Konvention: res://assets/covers/<id>.png (1:1 aus dem Web kopiert);
## neue Spiele (W3b GvZ) hängen hier eine Zeile an + legen ihr Cover ab.

const COVER_DIR := "res://assets/covers"

## Web MINIGAME.ENERGY_COST (data/constants.js §C6): 8 Energie pro Start —
## der Host bucht beim ECHTEN Rundenstart ab (E10-P1-2: die Coin-Bremse).
const DEFAULT_ENERGY_COST := 8

const GAMES: Array[Dictionary] = [
	{
		"id": "teaParty",
		"title_key": "mg.teaParty.title",
		"scene": "res://scripts/minigames/games/tea_party/tea_party.tscn",
		"coin_table": {"divisor": 4, "min": 4, "max": 26},
		"target": 85,
		"orientation": "portrait",
		"supports_endless": true,
		"energy_cost": 8,
	},
	{
		"id": "carrotCatch",
		"title_key": "mg.carrotCatch.title",
		"scene": "res://scripts/minigames/games/carrot_catch/carrot_catch.tscn",
		"coin_table": {"divisor": 3, "min": 4, "max": 25},
		"target": 70,
		"orientation": "portrait",
		"supports_endless": true,
		"energy_cost": 8,
	},
	{
		"id": "gvz",
		"title_key": "mg.gvz.title",
		"scene": "res://scripts/minigames/games/gvz/gvz_game.tscn",
		# E10-P1-3: die Row wird PRO gewonnenem Level angewandt (Coin-Chunks,
		# gvz_game meldet jeden Levelsieg). divisor 3 eicht auf die realen
		# Level-Scores 50–210 (vorher /12 auf den Session-Score = 10–20×
		# schlechter als teaParty).
		"coin_table": {"divisor": 3, "min": 4, "max": 40},
		"target": 300,
		"orientation": "landscape",
		"supports_endless": false,
		"energy_cost": 8,
	},
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

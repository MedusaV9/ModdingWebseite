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
	{
		"id": "gobnom",
		"title_key": "mg.gobnom.title",
		"scene": "res://scripts/minigames/games/gobnom/gobnom_game.tscn",
		# Level-Siege melden Coin-Chunks (E10-P1-3-Muster wie GvZ); die realen
		# Level-Scores liegen bei 44–219 (win_base 40 + Gläser + Level-Bonus
		# + First-Clear) — dieselbe Eichung wie GvZ passt.
		"coin_table": {"divisor": 3, "min": 4, "max": 40},
		"target": 300,
		"orientation": "landscape",
		"supports_endless": false,
		"energy_cost": 8,
	},
]

## W6: pro-Spiel-Manifeste (scripts/minigames/games/<ordner>/game.json).
## Damit koennen mehrere Agents/Teams Spiele PARALLEL hinzufuegen, ohne sich in
## dieser Datei zu ueberschreiben — und Content-Packs koennen spaeter Spiele
## nachliefern. Schema (alle Felder wie in GAMES):
##   {"id","title_key","scene","coin_table":{"divisor","min","max"},"target",
##    "orientation","supports_endless","energy_cost"}
const GAMES_DIR := "res://scripts/minigames/games"

static var _discovered: Array[Dictionary] = []
static var _scanned := false


static func _scan_manifests() -> void:
	if _scanned:
		return
	_scanned = true
	var dir := DirAccess.open(GAMES_DIR)
	if dir == null:
		return
	for sub in dir.get_directories():
		var path := "%s/%s/game.json" % [GAMES_DIR, sub]
		if not FileAccess.file_exists(path):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			push_error("Minigame-Manifest kaputt: %s" % path)
			continue
		var data: Variant = json.data
		if data is Dictionary and data.has("id") and data.has("scene"):
			_discovered.append(data as Dictionary)


## Alle bekannten Spiele: fest eingetragene + per Manifest entdeckte.
static func all_games() -> Array[Dictionary]:
	_scan_manifests()
	var out: Array[Dictionary] = GAMES.duplicate()
	var known := {}
	for game in out:
		known[game["id"]] = true
	for game in _discovered:
		if not known.has(game["id"]):
			out.append(game)
	return out


static func get_game(id: String) -> Dictionary:
	for game in all_games():
		if game["id"] == id:
			return game
	return {}


## Nur die spielbaren Einträge (mit Szene, ohne coming_soon).
static func playable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for game in all_games():
		if not game.get("coming_soon", false):
			out.append(game)
	return out


static func cover_path(id: String) -> String:
	return "%s/%s.png" % [COVER_DIR, id]

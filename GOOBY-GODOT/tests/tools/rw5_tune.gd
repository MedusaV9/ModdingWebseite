extends SceneTree
## RW-5 Wegwerf-Tuning: Sieg-/Podium-Quoten je Bot-Band-Konfiguration.

const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")
const Bots := preload("res://scripts/ranch/comp/comp_bots.gd")
const Turnier := preload("res://scripts/ranch/comp/comp_turnier.gd")

const N := 120


func _initialize() -> void:
	var basis := RanchWirtschaft.read_json(Katalog.BALANCE_PATH)
	var kandidaten := {
		"aktuell": basis.get("bot_koennen"),
		"weicher":
		{
			"holz": [0.12, 0.32],
			"bronze": [0.3, 0.5],
			"silber": [0.48, 0.66],
			"gold": [0.62, 0.8],
			"sternenklasse": [0.76, 0.92],
		},
		"weich2":
		{
			"holz": [0.1, 0.28],
			"bronze": [0.28, 0.48],
			"silber": [0.46, 0.64],
			"gold": [0.6, 0.78],
			"sternenklasse": [0.74, 0.9],
		},
	}
	var anf := {"tempo": 8, "sprungkraft": 8, "wendigkeit": 8, "ausdauer": 8, "gelassenheit": 8}
	var top := {
		"tempo": 18, "sprungkraft": 18, "wendigkeit": 18, "ausdauer": 18, "gelassenheit": 18
	}
	for name: String in kandidaten:
		var bal := basis.duplicate(true)
		bal["bot_koennen"] = kandidaten[name]
		print(
			(
				"%s: holzSieg=%.2f sternSchwachSieg=%.2f sternTopPodium=%.2f goldAnfPodium=%.2f"
				% [
					name,
					_quote(bal, "holz", anf, 0.55, false),
					_quote(bal, "sternenklasse", anf, 0.55, false),
					_quote(bal, "sternenklasse", top, 0.9, true),
					_quote(bal, "gold", anf, 0.55, true),
				]
			)
		)
	quit(0)


func _quote(bal: Dictionary, klasse: String, stats: Dictionary, fahr: float, podium: bool) -> float:
	var treffer := 0
	var disziplinen: Array[String] = ["tonnen", "springen", "gelaende"]
	for i in N:
		var disziplin: String = disziplinen[i % disziplinen.size()]
		var seed_wert := 31000 + i * 17
		var bots := Turnier.bots_simulieren(bal, disziplin, klasse, seed_wert)
		var koennen := Bots.spieler_koennen(bal, disziplin, stats, fahr)
		var lauf := Bots.simuliere_lauf(bal, disziplin, klasse, koennen, seed_wert + 5)
		var stand := Turnier.endstand(bal, disziplin, bots, lauf)
		var platz := Turnier.spieler_platz(stand)
		if (podium and platz <= 3) or (not podium and platz == 1):
			treffer += 1
	return float(treffer) / N

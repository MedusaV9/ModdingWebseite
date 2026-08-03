extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Level-Reise" (W18/R3, G8-IDEE Progression Nr. 2): Boot → Onboarding →
## Profil öffnen → die Reise-Karte 1→40 ist sichtbar (Titel, Stempel-Pfad,
## echte Tore) → zurück ins Zuhause → Debug-XP exakt bis Level 5 → das
## Meilenstein-Fest feiert im Raum (Torte + Konfetti + Jubel + Toast) →
## Debug-XP bis Level 10: der level10-ERFOLG feiert ZUERST, das Fest kommt
## sauber DANACH durch dieselbe RewardHub-Queue (kein Overlay-Stapel) →
## Profil erneut öffnen: die Reise trägt die Stempel, der Pass die
## Meilenstein-Stempel. Aufruf: tools/ci/run_playtest.sh flow_levelreise

const Leveling := preload("res://scripts/logic/leveling.gd")

## Feier-Reihenfolge am RewardHub ("erfolg"/"fest") — der Kern-Beleg, dass
## das Fest NACH bestehenden Feiern drankommt, nie darüber.
var _reihenfolge: Array[String] = []


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_profil_und_reise_schritte())
	liste.append_array(_fest_level5_schritte())
	liste.append_array(_erfolg_dann_fest_level10_schritte())
	liste.append_array(_stempel_schritte())
	return liste


## ---------------------------------------------------------------- Abschnitte


## Profil öffnen und die Reise-Karte ins Bild scrollen (sie wohnt unter der
## Pass-Karte; die ersten Tore L5/L8 liegen im Startausschnitt des Bands).
func _profil_und_reise_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "profil_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnProfil",
			"erwarte": {"route": "profil"},
			"timeout_s": 90.0,
		},
		{
			"name": "reise_karte_da",
			"aktion": "warte_bis",
			"bedingung": reise_karte_im_baum,
			"timeout_s": 30.0,
		},
		{
			"name": "reise_ins_bild_wischen",
			"aktion": "wisch",
			"von_rel": Vector2(0.5, 0.75),
			"nach_rel": Vector2(0.5, 0.3),
			"dauer_s": 0.8,
		},
		{"name": "reise_karte_mit_toren", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "zurueck_ins_zuhause",
			"aktion": "tipp_name",
			"node": "BackBtn",
			"erwarte": {"route": "home/living"},
			"timeout_s": 90.0,
		},
		{"name": "im_zuhause_ankommen", "aktion": "warte", "sekunden": 2.0},
		{"name": "feier_recorder_anhaengen", "aktion": "tue", "funktion": recorder_anhaengen},
	]


## Debug-XP exakt bis Level 5 → das erste Meilenstein-Fest (nur das Fest,
## Level 5 hat keinen eigenen Erfolg — der Reihenfolge-Beleg kommt bei 10).
func _fest_level5_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "debug_xp_bis_level5",
			"aktion": "tue",
			"funktion": debug_xp_bis_meilenstein,
		},
		{
			"name": "fest5_gefeiert",
			"aktion": "warte_bis",
			"bedingung": fest5_kam,
			"timeout_s": 60.0,
		},
		{
			"name": "torte_im_raum",
			"aktion": "warte_bis",
			"bedingung": torte_im_raum_da,
			"timeout_s": 20.0,
		},
		{"name": "fest5_ansehen", "aktion": "warte", "sekunden": 2.5},
	]


## Debug-XP bis Level 10: level10-Erfolg + Meilenstein-Fest entstehen im
## selben Level-Sprung — die Hub-Queue feiert den ERFOLG ZUERST und das
## Fest sauber DANACH (Serialisierung statt Overlay-Stapel).
func _erfolg_dann_fest_level10_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "debug_xp_bis_level10",
			"aktion": "tue",
			"funktion": debug_xp_bis_meilenstein,
		},
		{
			"name": "erfolg_feiert_zuerst",
			"aktion": "warte_bis",
			"bedingung": erfolg_vor_fest10,
			"timeout_s": 60.0,
		},
		{
			"name": "fest10_kommt_danach",
			"aktion": "warte_bis",
			"bedingung": fest10_nach_erfolg,
			"timeout_s": 90.0,
		},
		{"name": "fest10_ansehen", "aktion": "warte", "sekunden": 2.5},
	]


## Profil erneut öffnen: die Reise trägt jetzt Stempel bis Level 10 und der
## Save die Meilenstein-Buchhaltung (5 und 10 mit echtem Fest-Datum).
func _stempel_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "profil_wieder_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnProfil",
			"erwarte": {"route": "profil"},
			"timeout_s": 90.0,
		},
		{
			"name": "meilensteine_im_save_gestempelt",
			"aktion": "warte_bis",
			"bedingung": stempel_5_und_10_im_save,
			"timeout_s": 15.0,
		},
		{
			"name": "reise_mit_stempeln_ins_bild",
			"aktion": "wisch",
			"von_rel": Vector2(0.5, 0.75),
			"nach_rel": Vector2(0.5, 0.3),
			"dauer_s": 0.8,
		},
		{"name": "reise_mit_stempeln_zeigen", "aktion": "warte", "sekunden": 1.5},
	]


## ---------------------------------------------------------------- Bausteine


func reise_karte_im_baum() -> bool:
	return _finde_node(harness.root, "LevelReiseCard") != null


## Feier-Reihenfolge am Hub mitschreiben (erfolg vs. fest) — Lambdas leben
## am Hub-Node und sterben mit ihm.
func recorder_anhaengen() -> bool:
	var hub := harness.get_first_node_in_group(&"reward_hub")
	if hub == null:
		return false
	hub.achievement_celebrated.connect(
		func(_def: Dictionary) -> void: _reihenfolge.append("erfolg")
	)
	hub.meilenstein_celebrated.connect(func(_level: int) -> void: _reihenfolge.append("fest"))
	return true


## Debug-XP: exakt bis zum NÄCHSTEN Meilenstein auffüllen — über die echte
## Kurven-Mathematik (Leveling.apply_xp, nur LESEN der Konstanten).
func debug_xp_bis_meilenstein() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var vorher := int(gs.get_value("progression.level", 1))
	var ziel := LevelReiseLogic.naechster_meilenstein(vorher)
	if ziel <= 0:
		return false
	gs.update(
		func(s: Dictionary) -> void:
			var prog: Dictionary = s["progression"]
			var level := int(prog.get("level", 1))
			var xp := float(prog.get("xp", 0.0))
			var fehlt := (
				float(Leveling.cumulative_xp_to_level(ziel))
				- float(Leveling.cumulative_xp_to_level(level))
				- xp
			)
			var res := Leveling.apply_xp({"xp": xp, "level": level}, fehlt)
			prog["xp"] = res["xp"]
			prog["level"] = res["level"]
	)
	var nachher := int(gs.get_value("progression.level", 1))
	print("[LEVELREISE] Debug-XP: Level %d -> %d (Ziel %d)" % [vorher, nachher, ziel])
	return nachher == ziel


## Fest 5 ist da und war die LETZTE Feier — falls im selben Sprung ein
## Erfolg entstand (z. B. Münz-Meilenstein durch Level-Up-Coins), feierte
## er VORHER durch dieselbe Queue (nie über dem Fest).
func fest5_kam() -> bool:
	var feste := _reihenfolge.count("fest")
	return feste == 1 and _reihenfolge[_reihenfolge.size() - 1] == "fest"


## Nach dem Level-10-Sprung feiert der level10-ERFOLG zuerst (Fest 10 steht
## noch aus — die Queue serialisiert).
func erfolg_vor_fest10() -> bool:
	if _reihenfolge.count("fest") != 1:
		return false
	return _reihenfolge[_reihenfolge.size() - 1] == "erfolg"


## Fest 10 kam als LETZTES — und zwischen Fest 5 und Fest 10 feierte
## mindestens ein Erfolg (level10) VOR dem Fest: kein Overlay-Stapel,
## saubere Reihenfolge durch die RewardHub-Queue.
func fest10_nach_erfolg() -> bool:
	if _reihenfolge.count("fest") != 2:
		return false
	if _reihenfolge[_reihenfolge.size() - 1] != "fest":
		return false
	var erster := _reihenfolge.find("fest")
	var letzter := _reihenfolge.rfind("fest")
	for i in range(erster + 1, letzter):
		if _reihenfolge[i] == "erfolg":
			return true
	return false


func torte_im_raum_da() -> bool:
	return _finde_node(harness.root, "MeilensteinTorte") != null


func stempel_5_und_10_im_save() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var done := LevelReiseLogic.gefeierte(gs.state())
	return int(done.get("5", 0)) > 0 and int(done.get("10", 0)) > 0


func _finde_node(wurzel: Node, gesucht: String) -> Node:
	if wurzel.name == StringName(gesucht):
		return wurzel
	for kind in wurzel.get_children():
		var treffer := _finde_node(kind, gesucht)
		if treffer != null:
			return treffer
	return null

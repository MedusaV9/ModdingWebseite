extends SceneTree
## ASSET-ROT-Audit (KEIN Test — kein test_-Präfix): instanziert alle Welt-,
## Ort- und Minispiel-Szenen headless, lässt sie ihren prozeduralen Aufbau
## fahren und prüft alle platzierten GLB-Instanzen/Modell-Holder auf
## Fehl-Orientierung (Regeln: tests/tools/asset_rot_regeln.gd). Die .tscn
## dieses Projekts sind bewusst dünne Hüllen — die Platzierung passiert in
## _ready()-Code, deshalb scannt das Audit den LAUFZEIT-Baum statt der Datei.
##
## Aufruf (immer über den Isolations-Wrapper + VM-weiten Godot-Lock):
##   flock -w 7200 /tmp/gooby_godot_global.lock \
##     tools/ci/run_godot_isolated.sh godot --headless --path GOOBY-GODOT \
##     --script res://tests/tools/asset_rot_audit.gd
## Optionen (nach `--`):
##   nur=<teilstring>   nur Szenen, deren Pfad den Teilstring enthält
##   ohne-minigames     Minispiele überspringen (schneller Weltlauf)
##
## Ausgabe: Markdown + JSON unter /tmp/gooby-godot/artifacts/ASSET-ROT/
## Exit 0 = Lauf ok (Befunde stehen im Bericht), 1 = Werkzeugfehler.

const Regeln := preload("res://tests/tools/asset_rot_regeln.gd")

const OUT_DIR := "/tmp/gooby-godot/artifacts/ASSET-ROT"
## Fester Seed für Minispiel-Mounts — deterministische Läufe (AGENTS-Regel:
## Zufall immer injizieren).
const MINIGAME_SEED := 4242
## Aufbau-Beruhigung: mindestens so viele Frames, dann bis der Node-Zähler
## 5 Frames stabil steht (prozedurale Bauten + deferred-Ketten).
const SETTLE_MIN_FRAMES := 12
const SETTLE_MAX_FRAMES := 120

## Welt-/Ort-Szenen ohne Parameterbedarf (Minispiele kommen aus der Registry).
const WELT_SZENEN: Array[String] = [
	"res://scenes/home/schlafzimmer.tscn",
	"res://scenes/home/wohnzimmer.tscn",
	"res://scenes/home/kueche.tscn",
	"res://scenes/home/bad.tscn",
	"res://scenes/home/garten.tscn",
	"res://scenes/city/city_scene.tscn",
	"res://scenes/city/orte/autohaus.tscn",
	"res://scenes/city/orte/baumarkt.tscn",
	"res://scenes/city/orte/flughafen.tscn",
	"res://scenes/city/orte/goobyman.tscn",
	"res://scenes/city/orte/goobytheke.tscn",
	"res://scenes/city/orte/gouhbus.tscn",
	"res://scenes/city/orte/post.tscn",
	"res://scenes/city/orte/pow.tscn",
	"res://scenes/city/orte/raumstation.tscn",
	"res://scenes/city/orte/rehwei.tscn",
	"res://scenes/city/orte/tierarzt.tscn",
	"res://scenes/city/orte/wochenmarkt.tscn",
	"res://scenes/city/urlaub/urlaub_berge.tscn",
	"res://scenes/city/urlaub/urlaub_stadt.tscn",
	"res://scenes/city/urlaub/urlaub_strand.tscn",
	"res://scenes/city/reise_cutscene.tscn",
	"res://scenes/park/funkelpark.tscn",
	"res://scenes/ranch/ranch_hof.tscn",
	"res://scenes/ranch/ranch_fahrt.tscn",
	"res://scenes/ranch/dorf/hufingen.tscn",
	"res://scenes/ranch/dorf/ranch_bau_hof.tscn",
	"res://scenes/ranch/welt/ranch_region.tscn",
	"res://scripts/dlc/goobye/laden_scene.tscn",
	"res://scripts/dlc/mcgooby/schicht_scene.tscn",
	"res://scripts/social/visit_scene.tscn",
	"res://scripts/character/gooby_showcase.tscn",
]

var _filter := ""
var _mit_minigames := true
var _befunde: Array[Dictionary] = []
var _szenen_fehler: Array[String] = []
var _geprueft := 0


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("nur="):
			_filter = arg.trim_prefix("nur=")
		elif arg == "ohne-minigames":
			_mit_minigames = false
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for pfad in WELT_SZENEN:
		if _passt(pfad):
			await _pruefe_szene(pfad, "")
	if _mit_minigames:
		for meta in MinigameRegistry.GAMES:
			var pfad := str(meta.get("scene", ""))
			if pfad != "" and _passt(pfad):
				await _pruefe_szene(pfad, str(meta["id"]))
	_schreibe_bericht()
	quit(0)


func _passt(pfad: String) -> bool:
	return _filter == "" or pfad.contains(_filter)


func _pruefe_szene(pfad: String, minigame_id: String) -> void:
	if not ResourceLoader.exists(pfad):
		_szenen_fehler.append("%s — Datei fehlt" % pfad)
		return
	var packed: PackedScene = load(pfad)
	if packed == null or not packed.can_instantiate():
		_szenen_fehler.append("%s — lädt nicht" % pfad)
		return
	var node: Node = packed.instantiate()
	root.add_child(node)
	if minigame_id != "":
		var ctx := MinigameCtx.new()
		ctx.game_id = minigame_id
		ctx.difficulty = "normal"
		ctx.orientation = str(MinigameRegistry.get_game(minigame_id).get("orientation", "portrait"))
		ctx.run_seed = MINIGAME_SEED
		node.call("setup", ctx)
		await _beruhige()
		node.call("start")
	await _beruhige()
	var stats: Dictionary = {}
	var neu := Regeln.pruefe_baum(node, pfad, stats)
	_befunde.append_array(neu)
	_geprueft += 1
	var rot := 0
	for befund in neu:
		if Regeln.stufe(befund) == "ROT":
			rot += 1
	print(
		(
			"[ASSET-ROT] %s — %d GLB + %d Holder geprüft, %d Befunde (%d ROT)"
			% [pfad, int(stats.get("glb", 0)), int(stats.get("holder", 0)), neu.size(), rot]
		)
	)
	node.queue_free()
	await process_frame
	await process_frame


## Wartet, bis der Baum „ausgebaut“ ist: Mindest-Frames, dann Node-Zähler
## 5 Frames in Folge stabil (prozedurale Bauten, deferred-Ketten, Preloads).
func _beruhige() -> void:
	for _i in SETTLE_MIN_FRAMES:
		await process_frame
	var stabil := 0
	var letzte := -1
	for _i in SETTLE_MAX_FRAMES:
		var jetzt := root.get_child_count()
		var gesamt := _zaehle(root)
		jetzt = gesamt
		stabil = stabil + 1 if jetzt == letzte else 0
		letzte = jetzt
		if stabil >= 5:
			return
		await process_frame


func _zaehle(node: Node) -> int:
	var summe := 1
	for kind in node.get_children():
		summe += _zaehle(kind)
	return summe


func _schreibe_bericht() -> void:
	var whitelist := Regeln.lade_whitelist()
	var rot: Array[Dictionary] = []
	var erlaubt: Array[Dictionary] = []
	var gelb: Array[Dictionary] = []
	for befund in _befunde:
		if Regeln.stufe(befund) == "ROT":
			if Regeln.ist_erlaubt(befund, whitelist):
				erlaubt.append(befund)
			else:
				rot.append(befund)
		else:
			gelb.append(befund)
	var zeilen: Array[String] = []
	zeilen.append("# ASSET-ROT-Audit — Orientierungs-Scan aller Szenen")
	zeilen.append("")
	zeilen.append(
		(
			"Szenen geprüft: %d · Befunde: %d ROT / %d Whitelist / %d GELB"
			% [_geprueft, rot.size(), erlaubt.size(), gelb.size()]
		)
	)
	zeilen.append("")
	for titel_und_liste: Array in [
		["ROT (fixen oder whitelisten!)", rot],
		["Whitelist-Ausnahmen (bewusst so)", erlaubt],
		["GELB (Hinweise, Sichtung)", gelb],
	]:
		zeilen.append("## %s" % str(titel_und_liste[0]))
		zeilen.append("")
		var liste: Array[Dictionary] = titel_und_liste[1]
		if liste.is_empty():
			zeilen.append("_keine_")
			zeilen.append("")
			continue
		zeilen.append("| Szene | Node | Asset | Art | Kipp | det | rot° | Pos |")
		zeilen.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
		for befund in liste:
			(
				zeilen
				. append(
					(
						"| %s | %s | %s | %s%s | %.0f° | %.2f | %s | %s |"
						% [
							str(befund["szene"]).trim_prefix("res://"),
							str(befund["pfad"]),
							str(befund["asset"]),
							str(befund["art"]),
							" (RICHTUNG)" if bool(befund["richtung"]) else "",
							float(befund["kipp_grad"]),
							float(befund["det"]),
							str(befund["rot_grad"]),
							str(befund["pos"]),
						]
					)
				)
			)
		zeilen.append("")
	if not _szenen_fehler.is_empty():
		zeilen.append("## Szenen-Fehler (nicht prüfbar)")
		zeilen.append("")
		for fehler in _szenen_fehler:
			zeilen.append("- %s" % fehler)
		zeilen.append("")
	var report := FileAccess.open("%s/bericht.md" % OUT_DIR, FileAccess.WRITE)
	report.store_string("\n".join(zeilen) + "\n")
	report.flush()
	var json := FileAccess.open("%s/befunde.json" % OUT_DIR, FileAccess.WRITE)
	json.store_string(JSON.stringify({"befunde": _befunde, "fehler": _szenen_fehler}, "\t"))
	json.flush()
	print("[ASSET-ROT] Bericht: %s/bericht.md" % OUT_DIR)
	print(
		(
			"[ASSET-ROT] Ergebnis: %d Szenen, %d ROT, %d Whitelist, %d GELB"
			% [_geprueft, rot.size(), erlaubt.size(), gelb.size()]
		)
	)

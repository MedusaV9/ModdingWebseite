class_name SeeleRunner
extends Node
## SEELE-2-Komponente am GoobyReactions-Runner (hängt als Kind daran):
## bündelt alles, was die DURCHGEHENDE Stimmung lebendig macht —
##  - Stimmungs-Takt: SoulMood.advance Richtung Stats-Wahrheit + Ereignis-
##    Stöße (füttern, streicheln, Wiedersehen), persistiert im Soul-Slice.
##  - Verteilung an alle Kanäle: Ruhe-Gesicht (statt hart „happy“),
##    Ausdrucks-Schicht (GoobyExpressions: Ohren/Lider/Blick) und Stimme
##    (GoobyVoice-Modulation nach Laune).
##  - Absichts-Verhalten: SoulIntent wählt das dringendste Bedürfnis, hier
##    wird es SICHTBAR ausgeführt (hinlaufen, Ziel anschauen, dann dich).
##  - Gruß-Annäherung: gute Laune kommt dir entgegen, miese bleibt sitzen.
##
## Der Runner (gooby_reactions.gd) bleibt der Orchestrator und delegiert
## hierher; Zeit/Zufall laufen über SEINE Overrides (now_ms/rng) — diese
## Komponente hält nur Stimmung-, Ausdrucks- und Absichts-Zustand.

const Sleep := preload("res://scripts/logic/sleep.gd")
const Health := preload("res://scripts/logic/health.gd")

## Stimmung alle paar Sekunden Richtung Stats-Ziel takten.
const MOOD_REFRESH_S := 5.0
## Ereignis-Stöße auf die Stimmung (SoulMood.bump ist zusätzlich gedeckelt).
const STOSS_FUETTERN := 5.0
const STOSS_STREICHELN := 1.0
const STOSS_KITZELN := 2.0
const GRUSS_STOSS := {
	"gruss_gefreut": 3.0,
	"gruss_vermisst": 5.0,
	"gruss_eingeschnappt": -4.0,
}
## Streichel-Stöße zählen nur bis hierhin pro Tag (kein Laune-Pumpen).
const STOSS_PET_MAX_PRO_TAG := 20

## Der GoobyReactions-Runner (bewusst untypisiert — kein Klassen-Zyklus).
var runner: Node = null

var _expressions: GoobyExpressions = null
var _voice: GoobyVoice = null
var _mood_timer := 0.0
var _wert := SoulMood.DEFAULT_WERT
var _intent_cooldowns: Dictionary = {}
## Solange ein Moment sein Gesicht trägt, überschreibt der Stimmungs-Takt
## es nicht (Zeitstempel statt Flag — überlappende Momente verlängern).
var _emotion_temp_bis_ms := 0


## Komponente erzeugen und an den Runner hängen (idempotent).
static func attach_to(target_runner: Node) -> SeeleRunner:
	var existing := target_runner.get_node_or_null("SeeleRunner")
	if existing is SeeleRunner:
		return existing
	var seele := SeeleRunner.new()
	seele.name = "SeeleRunner"
	target_runner.add_child(seele)
	seele.setup(target_runner)
	return seele


func setup(target_runner: Node) -> void:
	runner = target_runner
	_setup_ausdruck_und_stimme()
	refresh_stimmung()


## Ausdrucks-Schicht ans Rig hängen, Stimme an Gooby (beide idempotent) —
## das Gebrabbel bekommt Lipsync über den babble_pulse-Hook des Rigs.
func _setup_ausdruck_und_stimme() -> void:
	var gooby: Node = runner.gooby
	if gooby == null or not (gooby.get("rig") is GoobyRig):
		return
	_expressions = GoobyExpressions.attach_to(gooby.rig)
	var existing := gooby.get_node_or_null("GoobyVoice")
	if existing is GoobyVoice:
		_voice = existing
	else:
		_voice = GoobyVoice.new()
		_voice.name = "GoobyVoice"
		gooby.add_child(_voice)
	if not _voice.silbe.is_connected(_on_silbe):
		_voice.silbe.connect(_on_silbe)


func _on_silbe(_index: int, _anzahl: int) -> void:
	var gooby: Node = runner.gooby
	if gooby != null and gooby.get("rig") is GoobyRig:
		gooby.rig.babble_pulse()


# ── Stimmungs-Takt ───────────────────────────────────────────────────────────


## Vom Runner-_process gerufen: alle MOOD_REFRESH_S einmal takten.
func tick(delta: float) -> void:
	_mood_timer -= delta
	if _mood_timer <= 0.0:
		_mood_timer = MOOD_REFRESH_S
		refresh_stimmung()


func wert() -> float:
	return _wert


func band() -> String:
	return SoulMood.band(_wert)


## Faktor auf den Idle-Takt: schlechte Laune = träger, gute = lebhafter.
func idle_takt_faktor() -> float:
	return SoulMood.idle_takt_faktor(_wert)


## Stimmung Richtung Stats-Wahrheit takten (SoulMood.advance, träge) und an
## alle Kanäle verteilen: Ruhe-Gesicht, Ausdrucks-Schicht, Stimme.
func refresh_stimmung() -> void:
	var state: Dictionary = runner.gs.state()
	var now: int = runner._now_ms()
	var ziel := SoulMood.ziel(_stats_now(state), Sleep.grumpy_debuff(_gooby_slice(state), now))
	SoulState.mutate(
		runner.gs,
		func(s: Dictionary) -> void: s["stimmung"] = SoulMood.advance(s["stimmung"], ziel, now)
	)
	_verteile_stimmung()


## Ereignis-Stoß auf die Laune (füttern +, eingeschnappt −, ...). Klein und
## gedeckelt (SoulMood.bump) — die Trägheit bleibt spürbar.
func stoss(delta: float) -> void:
	var now: int = runner._now_ms()
	SoulState.mutate(
		runner.gs,
		func(s: Dictionary) -> void: s["stimmung"] = SoulMood.bump(s["stimmung"], delta, now)
	)
	_verteile_stimmung()


## Wiedersehen bewegt die Laune — freudig hebt, Schmollen senkt.
func stoss_gruss(moment_id: String) -> void:
	if GRUSS_STOSS.has(moment_id):
		stoss(float(GRUSS_STOSS[moment_id]))


## Streicheln hebt sanft — aber nur bis zum Tagesdeckel (kein Pumpen).
func stoss_streicheln(pets_today: int) -> void:
	if pets_today <= STOSS_PET_MAX_PRO_TAG:
		stoss(STOSS_STREICHELN)


func _verteile_stimmung() -> void:
	_wert = float(SoulState.slice_of(runner.gs)["stimmung"]["wert"])
	if _expressions != null:
		_expressions.set_stimmung(_wert)
	if _voice != null:
		_voice.set_stimmung(_wert)
	apply_ruhe_emotion()


## Ruhe-Gesicht ZWISCHEN den Momenten anlegen — aber nie über ein noch
## laufendes Moment-Gesicht, den Schlaf (PflegeRunner-Pose) oder den
## Vernachlässigungs-Blick drüberbügeln.
func apply_ruhe_emotion() -> void:
	var gooby: Node = runner.gooby
	if gooby == null or not (gooby.get("rig") is GoobyRig):
		return
	if bool(runner._sad) or runner._now_ms() < _emotion_temp_bis_ms:
		return
	var state: Dictionary = runner.gs.state()
	if Sleep.is_sleeping(_gooby_slice(state)):
		return
	gooby.rig.set_emotion(SoulMood.ruhe_emotion(_wert, _stats_now(state), _krank_grad(state)))


func ruhe_emotion_jetzt() -> String:
	var state: Dictionary = runner.gs.state()
	return SoulMood.ruhe_emotion(_wert, _stats_now(state), _krank_grad(state))


## Ein Moment trägt jetzt sein Gesicht — der Takt lässt es so lange in Ruhe.
func emotion_temp_setzen(dauer_s: float) -> void:
	_emotion_temp_bis_ms = runner._now_ms() + int(dauer_s * 1000.0)


func emotion_temp_frei() -> void:
	_emotion_temp_bis_ms = 0


## Aufmerken (Ohren-Perk + Blick zur Kamera) mit Latenz nach Laune.
func aufmerken() -> void:
	if _expressions != null:
		_expressions.aufmerken()


## Gebrabbel zur Bubble: die Stimme moduliert nach Stimmung UND Moment-
## Emotion (GoobyVoice.modulation) — man HÖRT, wie es Gooby geht.
func sagt(text: String, emotion := "") -> void:
	if _voice != null:
		_voice.sagt(text, emotion if not emotion.is_empty() else ruhe_emotion_jetzt())


## Annäherung beim Gruß: ab „happy“ läuft Gooby ein Stück Richtung Kamera
## (also zu DIR) und sucht Blickkontakt; darunter bleibt er, wo er ist.
func gruss_annaeherung() -> void:
	var gooby: Node3D = runner.gooby
	if not bool(runner.visuals_enabled) or gooby == null:
		return
	if SoulMood.band_index(band()) < SoulMood.band_index("happy"):
		return
	if _expressions != null:
		_expressions.blick_zur_kamera(3.0)
	var camera := gooby.get_viewport().get_camera_3d() if gooby.is_inside_tree() else null
	if camera == null:
		return
	var richtung := camera.global_position - gooby.global_position
	richtung.y = 0.0
	if richtung.length() < 1.5:
		return
	gooby.walk_to(gooby.global_position + richtung.normalized() * 1.2, 4.0)


# ── Eigenleben mit Absicht ───────────────────────────────────────────────────


## Bedürfnis → sichtbare Handlung: Gooby läuft zum Ziel (Kühlschrank, Bett,
## Spielzeug, Fenster …) und schaut dich danach an. true = Absicht lief,
## das Zufalls-Idle fällt diese Runde aus.
func try_intent() -> bool:
	var state: Dictionary = runner.gs.state()
	var ctx := {
		"regen": bool(runner._ctx(0)["wetter"].get("regen", false)),
		"schlaeft": Sleep.is_sleeping(_gooby_slice(state)),
		"vorhanden": intent_ziele_vorhanden(),
	}
	var now: int = runner._now_ms()
	var absicht := SoulIntent.waehle(_stats_now(state), ctx, _intent_cooldowns, now)
	if absicht.is_empty():
		return false
	_intent_cooldowns[str(absicht["id"])] = now + SoulIntent.COOLDOWN_MS
	_perform_intent(absicht)
	return true


## Welche Absichts-Ziele sind in DIESEM Raum auflösbar? (SoulIntent fragt
## nur nach — ein Wollen ohne sichtbares Wohin wirkt kaputt, nicht beseelt.)
func intent_ziele_vorhanden() -> Dictionary:
	var out := {}
	for eintraege: Array in SoulIntent.ZIELE.values():
		for eintrag: String in eintraege:
			if out.has(eintrag) or eintrag == "fenster":
				continue
			var teile := eintrag.split(":")
			if teile[0] == "item":
				out[eintrag] = not runner._find_items_by_prefix(teile[1]).is_empty()
			elif teile[0] == "tuer":
				out[eintrag] = not _door_to_room(teile[1]).is_empty()
	return out


## Tür-Def dieses Raums, die in den Ziel-Raum führt ({} = keine).
func _door_to_room(ziel_raum: String) -> Dictionary:
	var room_def := RoomDefs.room(str(runner.room.get("room_id")))
	for door_def: Dictionary in room_def.get("doors", []):
		if str(door_def.get("to", "")) == ziel_raum:
			return door_def
	return {}


## Die Handlung selbst: hinlaufen (Blick aufs Ziel), ankommen, den Spieler
## anschauen — DANN erst (vielleicht) ein Satz. Die Absicht spricht zuerst
## durch den Körper; Text läuft über die vorhandene Bubble-Bremse.
func _perform_intent(absicht: Dictionary) -> void:
	var moment := {}
	var def := SoulService.def_by_id(runner._defs, str(absicht["id"]))
	if not def.is_empty():
		moment = runner._moment_of(def, runner._ctx(0))
	var ziel_welt := _intent_ziel_welt(absicht)
	var gooby: Node3D = runner.gooby
	if bool(runner.visuals_enabled) and gooby != null:
		if _expressions != null and ziel_welt != Vector3.INF:
			_expressions.blick_auf_punkt(ziel_welt + Vector3(0.0, 0.4, 0.0), 5.0)
		match str(absicht["ziel_art"]):
			"fenster":
				runner._walk_to_window()
			"tuer":
				if ziel_welt != Vector3.INF:
					await gooby.walk_to(ziel_welt, 6.0)
			_:
				runner._walk_to_item_prefix(str(absicht["ziel"]))
		if _expressions != null:
			_expressions.blick_zur_kamera(2.5)
	runner._show_moment(moment, true)


## Weltposition des Absichts-Ziels (Vector3.INF = nicht bestimmbar).
func _intent_ziel_welt(absicht: Dictionary) -> Vector3:
	match str(absicht["ziel_art"]):
		"item":
			var found: Array = runner._find_items_by_prefix(str(absicht["ziel"]))
			if not found.is_empty():
				return GridData.world_center(found[0], Vector2i.ONE, 0)
		"tuer":
			var door_def := _door_to_room(str(absicht["ziel"]))
			if not door_def.is_empty():
				var room_def := RoomDefs.room(str(runner.room.get("room_id")))
				var inward := RoomDefs.wall_inward(str(door_def.get("wall", "N")))
				return RoomDefs.door_world_pos(room_def, door_def) + inward * 0.7
		_:
			pass
	return Vector3.INF


# ── Save-Helfer ──────────────────────────────────────────────────────────────


func _gooby_slice(state: Dictionary) -> Dictionary:
	var slice: Variant = state.get("gooby", {})
	return slice if slice is Dictionary else {}


func _stats_now(state: Dictionary) -> Dictionary:
	var stats: Variant = _gooby_slice(state).get("stats", {})
	return stats if stats is Dictionary else {}


func _krank_grad(state: Dictionary) -> int:
	return Health.grade(_gooby_slice(state).get("health"))

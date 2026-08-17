class_name Klangbett
extends Node
## W18/J5 „Jeder Ort ein Klangbett“ (Idee I-33): EIN zentraler Fahrer für die
## dezenten Orts-Ambience-Loops. Er hängt sich an SceneRouter.travel_finished
## (Muster RanchAudio) und fährt pro Reiseziel die Betten-Ebenen aus der
## EINEN Ort→Bett-Zuordnung ORT_BETTEN — die Orts-/Raum-Szenen selbst
## brauchen KEINE Verdrahtung und bleiben unberührt (J3-Zone).
##
## Klang-Hierarchie (leise gemischt): Betten laufen auf dem BESTEHENDEN
## Sfx-Bus (Regler + Stumm-Modus greifen automatisch), ihre SfxMap-Trims
## legen sie eff. auf ≈ −34…−36 dBFS — deutlich unter Musik-Playback
## (≈ −30) und SFX-Median (≈ −22,6). Wache: tests/unit/test_j5_klangbett.gd.
##
## Abgrenzungen (bewusst):
## - ranch/*-Ziele fährt weiterhin RanchAudio (Wind/Vögel/Bach/Grillen je
##   Zone/Wetter) — das Klangbett stoppt dort sein eigenes Bett.
## - Läden: das Bett liefert nur den RAUMTON (Lüftung); Markt-Gemurmel,
##   Tür-Glöckchen und Kassen-Piep bleiben Sache von OrtLeben (G7-P55/J3).
## - Unbekannte Ziele (Album/Sozial/Settings-Screens) behalten das laufende
##   Bett — dieselbe Regel wie die Kontext-Musik im MusicDirector.
##
## Ducking: Spricht Gooby (Gebrabbel, Hook in GoobyVoice._babble) oder
## läuft ein Jingle (MusicDirector.play_stinger), duckt das Bett weich auf
## DUCK_FAKTOR und kommt langsamer zurück. Die komplette Kurve ist PURE
## (duck_ziel/duck_schritt/gain_schritt/ebene_db) und läuft über takt(delta)
## mit injizierter Zeit — deterministisch testbar, keine Tweens/OS-Uhr.
## Headless-sicher: der Dummy-Treiber spielt still, die Zustands-Mathematik
## läuft identisch (Playtest-Beweis über debug_dump()).

const NODE_NAME := "Klangbett"
## Weiche Bett-Übergänge beim Ortswechsel (volle Skala 0→1 in dieser Zeit).
const BETT_FADE_S := 2.5
## Ducking: Zielfaktor unter Stimme/Jingle (≈ −12 dB) …
const DUCK_FAKTOR := 0.25
## … schnell weg (Bett soll der Stimme sofort Platz machen) …
const DUCK_ZU_S := 0.25
## … und gemächlich zurück (kein Pump-Effekt nach jedem Satz).
const DUCK_AUF_S := 0.9
## Jingle-Duck hält einen Tick über das Stinger-Ende hinaus.
const STINGER_NACHHALL_S := 0.4
## Unter diesem Gain gilt eine Ebene als still → Player stoppt.
const STILL_SCHWELLE := 0.001

## Ebenen-Name → SfxMap-Id (Dateien: assets/audio/sfx/ambient/, CC0 —
## tools/audio/gen_klangbetten.py + LICENSE.md dort).
const EBENEN_IDS := {
	"kamin": "bett_kamin",
	"uhr": "bett_uhr",
	"voegel": "bett_voegel",
	"wind": "bett_wind",
	"stadt": "bett_stadt",
	"laden": "bett_laden",
}

## DIE zentrale Ort→Bett-Zuordnung: Router-Ziel → {Ebene: Gain 0..1}.
## Heim: Kamin im Wohnzimmer, Uhr-Ticken in den übrigen Räumen (Bad nur
## durch die Wand); Garten: Vögel + Brise; Stadt: fernes Grummeln/Verkehr;
## Läden: leiser Raumton (Gemurmel/Kasse bleibt OrtLeben, s. Kopf).
const ORT_BETTEN := {
	"home/living": {"kamin": 0.85, "uhr": 0.3},
	"home/kitchen": {"uhr": 0.7},
	"home/bathroom": {"uhr": 0.35},
	"home/bedroom": {"uhr": 0.55},
	"home/garden": {"voegel": 0.8, "wind": 0.5},
	"city": {"stadt": 0.85, "voegel": 0.3},
	"city/ort/wochenmarkt": {"stadt": 0.5, "voegel": 0.35},
	"city/ort/funkelpark": {"voegel": 0.6, "stadt": 0.35},
	"city/ort/flughafen": {"laden": 0.6, "stadt": 0.3},
	"ikea": {"laden": 0.75},
	"arcade": {"laden": 0.45},
}
## Innenraum-Fallback für city/ort/*-Ziele ohne eigenen Eintrag.
const LADEN_STANDARD := {"laden": 0.7}
## Präfixe, auf denen ein ANDERES System die Ambience fährt (RanchAudio).
const FREMD_PREFIXE: Array[String] = ["ranch/"]
## Durchgangs-/Spiel-Stationen: Bett aus, die Spiele haben eigene Kulisse.
const STOPP_ZIELE: Array[String] = ["mg_pregame", "mg_host"]

static var _fallback: Klangbett

## Test-Hooks (Muster OrtLeben): auto_takt=false → Zeit nur über takt();
## stumm=true → Zustands-Mathematik ohne echte Player (Runner-Exit bleibt
## sauber, keine nachklingenden Samples).
var auto_takt := true
var stumm := false

var _ziel_ort := ""
## Ebene → {"ist": float, "ziel": float, "player": AudioStreamPlayer|null}.
var _ebenen: Dictionary = {}
var _duck := 1.0
var _stinger_rest := 0.0
## Instanz-Id → Objekt der gerade brabbelnden GoobyVoice-Quellen.
var _gebrabbel: Dictionary = {}
var _streams: Dictionary = {}


## Autoload-frei nutzbar (Muster RanchAudio): /root/Klangbett bevorzugt,
## sonst lazy-Instanz unter /root. Bootstrap macht der MusicDirector.
static func get_or_create(from: Node) -> Klangbett:
	var existing := from.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is Klangbett:
		return existing
	if _fallback != null and is_instance_valid(_fallback):
		return _fallback
	var node := Klangbett.new()
	node.name = NODE_NAME
	_fallback = node
	from.get_tree().root.add_child.call_deferred(node)
	return node


## Vorhandene Instanz finden OHNE eine zu erzeugen — für die Duck-Hooks
## (GoobyVoice/MusicDirector): ohne Klangbett ist Ducken sinnlos, und
## Fremd-Tests sollen keinen Beifang-Knoten unter /root bekommen.
static func _finde(from: Node) -> Klangbett:
	if from == null or not from.is_inside_tree():
		return null
	var existing := from.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is Klangbett:
		return existing
	if _fallback != null and is_instance_valid(_fallback) and _fallback.is_inside_tree():
		return _fallback
	return null


## Duck-Hook Gebrabbel (GoobyVoice._babble): aktiv=true beim Sprech-Start,
## false am Ende. Mehrere Stimmen gleichzeitig sind ok (Set-Semantik).
static func melde_gebrabbel(from: Node, aktiv: bool) -> void:
	var bett := _finde(from)
	if bett != null:
		bett.gebrabbel_setzen(from, aktiv)


## Duck-Hook Jingle (MusicDirector.play_stinger): duckt für dauer_s.
static func melde_stinger(from: Node, dauer_s: float) -> void:
	var bett := _finde(from)
	if bett != null:
		bett.stinger_setzen(dauer_s)


# ── PURE: Zuordnung + Duck-/Fade-Mathematik (Runner-testbar) ─────────────────


## Reiseziel → Bett-Plan {"wechsel": bool, "ebenen": {Ebene: Gain}}.
## wechsel=false: Ziel ist ein UI-Screen o. Ä. — das laufende Bett bleibt
## (dieselbe Regel wie die Kontext-Musik). Leere ebenen bei wechsel=true
## bedeuten „Bett aus“ (Ranch → RanchAudio, Minigames → eigene Kulisse).
static func bett_plan_fuer(ziel: String) -> Dictionary:
	if ziel.is_empty():
		return {"wechsel": false, "ebenen": {}}
	for prefix in FREMD_PREFIXE:
		if ziel.begins_with(prefix):
			return {"wechsel": true, "ebenen": {}}
	if STOPP_ZIELE.has(ziel):
		return {"wechsel": true, "ebenen": {}}
	if ORT_BETTEN.has(ziel):
		return {"wechsel": true, "ebenen": (ORT_BETTEN[ziel] as Dictionary).duplicate()}
	if ziel.begins_with("city/ort/"):
		return {"wechsel": true, "ebenen": LADEN_STANDARD.duplicate()}
	return {"wechsel": false, "ebenen": {}}


## Duck-Zielfaktor: 1.0 frei, DUCK_FAKTOR solange Stimme ODER Jingle aktiv.
static func duck_ziel(gebrabbel_aktiv: bool, stinger_rest_s: float) -> float:
	return DUCK_FAKTOR if gebrabbel_aktiv or stinger_rest_s > 0.0 else 1.0


## Ein Duck-Zeitschritt: linear mit fester Rate — runter schnell
## (DUCK_ZU_S), rauf gemächlich (DUCK_AUF_S). Pur + deterministisch.
static func duck_schritt(aktuell: float, ziel: float, delta: float) -> float:
	var spanne := 1.0 - DUCK_FAKTOR
	var rate := spanne / DUCK_ZU_S if ziel < aktuell else spanne / DUCK_AUF_S
	return move_toward(aktuell, ziel, rate * maxf(delta, 0.0))


## Ein Bett-Fade-Zeitschritt (volle Skala in BETT_FADE_S).
static func gain_schritt(aktuell: float, ziel: float, delta: float) -> float:
	return move_toward(aktuell, ziel, maxf(delta, 0.0) / BETT_FADE_S)


## Ebenen-Lautstärke: SfxMap-Trim + Gain×Duck (nie über den Trim hinaus).
static func ebene_db(basis_db: float, gain: float, duck: float) -> float:
	return basis_db + linear_to_db(clampf(gain * duck, 0.0001, 1.0))


# ── Laufzeit ──────────────────────────────────────────────────────────────────


func _ready() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_travel_finished)


func _exit_tree() -> void:
	for ebene: String in _ebenen:
		var player: AudioStreamPlayer = _ebenen[ebene]["player"]
		if player != null and is_instance_valid(player):
			player.stop()


func _process(delta: float) -> void:
	if auto_takt:
		takt(delta)


## DER Zeitschritt (vom _process ODER von Tests mit injizierter Zeit):
## Duck-Hüllkurve, Bett-Fades und Player-Pegel in einem Rutsch.
func takt(delta: float) -> void:
	_gebrabbel_aufraeumen()
	_stinger_rest = maxf(0.0, _stinger_rest - delta)
	_duck = duck_schritt(_duck, duck_ziel(not _gebrabbel.is_empty(), _stinger_rest), delta)
	for ebene: String in _ebenen:
		_fahre_ebene(ebene, delta)


## Router-Hook-Kern (auch direkt testbar): Bett auf das Ziel einstellen.
func wechsle_zu(ziel: String) -> void:
	var plan := bett_plan_fuer(ziel)
	if not bool(plan["wechsel"]):
		return
	_ziel_ort = ziel
	var neu: Dictionary = plan["ebenen"]
	for ebene: String in EBENEN_IDS:
		if neu.has(ebene):
			_setze_ziel(ebene, clampf(float(neu[ebene]), 0.0, 1.0))
		elif _ebenen.has(ebene):
			_setze_ziel(ebene, 0.0)


func ziel_ort() -> String:
	return _ziel_ort


func duck_faktor() -> float:
	return _duck


## Gebrabbel-Quelle an-/abmelden (idempotent, Set-Semantik je Instanz).
func gebrabbel_setzen(quelle: Object, aktiv: bool) -> void:
	if quelle == null:
		return
	if aktiv:
		_gebrabbel[quelle.get_instance_id()] = quelle
	else:
		_gebrabbel.erase(quelle.get_instance_id())


## Jingle-Duck für dauer_s (+ Nachhall) halten; verlängert, kürzt nie.
func stinger_setzen(dauer_s: float) -> void:
	_stinger_rest = maxf(_stinger_rest, maxf(dauer_s, 0.0) + STINGER_NACHHALL_S)


## Zustands-Foto für Playtest-/Debug-Pegel-Dumps (Bett an/aus/duck).
func debug_dump() -> Dictionary:
	var ebenen := {}
	for ebene: String in _ebenen:
		var zustand: Dictionary = _ebenen[ebene]
		var player: AudioStreamPlayer = zustand["player"]
		ebenen[ebene] = {
			"ist": snappedf(float(zustand["ist"]), 0.001),
			"ziel": float(zustand["ziel"]),
			"volume_db": snappedf(player.volume_db, 0.1) if player != null else null,
			"spielt": player != null and player.playing,
		}
	var sfx_idx := AudioServer.get_bus_index("Sfx")
	return {
		"ziel_ort": _ziel_ort,
		"duck": snappedf(_duck, 0.001),
		"stinger_rest_s": snappedf(_stinger_rest, 0.01),
		"gebrabbel_quellen": _gebrabbel.size(),
		"ebenen": ebenen,
		"sfx_bus_db":
		snappedf(AudioServer.get_bus_volume_db(sfx_idx), 0.1) if sfx_idx >= 0 else null,
		"sfx_bus_mute": AudioServer.is_bus_mute(sfx_idx) if sfx_idx >= 0 else null,
	}


# ── Intern ────────────────────────────────────────────────────────────────────


func _on_travel_finished(target: StringName) -> void:
	wechsle_zu(String(target))


func _setze_ziel(ebene: String, gain: float) -> void:
	if not _ebenen.has(ebene):
		if gain <= 0.0:
			return
		_ebenen[ebene] = {"ist": 0.0, "ziel": gain, "player": null}
		return
	_ebenen[ebene]["ziel"] = gain


func _fahre_ebene(ebene: String, delta: float) -> void:
	var zustand: Dictionary = _ebenen[ebene]
	var ist := gain_schritt(float(zustand["ist"]), float(zustand["ziel"]), delta)
	zustand["ist"] = ist
	var player: AudioStreamPlayer = zustand["player"]
	if ist <= STILL_SCHWELLE and float(zustand["ziel"]) <= 0.0:
		if player != null and is_instance_valid(player) and player.playing:
			player.stop()
		return
	if stumm:
		return
	if player == null:
		player = _erzeuge_player(str(EBENEN_IDS[ebene]))
		if player == null:
			return
		zustand["player"] = player
	if not player.playing:
		player.play()
	var basis := float(SfxMap.entry(str(EBENEN_IDS[ebene])).get("volume_db", 0.0))
	player.volume_db = ebene_db(basis, ist, _duck)


## Loop-Player auf dem Sfx-Bus (Muster RanchAudio; Stream dupliziert,
## damit der One-Shot-Cache des AudioDirector loop-frei bleibt).
func _erzeuge_player(sfx_id: String) -> AudioStreamPlayer:
	var pfad := SfxMap.path(sfx_id)
	if pfad.is_empty() or not ResourceLoader.exists(pfad):
		push_warning("[klangbett] Bett-Datei fehlt: %s (%s)" % [sfx_id, pfad])
		return null
	if not _streams.has(sfx_id):
		var stream: AudioStream = (load(pfad) as AudioStream).duplicate()
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_streams[sfx_id] = stream
	var player := AudioStreamPlayer.new()
	player.bus = &"Sfx"
	player.stream = _streams[sfx_id]
	player.volume_db = -60.0
	add_child(player)
	return player


## Erloschene Sprech-Quellen aus dem Duck-Set fegen: freigegebene Objekte
## (Szene entladen, Ende nie gemeldet) UND verstummte Stimmen — GoobyVoice
## meldet über ist_am_reden() die Wahrheit, damit hält kein verpasstes
## Ende-Signal das Bett dauerhaft unten (Selbstheilung pro Takt).
func _gebrabbel_aufraeumen() -> void:
	for id: int in _gebrabbel.keys():
		# Freigegebene Instanz NIE erst typisiert zuweisen (Script-Error
		# „previously freed instance“) — direkt am Dictionary-Wert prüfen.
		if not is_instance_valid(_gebrabbel[id]):
			_gebrabbel.erase(id)
			continue
		var quelle: Object = _gebrabbel[id]
		if quelle.has_method("ist_am_reden") and not bool(quelle.call("ist_am_reden")):
			_gebrabbel.erase(id)

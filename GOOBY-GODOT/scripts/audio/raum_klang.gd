class_name RaumKlang
extends Node
## G6-FEEL — Orts-Raumgefühl, Bus-basiert und bewusst DEZENT: ein einziger
## AudioEffectReverb auf dem bestehenden Sfx-Bus (KEINE neuen Busse,
## Lautstärkeregler greifen weiter), dessen Wet-Anteil weich zwischen
## Zonen-Profilen überblendet wird. Laden-Innenräume bekommen einen kleinen
## warmen Raum, die Stations-Halle etwas mehr Luft, die Ranch-Weite einen
## hauchzarten offenen Hall — draußen und überall sonst bleibt alles
## trocken (Effekt wird dann komplett deaktiviert, Mobile-Budget).
##
## Verdrahtung (defensiv, Muster RanchAudio): der Knoten hängt als Kind
## unter dem Audio-Autoload (AudioDirector legt ihn an) und hört auf
## SceneRouter.travel_finished — Ranch-Ziele werden „weite", alles außer
## Orten fällt auf „neutral" zurück. Orte melden ihre Zone selbst in
## OrtScene._ready() über den Hook `_raum_zone()` (innen/draußen kennt nur
## die Szene; travel_finished feuert NACH _ready und lässt city/ort-Ziele
## deshalb unangetastet). Headless-sicher: ohne Baum springen Fades sofort
## ans Ziel, der Dummy-Treiber spielt still.
##
## Die Zonen-Mathematik (zone_fuer_ziel, profil) ist PURE und im Runner
## testbar; Wache: tests/unit/test_g6_audio_feel.gd (inkl. Dezenz-Deckel).

const NODE_NAME := "RaumKlang"
const BUS_NAME := "Sfx"
## Weiche Zonen-Übergänge (an den Ambience-Fade der Ranch angelehnt).
const FADE_S := 0.8
## Dezenz-Deckel: kein Profil darf nasser sein (Wache im Test).
const MAX_WET := 0.15

## Zone → Reverb-Profil. wet 0 = Effekt aus (trocken).
const PROFILE := {
	"neutral": {"wet": 0.0, "room_size": 0.3, "damping": 0.6, "predelay_ms": 10.0},
	"laden_innen": {"wet": 0.10, "room_size": 0.30, "damping": 0.62, "predelay_ms": 12.0},
	"ort_draussen": {"wet": 0.0, "room_size": 0.3, "damping": 0.6, "predelay_ms": 10.0},
	"station_halle": {"wet": 0.13, "room_size": 0.55, "damping": 0.45, "predelay_ms": 22.0},
	"weite": {"wet": 0.06, "room_size": 0.95, "damping": 0.30, "predelay_ms": 40.0},
}

static var _fallback: RaumKlang

var _zone := "neutral"
var _wet := 0.0
var _tween: Tween


## Autoload-frei nutzbar (Muster RanchAudio): Kind des Audio-Autoloads
## bevorzugt, sonst /root/RaumKlang, sonst lazy-Instanz unter /root.
static func get_or_create(from: Node) -> RaumKlang:
	for pfad in ["/root/Audio/%s" % NODE_NAME, "/root/%s" % NODE_NAME]:
		var existing := from.get_node_or_null(pfad)
		if existing is RaumKlang:
			return existing
	if _fallback != null and is_instance_valid(_fallback):
		return _fallback
	var node := RaumKlang.new()
	node.name = NODE_NAME
	_fallback = node
	from.get_tree().root.add_child.call_deferred(node)
	return node


## Bequemer One-Liner für Szenen-Wiring: Zone setzen, wenn ein Baum da ist —
## sonst still no-op (Unit-Tests mit freien Nodes, allererster Frame).
static func betrete(from: Node, zone: String) -> void:
	if from == null or not from.is_inside_tree():
		return
	get_or_create(from).setze_zone(zone)


# ── PURE: Zonen-Zuordnung + Profile (Runner-testbar) ─────────────────────────


## Router-Ziel → Zone. "" = nicht anfassen: city/ort-Ziele melden ihre Zone
## selbst über OrtScene._raum_zone() (innen vs. draußen kennt nur die Szene).
static func zone_fuer_ziel(ziel: String) -> String:
	if ziel.begins_with("city/ort/"):
		return ""
	if ziel.begins_with("ranch/"):
		return "weite"
	if ziel == "arcade":
		return "laden_innen"
	return "neutral"


## Zonen-Profil ({} = unbekannte Zone — Aufrufer lässt dann alles stehen).
static func profil(zone: String) -> Dictionary:
	return PROFILE.get(zone, {})


static func kennt(zone: String) -> bool:
	return PROFILE.has(zone)


# ── Zonen-Fahrer (Bus-Effekt + weicher Wet-Fade) ─────────────────────────────


func _ready() -> void:
	# Deferred: der SceneRouter-Autoload wird NACH dem Audio-Autoload
	# initialisiert — beim Audio-_ready existiert er noch nicht.
	_verbinde_router.call_deferred()


func zone() -> String:
	return _zone


## Zone mit weichem Übergang anfahren; sofort=true springt (Tests/Headless).
func setze_zone(neue_zone: String, sofort := false) -> void:
	if not kennt(neue_zone) or neue_zone == _zone:
		return
	_zone = neue_zone
	var ziel: Dictionary = profil(neue_zone)
	var effekt := _hole_effekt()
	if effekt == null:
		return
	effekt.room_size = float(ziel["room_size"])
	effekt.damping = float(ziel["damping"])
	effekt.predelay_msec = float(ziel["predelay_ms"])
	effekt.dry = 1.0
	var ziel_wet := minf(float(ziel["wet"]), MAX_WET)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if sofort or not is_inside_tree():
		_wende_wet_an(ziel_wet)
		return
	_setze_effekt_aktiv(true)
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_wende_wet_an, _wet, ziel_wet, FADE_S)


## Aktueller Wet-Anteil (0..1) — für Tests/Diagnose.
func wet() -> float:
	return _wet


func _verbinde_router() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_signal("travel_finished"):
		return
	if not router.travel_finished.is_connected(_on_travel_finished):
		router.travel_finished.connect(_on_travel_finished)


func _on_travel_finished(target: StringName) -> void:
	var neue_zone := zone_fuer_ziel(String(target))
	if not neue_zone.is_empty():
		setze_zone(neue_zone)


func _wende_wet_an(wert: float) -> void:
	_wet = wert
	var idx := _effekt_index()
	if idx < 0:
		return
	var bus := AudioServer.get_bus_index(BUS_NAME)
	var effekt := AudioServer.get_bus_effect(bus, idx) as AudioEffectReverb
	effekt.wet = wert
	# Trocken = Effekt ganz aus (spart DSP auf Mobile).
	AudioServer.set_bus_effect_enabled(bus, idx, wert > 0.0005)


func _setze_effekt_aktiv(aktiv: bool) -> void:
	var idx := _effekt_index()
	if idx >= 0:
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(BUS_NAME), idx, aktiv)


## Den EINEN Reverb auf dem Sfx-Bus finden oder anlegen (nie duplizieren).
func _hole_effekt() -> AudioEffectReverb:
	var bus := AudioServer.get_bus_index(BUS_NAME)
	if bus < 0:
		return null
	var idx := _effekt_index()
	if idx >= 0:
		return AudioServer.get_bus_effect(bus, idx) as AudioEffectReverb
	var effekt := AudioEffectReverb.new()
	effekt.wet = 0.0
	effekt.dry = 1.0
	AudioServer.add_bus_effect(bus, effekt)
	AudioServer.set_bus_effect_enabled(bus, AudioServer.get_bus_effect_count(bus) - 1, false)
	return effekt


func _effekt_index() -> int:
	var bus := AudioServer.get_bus_index(BUS_NAME)
	if bus < 0:
		return -1
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectReverb:
			return i
	return -1

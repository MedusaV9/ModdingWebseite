class_name GobtyClipPlayer
extends RefCounted
## GOB.TY-Abspiellogik (W13C/GOBTY) — PURE Ablaufmaschine, komplett
## zeitinjiziert (alle Methoden nehmen `now_ms`): kein Timer, kein Zufall,
## kein Node. Der Fernseher (fernseher.gd) treibt sie aus _process und
## inszeniert die zurückgegebenen Schritte auf der GobtyTvStage; Tests
## treiben sie mit synthetischen Zeiten.
##
## Verantwortung:
##  - Schritt-Scheduling innerhalb eines Clips (Schritt n zur Zeit t),
##  - Auto-Rotation ans Clip-Ende (nächster Sendeplatz) + manuelles Zapping,
##  - Schlagzeilen-Rotation des News-Clips (jeder Durchlauf 3 neue),
##  - Fun-Gutschrift der Sitzung: +1 Spaß je FUN_INTERVALL_MS, gedeckelt
##    auf FUN_CAP pro Sitzung (Einschalten → Ausschalten).

const Stats := preload("res://scripts/logic/stats.gd")

## Fernsehen macht langsam Spaß: alle 30 s ein Pünktchen …
const FUN_INTERVALL_MS := 30_000
## … aber höchstens +10 pro Sitzung (reines Gemütlichkeits-Feature,
## kein Energie-/Zeitverbrauch).
const FUN_CAP := 10

var clips: Array[Dictionary] = []
var index := 0

var _clip_start_ms := 0
var _session_start_ms := 0
var _schritt_cursor := -1
var _fun_gutgeschrieben := 0
var _news_rotation := -1


func _init(programm: Array[Dictionary]) -> void:
	clips = programm


## Sitzung starten (Einschalten): Sendeplatz 1, Fun-Zähler auf null.
func start(now_ms: int) -> void:
	_session_start_ms = now_ms
	_fun_gutgeschrieben = 0
	index = -1
	_naechster_clip(now_ms)


## Manuelles Zapping (Tap auf den laufenden Fernseher): nächster Sendeplatz.
func zap(now_ms: int) -> void:
	_naechster_clip(now_ms)


## Ein Takt: liefert {schritte, clip_gewechselt, fun_delta}.
##  - schritte: alle Schritte, deren t seit dem letzten Takt erreicht wurde
##    (in Def-Reihenfolge — die Bühne spielt sie nacheinander an),
##  - clip_gewechselt: true, wenn der Clip zu Ende war und rotiert wurde,
##  - fun_delta: fällige, noch nicht gutgeschriebene Spaß-Punkte (0..).
func tick(now_ms: int) -> Dictionary:
	var out := {"schritte": [] as Array[Dictionary], "clip_gewechselt": false, "fun_delta": 0}
	if clips.is_empty():
		return out
	if verstrichen_s(now_ms) >= float(aktueller_clip()["dauer_s"]):
		_naechster_clip(now_ms)
		out["clip_gewechselt"] = true
	var schritte: Array = aktueller_clip()["schritte"]
	var ziel := schritt_index(aktueller_clip(), verstrichen_s(now_ms))
	while _schritt_cursor < ziel:
		_schritt_cursor += 1
		(out["schritte"] as Array[Dictionary]).append(schritte[_schritt_cursor])
	var faellig := fun_faellig(now_ms)
	out["fun_delta"] = faellig - _fun_gutgeschrieben
	_fun_gutgeschrieben = faellig
	return out


func aktueller_clip() -> Dictionary:
	return clips[index] if index >= 0 and index < clips.size() else {}


## Sekunden seit Clip-Start (zeitinjiziert).
func verstrichen_s(now_ms: int) -> float:
	return maxf(0.0, float(now_ms - _clip_start_ms) / 1000.0)


## Fällige Fun-Punkte der GANZEN Sitzung (monoton, gedeckelt) — Zapping
## setzt NICHT zurück, nur eine neue Sitzung.
func fun_faellig(now_ms: int) -> int:
	return mini(FUN_CAP, int((now_ms - _session_start_ms) / float(FUN_INTERVALL_MS)))


func fun_gutgeschrieben() -> int:
	return _fun_gutgeschrieben


## Schlagzeilen-Key für einen News-Schritt (banner == "schlagzeile").
func schlagzeile_fuer(schritt: Dictionary) -> String:
	return GobtyClipDefs.schlagzeilen_key(maxi(0, _news_rotation), int(schritt.get("slot", 0)))


## PURE: Index des letzten Schritts mit t <= verstrichen (Schritt n zur
## Zeit t — deterministisch, Tests messen hierüber).
static func schritt_index(clip: Dictionary, verstrichen: float) -> int:
	var schritte: Array = clip.get("schritte", [])
	var ziel := -1
	for i in schritte.size():
		if float((schritte[i] as Dictionary).get("t", 0.0)) <= verstrichen:
			ziel = i
	return ziel


## PURE: Fun-Delta über die bestehende Stats-API auf den Save anwenden
## (gooby.stats via Stats.apply_deltas — clamped, nur der fun-Kanal).
static func wende_fun_an(state: Dictionary, delta: int) -> void:
	if delta <= 0:
		return
	var gooby: Dictionary = state.get("gooby", {})
	var stats: Dictionary = gooby.get("stats", {})
	gooby["stats"] = Stats.apply_deltas(stats, {"fun": float(delta)})
	state["gooby"] = gooby


func _naechster_clip(now_ms: int) -> void:
	if clips.is_empty():
		return
	index = posmod(index + 1, clips.size())
	_clip_start_ms = now_ms
	_schritt_cursor = -1
	if str(aktueller_clip().get("id", "")) == "news":
		_news_rotation += 1

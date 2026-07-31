class_name FuetterSequenz
extends RefCounted
## W14/FRIDGE — PURE Fütter-Sequenz-Statemaschine (zeitinjiziert, headless
## testbar). Der User-Wunsch: „Gooby muss gefüttert werden"-GEFÜHL — nach der
## Auswahl wird NICHT mehr sofort gebucht, sondern die Speise schwebt zu
## Gooby, es gibt Mampf-Bisse, Schluck und eine Emotion; ERST das letzte
## Ereignis (`buchen`) gibt die Buchung frei (FoodCatalog.apply_feed bleibt
## beim Aufrufer — die Buchungs-Semantik ist unangetastet).
##
## Kein Node, kein Timer: der Aufrufer pumpt `tick(now_ms)` und bekommt jedes
## fällige Ereignis GENAU EINMAL in Reihenfolge. `start()` während einer
## laufenden Sequenz ist der Doppel-Tap-Guard (false, nichts passiert) — und
## mit ~2,5 s Gesamtlänge ist die Sequenz bewusst kurz genug, um NICHT
## unterbrechbar zu sein.

const PHASE_BEREIT := "bereit"
const PHASE_SCHWEBEN := "schweben"
const PHASE_MAMPF := "mampf"
const PHASE_SCHLUCK := "schluck"
const PHASE_EMOTION := "emotion"
const PHASE_FERTIG := "fertig"

## Volle Sequenz: 700 + 3×350 + 300 + 450 = 2500 ms (~2,5 s).
const SCHWEBEN_MS := 700
const BISS_MS := 350
const SCHLUCK_MS := 300
const EMOTION_MS := 450
const BISSE_VOLL := 3
## Reduced Motion: Kurzfassung — kürzerer Anflug + genau EIN Biss (1500 ms).
const SCHWEBEN_REDUZIERT_MS := 400
const BISSE_REDUZIERT := 1

## Emotions-Arten am Sequenz-Ende (Regie inszeniert sie im Raum).
const EMOTION_VERLIEBT := "verliebt"
const EMOTION_ZUCKER := "zucker"
const EMOTION_FROH := "froh"

var _food_id := ""
var _laeuft := false
var _start_ms := 0
var _naechster := 0
var _events: Array[Dictionary] = []


## Refusal-Kurzschluss VOR der Sequenz — nutzt die BESTEHENDEN Gates
## (FoodCatalog.too_full + Vorrat > 0), dupliziert KEINE Buchungslogik;
## apply_feed prüft beim Buchen weiterhin selbst (fail-closed).
## "" = frei, sonst "satt" | "leer".
static func refusal(state: Dictionary, food_id: String) -> String:
	if FoodCatalog.too_full(state):
		return "satt"
	var food: Variant = state.get("inventory", {}).get("food")
	var count := 0
	if food is Dictionary:
		var raw: Variant = (food as Dictionary).get(food_id)
		count = int(raw) if (raw is int or raw is float) else 0
	if count <= 0:
		return "leer"
	return ""


## Emotion am Ende: Lieblingsessen → verliebt, Junk → Zucker-Zittern-Gag,
## sonst schlicht froh.
static func emotion_fuer(food_id: String) -> String:
	if FoodCatalog.is_favorite(food_id):
		return EMOTION_VERLIEBT
	if FoodCatalog.is_junk(food_id):
		return EMOTION_ZUCKER
	return EMOTION_FROH


## Sequenz starten. false = läuft bereits (Doppel-Tap abgewehrt).
func start(food_id: String, now_ms: int, reduziert := false) -> bool:
	if _laeuft:
		return false
	_food_id = food_id
	_laeuft = true
	_start_ms = now_ms
	_naechster = 0
	_events = _baue_zeitplan(food_id, reduziert)
	return true


func ist_aktiv() -> bool:
	return _laeuft


func food_id() -> String:
	return _food_id


## Gesamtlänge in ms (Zeitpunkt des `buchen`-Ereignisses).
func dauer_ms() -> int:
	if _events.is_empty():
		return 0
	return int(_events[-1]["at"])


func biss_anzahl() -> int:
	var out := 0
	for ev: Dictionary in _events:
		if str(ev["typ"]) == "biss":
			out += 1
	return out


## Fällige Ereignisse seit dem letzten Tick — jedes GENAU EINMAL, in
## Reihenfolge. Das letzte (`buchen`) beendet die Sequenz.
func tick(now_ms: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	if not _laeuft:
		return due
	var offset := now_ms - _start_ms
	while _naechster < _events.size() and int(_events[_naechster]["at"]) <= offset:
		due.append(_events[_naechster])
		_naechster += 1
	if _naechster >= _events.size():
		_laeuft = false
	return due


## Zeit-abgeleitete Phase (rein informativ, z. B. für Screenshots/Tests).
func phase(now_ms: int) -> String:
	if _events.is_empty():
		return PHASE_BEREIT
	var offset := now_ms - _start_ms
	if offset >= dauer_ms() and not _laeuft:
		return PHASE_FERTIG
	var aktuell := PHASE_SCHWEBEN
	for ev: Dictionary in _events:
		if int(ev["at"]) > offset:
			break
		match str(ev["typ"]):
			"biss":
				aktuell = PHASE_MAMPF
			"schluck":
				aktuell = PHASE_SCHLUCK
			"emotion":
				aktuell = PHASE_EMOTION
			"buchen":
				aktuell = PHASE_FERTIG
	return aktuell


static func _baue_zeitplan(food_id: String, reduziert: bool) -> Array[Dictionary]:
	var bisse := BISSE_REDUZIERT if reduziert else BISSE_VOLL
	var schweben := SCHWEBEN_REDUZIERT_MS if reduziert else SCHWEBEN_MS
	var out: Array[Dictionary] = [{"at": 0, "typ": "schwebt", "dauer_ms": schweben}]
	var t := schweben
	for i in bisse:
		out.append({"at": t, "typ": "biss", "index": i + 1, "von": bisse})
		t += BISS_MS
	out.append({"at": t, "typ": "schluck"})
	t += SCHLUCK_MS
	out.append({"at": t, "typ": "emotion", "art": emotion_fuer(food_id)})
	t += EMOTION_MS
	out.append({"at": t, "typ": "buchen"})
	return out

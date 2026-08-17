class_name GeistRekord
extends RefCounted
## W19/GEIST — Rekord-Geist der Arcade-Minigames (pure Logik, kein Node):
## zeichnet während einer Runde die Score-über-Zeit-Kurve auf und vergleicht
## eine laufende Runde live gegen den gespeicherten Bestlauf des Spiels
## (Konzept-Vorbild: der asynchrone „Geisterlauf“ aus RANCH-DLC-IDEAS-3 §5.3
## — hier score-basiert statt positionsbasiert generalisiert).
##
## ZEIT: getaktet über die Framework-Zeit des Hosts (injizierte _process-
## Deltas — läuft nur, während das Spiel wirklich tickt: nach dem GO, nicht
## in Pause/Freeze). KEINE OS-Uhr, kein RNG — vollständig deterministisch
## testbar (AGENTS.md-Regel „Zeit/RNG immer injizieren“).
##
## GRÖSSENBUDGET (Save): pro Spiel EINE Bestlauf-Kurve unter
## `minigames.geist.<gameId>` (additiver v5-Key, merge_defaults lässt ihn
## überleben — Muster `minigames.difficulty`). Abtastung 1 Hz; ab
## MAX_STUETZEN Stützstellen wird die Kurve verlustbehaftet verdichtet
## (jede 2. Stützstelle fällt weg, Schrittweite verdoppelt sich) — die
## Kurve bleibt damit IMMER <= MAX_STUETZEN Ganzzahlen (~<1 KB JSON pro
## Spiel, Scores zusätzlich auf 0..SCORE_MAX geklemmt). 160 Stützstellen
## decken 160 s in voller Auflösung, längere/Endlos-Runden entsprechend
## gröber (2 s/4 s/…) — für den ±Delta-Chip mehr als genug.
##
## REKORD-REGEL: Der Geist lebt in der ROHEN Live-Score-Welt (das, was der
## Spieler in der Top-Bar sieht) — Modifier-Boosts (score_mult) und die
## per-Modus-Boards des Awards bleiben unberührt. Die Kurve wird GENAU dann
## ersetzt, wenn der Endstand einer regulär beendeten Runde MIT Live-Score-
## Fluss den gespeicherten Kurven-Score übertrifft (Gleichstand ersetzt
## nicht); Runden ohne Live-Score-Meldung zeichnen nie eine Kurve auf.

## Abtastintervall der Aufzeichnung in Sekunden (1 Hz laut Paket-Umfang).
const SCHRITT_SEC := 1.0
## Budget: maximale Stützstellen einer Kurve (s. Datei-Kopf).
const MAX_STUETZEN := 160
## Sanity-Klemme für gespeicherte Scores (kompaktes JSON, kein Overflow).
const SCORE_MAX := 9_999_999

## Aufzeichnung der laufenden Runde (Stützstelle i = Zeit i * _schritt).
var _kurve: Array[int] = [0]
var _schritt := SCHRITT_SEC
var _zeit := 0.0
var _naechste := SCHRITT_SEC
## true, sobald das Spiel während der Runde report_score gemeldet hat —
## das Gate für Chip UND Kurven-Speicherung (Spiele ohne Score-Fluss raus).
var _live_score := false
## Gespeicherter Bestlauf beim Rundenstart ({} = kein Geist-Vergleich).
var _referenz: Dictionary = {}


## Rekorder für eine frische Runde aufsetzen. `referenz` = gespeicherter
## Bestlauf des Spiels (rekord_von) — ungültige Rekorde werden verworfen.
func starte(referenz: Dictionary) -> void:
	_kurve = [0]
	_schritt = SCHRITT_SEC
	_zeit = 0.0
	_naechste = _schritt
	_live_score = false
	_referenz = referenz if ist_gueltig(referenz) else {}


## Framework-Zeit voranschreiben (injiziert, s. Datei-Kopf) und den
## aktuellen Live-Score an jeder überschrittenen Abtastgrenze festhalten.
func tick(delta_sec: float, score: int) -> void:
	if delta_sec <= 0.0:
		return
	_zeit += delta_sec
	while _zeit >= _naechste:
		_kurve.append(_clamp_score(score))
		_naechste += _schritt
		if _kurve.size() > MAX_STUETZEN:
			_verdichte()


## Vom Host bei jeder report_score-Meldung der Runde gerufen (Gate, s. oben).
func melde_live_score() -> void:
	_live_score = true


func hat_referenz() -> bool:
	return not _referenz.is_empty()


func hat_live_score() -> bool:
	return _live_score


func zeit() -> float:
	return _zeit


## Live-Delta zum Geist an der aktuellen Rundenzeit (+ = vor dem Bestlauf).
func delta_aktuell(score: int) -> int:
	return delta_fuer(_referenz, _zeit, score)


## „Geist geschlagen“: es GAB einen Bestlauf und der Endstand übertrifft ihn.
func geschlagen(final_score: int) -> bool:
	return hat_referenz() and _clamp_score(final_score) > rekord_score(_referenz)


## Speicherbarer Bestlauf-Kandidat der Runde ({} ohne Live-Score-Fluss).
func snapshot(final_score: int) -> Dictionary:
	if not _live_score:
		return {}
	return {
		"score": _clamp_score(final_score),
		"schritt_sec": _schritt,
		"dauer_sec": _zeit,
		"kurve": _kurve.duplicate(),
	}


## Defensiver Save-Reader: gespeicherter Bestlauf oder {} (nie werfen —
## Muster MinigameFrameworkLogic.difficulty_slice_of).
static func rekord_von(state: Dictionary, game_id: String) -> Dictionary:
	var geist := _dict(_dict(state.get("minigames")).get("geist"))
	var rekord := _dict(geist.get(game_id))
	return rekord if ist_gueltig(rekord) else {}


static func ist_gueltig(rekord: Dictionary) -> bool:
	var kurve: Variant = rekord.get("kurve")
	if not (kurve is Array) or (kurve as Array).is_empty():
		return false
	return _num(rekord.get("schritt_sec")) > 0.0


static func rekord_score(rekord: Dictionary) -> int:
	return _clamp_score(int(floor(_num(rekord.get("score")))))


## Geist-Wert bei t_sec: linear interpoliert zwischen den Stützstellen;
## hinter der letzten Stützstelle läuft die Kurve auf den Endstand zu und
## bleibt ab dauer_sec dort stehen (JSON-Round-Trip macht aus ints floats —
## alle Lesezugriffe sind entsprechend defensiv).
static func wert_bei(rekord: Dictionary, t_sec: float) -> float:
	if not ist_gueltig(rekord):
		return 0.0
	var kurve: Array = rekord["kurve"]
	var schritt := _num(rekord.get("schritt_sec"), SCHRITT_SEC)
	var final_score := float(rekord_score(rekord))
	var letzte_zeit := float(kurve.size() - 1) * schritt
	var dauer := maxf(_num(rekord.get("dauer_sec")), letzte_zeit)
	if t_sec <= 0.0:
		return maxf(0.0, _num(kurve[0]))
	if t_sec >= dauer:
		return final_score
	if t_sec >= letzte_zeit:
		var span := dauer - letzte_zeit
		if span <= 0.0:
			return final_score
		var rest := (t_sec - letzte_zeit) / span
		return lerpf(maxf(0.0, _num(kurve[kurve.size() - 1])), final_score, rest)
	var pos := t_sec / schritt
	var i := int(floor(pos))
	var a := maxf(0.0, _num(kurve[i]))
	var b := maxf(0.0, _num(kurve[mini(i + 1, kurve.size() - 1)]))
	return lerpf(a, b, pos - float(i))


## Vorzeichen-Delta Spieler minus Geist bei t_sec ({} = Delta zum Nullpunkt
## — Aufrufer gaten sichtbare Anzeigen über hat_referenz()).
static func delta_fuer(rekord: Dictionary, t_sec: float, score: int) -> int:
	return score - int(round(wert_bei(rekord, t_sec)))


## Bestlauf-Ablösung: ersetzt `minigames.geist.<gameId>` GENAU dann, wenn
## `snap` gültig ist und dessen Score den gespeicherten übertrifft (bzw.
## noch kein gültiger Rekord existiert). Mutiert `state` in place —
## innerhalb von GameState.update aufrufen. true = Kurve wurde ersetzt.
static func uebernehme_rekord(state: Dictionary, game_id: String, snap: Dictionary) -> bool:
	if not ist_gueltig(snap):
		return false
	var mg: Variant = state.get("minigames")
	if not (mg is Dictionary):
		return false
	var alt := rekord_von(state, game_id)
	if not alt.is_empty() and rekord_score(snap) <= rekord_score(alt):
		return false
	if not ((mg as Dictionary).get("geist") is Dictionary):
		(mg as Dictionary)["geist"] = {}
	((mg as Dictionary)["geist"] as Dictionary)[game_id] = snap.duplicate(true)
	return true


## Chip-Text fürs Live-Delta: „+12“ / „−5“ (echtes Minus U+2212) / „±0“.
static func delta_text(delta: int) -> String:
	if delta > 0:
		return "+%d" % delta
	if delta < 0:
		return "−%d" % absi(delta)
	return "±0"


## Budget-Verdichtung: jede 2. Stützstelle fällt weg, Schrittweite ×2 —
## Zeitachse bleibt identisch (Stützstelle i sitzt weiter bei i * _schritt).
func _verdichte() -> void:
	var neu: Array[int] = []
	for i in range(0, _kurve.size(), 2):
		neu.append(_kurve[i])
	_kurve = neu
	_schritt *= 2.0
	_naechste = float(_kurve.size()) * _schritt


static func _clamp_score(score: int) -> int:
	return clampi(score, 0, SCORE_MAX)


static func _num(value: Variant, fallback := 0.0) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

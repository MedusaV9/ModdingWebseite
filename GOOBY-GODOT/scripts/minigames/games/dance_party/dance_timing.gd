class_name DanceTiming
extends RefCounted
## W15/TECHKIT (Doc G §9 R5) — Audio-Latenz-Kalibrierung für danceParty.
##
## PURE Timing-Quelle: kapselt die Godot-Standard-Kompensation für
## Rhythm-Games (Docs „Sync the gameplay with audio") — die GEHÖRTE Songzeit
## hinkt der Spiel-Uhr um `AudioServer.get_output_latency()` hinterher,
## `AudioServer.get_time_since_last_mix()` glättet chunk-weise springende
## Playback-Positionen. Dazu kommt ein MANUELLER Feinoffset aus der
## Metronom-Kalibrierung (Median aus 8 Tipps, geklemmt auf ±150 ms), der
## additiv im Save-Slice `minigames.danceOffsetMs` liegt (v5-additiver Key,
## Muster `minigames.difficulty.<id>` aus pregame.gd).
##
## WICHTIG (CROSSCHECK-Vertrag): Diese Klasse berührt WEDER die Wertungs-
## noch die Score-Formel (dance_party_logic.gd bleibt zahlengleich zum Web)
## und wird von `simulate_autoplay` NIE benutzt — der Zertifizierungs-Bot
## läuft mit Offset 0. Nur die SZENE verschiebt ihre sichtbare/gefühlte
## Zeitachse (Note-Position + Treffer-Fenster) um den Gesamtoffset.

## Klemme des manuellen Feinoffsets (ms) — mehr ist immer ein Messfehler.
const MANUAL_CLAMP_MS := 150.0
## Sicherheitsdeckel der automatischen Basis-Latenz (ms) — kaputte Treiber
## melden teils absurde Werte, die den Song unspielbar verschieben würden.
const BASE_CLAMP_MS := 500.0
## Metronom-Kalibrierung: 8 Schläge im danceParty-Takt (100 BPM = 0,6 s).
const CALIBRATION_BEATS := 8
const CALIBRATION_BEAT_SEC := 0.6
const CALIBRATION_LEAD_IN_SEC := 1.2
## Additiver Save-Key im minigames-Slice.
const SAVE_KEY := "danceOffsetMs"

## Automatische Basis-Kompensation (ms), einmal beim Setup gemessen.
var base_latency_ms := 0.0
## Manueller Feinoffset (ms) aus der Kalibrierung (Save).
var manual_offset_ms := 0.0


## Szenen-Einstieg: liest die AudioServer-Latenz EINMAL (der Aufruf kann je
## Plattform teuer sein) und kombiniert sie mit dem Save-Feinoffset.
static func from_audio_server(manual_ms := 0.0) -> DanceTiming:
	var timing := DanceTiming.new()
	timing.base_latency_ms = base_latency_from(
		AudioServer.get_output_latency(), AudioServer.get_time_since_last_mix()
	)
	timing.manual_offset_ms = clamp_manual(manual_ms)
	return timing


## Pure Basis-Latenz aus injizierten AudioServer-Werten (ms). since_mix
## dient nur als Plausibilitäts-Glättung: direkt nach einem Mix ist die
## effektive Rest-Latenz um die bereits verstrichene Mix-Zeit kleiner.
static func base_latency_from(output_latency_sec: float, since_mix_sec: float) -> float:
	var latency := output_latency_sec - minf(maxf(since_mix_sec, 0.0), output_latency_sec)
	return clampf(latency * 1000.0, 0.0, BASE_CLAMP_MS)


## Godot-Standard-Formel für Song-Uhren MIT echter Playback-Position
## (AudioStreamPlayer): Position + Mix-Glättung − Ausgabe-Latenz.
static func smoothed_playback_sec(
	playback_pos_sec: float, since_mix_sec: float, output_latency_sec: float
) -> float:
	return playback_pos_sec + since_mix_sec - output_latency_sec


## Manuellen Feinoffset klemmen (±150 ms).
static func clamp_manual(ms: float) -> float:
	if not is_finite(ms):
		return 0.0
	return clampf(ms, -MANUAL_CLAMP_MS, MANUAL_CLAMP_MS)


## Gesamtoffset (ms) = automatische Basis + geklemmter manueller Anteil.
func total_offset_ms() -> float:
	return clampf(base_latency_ms, 0.0, BASE_CLAMP_MS) + clamp_manual(manual_offset_ms)


## DIE kompensierte Zeitachse der Szene: Note-Position und Treffer-Fenster
## rechnen mit dieser Zeit statt mit der rohen Spiel-Uhr.
func play_time(song_time: float) -> float:
	return song_time - total_offset_ms() / 1000.0


## Median einer ms-Liste (Kalibrier-Tipps): robust gegen einzelne Ausreißer;
## Nicht-Zahlen werden IGNORIERT (nicht als 0 gewertet — das würde den
## Median hostiler Eingaben Richtung 0 ziehen).
static func median_ms(values: Array) -> float:
	var clean: Array[float] = []
	for value: Variant in values:
		var f := _num(value, NAN)
		if is_finite(f):
			clean.append(f)
	if clean.is_empty():
		return 0.0
	clean.sort()
	var mid := clean.size() / 2
	if clean.size() % 2 == 1:
		return clean[mid]
	return (clean[mid - 1] + clean[mid]) * 0.5


## Kalibrier-Ergebnis: Median der Tipp-Abweichungen MINUS die schon
## automatisch kompensierte Basis-Latenz (sonst würde sie doppelt zählen),
## geklemmt auf ±150 ms.
static func manual_from_taps(tap_deltas_ms: Array, base_ms: float) -> float:
	if tap_deltas_ms.is_empty():
		return 0.0
	return clamp_manual(median_ms(tap_deltas_ms) - clampf(base_ms, 0.0, BASE_CLAMP_MS))


## Einen Kalibrier-Tipp dem nächstliegenden Metronom-Schlag zuordnen.
## Liefert {"beat": Index 0..beats-1, "delta_ms": Tipp − Schlagzeit}.
static func tap_delta_ms(
	tap_sec: float,
	lead_in_sec := CALIBRATION_LEAD_IN_SEC,
	beat_sec := CALIBRATION_BEAT_SEC,
	beats := CALIBRATION_BEATS
) -> Dictionary:
	var raw := (tap_sec - lead_in_sec) / maxf(beat_sec, 0.001)
	var beat := clampi(int(round(raw)), 0, maxi(beats - 1, 0))
	var delta := (tap_sec - (lead_in_sec + beat * beat_sec)) * 1000.0
	return {"beat": beat, "delta_ms": delta}


## Defensiver Save-Reader (Muster framework_logic.difficulty_slice_of):
## hostile/fehlende Container liefern 0.
static func manual_offset_from_state(state: Dictionary) -> float:
	var mg: Variant = state.get("minigames")
	if not (mg is Dictionary):
		return 0.0
	return clamp_manual(_num((mg as Dictionary).get(SAVE_KEY)))


## Save-Mutator (in gs.update aufrufen): legt den additiven Key an.
static func store_manual_offset(state: Dictionary, ms: float) -> void:
	if not (state.get("minigames") is Dictionary):
		state["minigames"] = {}
	state["minigames"][SAVE_KEY] = int(round(clamp_manual(ms)))


## Reset-Knopf: Feinoffset zurück auf 0 (Key bleibt additiv erhalten).
static func reset_manual_offset(state: Dictionary) -> void:
	store_manual_offset(state, 0.0)


static func _num(value: Variant, fallback := 0.0) -> float:
	if value is float or value is int:
		return float(value)
	return fallback

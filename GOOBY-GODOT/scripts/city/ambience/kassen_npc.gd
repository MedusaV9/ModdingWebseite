class_name KassenNpc
extends Node
## G7-P55 — Kassen-Verhalten für den Haupt-NPC eines Ladens: die Figur
## „tippt“ im Takt an der Kasse (Mund-/Brabbel-Puls), winkt Gooby ab und
## zu freundlich zu und quittiert jeden Kauf mit Piep + Winken
## (`kunde_zahlt()` — die Ort-Szene verdrahtet das an ihr Händler-Sheet).
##
## Kein Timer, keine Lambdas (REST5): alles läuft über _process-Akkus.
## Reduced Motion: kein automatisches Winken, Tippen im halben Takt.

## Tipp-Puls (Kassen-Getippe) und Zuwink-Takt in Sekunden.
const TIPP_ALLE_S := 2.4
const WINK_ALLE_S := 11.0
## Kassen-Piep (G6-FEEL): eigener Scanner-Piep — ui_coins ist laut
## Audio-Grammatik für Münz-EINNAHMEN des Spielers reserviert.
const PIEP_ID := "kasse_piep"
const PIEP_PITCH := 1.0

## Die Figur an der Kasse (der Haupt-NPC der Ort-Szene).
var rig: GoobyRig
## Test-Hooks/Beobachtung: gezählte Käufe + letzte gespielte Aktion.
var piep_zaehler := 0
var letzte_aktion := ""
## Reduced-Motion erzwingen (-1 = AppSettings fragen).
var reduced_override := -1

var _tipp_zeit := 0.0
var _wink_zeit := 0.0


func _process(delta: float) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var reduziert := _reduziert()
	_tipp_zeit += delta
	_wink_zeit += delta
	if _tipp_zeit >= TIPP_ALLE_S * (2.0 if reduziert else 1.0):
		_tipp_zeit = 0.0
		rig.babble_pulse()
		letzte_aktion = "tippt"
	if not reduziert and _wink_zeit >= WINK_ALLE_S:
		_wink_zeit = 0.0
		rig.play_clip("wave")
		letzte_aktion = "winkt"


## Ein Kunde zahlt: Kassen-Piep + freundliches Winken.
func kunde_zahlt() -> void:
	piep_zaehler += 1
	AudioDirector.try_play(self, PIEP_ID, PIEP_PITCH)
	if rig != null and is_instance_valid(rig):
		rig.play_clip("wave")
	letzte_aktion = "kassiert"


func _reduziert() -> bool:
	if reduced_override >= 0:
		return reduced_override == 1
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()

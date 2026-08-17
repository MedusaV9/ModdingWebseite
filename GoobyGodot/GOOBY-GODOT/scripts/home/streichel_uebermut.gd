class_name StreichelUebermut
extends RefCounted
## W15/VOICE2: PURE Übermut-Zustandsmaschine für den Streichel-Gag im
## GoobyReactions-Runner (Muster BoardEmotes.TomatoTracker) — Zeit kommt
## injiziert herein (now_ms), keine OS-Uhr. registriere() meldet true genau
## EINMAL, wenn MEHR als MAX_PETS Streichler ins 30-s-Fenster fallen;
## danach schweigt sie bis zum Cooldown-Ende (und sammelt neu).

const MAX_PETS := 10
const FENSTER_MS := 30_000
const COOLDOWN_MS := 120_000

var _stamps: Array[int] = []
var _still_bis_ms := 0


## Einen Streichler buchen; true = der Gag darf JETZT feuern.
func registriere(now_ms: int) -> bool:
	_stamps.append(now_ms)
	var frisch: Array[int] = []
	for stamp in _stamps:
		if now_ms - stamp < FENSTER_MS:
			frisch.append(stamp)
	_stamps = frisch
	if now_ms < _still_bis_ms or _stamps.size() <= MAX_PETS:
		return false
	_still_bis_ms = now_ms + COOLDOWN_MS
	_stamps = []
	return true

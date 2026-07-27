class_name RadioLogic
extends RefCounted
## Pure Radio-UI-Logik (REST-4, EVAL Rang 10) — Port der puren Teile von
## GOOBY/src/ui/radioScreen.logic.js auf die Godot-MusicRegistry:
## Sender-/Titel-Sperren nach Spieler-Level, Freischalt-Zähler und die
## Lieblingssongs ("gefällt mir", Web-additiv: `radio.likes` im Save —
## KEIN Version-Bump, merge_defaults konserviert unbekannte Keys).
##
## Abspiel-Motor bleibt der MusicDirector (scripts/audio/music_director.gd,
## NUR benutzt, nie geändert): radio_play/radio_stop/radio_next +
## track_changed/station_changed. Diese Datei rechnet nur.


## Web isStationLocked: Level < unlock_level sperrt den Sender.
static func ist_sender_gesperrt(station: Dictionary, level: int) -> bool:
	return maxi(1, level) < int(station.get("unlock_level", 1))


## Sender-Zeilen der Registry mit Sperr-Status fürs UI.
static func sender(level: int) -> Array:
	var out: Array = []
	for row: Dictionary in MusicRegistry.stations():
		var kopie := row.duplicate(true)
		kopie["locked"] = ist_sender_gesperrt(row, level)
		out.append(kopie)
	return out


## Titel-Zeilen eines Senders: {id, title, duration_sec, unlock_level,
## locked, liked} — gesperrte Titel INKLUSIVE (Liste zeigt Schlösser).
static func titel(station_id: String, level: int, likes: Dictionary) -> Array:
	var out: Array = []
	for track_id: String in MusicRegistry.station_track_ids(station_id):
		var entry := MusicRegistry.entry(track_id)
		var unlock := int(entry.get("unlock_level", 1))
		(
			out
			. append(
				{
					"id": track_id,
					"title": str(entry.get("title", track_id)),
					"duration_sec": float(entry.get("duration_sec", 0.0)),
					"unlock_level": unlock,
					"locked": maxi(1, level) < unlock,
					"liked":
					likes.get(track_id, false) is bool and bool(likes.get(track_id, false)),
				}
			)
		)
	return out


## Freigeschaltete Titel eines Senders (Zähler "n von gesamt").
static func frei_zaehler(station_id: String, level: int) -> Dictionary:
	var alle := MusicRegistry.station_track_ids(station_id)
	var frei := 0
	for track_id: String in alle:
		if int(MusicRegistry.entry(track_id).get("unlock_level", 1)) <= maxi(1, level):
			frei += 1
	return {"frei": frei, "gesamt": alle.size()}


## Likes-Map aus dem Save lesen (nur strikte true-Werte zählen).
static func likes_von(state: Dictionary) -> Dictionary:
	var radio: Variant = state.get("radio")
	if not (radio is Dictionary):
		return {}
	var raw: Variant = (radio as Dictionary).get("likes")
	if not (raw is Dictionary):
		return {}
	var out := {}
	for id: Variant in (raw as Dictionary).keys():
		var v: Variant = (raw as Dictionary)[id]
		if id is String and MusicRegistry.entry(id).size() > 0 and v is bool and v:
			out[id] = true
	return out


## Like togglen (mutiert den Save-Draft; Rückgabe = neuer Zustand).
## Unbekannte Track-Ids werden verworfen (Cheat-/Altlast-Schutz).
static func toggle_like(state: Dictionary, track_id: String) -> bool:
	if MusicRegistry.entry(track_id).is_empty():
		return false
	if not (state.get("radio") is Dictionary):
		state["radio"] = {}
	var radio: Dictionary = state["radio"]
	if not (radio.get("likes") is Dictionary):
		radio["likes"] = {}
	var likes: Dictionary = radio["likes"]
	if likes.get(track_id, false) is bool and bool(likes.get(track_id, false)):
		likes.erase(track_id)
		return false
	likes[track_id] = true
	return true


## Anzahl gemerkter Lieblingssongs.
static func like_anzahl(state: Dictionary) -> int:
	return likes_von(state).size()


## Anzeigename eines Senders (Registry-name_key → I18n).
static func sender_name(station: Dictionary) -> String:
	return I18nService.t(str(station.get("name_key", "")))


## mm:ss-Anzeige (Web formatTime).
static func zeit(sekunden: float) -> String:
	var sec := maxi(0, int(floor(sekunden)))
	@warning_ignore("integer_division")
	return "%d:%02d" % [sec / 60, sec % 60]

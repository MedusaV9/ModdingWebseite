class_name RadioLogic
extends RefCounted
## Pure Radio-UI-Logik (REST-4, EVAL Rang 10) — Port der puren Teile von
## GOOBY/src/ui/radioScreen.logic.js auf die Godot-MusicRegistry:
## Sender-/Titel-Sperren nach Spieler-Level, Freischalt-Zähler und die
## Lieblingssongs ("gefällt mir", Web-additiv: `radio.likes` im Save —
## KEIN Version-Bump, merge_defaults konserviert unbekannte Keys).
##
## Abspiel-Motor bleibt der MusicDirector (scripts/audio/music_director.gd):
## radio_play/radio_stop/radio_next/bordmusik_play + track_changed/
## station_changed. Diese Datei rechnet nur.
##
## W13/RADIO (H §6.1): Das IKEA-Kauf-Gate rechnet ebenfalls hier —
## besitzt_radio() (Save-Wert aus Grandfathering ODER Radio-Möbel im
## Besitz/platziert) und aktion_erlaubt() (Bordmusik-Modus: nur Play/Pause).

## Radio-Möbel, deren Besitz das Vollradio freischaltet. Muss zum
## IKEA-Katalog (scripts/home/data/furniture_catalog.json) passen; der
## `speaker` dockt zwar die RadioSheet an (InteractablesHost.RADIO_IDS),
## ist aber nur ein Lautsprecher — er zählt NICHT als gekauftes Radio.
const RADIO_MOEBEL_IDS: Array[String] = ["radio", "radioRetro"]

## Sender-Cover (H §6.1 Cover-Optik OHNE neue Bild-Assets): farbige
## AC-Karte + Glyph. Farben kommen ausschließlich aus AcTokens (Theme
## bleibt read-only); die Glyphen sind Bestands-Unicode (Minigames nutzen
## dieselben Zeichen, Font-Fallback vorhanden).
const SENDER_COVER := {
	"bordmusik": {"glyph": "♫", "farbe": "SKY_SOFT"},
	"gooby-fm": {"glyph": "♥", "farbe": "PINK"},
	"recap-fm": {"glyph": "★", "farbe": "GOLD"},
	"game-fm": {"glyph": "◆", "farbe": "LEAF"},
	"alle": {"glyph": "●", "farbe": "TEAL"},
}
const SENDER_COVER_FALLBACK := {"glyph": "♪", "farbe": "PAPER_SHADE"}


## KAUF-GATE HART (H §6.1): Vollradio nur mit gekauftem Radio. `true` wenn
## der Save-Wert `radio.owned` gesetzt ist (Grandfathering-Migration bzw.
## einmal freigeschaltet) ODER ein Radio-Möbel im Besitz ist. Einschalten
## alleine setzt den Wert NIE.
static func besitzt_radio(state: Dictionary) -> bool:
	var radio: Variant = state.get("radio")
	if radio is Dictionary:
		var owned: Variant = (radio as Dictionary).get("owned")
		if owned is bool and owned:
			return true
	return radio_moebel_vorhanden(state)


## IKEA-Kauf-Nachweis: Radio-Möbel im Lager (`home.storage`) oder in
## irgendeinem Raum platziert (`home.rooms.<id>.items`).
static func radio_moebel_vorhanden(state: Dictionary) -> bool:
	var home: Variant = state.get("home")
	if not (home is Dictionary):
		return false
	var storage: Variant = (home as Dictionary).get("storage")
	if storage is Array:
		for entry: Variant in storage:
			if not (entry is Dictionary):
				continue
			var eintrag: Dictionary = entry
			var im_lager := int(eintrag.get("count", 1)) > 0
			if str(eintrag.get("item", "")) in RADIO_MOEBEL_IDS and im_lager:
				return true
	var rooms: Variant = (home as Dictionary).get("rooms")
	if not (rooms is Dictionary):
		return false
	for room_id: Variant in rooms as Dictionary:
		var room: Variant = (rooms as Dictionary)[room_id]
		if not (room is Dictionary):
			continue
		var items: Variant = (room as Dictionary).get("items")
		if not (items is Array):
			continue
		for entry: Variant in items:
			if (
				entry is Dictionary
				and str((entry as Dictionary).get("item", "")) in RADIO_MOEBEL_IDS
			):
				return true
	return false


## Gate-Matrix (H §6.1): Bordmusik-Modus (ohne Besitz) erlaubt NUR
## Play/Pause; Skip/Senderwahl/Lieblingssongs brauchen das Vollradio.
static func aktion_erlaubt(owned: bool, aktion: String) -> bool:
	match aktion:
		"play", "pause":
			return true
		"skip", "sender", "like":
			return owned
		_:
			return false


## Cover eines Senders: {"glyph": String, "farbe": Color}.
static func cover(station_id: String) -> Dictionary:
	var raw: Dictionary = SENDER_COVER.get(station_id, SENDER_COVER_FALLBACK)
	return {"glyph": str(raw["glyph"]), "farbe": Color(AcTokens.COLORS[str(raw["farbe"])])}


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

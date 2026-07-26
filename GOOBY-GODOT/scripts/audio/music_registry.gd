class_name MusicRegistry
extends RefCounted
## Musik-Registry (FIX-4) — Port der Web-Registry (GOOBY/src/systems/
## musicRegistry.js + musicManifest.json). Die 51 generierten Musikstücke aus
## dem Web-Projekt liegen jetzt unter assets/music/<kategorie>/<track-id>.ogg
## (mp3-Quellen mit ffmpeg zu OGG q5 konvertiert, Trims 1:1 übernommen).
## EINZIGE Quelle der Wahrheit für "welcher Track läuft wo" — MusicDirector
## fragt hier nach; neue Tracks NUR hier eintragen.
##
## Kontext-Tokens (track_for): "room:kitchen|living|bathroom|bedroom|garden",
## "game:<minigameId>", "location:city|shop|vet", "arcade" — plus Aliasse
## "home"→room:living, "home_night"→room:bedroom (sleeping), "garden",
## "city", "shop" (REHWEI/IKEA), "vet", "vacation" (Urlaub → Vacation Day).
## Sender (§Web C-SYS1.2): bordmusik/gooby-fm/recap-fm/game-fm/alle;
## Stinger (< 10 s) laufen NIE in einem Sender — One-Shot-Cues.
##
## RW-8 (Ranch-DLC): 5 zusätzliche Tracks (Kategorie "Ranch", Dateien unter
## assets/ranch/audio/musik/ — file-Einträge sind absolute res://-Pfade,
## path() reicht sie durch). Kontexte: "ranch" (Hof), "ranch_reiten"
## (Weite), "ranch_turnier", "ranch_nacht", "ranch_menue". Kontextwechsel
## beim Reisen fährt RanchAudio (scripts/audio/ranch_audio.gd); die Trims
## sind auf die Bestands-Loudness (~-16 dB mean) eingemessen. Ranch-Tracks
## laufen in keinem Themen-Sender, nur in "alle".

const BASE_DIR := "res://assets/music"
const RANCH_MUSIK_DIR := "res://assets/ranch/audio/musik"
## Sub-10-Sekunden-Dateien sind One-Shot-Stinger (Web STINGER_MAX_SEC).
const STINGER_MAX_SEC := 10.0

## Sender-Tabelle (Web STATION_DEFS; Label-Keys in strings/*/audio.json).
const STATION_DEFS := [
	{"id": "bordmusik", "name_key": "audio.station.bordmusik", "unlock_level": 1},
	{"id": "gooby-fm", "name_key": "audio.station.gooby_fm", "unlock_level": 1},
	{"id": "recap-fm", "name_key": "audio.station.recap_fm", "unlock_level": 5},
	{"id": "game-fm", "name_key": "audio.station.game_fm", "unlock_level": 8},
	{"id": "alle", "name_key": "audio.station.alle", "unlock_level": 1},
]

## musicDirector-Aliasse → Kontext-Token des Manifests (Web CONTEXT_ALIASES
## + Godot-Zusätze home_night/vacation).
const CONTEXT_ALIASES := {
	"home": "room:living",
	"home_night": "room:bedroom",
	"garden": "room:garden",
	"city": "location:city",
	"shop": "location:shop",
	"vet": "location:vet",
	"arcade": "arcade",
	"ranch": "ranch:hof",
	"ranch_reiten": "ranch:reiten",
	"ranch_turnier": "ranch:turnier",
	"ranch_nacht": "ranch:nacht",
	"ranch_menue": "ranch:menue",
}

## Zusatz-Kontexte ohne Manifest-Token (Godot-additiv): Urlaub.
const EXTRA_CONTEXT_TRACKS := {
	"vacation": "bordmusik-vacation-day",
}

## Kontexte, die die Registry IMMER abdecken muss (Test-Kontrakt).
const REQUIRED_CONTEXTS := [
	"home",
	"home_night",
	"garden",
	"city",
	"shop",
	"vet",
	"arcade",
	"vacation",
	"room:kitchen",
	"room:bathroom",
	"room:bedroom",
	"ranch",
	"ranch_reiten",
	"ranch_turnier",
	"ranch_nacht",
	"ranch_menue",
]

## Beat-Manifeste der Recap-Tracks (Web beats/*.beats.json, Override gewinnt).
const BEAT_GRIDS := {
	"recap-bonus-stage-blitz": {"bpm": 94.3, "offset_sec": 0.13, "beats_per_bar": 4},
	"recap-recap-song-2-moreepic-victory": {"bpm": 131.0, "offset_sec": 0.39, "beats_per_bar": 4},
}

## Track-Id → Metadaten (aus dem Web-musicManifest.json generiert; gain_trim
## ist der lineare Web-Trim — trim_db() rechnet nach dB um).
const TRACKS := {
	"bordmusik-candy":
	{
		"file": "bordmusik/bordmusik-candy.ogg",
		"category": "Bordmusik",
		"title": "Candy",
		"duration_sec": 52.2,
		"gain_trim": 0.68,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-magic-bottle-town":
	{
		"file": "bordmusik/bordmusik-magic-bottle-town.ogg",
		"category": "Bordmusik",
		"title": "Magic Bottle Town",
		"duration_sec": 104.7,
		"gain_trim": 2,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-penguin-town":
	{
		"file": "bordmusik/bordmusik-penguin-town.ogg",
		"category": "Bordmusik",
		"title": "Penguin Town",
		"duration_sec": 35.3,
		"gain_trim": 0.61,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-piano-atmos":
	{
		"file": "bordmusik/bordmusik-piano-atmos.ogg",
		"category": "Bordmusik",
		"title": "Piano Atmos",
		"duration_sec": 51.2,
		"gain_trim": 1.97,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-piano-jazz":
	{
		"file": "bordmusik/bordmusik-piano-jazz.ogg",
		"category": "Bordmusik",
		"title": "Piano Jazz",
		"duration_sec": 51.2,
		"gain_trim": 1.48,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-piano-melodie":
	{
		"file": "bordmusik/bordmusik-piano-melodie.ogg",
		"category": "Bordmusik",
		"title": "Piano Melodie",
		"duration_sec": 51.2,
		"gain_trim": 1.76,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-piano-streicher":
	{
		"file": "bordmusik/bordmusik-piano-streicher.ogg",
		"category": "Bordmusik",
		"title": "Piano Streicher",
		"duration_sec": 51.2,
		"gain_trim": 1.66,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-playful-piano":
	{
		"file": "bordmusik/bordmusik-playful-piano.ogg",
		"category": "Bordmusik",
		"title": "Playful Piano",
		"duration_sec": 51.2,
		"gain_trim": 2,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-puzzle-pieces":
	{
		"file": "bordmusik/bordmusik-puzzle-pieces.ogg",
		"category": "Bordmusik",
		"title": "Puzzle Pieces",
		"duration_sec": 91.2,
		"gain_trim": 0.72,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-rabbit-town":
	{
		"file": "bordmusik/bordmusik-rabbit-town.ogg",
		"category": "Bordmusik",
		"title": "Rabbit Town",
		"duration_sec": 45.5,
		"gain_trim": 0.86,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-seaside":
	{
		"file": "bordmusik/bordmusik-seaside.ogg",
		"category": "Bordmusik",
		"title": "Seaside",
		"duration_sec": 53.3,
		"gain_trim": 0.9,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-vacation-day":
	{
		"file": "bordmusik/bordmusik-vacation-day.ogg",
		"category": "Bordmusik",
		"title": "Vacation Day",
		"duration_sec": 12.8,
		"gain_trim": 0.86,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"bordmusik-werkstatt":
	{
		"file": "bordmusik/bordmusik-werkstatt.ogg",
		"category": "Bordmusik",
		"title": "Werkstatt",
		"duration_sec": 22.6,
		"gain_trim": 0.93,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"game-hafenhupfer":
	{
		"file": "games/game-hafenhupfer.ogg",
		"category": "Game",
		"title": "Hafenhüpfer",
		"duration_sec": 90.5,
		"gain_trim": 1.1,
		"unlock_level": 1,
		"context": "game:harborHopper",
		"variant": "",
	},
	"game-kichergeister":
	{
		"file": "games/game-kichergeister.ogg",
		"category": "Game",
		"title": "Kichergeister",
		"duration_sec": 98.8,
		"gain_trim": 1.07,
		"unlock_level": 1,
		"context": "game:ghostHunt",
		"variant": "",
	},
	"game-kuchenwirbel":
	{
		"file": "games/game-kuchenwirbel.ogg",
		"category": "Game",
		"title": "Kuchenwirbel",
		"duration_sec": 114.4,
		"gain_trim": 1.01,
		"unlock_level": 1,
		"context": "game:purblePlace",
		"variant": "",
	},
	"game-running-loops":
	{
		"file": "games/game-running-loops.ogg",
		"category": "Game",
		"title": "Running Loops",
		"duration_sec": 89.8,
		"gain_trim": 1.2,
		"unlock_level": 1,
		"context": "game:shoppingSurf",
		"variant": "",
	},
	"game-spielzeugflitzer":
	{
		"file": "games/game-spielzeugflitzer.ogg",
		"category": "Game",
		"title": "Spielzeugflitzer",
		"duration_sec": 84.6,
		"gain_trim": 1.17,
		"unlock_level": 1,
		"context": "game:toyRacer",
		"variant": "",
	},
	"game-splat-wunderwelt":
	{
		"file": "games/game-splat-wunderwelt.ogg",
		"category": "Game",
		"title": "Splat-Wunderwelt",
		"duration_sec": 74.8,
		"gain_trim": 1.01,
		"unlock_level": 1,
		"context": "game:goobyWelt",
		"variant": "",
	},
	"game-sternenhopser":
	{
		"file": "games/game-sternenhopser.ogg",
		"category": "Game",
		"title": "Sternenhopser",
		"duration_sec": 108.7,
		"gain_trim": 1.26,
		"unlock_level": 1,
		"context": "game:starHopper",
		"variant": "",
	},
	"location-ikea-quest":
	{
		"file": "locations/location-ikea-quest.ogg",
		"category": "Location",
		"title": "Ikea Quest",
		"duration_sec": 42.8,
		"gain_trim": 1.33,
		"unlock_level": 1,
		"context": "location:shop",
		"variant": "",
	},
	"location-sanfte-pfoten":
	{
		"file": "locations/location-sanfte-pfoten.ogg",
		"category": "Location",
		"title": "Sanfte Pfoten",
		"duration_sec": 94.9,
		"gain_trim": 1.06,
		"unlock_level": 1,
		"context": "location:vet",
		"variant": "",
	},
	"location-stadtrundfahrt":
	{
		"file": "locations/location-stadtrundfahrt.ogg",
		"category": "Location",
		"title": "Stadtrundfahrt",
		"duration_sec": 124.2,
		"gain_trim": 1.19,
		"unlock_level": 1,
		"context": "location:city",
		"variant": "",
	},
	"radio-der-dicke-hase-gooby":
	{
		"file": "radio/radio-der-dicke-hase-gooby.ogg",
		"category": "Radio",
		"title": "Der Dicke Hase Gooby",
		"duration_sec": 130.6,
		"gain_trim": 1.24,
		"unlock_level": 5,
		"context": "",
		"variant": "",
	},
	"radio-der-gartenkonig-gooby":
	{
		"file": "radio/radio-der-gartenkonig-gooby.ogg",
		"category": "Radio",
		"title": "Der Gartenkönig Gooby",
		"duration_sec": 135.5,
		"gain_trim": 1.3,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"radio-der-gartenkonig-gooby-2":
	{
		"file": "radio/radio-der-gartenkonig-gooby-2.ogg",
		"category": "Radio",
		"title": "Der Gartenkönig Gooby",
		"duration_sec": 135.5,
		"gain_trim": 1.3,
		"unlock_level": 15,
		"context": "",
		"variant": "",
	},
	"radio-goldene-karotten":
	{
		"file": "radio/radio-goldene-karotten.ogg",
		"category": "Radio",
		"title": "Goldene Karotten",
		"duration_sec": 155.7,
		"gain_trim": 1.22,
		"unlock_level": 20,
		"context": "",
		"variant": "",
	},
	"radio-gooby-der-dicke-hase":
	{
		"file": "radio/radio-gooby-der-dicke-hase.ogg",
		"category": "Radio",
		"title": "Gooby der Dicke Hase",
		"duration_sec": 181.8,
		"gain_trim": 1.24,
		"unlock_level": 10,
		"context": "",
		"variant": "",
	},
	"radio-goobys-abenteuer":
	{
		"file": "radio/radio-goobys-abenteuer.ogg",
		"category": "Radio",
		"title": "Goobys Abenteuer",
		"duration_sec": 125.2,
		"gain_trim": 1.27,
		"unlock_level": 5,
		"context": "",
		"variant": "",
	},
	"radio-hopp-hopp-gooby":
	{
		"file": "radio/radio-hopp-hopp-gooby.ogg",
		"category": "Radio",
		"title": "Hopp Hopp Gooby!",
		"duration_sec": 172.6,
		"gain_trim": 1.27,
		"unlock_level": 5,
		"context": "",
		"variant": "",
	},
	"radio-konig-im-kleefeld":
	{
		"file": "radio/radio-konig-im-kleefeld.ogg",
		"category": "Radio",
		"title": "König im Kleefeld",
		"duration_sec": 166.3,
		"gain_trim": 1.2,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"radio-konig-im-kleefeld-2":
	{
		"file": "radio/radio-konig-im-kleefeld-2.ogg",
		"category": "Radio",
		"title": "König im Kleefeld",
		"duration_sec": 166.3,
		"gain_trim": 1.2,
		"unlock_level": 15,
		"context": "",
		"variant": "",
	},
	"radio-kronenfest":
	{
		"file": "radio/radio-kronenfest.ogg",
		"category": "Radio",
		"title": "Kronenfest",
		"duration_sec": 136.4,
		"gain_trim": 1.1,
		"unlock_level": 30,
		"context": "",
		"variant": "",
	},
	"radio-mohrenberg-monarch":
	{
		"file": "radio/radio-mohrenberg-monarch.ogg",
		"category": "Radio",
		"title": "Möhrenberg Monarch",
		"duration_sec": 145.7,
		"gain_trim": 1.41,
		"unlock_level": 10,
		"context": "",
		"variant": "",
	},
	"radio-mohrenmond-tanz":
	{
		"file": "radio/radio-mohrenmond-tanz.ogg",
		"category": "Radio",
		"title": "Möhrenmond-Tanz",
		"duration_sec": 150.3,
		"gain_trim": 1.08,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"radio-round-rabbit-rock":
	{
		"file": "radio/radio-round-rabbit-rock.ogg",
		"category": "Radio",
		"title": "Round Rabbit Rock",
		"duration_sec": 152.3,
		"gain_trim": 1.5,
		"unlock_level": 10,
		"context": "",
		"variant": "",
	},
	"radio-wackelpo-im-klee":
	{
		"file": "radio/radio-wackelpo-im-klee.ogg",
		"category": "Radio",
		"title": "Wackelpo im Klee",
		"duration_sec": 169.3,
		"gain_trim": 1.35,
		"unlock_level": 15,
		"context": "",
		"variant": "",
	},
	"radio-wolkenkonig":
	{
		"file": "radio/radio-wolkenkonig.ogg",
		"category": "Radio",
		"title": "Wolkenkönig",
		"duration_sec": 138.8,
		"gain_trim": 1.05,
		"unlock_level": 25,
		"context": "",
		"variant": "",
	},
	"radio-zuckende-nase":
	{
		"file": "radio/radio-zuckende-nase.ogg",
		"category": "Radio",
		"title": "Zuckende Nase",
		"duration_sec": 164.2,
		"gain_trim": 1.26,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"recap-abenteuer":
	{
		"file": "recap/recap-abenteuer.ogg",
		"category": "Recap",
		"title": "Abenteuer",
		"duration_sec": 109.7,
		"gain_trim": 2,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"recap-bonus-stage-blitz":
	{
		"file": "recap/recap-bonus-stage-blitz.ogg",
		"category": "Recap",
		"title": "Bonus Stage Blitz",
		"duration_sec": 83.4,
		"gain_trim": 1.26,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"recap-recap-song-2-moreepic-victory":
	{
		"file": "recap/recap-recap-song-2-moreepic-victory.ogg",
		"category": "Recap",
		"title": "Recap Song 2 MoreEpic Victory",
		"duration_sec": 165.2,
		"gain_trim": 1.26,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"room-blubberbad":
	{
		"file": "rooms/room-blubberbad.ogg",
		"category": "Room",
		"title": "Blubberbad",
		"duration_sec": 90.9,
		"gain_trim": 1.33,
		"unlock_level": 1,
		"context": "room:bathroom",
		"variant": "",
	},
	"room-cloud-hopper-s-day-off":
	{
		"file": "rooms/room-cloud-hopper-s-day-off.ogg",
		"category": "Room",
		"title": "Cloud Hopper's Day Off",
		"duration_sec": 130.1,
		"gain_trim": 1.32,
		"unlock_level": 1,
		"context": "room:living",
		"variant": "",
	},
	"room-kitchen-dance-party":
	{
		"file": "rooms/room-kitchen-dance-party.ogg",
		"category": "Room",
		"title": "Kitchen Dance Party",
		"duration_sec": 103.2,
		"gain_trim": 1.33,
		"unlock_level": 1,
		"context": "room:kitchen",
		"variant": "",
	},
	"room-petal-path-picnic":
	{
		"file": "rooms/room-petal-path-picnic.ogg",
		"category": "Room",
		"title": "Petal Path Picnic",
		"duration_sec": 130,
		"gain_trim": 1.22,
		"unlock_level": 1,
		"context": "room:garden",
		"variant": "",
	},
	"room-pitter-patter-fun":
	{
		"file": "rooms/room-pitter-patter-fun.ogg",
		"category": "Room",
		"title": "Pitter Patter Fun",
		"duration_sec": 87.5,
		"gain_trim": 1.35,
		"unlock_level": 1,
		"context": "arcade",
		"variant": "",
	},
	"room-pixie-puddle-awake":
	{
		"file": "rooms/room-pixie-puddle-awake.ogg",
		"category": "Room",
		"title": "Pixie Puddle",
		"duration_sec": 74.1,
		"gain_trim": 1.27,
		"unlock_level": 1,
		"context": "room:bedroom",
		"variant": "awake",
	},
	"room-pixie-puddle-sleeping":
	{
		"file": "rooms/room-pixie-puddle-sleeping.ogg",
		"category": "Room",
		"title": "Pixie Puddle",
		"duration_sec": 43,
		"gain_trim": 1.53,
		"unlock_level": 1,
		"context": "room:bedroom",
		"variant": "sleeping",
	},
	"ranch-tag":
	{
		"file": RANCH_MUSIK_DIR + "/musik_ranch_tag.ogg",
		"category": "Ranch",
		"title": "Ranch-Tag",
		"duration_sec": 199.8,
		"gain_trim": 1.15,
		"unlock_level": 1,
		"context": "ranch:hof",
		"variant": "",
	},
	"ranch-reiten":
	{
		"file": RANCH_MUSIK_DIR + "/musik_reiten.ogg",
		"category": "Ranch",
		"title": "Weites Land",
		"duration_sec": 73.7,
		"gain_trim": 1.86,
		"unlock_level": 1,
		"context": "ranch:reiten",
		"variant": "",
	},
	"ranch-turnier":
	{
		"file": RANCH_MUSIK_DIR + "/musik_turnier.ogg",
		"category": "Ranch",
		"title": "Turnier-Galopp",
		"duration_sec": 187.5,
		"gain_trim": 1.84,
		"unlock_level": 1,
		"context": "ranch:turnier",
		"variant": "",
	},
	"ranch-nacht":
	{
		"file": RANCH_MUSIK_DIR + "/musik_nacht.ogg",
		"category": "Ranch",
		"title": "Nacht am Teich",
		"duration_sec": 235.0,
		"gain_trim": 1.2,
		"unlock_level": 1,
		"context": "ranch:nacht",
		"variant": "",
	},
	"ranch-menue":
	{
		"file": RANCH_MUSIK_DIR + "/musik_menue.ogg",
		"category": "Ranch",
		"title": "Ranch-Menü",
		"duration_sec": 114.5,
		"gain_trim": 1.82,
		"unlock_level": 1,
		"context": "ranch:menue",
		"variant": "",
	},
	"stinger-levelup":
	{
		"file": "stinger/stinger-levelup.ogg",
		"category": "Stinger",
		"title": "LevelUp",
		"duration_sec": 6,
		"gain_trim": 1.33,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
	"stinger-results":
	{
		"file": "stinger/stinger-results.ogg",
		"category": "Stinger",
		"title": "Results",
		"duration_sec": 4,
		"gain_trim": 2,
		"unlock_level": 1,
		"context": "",
		"variant": "",
	},
}


## Eintrag zu einer Track-Id ({} = unbekannt).
static func entry(track_id: String) -> Dictionary:
	return TRACKS.get(track_id, {})


## Ressourcen-Pfad einer Track-Id ("" = unbekannt). Absolute res://-Einträge
## (Ranch-Familie) gehen unverändert durch, alles andere hängt an BASE_DIR.
static func path(track_id: String) -> String:
	var row: Dictionary = TRACKS.get(track_id, {})
	if row.is_empty():
		return ""
	var file := str(row["file"])
	if file.begins_with("res://"):
		return file
	return "%s/%s" % [BASE_DIR, file]


## Alle bekannten Track-Ids.
static func ids() -> Array:
	return TRACKS.keys()


## Lautstärke-Trim eines Tracks in dB (Web gainTrim, linear → dB).
static func trim_db(track_id: String) -> float:
	var row: Dictionary = TRACKS.get(track_id, {})
	var trim := maxf(0.05, float(row.get("gain_trim", 1.0)))
	return linear_to_db(trim)


## Web isStinger: Kategorie Stinger ODER kürzer als 10 s.
static func is_stinger(track_id: String) -> bool:
	var row: Dictionary = TRACKS.get(track_id, {})
	if row.is_empty():
		return false
	if str(row.get("category", "")) == "Stinger":
		return true
	var dur := float(row.get("duration_sec", 0.0))
	return dur > 0.0 and dur < STINGER_MAX_SEC


## Web trackBelongsTo — Sender-Mitgliedschaft (Stinger nie).
static func track_belongs_to(track_id: String, station_id: String) -> bool:
	var row: Dictionary = TRACKS.get(track_id, {})
	if row.is_empty() or is_stinger(track_id):
		return false
	var category := str(row.get("category", ""))
	match station_id:
		"alle":
			return true
		"bordmusik":
			return category == "Bordmusik"
		"gooby-fm":
			return category == "Radio"
		"recap-fm":
			return category == "Recap"
		"game-fm":
			return category == "Game"
		_:
			return false


## Mitglieds-Tracks eines Senders (Level-gesperrte Tracks INKLUSIVE — die
## Abspiel-Queue filtert nach Spieler-Level, die Liste zeigt Schlösser).
static func station_track_ids(station_id: String) -> Array:
	var out: Array = []
	for track_id: String in TRACKS:
		if track_belongs_to(track_id, station_id):
			out.append(track_id)
	out.sort()
	return out


## Sender-Zeilen fürs Radio-UI (Sender ohne Tracks entfallen).
static func stations() -> Array:
	var out: Array = []
	for def: Dictionary in STATION_DEFS:
		var track_ids := station_track_ids(str(def["id"]))
		if track_ids.is_empty():
			continue
		var row := def.duplicate()
		row["track_ids"] = track_ids
		row["count"] = track_ids.size()
		out.append(row)
	return out


## Web trackFor: der echte Musik-Track hinter einem Szenen-Kontext.
## sleeping wählt im Schlafzimmer die Sleeping-Variante. "" = kein Track.
static func track_for(context: String, sleeping := false) -> String:
	if EXTRA_CONTEXT_TRACKS.has(context):
		return str(EXTRA_CONTEXT_TRACKS[context])
	var token: String = str(CONTEXT_ALIASES.get(context, context))
	if context == "home_night":
		sleeping = true
	if token.is_empty():
		return ""
	var matches: Array = []
	for track_id: String in TRACKS:
		var row: Dictionary = TRACKS[track_id]
		if str(row.get("context", "")) == token and not is_stinger(track_id):
			matches.append(track_id)
	if matches.is_empty():
		return ""
	matches.sort()
	if token == "room:bedroom":
		var want_variant := "sleeping" if sleeping else "awake"
		for track_id: String in matches:
			if str(TRACKS[track_id].get("variant", "")) == want_variant:
				return track_id
	return matches[0]


## Beat-Raster eines (Recap-)Tracks — fehlt eines, greift der Default
## (RecapEngine.DEFAULT_GRID, Web resolveBeats).
static func beat_grid(track_id: String) -> Dictionary:
	return BEAT_GRIDS.get(track_id, {})

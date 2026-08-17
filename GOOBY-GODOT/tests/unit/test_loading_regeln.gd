extends TestCase
## RW-8: LoadingScreenRules — voller Ladebildschirm NUR bei langen Reisen,
## kontextpassende Artwork-Wahl (inkl. Nacht-Override), alle Artwork-Dateien
## vorhanden, und Ehrlichkeits-Wächter: Ladezeiten werden nicht künstlich
## verlängert (Router-Mindestanzeige + Veil-Blenden bleiben kurz).

const RouterScript := preload("res://scripts/core/scene_router.gd")

const LANGE := [&"ranch/hof", &"ranch/welt", &"ranch/fahrt", &"ranch/dorf", &"social/visit"]
const KURZE := [
	&"home",
	&"home/living",
	&"home/kitchen",
	&"city",
	&"city/ort/rehwei",
	&"arcade",
	&"mg_pregame",
	&"album",
	&"social/chess",
]


func test_lange_reisen_bekommen_vollen_schirm() -> void:
	for ziel: StringName in LANGE:
		assert_true(LoadingScreenRules.ist_lange_reise(ziel, 0), "Lange Reise erkannt: %s" % ziel)


func test_kurze_reisen_bekommen_keinen_vollen_schirm() -> void:
	for ziel: StringName in KURZE:
		assert_false(
			LoadingScreenRules.ist_lange_reise(ziel, 0), "Kurze Reise bleibt klein: %s" % ziel
		)


func test_door_travel_nie_voller_schirm() -> void:
	for ziel: StringName in LANGE:
		assert_false(
			LoadingScreenRules.ist_lange_reise(ziel, LoadingScreenRules.DOOR_TRAVEL),
			"DOOR_TRAVEL bleibt kurzer Cut: %s" % ziel
		)
	assert_eq(
		LoadingScreenRules.DOOR_TRAVEL,
		RouterScript.TravelType.DOOR_TRAVEL,
		"Gespiegelter DOOR_TRAVEL-Wert stimmt mit dem Router überein."
	)


func test_artwork_wahl_nach_kontext() -> void:
	assert_eq(LoadingScreenRules.artwork_id_fuer(&"ranch/hof", 12.0), "stall")
	assert_eq(LoadingScreenRules.artwork_id_fuer(&"ranch/dorf", 12.0), "stall")
	assert_eq(LoadingScreenRules.artwork_id_fuer(&"ranch/welt", 12.0), "galopp")
	assert_eq(LoadingScreenRules.artwork_id_fuer(&"ranch/fahrt", 12.0), "galopp")
	assert_eq(LoadingScreenRules.artwork_id_fuer(&"ranch/turnier", 12.0), "turnier")
	assert_eq(LoadingScreenRules.artwork_id_fuer(&"social/visit", 12.0), "key")
	assert_eq(
		LoadingScreenRules.artwork_id_fuer(&"home/living", 12.0), "", "Kurzziel → kein Artwork"
	)


func test_artwork_nacht_override() -> void:
	assert_eq(LoadingScreenRules.artwork_id_fuer(&"ranch/hof", 22.0), "nacht")
	assert_eq(LoadingScreenRules.artwork_id_fuer(&"ranch/welt", 3.5), "nacht")
	assert_eq(
		LoadingScreenRules.artwork_id_fuer(&"ranch/turnier", 22.0),
		"turnier",
		"Turnier-Kontext schlägt die Nacht."
	)
	assert_true(LoadingScreenRules.ist_nacht(20.0))
	assert_true(LoadingScreenRules.ist_nacht(5.9))
	assert_false(LoadingScreenRules.ist_nacht(6.0))
	assert_false(LoadingScreenRules.ist_nacht(19.9))


func test_alle_artwork_dateien_existieren() -> void:
	for id: String in LoadingScreenRules.ARTWORKS:
		var pfad := LoadingScreenRules.artwork_pfad(id)
		assert_true(ResourceLoader.exists(pfad), "Artwork fehlt: %s (%s)" % [id, pfad])
	assert_true(
		ResourceLoader.exists(LoadingScreenRules.LOGO_PFAD),
		"Logo fehlt: %s" % LoadingScreenRules.LOGO_PFAD
	)
	assert_eq(LoadingScreenRules.artwork_pfad("gibtsnicht"), "", "Unbekannte Id → leer")


## Ehrlichkeit vor Show: der volle Schirm verlängert NICHTS künstlich —
## Router-Mindestanzeige bleibt beim W1a-Wert, die Veil-Blenden bleiben kurz.
func test_ladezeiten_nicht_kuenstlich_verlaengert() -> void:
	var router: Node = RouterScript.new()
	assert_eq(int(router.min_shown_ms), 600, "min_shown_ms bleibt beim W1a-Default.")
	router.free()
	assert_true(LoadingVeil.COVER_DURATION <= 0.4, "Einblende bleibt kurz.")
	assert_true(LoadingVeil.REVEAL_DURATION <= 0.4, "Ausblende bleibt kurz.")

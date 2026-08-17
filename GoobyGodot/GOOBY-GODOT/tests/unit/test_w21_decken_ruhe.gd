extends TestCase
## W21 Home/HUD — DECKEN-RUHE-WACHE (Playtest-Befund „braune, halb-
## transparente Decken-Bande über dem halben Bild in Küche/Wohnzimmer").
## Die RUHE-Kamera jedes Innenraums steht ÜBER der Wandkrone und schaut
## steil runter — die Decke muss dort KOMPLETT ausgeblendet sein (Ziel-
## Alpha exakt 0), sonst liegt dauerhaft ein Milchglas-Band im Bild.
## Die Wache rechnet die echte Ruhe-Geometrie nach (HomeCameraRig.
## follow_distanz + Follow-Pitch + look_at-Blickwinkel) für ALLE Innen-
## räume aus rooms.json in beiden Leitformaten — driftet eine der
## Konstanten (FOLLOW_OFFSET/DIST_MIN/Fade-Band), schlägt sie an.

const ROOMS_JSON := "res://scripts/home/data/rooms.json"
## Leitformat-Aspekte (iPhone 17 Pro Max quer/hoch) — für die Kamera-
## Distanz zählt nur das Seitenverhältnis, nicht die Pixelzahl.
const ASPEKTE: Array = [2868.0 / 1320.0, 1320.0 / 2868.0]
## Blickziel des Rigs: look_at(pivot + 0,5 m) — s. HomeCameraRig._apply.
const BLICK_ZIEL_Y := 0.5


func _innenraeume() -> Array:
	var text := FileAccess.get_file_as_string(ROOMS_JSON)
	var daten: Variant = JSON.parse_string(text)
	assert_true(daten is Dictionary, "rooms.json parst")
	var raeume: Array = (daten as Dictionary).get("rooms", [])
	var out: Array = []
	for raum: Variant in raeume:
		var def := raum as Dictionary
		if bool(def.get("outdoor", false)):
			continue
		out.append(def)
	assert_true(out.size() >= 4, "mindestens 4 Innenräume gefunden")
	return out


## Ruhe-Kamera nachgerechnet wie HomeCameraRig: Offset = FOLLOW_OFFSET
## normalisiert × follow_distanz; Blick auf pivot + 0,5 m.
func _ruhe_geometrie(world_size: Vector2, aspekt: float) -> Dictionary:
	var distanz := HomeCameraRig.follow_distanz(world_size, aspekt)
	var offset := HomeCameraRig.FOLLOW_OFFSET.normalized() * distanz
	var forward := (Vector3(0.0, BLICK_ZIEL_Y, 0.0) - offset).normalized()
	return {
		"hoehe": offset.y,
		"blick": DeckenFade.blick_runter_grad(forward),
	}


func test_ruhe_kamera_blendet_decke_komplett_aus() -> void:
	for def: Variant in _innenraeume():
		var grid: Array = (def as Dictionary).get("grid", [8, 8])
		var world := Vector2(float(grid[0]), float(grid[1])) * GridData.CELL_SIZE
		for aspekt: Variant in ASPEKTE:
			var geo := _ruhe_geometrie(world, float(aspekt))
			var alpha := DeckenFade.ziel_alpha(float(geo["hoehe"]), float(geo["blick"]))
			assert_almost(
				alpha,
				0.0,
				1e-6,
				(
					"Decke in Ruhe weg: %s @ Aspekt %.2f (h=%.2f, Blick=%.1f°)"
					% [(def as Dictionary).get("id", "?"), aspekt, geo["hoehe"], geo["blick"]]
				)
			)


func test_unter_der_wandkrone_bleibt_die_decke() -> void:
	# Kamera UNTER der Krone (Türfahrt 1,45 m; knapp unter 2,5 m): Decke
	# bleibt voll da, egal wie steil der Blick — kein Flackern beim Travel.
	assert_almost(DeckenFade.ziel_alpha(DoorTravelFahrt.KAMERA_TUER_HOEHE_M, 60.0), 1.0, 1e-6)
	assert_almost(DeckenFade.ziel_alpha(2.45, 80.0), 1.0, 1e-6, "knapp unter der Krone")
	# Und das Band bleibt oberhalb der Krone verankert (Wandkrone 2,5 m).
	assert_true(DeckenFade.HOEHE_FREI_AB_M >= 2.5 - 1e-6, "Fade beginnt nicht unter der Wandkrone")

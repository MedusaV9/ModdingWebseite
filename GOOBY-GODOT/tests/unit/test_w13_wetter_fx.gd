extends TestCase
## W13/WETTER-FX — Sichtbares Wetter überall (nicht nur Ranch): das pure
## Mapping Tagesplan → FX-Zustand (deterministisch, Fake-Plan injiziert),
## Indoor-/Outdoor-Modus, der Reduced-Motion-Pfad, die Stadt liest den
## ECHTEN SoulWetter-Plan statt des alten Hardcodes {"typ":"sonne"}, der
## Garten-Hook (GardenWorld.wetter_fx_anhaengen) und der Fenster-Regen der
## Dioramen.


## Fake-Garten-Raum: nur das, was der Hook abfragt (room_id + Baum-Platz).
class FakeGartenRaum:
	extends Node3D
	var room_id := "garden"


func test_fx_plan_mapping_deterministisch() -> void:
	var sonne := WetterFx.fx_plan({"typ": "sonne", "regen": false, "schnee": false}, false, false)
	assert_false(bool(sonne["regen"]), "Sonne: kein Regen")
	assert_false(bool(sonne["schnee"]), "Sonne: kein Schnee")
	assert_false(bool(sonne["blitz"]), "Sonne: kein Blitz")
	assert_almost(float(sonne["nebel"]), 0.0, 1e-6, "Sonne: kein Nebel")
	var regen := WetterFx.fx_plan({"typ": "regen", "regen": true, "schnee": false}, false, false)
	assert_true(bool(regen["regen"]), "Regen emittiert")
	assert_true(bool(regen["spritzer"]), "Regen hat Boden-Spritzer (außen)")
	assert_false(bool(regen["blitz"]), "Regen: kein Blitz")
	var gewitter := WetterFx.fx_plan(
		{"typ": "gewitter", "regen": true, "schnee": false}, false, false
	)
	assert_true(bool(gewitter["regen"]), "Gewitter regnet")
	assert_true(bool(gewitter["blitz"]), "Gewitter blitzt")
	var schnee := WetterFx.fx_plan({"typ": "schnee", "regen": false, "schnee": true}, false, false)
	assert_true(bool(schnee["schnee"]), "Schnee emittiert")
	assert_false(bool(schnee["regen"]), "Schnee: kein Regen")
	var nebel := WetterFx.fx_plan({"typ": "nebel", "regen": false, "schnee": false}, false, false)
	assert_true(float(nebel["nebel"]) > 0.5, "Nebel-Dichte gesetzt")
	var niesel := WetterFx.fx_plan({"typ": "niesel", "regen": true, "schnee": false}, false, false)
	assert_true(float(niesel["staerke"]) < float(regen["staerke"]), "Niesel schwächer als Regen")
	assert_eq(
		WetterFx.fx_plan({"typ": "regen", "regen": true, "schnee": false}, false, false),
		regen,
		"gleicher Zustand = gleicher FX-Plan"
	)


func test_fx_plan_indoor_und_reduced_motion() -> void:
	var innen := WetterFx.fx_plan({"typ": "regen", "regen": true, "schnee": false}, true, false)
	assert_true(bool(innen["regen"]), "Indoor: Regen-Streifen an")
	assert_false(bool(innen["spritzer"]), "Indoor: keine Boden-Spritzer")
	var reduced := WetterFx.fx_plan(
		{"typ": "gewitter", "regen": true, "schnee": false}, false, true
	)
	assert_false(bool(reduced["regen"]), "Reduced Motion: keine Regen-Partikel")
	assert_false(bool(reduced["spritzer"]), "Reduced Motion: keine Spritzer")
	assert_false(bool(reduced["blitz"]), "Reduced Motion: kein Blitz-Flash")
	var reduced_schnee := WetterFx.fx_plan(
		{"typ": "schnee", "regen": false, "schnee": true}, false, true
	)
	assert_false(bool(reduced_schnee["schnee"]), "Reduced Motion: kein Schnee")
	var reduced_nebel := WetterFx.fx_plan(
		{"typ": "nebel", "regen": false, "schnee": false}, false, true
	)
	assert_true(float(reduced_nebel["nebel"]) > 0.5, "Reduced Motion: Nebel (statisch) bleibt")


func test_wetter_fx_node_wendet_plan_an() -> void:
	var fx := WetterFx.new()
	fx.reduced_motion_override = 0
	fx.partikel_faktor_override = 1.0
	tree.root.add_child(fx)
	fx.wende_zustand_an({"typ": "regen", "regen": true, "schnee": false})
	var regen: GPUParticles3D = fx.get_node("Regen")
	var spritzer: GPUParticles3D = fx.get_node("RegenSpritzer")
	var schnee: GPUParticles3D = fx.get_node("Schnee")
	assert_true(regen.emitting, "Regen-Emitter an")
	assert_true(spritzer.emitting, "Spritzer-Emitter an")
	assert_false(schnee.emitting, "Schnee-Emitter aus")
	fx.wende_zustand_an({"typ": "sonne", "regen": false, "schnee": false})
	assert_false(regen.emitting, "Sonne: Regen aus")
	assert_false(spritzer.emitting, "Sonne: Spritzer aus")
	fx.wende_zustand_an({"typ": "schnee", "regen": false, "schnee": true})
	assert_true(schnee.emitting, "Winter: Schnee an")
	assert_false(regen.emitting, "Winter: kein Regen")
	fx.partikel_faktor_override = 0.5
	fx.wende_zustand_an({"typ": "regen", "regen": true, "schnee": false, "intensitaet": 1.0})
	assert_almost(regen.amount_ratio, 0.5, 1e-4, "Partikel-Budget skaliert die Menge")
	fx.queue_free()
	await wait_frames(1)


func test_wetter_fx_reduced_motion_pfad() -> void:
	var fx := WetterFx.new()
	fx.reduced_motion_override = 1
	tree.root.add_child(fx)
	fx.wende_zustand_an({"typ": "gewitter", "regen": true, "schnee": false})
	assert_false((fx.get_node("Regen") as GPUParticles3D).emitting, "Reduced: kein Regen")
	assert_false(bool(fx.fx_zustand()["blitz"]), "Reduced: kein Blitz")
	fx.queue_free()
	await wait_frames(1)


func test_process_gate_schlaeft_bei_klarwetter() -> void:
	# Quickwin #9: _process (Kamera-Folge/Blitz/Loop-Fades) tickt nur, wenn
	# es etwas zu tun gibt — Klarwetter ohne klingende Loops schläft.
	var fx := WetterFx.new()
	fx.reduced_motion_override = 0
	fx.partikel_faktor_override = 1.0
	tree.root.add_child(fx)
	await wait_frames(1)
	assert_false(fx.is_processing(), "ohne Wetterplan: kein Frame-Tick")
	fx.wende_zustand_an({"typ": "regen", "regen": true, "schnee": false})
	assert_true(fx.is_processing(), "Regen weckt den Tick")
	fx.wende_zustand_an({"typ": "sonne", "regen": false, "schnee": false})
	await wait_frames(2)
	assert_false(fx.is_processing(), "Klarwetter (Loops still): Tick schläft wieder")
	fx.folge_kamera = true
	fx.wende_zustand_an({"typ": "sonne", "regen": false, "schnee": false})
	assert_true(fx.is_processing(), "Kamera-Folge braucht den Tick weiter")
	fx.queue_free()
	await wait_frames(1)


func test_stadt_liest_echten_plan_statt_hardcode() -> void:
	# Gleiche API wie das Zuhause: identisch zu SoulWetter, kein Hardcode.
	var datum := "2026-07-26"
	assert_eq(
		CityBau.wetter_jetzt(12.0, datum),
		SoulWetter.zustand(datum, 12.0),
		"Stadt-Plan == SoulWetter-Plan"
	)
	# Der Plan liefert (über 60 Tage) auch NICHT-Sonne — ein Hardcode täte
	# das nie. Muster aus test_rest3_krankheit.
	var gefunden := false
	for tag in 60:
		for stunde in 24:
			var datum_tag := _test_datum(tag)
			if str(CityBau.wetter_jetzt(float(stunde), datum_tag)["typ"]) != "sonne":
				gefunden = true
				break
		if gefunden:
			break
	assert_true(gefunden, "Stadt-Wetter kennt mehr als Sonne")
	# Schnee liest sich am Himmel als bedeckter Tag (Shader kennt kein
	# "schnee") — Regen bleibt Regen.
	assert_eq(
		str(WetterFx.himmel_zustand({"typ": "schnee", "schnee": true})["typ"]),
		"wolken",
		"Schnee-Himmel = Wolken-Stimmung"
	)
	assert_eq(
		str(WetterFx.himmel_zustand({"typ": "regen", "regen": true})["typ"]),
		"regen",
		"Regen-Himmel bleibt Regen"
	)


func test_stadt_licht_wird_vom_wetter_gedimmt() -> void:
	var profil := CityAmbiente.licht_profil(12.0)
	var regen := CityAmbiente.wetter_licht_profil(profil, {"typ": "regen", "regen": true})
	assert_true(
		float(regen["sonnen_energie"]) < float(profil["sonnen_energie"]), "Regen dimmt die Sonne"
	)
	assert_true(
		float(regen["ambient_energie"]) < float(profil["ambient_energie"]),
		"Regen dimmt das Ambient"
	)
	var sonne := CityAmbiente.wetter_licht_profil(profil, {"typ": "sonne", "regen": false})
	assert_almost(
		float(sonne["sonnen_energie"]),
		float(profil["sonnen_energie"]),
		1e-6,
		"Sonne lässt das Licht unangetastet"
	)
	var schnee := CityAmbiente.wetter_licht_profil(profil, {"typ": "schnee", "schnee": true})
	assert_true(
		float(schnee["sonnen_energie"]) < float(profil["sonnen_energie"]),
		"Schnee dimmt wie ein bedeckter Tag"
	)


func test_garten_hook_haengt_wetter_fx_an() -> void:
	# Einen deterministisch nassen Moment im Plan suchen (SoulWetter würfelt
	# pro Tag stabil — wir injizieren genau diesen Tag + Stunde).
	var nass_datum := ""
	var nass_stunde := -1.0
	for tag in 60:
		for stunde in 24:
			var datum := _test_datum(tag)
			if bool(SoulWetter.zustand(datum, float(stunde))["regen"]):
				nass_datum = datum
				nass_stunde = float(stunde)
				break
		if not nass_datum.is_empty():
			break
	assert_true(not nass_datum.is_empty(), "Plan hat einen Regen-Moment")
	var raum := FakeGartenRaum.new()
	tree.root.add_child(raum)
	var fx := GardenWorld.wetter_fx_anhaengen(raum, nass_datum, nass_stunde)
	if fx == null:
		fail_test("Hook liefert keine Komponente")
		raum.queue_free()
		return
	assert_true(bool(fx.fx_zustand()["regen"]), "Regen-Tag = sichtbarer Regen im Garten")
	assert_false(fx.indoor_modus, "Garten ist Outdoor-Modus")
	var nochmal := GardenWorld.wetter_fx_anhaengen(raum, nass_datum, nass_stunde)
	assert_eq(nochmal, fx, "idempotent: zweiter Aufruf liefert dieselbe Instanz")
	var kein_garten := Node3D.new()
	tree.root.add_child(kein_garten)
	assert_eq(
		GardenWorld.wetter_fx_anhaengen(kein_garten, nass_datum, nass_stunde),
		null,
		"nur der Garten bekommt den Hook"
	)
	raum.queue_free()
	kein_garten.queue_free()
	await wait_frames(1)


func test_diorama_zeigt_indoor_regen() -> void:
	var diorama := StreetDiorama.new()
	diorama.wetter_override = {"typ": "regen", "regen": true, "schnee": false}
	tree.root.add_child(diorama)
	await wait_frames(1)
	var fx := diorama.wetter_fx()
	if fx == null:
		fail_test("Diorama hat keine Wetter-Komponente")
		diorama.queue_free()
		return
	assert_true(fx.indoor_modus, "Fenster-Regen läuft im Indoor-Modus")
	assert_true(bool(fx.fx_zustand()["regen"]), "Regen-Streifen vor dem Fenster an")
	assert_false(bool(fx.fx_zustand()["spritzer"]), "keine Boden-Spritzer hinterm Fenster")
	var tafel := diorama.get_node_or_null("BlitzTafel")
	assert_true(tafel is MeshInstance3D, "Blitz-Tafel existiert")
	assert_false((tafel as MeshInstance3D).visible, "Blitz-Tafel ruht ohne Gewitter")
	diorama.queue_free()
	var garten := GartenDiorama.new()
	garten.wetter_override = {"typ": "gewitter", "regen": true, "schnee": false}
	tree.root.add_child(garten)
	await wait_frames(1)
	assert_true(bool(garten.wetter_fx().fx_zustand()["blitz"]), "Gewitter aktiviert den Blitz")
	garten.queue_free()
	await wait_frames(1)


## Deterministischer Test-Kalender: 60 Tage über Juli–September 2026.
func _test_datum(tag: int) -> String:
	return "2026-%02d-%02d" % [7 + int(tag / 28.0), 1 + tag % 28]

extends TestCase
## W15/DOORTRAVEL (Doc A §1.4) — additive Tür-Fahrt: pure Pfad-/Anker-/
## Fallback-Mathe, Zustands-Protokoll der inneren DOOR_TRAVEL-Variante
## (Quelle entladen, Ziel aktiv, Gooby an der Ziel-Tür, Wisch bleibt
## Fallback-Codepfad) und Leak-Freiheit (Node-Niveau vorher == nachher,
## Muster tests/tools/leak_gate.gd). Router-API/Signale bleiben frozen —
## test_scene_router.gd/test_ef3_door_wipe.gd laufen UNVERÄNDERT.

const ROUTER_SCRIPT := preload("res://scripts/core/scene_router.gd")
const FAKE_VEIL_SCRIPT := preload("res://tests/fixtures/fake_veil.gd")

const LIVING := &"home/living"
const KITCHEN := &"home/kitchen"

## ── Pure Mathe ───────────────────────────────────────────────────────────────


func test_fallback_entscheidung() -> void:
	assert_eq(DoorTravelFahrt.fallback_grund(true, false, 0), "reduced_motion")
	assert_eq(DoorTravelFahrt.fallback_grund(false, true, 0), "low_end")
	assert_eq(DoorTravelFahrt.fallback_grund(false, false, 251), "ladezeit", "über Budget")
	assert_eq(DoorTravelFahrt.fallback_grund(false, false, 250), "", "Budget inklusiv")
	assert_eq(DoorTravelFahrt.fallback_grund(false, false, 0), "", "Normalfall fährt")
	assert_eq(DoorTravelFahrt.fallback_grund(false, false, 90, 80), "ladezeit", "Budget injiziert")
	assert_eq(DoorTravelFahrt.fallback_grund(true, true, 999), "reduced_motion", "RM gewinnt")


func test_tuer_anker_aus_room_defs() -> void:
	var anker := RoomDefs.door_anker("living", "living_kueche")
	assert_false(anker.is_empty(), "bekannte Tür hat Anker")
	var door_def := RoomDefs.door("living", "living_kueche")
	assert_eq(anker["pos"], RoomDefs.door_world_pos(RoomDefs.room("living"), door_def))
	assert_eq(anker["inward"], RoomDefs.wall_inward("N"))
	assert_true(RoomDefs.door_anker("living", "gibtsnicht").is_empty(), "unbekannte Tür → {}")
	assert_true(RoomDefs.door_anker("nirgends", "living_kueche").is_empty(), "unbekannter Raum")


func test_ziel_ausrichtung_tuer_auf_tuer() -> void:
	# Reales Paar aus rooms.json: living_kueche (N) ↔ kueche_living (W).
	var a := RoomDefs.door_anker("kitchen", "kueche_living")
	var b := RoomDefs.door_anker("living", "living_kueche")
	var t := DoorTravelFahrt.ziel_ausrichtung(a["pos"], a["inward"], b["pos"], b["inward"])
	var b_pos_neu: Vector3 = t * Vector3(b["pos"])
	assert_true((b_pos_neu - Vector3(a["pos"])).length() < 0.0001, "Türmitten liegen aufeinander")
	var b_inward_neu: Vector3 = t.basis * Vector3(b["inward"])
	assert_true(
		(b_inward_neu + Vector3(a["inward"])).length() < 0.0001, "Innenrichtungen entgegengesetzt"
	)
	# Nur Gieren + XZ-Verschiebung: Boden bleibt Boden.
	assert_almost(t.origin.y, 0.0, 0.0001, "keine Höhenverschiebung")
	assert_true(((t.basis * Vector3.UP) - Vector3.UP).length() < 0.0001, "UP bleibt UP")


func test_kamera_kurve_punkte_tangente_und_hoehe() -> void:
	var start := Vector3(3.0, 7.5, 9.0)
	var tuer := Vector3(1.5, DoorTravelFahrt.KAMERA_TUER_HOEHE_M, 0.0)
	var richtung := Vector3(0, 0, -1)
	var ende := Vector3(-2.0, 6.8, -8.0)
	var kurve := DoorTravelFahrt.kamera_kurve(start, tuer, richtung, ende)
	assert_eq(kurve.point_count, 4, "Start/Anflug/Tür/Ziel")
	assert_eq(kurve.get_point_position(0), start)
	var anflug := tuer - richtung * DoorTravelFahrt.ANFLUG_ABSTAND_M
	assert_true(
		(kurve.get_point_position(1) - anflug).length() < 0.0001, "Anflug-Punkt vor der Tür"
	)
	assert_eq(kurve.get_point_position(2), tuer)
	assert_eq(kurve.get_point_position(3), ende)
	# Anflug→Tür ist ein EBENER Korridor auf Türhöhe (Sinken passiert davor):
	# die Kamera hängt beim Durchgang nie im Türsturz oder in der Wand.
	var laenge := kurve.get_baked_length()
	var anflug_offset := kurve.get_closest_offset(anflug)
	var tuer_offset := kurve.get_closest_offset(tuer)
	var schritte := 8
	for i in schritte + 1:
		var o := lerpf(anflug_offset, tuer_offset, float(i) / schritte)
		var p := kurve.sample_baked(o)
		assert_almost(p.y, tuer.y, 0.01, "Korridor eben auf Türhöhe (Schritt %d)" % i)
	# Tangente am Türrahmen = Durchgangsrichtung (Kamera passiert senkrecht).
	var davor := kurve.sample_baked(tuer_offset - 0.1)
	var danach := kurve.sample_baked(minf(tuer_offset + 0.1, laenge))
	var tangente := (danach - davor).normalized()
	assert_true(tangente.dot(richtung) > 0.99, "Tangente an der Tür = Durchgangsrichtung")
	# Türhöhe bleibt unter Türsturz UND unter der DeckenFade-Schwelle —
	# der W14-Decken-Fade kann während des Durchgangs nicht flackern.
	assert_true(DoorTravelFahrt.KAMERA_TUER_HOEHE_M < DoorTransition.DOOR_HEIGHT, "unterm Sturz")
	assert_true(
		DoorTravelFahrt.KAMERA_TUER_HOEHE_M < DeckenFade.HOEHE_FREI_AB_M,
		"unter der Decken-Fade-Schwelle"
	)


func test_fahrt_dauer_und_ease_und_angleich() -> void:
	assert_almost(DoorTravelFahrt.fahrt_dauer(0.0), DoorTravelFahrt.DAUER_MIN_S)
	assert_almost(DoorTravelFahrt.fahrt_dauer(1000.0), DoorTravelFahrt.DAUER_MAX_S)
	assert_almost(DoorTravelFahrt.fahrt_dauer(18.9), 1.05, 0.0001, "Länge/Tempo dazwischen")
	assert_almost(DoorTravelFahrt.ease_fahrt(0.0), 0.0)
	assert_almost(DoorTravelFahrt.ease_fahrt(1.0), 1.0)
	assert_almost(DoorTravelFahrt.ease_fahrt(0.5), 0.5)
	assert_true(DoorTravelFahrt.ease_fahrt(0.2) < 0.2, "sanft rein")
	assert_true(DoorTravelFahrt.ease_fahrt(0.8) > 0.8, "sanft raus")
	assert_almost(DoorTravelFahrt.angleich_gewicht(0.0), 0.0)
	assert_almost(DoorTravelFahrt.angleich_gewicht(DoorTravelFahrt.ANGLEICH_AB), 0.0)
	assert_almost(DoorTravelFahrt.angleich_gewicht(1.0), 1.0, 1e-6, "t=1 → exakt Zielkamera")


func test_blick_punkt_bezier() -> void:
	var start := Vector3(0, 2, 8)
	var tuer := Vector3(1, 1, 0)
	var ende := Vector3(2, 2, -8)
	assert_eq(DoorTravelFahrt.blick_punkt(0.0, start, tuer, ende), start)
	assert_eq(DoorTravelFahrt.blick_punkt(1.0, start, tuer, ende), ende)
	var mitte := DoorTravelFahrt.blick_punkt(0.5, start, tuer, ende)
	assert_true(
		(mitte - (start * 0.25 + tuer * 0.5 + ende * 0.25)).length() < 0.0001,
		"quadratische Bezier-Mitte"
	)


## ── Fahrt-Plan (Eignung) ─────────────────────────────────────────────────────


func test_fahrt_plan_lehnt_fremde_szenen_und_falsche_tueren_ab() -> void:
	var fremd := Node3D.new()
	assert_true(DoorTravelFahrt.fahrt_plan(fremd, KITCHEN, {"door_id": "kueche_living"}).is_empty())
	fremd.free()
	var raum := await _raum_aufbauen("living")
	assert_true(
		DoorTravelFahrt.fahrt_plan(raum, &"arcade", {"door_id": "kueche_living"}).is_empty(),
		"kein home/-Ziel → Wisch"
	)
	assert_true(DoorTravelFahrt.fahrt_plan(raum, KITCHEN, {}).is_empty(), "ohne door_id → Wisch")
	assert_true(
		(
			DoorTravelFahrt
			. fahrt_plan(raum, &"home/bathroom", {"door_id": "bad_schlafzimmer"})
			. is_empty()
		),
		"Tür führt woandershin (bad_schlafzimmer.to == bedroom) → Wisch"
	)
	var plan := DoorTravelFahrt.fahrt_plan(raum, KITCHEN, {"door_id": "kueche_living"})
	assert_false(plan.is_empty(), "echtes Paar living→kitchen ist fahrbar")
	assert_eq(plan["quell_tuer_name"], "Door_living_kueche")
	assert_eq(plan["ziel_tuer_name"], "Door_kueche_living")
	assert_eq(plan["quell_anker"], RoomDefs.door_anker("living", "living_kueche"))
	assert_eq(plan["ziel_anker"], RoomDefs.door_anker("kitchen", "kueche_living"))
	raum.queue_free()
	await wait_frames(2)


## ── Zustands-Protokoll + Fallback + Leak (Integration, echte Räume) ──────────


func test_fahrt_zustandsprotokoll_quelle_weg_ziel_aktiv() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var veil: Node = ctx["veil"]
	var mount: Node3D = ctx["mount"]
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	router.goto(LIVING)
	await wait_until(func() -> bool: return finished.size() == 1, 15_000)
	var quelle: Node = router.get_current_scene()
	var cover_vor_fahrt: int = veil.cover_calls

	var states: Array = []
	var peak := {"nodes": 0, "cam_path": false}
	var beobachte := func(state: int) -> void:
		states.append(state)
		if state == ROUTER_SCRIPT.State.REVEAL and peak["nodes"] == 0:
			peak["nodes"] = _count_nodes(mount)
			var fahrt := mount.get_node_or_null("DoorTravelFahrt")
			peak["cam_path"] = fahrt != null and fahrt.get_node_or_null("CamPath") != null
	router.state_changed.connect(beobachte)
	router.goto(KITCHEN, {"door_id": "kueche_living"}, ROUTER_SCRIPT.TravelType.DOOR_TRAVEL)
	var done := await wait_until(func() -> bool: return finished.size() == 2, 15_000)
	assert_true(done, "Fahrt muss travel_finished liefern")
	await wait_frames(3)

	# Gleiches State-Protokoll wie immer (Vertrag frozen), aber OHNE Wisch.
	assert_eq(
		states,
		(
			[
				ROUTER_SCRIPT.State.COVER,
				ROUTER_SCRIPT.State.SWAP,
				ROUTER_SCRIPT.State.WAIT_READY,
				ROUTER_SCRIPT.State.REVEAL,
				ROUTER_SCRIPT.State.IDLE,
			]
			as Array
		),
		"State-Protokoll der Fahrt"
	)
	assert_eq(veil.cover_calls, cover_vor_fahrt, "Fahrt nutzt KEINEN Veil-Wisch")
	assert_true(peak["nodes"] > 0, "Spitzenlast gemessen")
	assert_true(peak["cam_path"], "Path3D-CamPath existiert während der Fahrt")
	# Quelle entladen, Ziel aktiv (exakt eine Szene im Mount).
	assert_false(is_instance_valid(quelle), "Quellraum ist vollständig entladen")
	var ziel: Node = router.get_current_scene()
	assert_true(is_instance_valid(ziel), "Zielraum aktiv")
	assert_eq(str(ziel.get("room_id")), "kitchen", "Ziel ist die Küche")
	assert_eq(mount.get_child_count(), 1, "genau eine Szene im Mount (Fahrt-Node weg)")
	# Gooby steht sichtbar im Zielraum an der Ziel-Tür (Spawn-Contract).
	var gooby: Node3D = ziel.gooby()
	assert_true(gooby != null and gooby.visible, "Ziel-Gooby sichtbar")
	var anker := RoomDefs.door_anker("kitchen", "kueche_living")
	var spawn: Vector3 = (
		Vector3(anker["pos"]) + Vector3(anker["inward"]) * DoorTravelFahrt.SPAWN_ABSTAND_M
	)
	var abstand := (gooby.global_position - spawn).length()
	assert_true(abstand < 0.75, "Gooby an der Ziel-Tür (Abstand %.2f m)" % abstand)
	# Ziel-Tür sichtbar — sie hat die offene Quell-Tür nahtlos übernommen.
	var tuer: Node3D = ziel.get_node_or_null("Door_kueche_living")
	assert_true(tuer != null and tuer.visible, "Ziel-Tür wiederhergestellt")
	print(
		(
			"[W15/DOORTRAVEL] Spitzenlast Fahrt: %d Nodes im Mount (danach: %d)"
			% [peak["nodes"], _count_nodes(mount)]
		)
	)
	await _cleanup(ctx)


func test_fallback_wisch_bei_reduced_motion() -> void:
	var settings: Node = tree.root.get_node("/root/AppSettings")
	settings.set_setting("reduced_motion", true)
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var veil: Node = ctx["veil"]
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	router.goto(LIVING)
	await wait_until(func() -> bool: return finished.size() == 1, 15_000)
	var cover_vorher: int = veil.cover_calls
	router.goto(KITCHEN, {"door_id": "kueche_living"}, ROUTER_SCRIPT.TravelType.DOOR_TRAVEL)
	await wait_until(func() -> bool: return finished.size() == 2, 15_000)
	assert_eq(veil.cover_calls, cover_vorher + 1, "Reduced Motion → Tür-Wisch statt Fahrt")
	assert_eq(str(router.get_current_scene().get("room_id")), "kitchen", "Ziel trotzdem erreicht")
	settings.set_setting("reduced_motion", false)
	await _cleanup(ctx)


func test_leak_niveau_nach_fahrt_exakt_ausgangsniveau() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	# Warm-up-Zyklus (ungemessen, wie leak_gate.gd): lazy Caches aufbauen.
	router.goto(LIVING)
	await wait_until(func() -> bool: return finished.size() == 1, 15_000)
	await _fahre(router, finished, KITCHEN, "kueche_living")
	await _fahre(router, finished, LIVING, "living_kueche")
	await _flush()
	var vorher := _snapshot()
	# Gemessener Zyklus: living → kitchen → living, beides als Fahrt.
	await _fahre(router, finished, KITCHEN, "kueche_living")
	await _fahre(router, finished, LIVING, "living_kueche")
	await _flush()
	var nachher := _snapshot()
	var node_drift: int = int(nachher["nodes"]) - int(vorher["nodes"])
	var orphan_drift: int = int(nachher["orphans"]) - int(vorher["orphans"])
	assert_eq(node_drift, 0, "Node-Niveau nach Fahrt-Zyklus exakt Ausgangsniveau")
	assert_eq(orphan_drift, 0, "keine Orphan-Nodes (queue_free-Vergesser)")
	print(
		(
			"[W15/DOORTRAVEL] Leak-Gate: nodes %d→%d (drift %+d), orphans %+d"
			% [int(vorher["nodes"]), int(nachher["nodes"]), node_drift, orphan_drift]
		)
	)
	await _cleanup(ctx)


## ── Helfer ───────────────────────────────────────────────────────────────────


func _fahre(router: Node, finished: Array, target: StringName, door_id: String) -> void:
	var vorher := finished.size()
	router.goto(target, {"door_id": door_id}, ROUTER_SCRIPT.TravelType.DOOR_TRAVEL)
	var ok := await wait_until(func() -> bool: return finished.size() == vorher + 1, 15_000)
	assert_true(ok, "Fahrt nach %s kam an" % target)


func _raum_aufbauen(room_id: String) -> Node3D:
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var raum: Node3D = scene.instantiate()
	var revealed := [false]
	raum.ready_for_reveal.connect(func() -> void: revealed[0] = true)
	tree.root.add_child(raum)
	await wait_until(func() -> bool: return revealed[0], 8000)
	return raum


func _make_router() -> Dictionary:
	var router: Node = ROUTER_SCRIPT.new()
	var veil: Node = FAKE_VEIL_SCRIPT.new()
	router.install_veil(veil)
	router.min_shown_ms = 0
	var mount := Node3D.new()
	tree.root.add_child(mount)
	tree.root.add_child(router)
	router.set_mount_point(mount)
	router.register_routes(RoomDefs.route_table())
	return {"router": router, "veil": veil, "mount": mount}


func _cleanup(ctx: Dictionary) -> void:
	(ctx["mount"] as Node).queue_free()
	(ctx["router"] as Node).queue_free()
	(ctx["veil"] as Node).free()
	await wait_frames(2)


## Ausklingen (Tür-Zufall-Tween 0,4 s, queue_free-Ketten), dann messen —
## Muster tests/tools/leak_gate.gd (_flush/_snapshot).
func _flush() -> void:
	var deadline := Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
	for _i in 4:
		await tree.process_frame


func _snapshot() -> Dictionary:
	return {
		"nodes": _count_nodes(tree.root),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}


func _count_nodes(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count_nodes(child)
	return n

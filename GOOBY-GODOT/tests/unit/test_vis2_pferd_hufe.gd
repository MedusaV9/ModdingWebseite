extends TestCase
## VIS-2, Trailer-Review 0:36/0:38/0:41: „Die Hufe des Pferdes clippen beim
## Laufen immer wieder leicht in den Boden bzw. in die Holzbretter der
## Hängebrücke.“ Ursache: die Reiter setzen den Knoten auf die Bodenhöhe
## der KÖRPERMITTE, und die Galopp-Clips tauchen die Hufe unter y=0.
## Fix (ranch_pferd.gd): `_halte_hufe_ueber_boden` misst nach jedem
## Skelett-Update alle vier Hufsohlen gegen den Boden (set_bodenkontakt-
## Callback oder Standflaeche) und hebt das sichtbare Rig gerade so weit,
## dass kein Huf eintaucht. Hier: Messung über N Frames auf drei
## Untergruenden (Wiese/Hang/Brueckendeck) — „mit Fix“ darf nie unter den
## Boden, „ohne Fix“ (Rohpose = Abstand minus Lift) belegt den Alt-Fehler.

const FRAMES := 100
## Numerik-Schlupf für die Welt-Messung (Bone-Pose × Transform, float32).
const EPS := 0.002


func _mount() -> RanchPferd:
	var pferd := RanchPferd.neu(Color("#D9A066"), Color("#8A5A33"))
	tree.root.add_child(pferd)
	await wait_frames(1)
	return pferd


func _cleanup(pferd: RanchPferd) -> void:
	pferd.queue_free()
	await wait_frames(1)


## N Frames laufen lassen und {mit, ohne, lift} (Minima/Maximum) einsammeln.
func _messe(pferd: RanchPferd, frames: int) -> Dictionary:
	var min_mit := INF
	var min_ohne := INF
	var max_lift := 0.0
	for _i in frames:
		await wait_frames(1)
		var mit: float = pferd.huf_bodenabstand_min()
		min_mit = minf(min_mit, mit)
		min_ohne = minf(min_ohne, mit - pferd._huf_lift)
		max_lift = maxf(max_lift, pferd._huf_lift)
	return {"mit": min_mit, "ohne": min_ohne, "lift": max_lift}


func test_wiese_galopp_hufe_tauchen_nicht_mehr_ein() -> void:
	var pferd := await _mount()
	pferd.set_gangart(RanchPferd.GANG_GALOPP)
	var mess: Dictionary = await _messe(pferd, FRAMES)
	assert_true(
		float(mess["ohne"]) < 0.0,
		"Alt-Fehler reproduziert: Galopp-Clip taucht ohne Fix ein (%.4f m)" % mess["ohne"]
	)
	assert_true(
		float(mess["mit"]) >= -EPS,
		"Wiese: kein Huf unter dem Boden (min %.4f m ueber %d Frames)" % [mess["mit"], FRAMES]
	)
	await _cleanup(pferd)


func test_hang_hufe_bleiben_ueber_dem_gelaende() -> void:
	var pferd := await _mount()
	# 35-%-Hang wie am Huegel: Boden steigt mit x, Koerpermitte bei y=0.
	pferd.set_bodenkontakt(func(x: float, _z: float) -> float: return 0.35 * x)
	pferd.set_gangart(RanchPferd.GANG_GALOPP)
	var mess: Dictionary = await _messe(pferd, FRAMES)
	assert_true(
		float(mess["ohne"]) < -0.03,
		"Alt-Fehler: am Hang steckten die Berg-Hufe tief im Boden (%.4f m)" % mess["ohne"]
	)
	assert_true(
		float(mess["mit"]) >= -EPS,
		"Hang: kein Huf unter dem Gelaende (min %.4f m ueber %d Frames)" % [mess["mit"], FRAMES]
	)
	assert_true(float(mess["lift"]) > 0.01, "Hang: die Wache hebt das Rig an")
	await _cleanup(pferd)


func test_brueckendeck_hufe_bleiben_ueber_den_planken() -> void:
	var pferd := await _mount()
	# Haengebruecke: unter den vorderen Hufen liegt eine 12 cm hoehere
	# Planke (Deckwoelbung), die Koerpermitte haengt noch auf 0.
	pferd.set_bodenkontakt(func(_x: float, z: float) -> float: return 0.12 if z < -0.3 else 0.0)
	pferd.set_gangart(RanchPferd.GANG_SCHRITT)
	var mess: Dictionary = await _messe(pferd, FRAMES)
	assert_true(
		float(mess["ohne"]) < -0.05,
		"Alt-Fehler: Hufe steckten in den Brueckenplanken (%.4f m)" % mess["ohne"]
	)
	assert_true(
		float(mess["mit"]) >= -EPS,
		"Bruecke: kein Huf unter der Planke (min %.4f m ueber %d Frames)" % [mess["mit"], FRAMES]
	)
	await _cleanup(pferd)


func test_gear_macht_die_anhebung_mit() -> void:
	var pferd := await _mount()
	pferd.equip("sattel", "rot")
	pferd.set_bodenkontakt(func(x: float, _z: float) -> float: return 0.35 * x)
	pferd.set_gangart(RanchPferd.GANG_GALOPP)
	await wait_frames(30)
	var sattel: Node3D = pferd.get_node("Gear_sattel")
	assert_true(pferd._huf_lift > 0.01, "Hang hebt das Rig an")
	assert_almost(
		sattel.position.y,
		RanchPferd.RUECKEN_Y + 0.06 + pferd._huf_lift,
		1e-4,
		"Sattel sitzt weiter auf dem (angehobenen) Ruecken"
	)
	await _cleanup(pferd)


func test_vertrag_bleibt_unberuehrt() -> void:
	var pferd := await _mount()
	pferd.set_bodenkontakt(func(x: float, _z: float) -> float: return 0.35 * x)
	pferd.set_gangart(RanchPferd.GANG_GALOPP)
	await wait_frames(30)
	# Die Wache korrigiert NUR das sichtbare Rig — Vertrags-API und
	# Node-Position (Fahr-Physik der Reiter/Controller) bleiben gleich.
	assert_almost(pferd.position.y, 0.0, 1e-6, "Node-Position unberuehrt")
	assert_true(pferd.body_height() > 1.0, "body_height weiter plausibel")
	assert_ne(pferd.head_pivot(), null, "head_pivot weiter da")
	var vorher := pferd.phase()
	pferd.tick(0.25, 2.0)
	assert_ne(pferd.phase(), vorher, "tick treibt die Phase weiter")
	await _cleanup(pferd)


func test_auto_verdrahtung_unter_dem_welt_reiter() -> void:
	# Duck-Typing wie RanchWeltReiter (springe_zu + aktuelle_zone): das
	# Pferd holt sich die Reit-Hoehe (inkl. Brueckendeck) automatisch.
	var reiter := _FakeReiter.new()
	tree.root.add_child(reiter)
	var pferd := RanchPferd.neu(Color("#D9A066"), Color("#8A5A33"))
	reiter.add_child(pferd)
	await wait_frames(1)
	assert_true(pferd._boden_cb.is_valid(), "Bodenkontakt automatisch verdrahtet")
	reiter.queue_free()
	await wait_frames(1)


class _FakeReiter:
	extends Node3D

	func springe_zu(_punkt: Vector3, _blick_rad := 0.0) -> void:
		pass

	func aktuelle_zone() -> String:
		return ""

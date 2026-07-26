extends TestCase
## RW-2 — GLB-Pferd (ranch_pferd.gd): das importierte Rig ersetzt das
## prozedurale Pferd, der RANCH-2-API-Vertrag (set_farbe/set_gait/tick/
## head_pivot/body_height/equip/phase) bleibt intakt, Fohlen-GLB wird
## per Alter gewechselt und die Gangart-Loops blinzeln manuell.

const CLIPS: Array[String] = [
	"idle",
	"schritt",
	"trab",
	"galopp",
	"sprung",
	"fressen",
	"kopfschuetteln",
	"schlafen",
	"blinzeln",
]


func test_glb_rig_hat_skelett_und_alle_clips() -> void:
	var pferd := _pferd()
	var skelett := pferd.find_children("*", "Skeleton3D", true, false)
	assert_eq(skelett.size(), 1, "genau ein Skeleton3D aus dem GLB")
	assert_eq((skelett[0] as Skeleton3D).get_bone_count(), 13, "13 Knochen (RANCH-ASSETS)")
	for name: String in ["head", "body", "leg.FL", "leg.FR", "leg.BL", "leg.BR"]:
		assert_true((skelett[0] as Skeleton3D).find_bone(name) >= 0, "Knochen %s" % name)
	var player := pferd.find_children("*", "AnimationPlayer", true, false)
	assert_eq(player.size(), 1, "AnimationPlayer aus dem GLB")
	var anim := player[0] as AnimationPlayer
	for clip in CLIPS:
		assert_true(
			anim.has_animation(clip) or anim.has_animation(clip + "-loop"),
			"Clip %s vorhanden" % clip
		)
	pferd.queue_free()


func test_api_vertrag_bleibt_intakt() -> void:
	var pferd := _pferd()
	pferd.set_farbe("fuchs")
	assert_eq(pferd.farbe, Color("#D98E5F"), "set_farbe nutzt die FELL-Tabelle")
	pferd.set_gait("galopp")
	assert_eq(pferd.gangart, RanchPferd.GANG_GALOPP, "set_gait uebersetzt RANCH-2-Ids")
	var phase_vor := pferd.phase()
	pferd.tick(0.1)
	assert_ne(pferd.phase(), phase_vor, "tick treibt die Phase")
	assert_true(pferd.phase() >= 0.0 and pferd.phase() < 1.0, "phase in 0..1")
	assert_true(pferd.head_pivot() != null, "head_pivot liefert den Kopf-Proxy")
	assert_true(pferd.head_pivot().is_inside_tree(), "Kopf-Proxy haengt im Baum")
	assert_almost(pferd.body_height(), 1.54, 0.001, "Sitzhoehe = Ruecken 1,42 + Sattel")
	pferd.equip("sattel", "rot")
	assert_true(pferd.has_node("Gear_sattel"), "Sattel-Aufsatz angebaut")
	pferd.equip("sattel", null)
	assert_false(
		(
			pferd.get_node_or_null("Gear_sattel") != null
			and not pferd.get_node("Gear_sattel").is_queued_for_deletion()
		),
		"Sattel wieder abgenommen"
	)
	pferd.queue_free()


func test_set_aussehen_wechselt_fohlen_glb_und_skala() -> void:
	var pferd := _pferd()
	var erwachsen := {
		"farbe": "palomino",
		"groesse": 1.1,
		"alter": "ausgewachsen",
		"gene": {"s": ["Sch", "s0"], "glitzer": ["gx", "gx"]},
		"abzeichen": {"blesse": true, "socken": [1, 0, 0, 0]},
	}
	pferd.set_aussehen(erwachsen)
	assert_true(pferd.schecke, "Sch-Allel = Schecke")
	assert_true(pferd.glitzer, "gx/gx = Glitzer")
	assert_almost(pferd.scale.x, 1.1, 0.001, "Groesse skaliert das ganze Pferd")
	pferd.set_aussehen({"farbe": "braun", "groesse": 1.0, "alter": "fohlen"})
	await wait_frames(2)
	assert_almost(
		pferd.scale.x, 0.55 / 0.62, 0.001, "Fohlen-GLB traegt die Restskala zur 0,55-Phase"
	)
	assert_true(
		pferd.find_children("*", "Skeleton3D", true, false).size() >= 1,
		"Fohlen-Rig steht nach dem Umbau"
	)
	assert_true(pferd.head_pivot() != null, "Kopf-Proxy nach Umbau erneuert")
	pferd.queue_free()


func test_gangart_loops_blinzeln_manuell() -> void:
	var pferd := _pferd()
	var player := pferd.find_children("*", "AnimationPlayer", true, false)
	var anim := player[0] as AnimationPlayer
	for basis: String in ["idle", "schritt", "trab", "galopp"]:
		var name := basis if anim.has_animation(basis) else basis + "-loop"
		var clip := anim.get_animation(name)
		for i in clip.get_track_count():
			assert_false(
				String(clip.track_get_path(i)).contains("augen_zu"),
				"%s: augen_zu-Track entfernt (manuelles Blinzeln)" % basis
			)
	pferd.queue_free()


func test_proxy_beine_schwingen_diagonal_im_trab() -> void:
	var pferd := _pferd()
	pferd.set_gait("trab")
	pferd.update_gang(0.1)
	var beine: Array = []
	for kind in pferd.get_children():
		if kind is Node3D and kind.get_class() == "Node3D" and str(kind.name) != "Rig":
			beine.append(kind)
	assert_true(beine.size() >= 4, "vier Proxy-Beine fuer Bestandstests")
	var b: Array = beine.slice(0, 4)
	assert_almost((b[0] as Node3D).rotation.x, (b[3] as Node3D).rotation.x, 1e-4, "Diagonale FL+BR")
	assert_almost((b[1] as Node3D).rotation.x, (b[2] as Node3D).rotation.x, 1e-4, "Diagonale FR+BL")
	assert_true(
		absf((b[0] as Node3D).rotation.x - (b[1] as Node3D).rotation.x) > 1e-3, "Paare gegenphasig"
	)
	pferd.queue_free()


func _pferd() -> RanchPferd:
	var pferd := RanchPferd.neu(Color("#B98A5E"), Color("#6E4B2E"))
	tree.root.add_child(pferd)
	return pferd

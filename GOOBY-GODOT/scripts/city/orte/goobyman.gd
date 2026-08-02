class_name OrtGoobyman
extends OrtScene
## GOOBYMAN — Drogerie-Laden (W13C, Doc H §6.4, Wortspiel auf Rossmann):
## Verkäufer-Gooby mit Heldenkomplex, Regale aus KayKit-Innen-Assets,
## prozedurales Schriftzug-Schild (Label3D — kein Bild-Asset). Sortiment
## (Zahnbürsten in 3 Qualitäten, Pflaster, Schlafmaske) via GoobymanSheet.
## Kauft man 5+ Artikel auf einmal, wirft sich der Verkäufer den
## „GOOBYMAN“-Handtuch-Umhang um (prozedurales Mesh + Tween, Doc H §4.3).
## G8-P1 „Jeder Ort lebt“ (PT2-B4): stöbernde Kundschaft zwischen den
## Regalen, der Verkäufer tippt an der Kasse (KassenNpc) und die Momente
## liefern Helden-Fans + Parfüm-Probe (die W17-Deko bleibt unangetastet).

const INNEN := "res://assets/city/innen"
## ASSET-SOURCE (W17): neue CC0-Laden-Modelle — docs/godot-rewrite/ASSET-CREDITS.md.
const INNEN2 := "res://assets/city/innen2"

var _umhang_laeuft := false


func _baue_innenraum() -> void:
	# KayKit-Basisgrößen: Counter ~2 m — Skalen klein halten (s. rehwei.gd).
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(0.0, 0.0, -1.2), 90.0, 0.9)
	# Tiegel-Regal: Cremes und Seifen-Gläser (reine Deko — Seife/Shampoo
	# stehen bewusst NICHT im Sortiment, s. goobyman_sortiment.json).
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-3.4, 0.0, -3.2), 0.0, 1.5)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-2.5, 0.0, -3.4), 15.0, 1.2)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-4.2, 0.0, -3.4), -10.0, 1.0)
	# Nachschub-Kartons + Angebots-Aufsteller.
	_prop("%s/crate.gltf" % INNEN, Vector3(3.4, 0.0, -1.6), 18.0, 0.65)
	_prop("%s/crate.gltf" % INNEN, Vector3(3.7, 0.0, 0.2), -12.0, 0.65)
	_prop("%s/menu.gltf" % INNEN, Vector3(-4.8, 0.0, -1.8), 30.0, 1.6)
	_prop("%s/kitchencounter_sink.gltf" % INNEN, Vector3(3.4, 0.0, -3.2), 0.0, 0.9)
	# ASSET-SOURCE (W17) Drogerie-Regalzone: weißes Hochregal neben den
	# Tiegeln, Holzregal rechts, Handtuch-Wandbord überm Spülcounter,
	# Mülltonne bei den Nachschub-Kartons, Monstera als Laden-Grün.
	# Regalböden (aus GLB gemessen): hoch 0.40/0.78/1.15/1.53, offen
	# 0.27/0.52/0.78/1.03 — kleine Tiegel als Regal-Ware obendrauf.
	_prop("%s/regal_hoch.glb" % INNEN2, Vector3(-1.7, 0.0, -3.6), 0.0, 1.0)
	_prop("%s/regal_offen.glb" % INNEN2, Vector3(5.2, 0.0, -3.4), -12.0, 1.0)
	_prop("%s/shelf_papertowel_decorated.gltf" % INNEN2, Vector3(1.7, 1.6, -3.8), 0.0, 0.8)
	_prop("%s/muelleimer_gruen.glb" % INNEN2, Vector3(2.7, 0.0, 1.8), 14.0, 0.9)
	_prop("%s/pflanze_laden_klein.glb" % INNEN2, Vector3(-5.5, 0.0, -0.9), 0.0, 0.9)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-1.7, 0.4, -3.6), 8.0, 0.3)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-1.7, 1.15, -3.6), -12.0, 0.28)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(5.2, 0.52, -3.4), 30.0, 0.3)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(5.2, 1.03, -3.4), -25.0, 0.26)
	_baue_schriftzug()


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/goobyman.json"


func _sortiment_pfad() -> String:
	return GoobymanKatalog.PFAD


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#F26D6D"), "emotion": "happy", "pos": Vector3(0.0, 0.0, -2.2)}


## Eigenes Händler-UI: GoobymanSheet (Bürsten-Status, Pflaster-Cap,
## Schlafmaske einmalig, Umhang-Gag-Zähler).
func oeffne_laden() -> void:
	var inhalt := GoobymanSheet.new()
	inhalt.gs = game_state()
	inhalt.waren = GoobymanKatalog.waren()
	inhalt.erstes_mal = ist_erstbesuch
	inhalt.gekauft.connect(_on_gekauft)
	inhalt.umhang_gag.connect(_spiele_umhang_gag)
	zeige_sheet(I18nService.t("city.ort.goobyman"), inhalt)


func _on_gekauft(_ware_id: String) -> void:
	if _umhang_laeuft:
		return
	# G8-P1: Kassen-Piep + Winken übernimmt der KassenNpc (Muster rehwei).
	if kassen_npc != null:
		kassen_npc.kunde_zahlt()
	elif rig != null:
		rig.play_clip("wave")


## G8-P1: Drogerie-Leben — drei Kunden stöbern Tiegel-Ecke, Gänge und
## Nachschub-Zone ab (KEINE Deko-Umbauten, nur Wege zwischen der W17-
## Einrichtung). Momente: Helden-Fan-Jubel („GOOBYMAN!“) und die
## Parfüm-Probe (care_wasser hochgestimmt = Pssst-pssst-Zerstäuber).
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 3,
		"punkte":
		[
			Vector3(-3.3, 0.0, -1.3),
			Vector3(-1.7, 0.0, 0.9),
			Vector3(2.3, 0.0, 1.3),
			Vector3(-4.6, 0.0, -0.4),
			Vector3(4.6, 0.0, -2.2),
		],
		"sprueche": "goobyman",
		"blick": Vector3(0.0, 0.0, -3.6),
		"gemurmel": true,
		"tuer_glocke": true,
		"kasse": true,
		"momente":
		[
			{
				"alle_s": 23.0,
				"versatz_s": 7.0,
				"sound": "emo_stolz",
				"pitch": 1.05,
				"clip": "celebrate",
				"sprueche": "goobyman_fans",
			},
			{
				"alle_s": 29.0,
				"versatz_s": 17.0,
				"sound": "care_wasser",
				"pitch": 1.5,
				"clip": "hop",
				"sprueche": "goobyman_probe",
			},
		],
	}


## Prozedurales Laden-Schild über der Theke (Doc H §6.4 „Logo“ ohne
## Bild-Asset): Schriftzug + Glyph als Label3D, Muster OrtSchild/city_bau.
func _baue_schriftzug() -> void:
	var schild := Label3D.new()
	schild.text = "🦸 %s" % I18nService.t("city.ort.goobyman")
	schild.font_size = 120
	schild.pixel_size = 0.008
	schild.modulate = Color("#D94F8C")
	schild.outline_size = 24
	schild.outline_modulate = AcTokens.INK
	schild.position = Vector3(0.0, 3.4, -3.8)
	add_child(schild)


## Umhang-Gag (Doc H §6.4/§4.3): der Verkäufer wirft sich ein „Handtuch“
## um (prozedurales PlaneMesh, KEIN Asset) und posiert — das Tuch weht per
## Tween, danach löst sich alles wieder auf.
func _spiele_umhang_gag() -> void:
	if rig == null or _umhang_laeuft:
		return
	_umhang_laeuft = true
	zeige_toast(I18nService.t("goobyman.umhang.gag"))
	rig.play_clip("wave")
	var umhang := _baue_umhang()
	rig.add_child(umhang)
	var tween := create_tween()
	# Anlegen: von oben einschweben …
	umhang.position.y += 0.6
	umhang.scale = Vector3.ONE * 0.1
	tween.tween_property(umhang, "position:y", umhang.position.y - 0.6, 0.25)
	tween.parallel().tween_property(umhang, "scale", Vector3.ONE, 0.25)
	# … dann 3× wehen (Rotations-Wobble) …
	for _i in 3:
		tween.tween_property(umhang, "rotation_degrees:x", -38.0, 0.28)
		tween.tween_property(umhang, "rotation_degrees:x", -14.0, 0.28)
	# … und wieder verschwinden.
	tween.tween_property(umhang, "scale", Vector3.ONE * 0.02, 0.3)
	tween.tween_callback(umhang.queue_free)
	tween.tween_callback(func() -> void: _umhang_laeuft = false)


func _baue_umhang() -> MeshInstance3D:
	var tuch := MeshInstance3D.new()
	tuch.name = "GoobymanUmhang"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.8, 1.0)
	var stoff := StandardMaterial3D.new()
	stoff.albedo_color = Color("#E8524A")
	stoff.cull_mode = BaseMaterial3D.CULL_DISABLED
	stoff.roughness = 0.9
	mesh.material = stoff
	tuch.mesh = mesh
	# Hinter den Schultern, leicht nach außen gekippt — „weht im Wind“.
	tuch.position = Vector3(0.0, 0.85, 0.35)
	tuch.rotation_degrees = Vector3(-24.0, 0.0, 0.0)
	return tuch

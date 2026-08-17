extends SceneTree
## RW-1-Screenshot-Tool (KEIN Test): rendert die Review-Artefakte der
## offenen Ranch-Region — alle Zonen, vier Wetterlagen, Nacht mit
## Glühwürmchen, Wildtiere nah und den Reiter im Gelände — und misst je
## Ansicht die Draw-Calls. Aufruf (echter Renderer):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/rw1_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RW1"
const SETTLE := 55

var _region: Node3D


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	var szene: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	_region = szene.instantiate()
	_region.stunde_override = 11.0
	_region.wetter_override = "sonne"
	root.add_child(_region)
	await _settle(30)
	# --- Zonen (Reiter-Perspektive, Blick auf das Zonen-Herzstück) ---
	await _zone_shot("hof", Vector2(0, 160), Vector2(0, 0), "zone_hof.png")
	await _zone_shot("weidetal", Vector2(-380, 90), Vector2(-590, 200), "zone_weidetal.png")
	await _zone_shot("waeldchen", Vector2(-350, -330), Vector2(-420, -400), "zone_waeldchen.png")
	await _zone_shot("see", Vector2(392, 190), Vector2(500, 270), "zone_see_steg.png")
	await _zone_shot(
		"huegelkamm", Vector2(150, -480), Vector2(0, 0), "zone_huegelkamm_aussicht.png"
	)
	await _zone_shot("bachlauf", Vector2(340, -30), Vector2(318, 0), "zone_bachlauf_bruecke.png")
	await _zone_shot("scheune_alt", Vector2(-470, 455), Vector2(-500, 480), "zone_scheune_alt.png")
	await _zone_shot("turnierplatz", Vector2(120, 400), Vector2(130, 470), "zone_turnierplatz.png")
	await _zone_shot("hufingen", Vector2(425, 470), Vector2(560, 530), "zone_hufingen.png")
	# --- Wetterlagen (am See — Wasser + Pfützen im Bild) ---
	_teleport(Vector2(392, 190), Vector2(500, 270))
	await _wetter_shot("regen", 11.0, "wetter_regen.png")
	await _wetter_shot("gewitter", 15.0, "wetter_gewitter.png")
	_teleport(Vector2(0, 160), Vector2(0, 0))
	await _wetter_shot("nebel", 7.5, "wetter_nebel_hof.png")
	await _wetter_shot("regenbogen", 18.0, "wetter_regenbogen_abend.png")
	# --- Nacht: Glühwürmchen auf der Waldlichtung ---
	_region.wetter_override = ""
	_region.wetter.wetter_override = "wolken"
	_region.stunde_override = 22.4
	_teleport(Vector2(-390, -370), Vector2(-420, -400))
	await _settle(SETTLE)
	await _shot("nacht_gluehwuermchen_lichtung.png")
	# --- Wildtiere nah ---
	_region.wetter.wetter_override = "sonne"
	_region.stunde_override = 8.0
	_teleport(Vector2(-395, -378), Vector2(-420, -400))
	await _settle(SETTLE + 30)
	await _shot("tiere_rehe_lichtung.png")
	_teleport(Vector2(415, 245), Vector2(444, 246))
	await _settle(SETTLE)
	await _shot("tiere_enten_see.png")
	_teleport(Vector2(-540, 165), Vector2(-590, 200))
	await _settle(SETTLE)
	await _shot("tiere_wildpferde_weide.png")
	# --- Reiter im Gelände (Trab den Hügelkamm hinauf) ---
	_region.stunde_override = 16.5
	_teleport(Vector2(100, -300), Vector2(160, -510))
	_region.reiter.pferd.set_gangart(RanchPferd.GANG_TRAB)
	await _settle(SETTLE)
	await _shot("reiter_im_gelaende_huegel.png")
	print("Screenshots fertig -> %s" % OUT_DIR)
	_region.queue_free()
	await process_frame
	quit(0)


func _zone_shot(zone_id: String, von: Vector2, nach: Vector2, datei: String) -> void:
	_region.stunde_override = 11.0
	_teleport(von, nach)
	await _settle(SETTLE)
	print("zone=%s reiter=%s" % [zone_id, _region.reiter.position])
	await _shot(datei)


func _wetter_shot(typ: String, stunde: float, datei: String) -> void:
	_region.wetter.wetter_override = typ
	_region.stunde_override = stunde
	await _settle(SETTLE + 25)
	await _shot(datei)


func _teleport(von: Vector2, nach: Vector2) -> void:
	var blick := atan2(-(nach.x - von.x), -(nach.y - von.y))
	_region.reiter.springe_zu(RanchKarte.punkt(von.x, von.y), blick)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(datei: String) -> void:
	await process_frame
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [OUT_DIR, datei])
	print("shot: %s  draw_calls=%d" % [datei, int(calls)])

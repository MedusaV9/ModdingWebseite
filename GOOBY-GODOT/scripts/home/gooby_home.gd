class_name GoobyHome
extends Node3D
## Gooby im Raum (W2a HOUSE, Doc F §7): W1b-GoobyRig + Navmesh-Pfadverfolgung,
## Idle-Streifzüge über freie Standplätze (12 Zufalls-Samples), skriptbares
## walk_to() für Tür-Reisen und der Spidergooby-Decken-Gag (Doc F §6).
##
## FIX2-Movement (P0, zweiteilige Ursache):
## (1) Der frühere NavigationAgent3D verglich Distanzen in 3D — die gebackenen
##     Navmesh-Wegpunkte liegen aber ~0.58 m ÜBER Goobys Origin (Voxel-Höhe
##     cell_height 0.25), womit path_desired_distance (0.2) nie erreichbar
##     war: der Pfad-Index blieb bei 0 stehen und Gooby pendelte im
##     2-Frame-Ping-Pong um den ersten Wegpunkt.
## (2) Das gebackene Navmesh selbst ist degeneriert: Visual-Mesh-Parsing +
##     agent_radius 0.28 bei cell_size 0.25 erodieren das 6×5-m-Wohnzimmer
##     auf 8 Polygone, die nur die Raummitte abdecken (plus abgetrennte
##     Mini-Inseln) — Navmesh-Pfade enden mitten im Raum.
## Deshalb läuft Gooby jetzt über das GRID (die autoritative Möbel-Belegung,
## GridData.walkable): BFS über begehbare Zellen + String-Pulling für weiche
## Diagonalen, Wegpunkt-Fortschritt rein in XZ.

signal arrived

const SPEED := 1.15
const WANDER_WAIT_MIN := 4.0
const WANDER_WAIT_MAX := 9.0
const IDLE_SPOT_SAMPLES := 12
const CEILING_Y := 2.3
## XZ-Abstand, ab dem ein Wegpunkt als erreicht gilt (Pfad-Index rückt vor).
const WAYPOINT_DIST := 0.08
## XZ-Abstand, ab dem das Ziel als erreicht gilt.
const ARRIVE_DIST := 0.15
## Ohne Grid (Raum noch im Aufbau) regelmäßig neu anfragen statt dauerhaft
## blind geradeaus zu laufen.
const PATH_RETRY_S := 0.5
## Goobys Körperradius fürs String-Pulling: Diagonalen brauchen seitlich so
## viel freie Zelle, damit die Silhouette nicht in Möbeln hängt.
const KOERPER_RADIUS := 0.2
## Abtastschritt der Sichtlinien-Prüfung (deutlich unter CELL_SIZE 0.5).
const LOS_SCHRITT := 0.1
## W13/HUD-WIRES „Wo ist mein Gooby?": so lange gilt ein Idle-Akt / eine
## Absicht noch als frische „Tat" für die Bubble — danach erzählt Gooby
## nur noch den Fallback (nichts Erfundenes behaupten).
const TAT_FRISCH_MS := 120_000
## Wie weit Gooby nach der Suche auf den Spieler (die Kamera) zukommt.
const KOMM_HER_DISTANZ := 1.2
## Näher als das steht er schon beim Spieler — kein Extra-Lauf nötig.
const KOMM_HER_MIN := 1.5
## W13C: Idle-Akt-Rotation — beim Wander-Takt gönnt sich Gooby manchmal
## einen Idle-Variety-Clip an Ort und Stelle statt loszulaufen. Die zwei
## neuen Rig-Clips sind bewusst selten (zusammen ~10 % der Akte), der Rest
## bleibt der bekannte Streifzug. Auswahl ist PURE (Roll wird injiziert).
const IDLE_AKT_WANDER := "wander"
const IDLE_AKTE: Array[Dictionary] = [
	{"akt": IDLE_AKT_WANDER, "gewicht": 0.90},
	{"akt": "idle_ear_flick", "gewicht": 0.05},
	{"akt": "idle_stretch", "gewicht": 0.05},
]
## Wie lange ein Idle-Variety-Loop steht, bevor der Rig in move zurückkehrt.
const IDLE_CLIP_DAUER_S := 2.6

## Schlaf-Logik (pure) für die Tat-Bubble („Psst… er schläft").
const Sleep := preload("res://scripts/logic/sleep.gd")

var rig: GoobyRig
var grid: GridData
## REST-3 (Pflege): Tempo-Faktor 0..1 — müde/kranke Goobys watscheln
## sichtbar langsamer (PflegeRunner setzt das; 1.0 = normal).
var speed_mult := 1.0

var _wander_enabled := true
var _wander_timer := 0.0
var _walking := false
var _scripted := false
var _last_cell := Vector2i(-99, -99)
var _rng := RandomNumberGenerator.new()
var _target := Vector3.ZERO
var _path := PackedVector3Array()
var _path_index := 0
var _path_retry := 0.0


func _ready() -> void:
	rig = GoobyRig.new()
	add_child(rig)
	# FIX-F-Handoff: gespeicherte Char-Editor-Morphs auf den Spieler-Gooby anwenden.
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		rig.apply_saved_morphs(gs)
	add_child(_make_blob_shadow())
	_wander_timer = _rng.randf_range(1.0, 3.0)


## Blob-Shadow (W4-P3 POLISH-6, Doc A §7): weicher Schattenfleck statt
## teurer Echtzeit-Schatten — die Raum-Sonne rendert ohne Shadow-Map.
func _make_blob_shadow() -> MeshInstance3D:
	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.72)
	quad.orientation = PlaneMesh.FACE_Y
	blob.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _blob_textur()
	mat.no_depth_test = false
	blob.material_override = mat
	blob.position = Vector3(0.0, 0.02, 0.0)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return blob


## Radialer Schwarz-nach-transparent-Verlauf (kein Asset nötig).
static func _blob_textur() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.24, 0.18, 0.14, 0.4))
	gradient.set_color(1, Color(0.24, 0.18, 0.14, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex


func set_wander_enabled(enabled: bool) -> void:
	_wander_enabled = enabled
	if not enabled:
		_stop_walking()


## Läuft Gooby gerade (Wandern ODER Skript-Lauf)? Für die Tat-Bubble des
## „Wo ist mein Gooby?"-Chips (W13/HUD-WIRES).
func is_walking() -> bool:
	return _walking


## Läuft gerade ein SKRIPT-Lauf (walk_to — Tür-Reise/Interactable-Anlauf)?
## Freies Wandern zählt nicht. Der InteractablesHost sperrt Interactable-
## Taps, solange Skript-Lauf UND Wander-Stopp zusammenkommen (PT1-B2-
## Wiedereintritts-Sperre gegen Anlauf-Races — s. is_tap_blocked).
func is_scripted_walk() -> bool:
	return _scripted


## Ist das freie Wandern gerade erlaubt? Interactable-Sequenzen schalten es
## vor ihrem Anlauf ab — zusammen mit is_scripted_walk unterscheidet das
## kommandierte Anläufe von ambienten Läufen (Seelen-Gruß, Komm-her).
func is_wander_enabled() -> bool:
	return _wander_enabled


# ── „Wo ist mein Gooby?" (W13/HUD-WIRES, Doc F §4.2) ─────────────────────────


## PURE: jüngster Eintrag eines Cooldown-Buchs (id → now_ms + cooldown_ms,
## wie GoobyReactions._idle_cooldowns / SeeleRunner._intent_cooldowns).
## Liefert {"id": String, "alter_ms": int} — oder {} bei leerem Buch.
static func juengster_akt(cooldowns: Dictionary, cooldown_ms: int, now_ms: int) -> Dictionary:
	var best_id := ""
	var best_ablauf := 0
	for akt_id: Variant in cooldowns:
		var ablauf := int(cooldowns[akt_id])
		if best_id.is_empty() or ablauf > best_ablauf:
			best_ablauf = ablauf
			best_id = str(akt_id)
	if best_id.is_empty():
		return {}
	return {"id": best_id, "alter_ms": now_ms - (best_ablauf - cooldown_ms)}


## PURE: Text-Key der Tat-Bubble. `zustand` = {"schlaeft": bool,
## "unterwegs": bool, "akt": {id, alter_ms}|{}, "absicht": {id, alter_ms}|{}}.
## Priorität: Schlaf > frischeste Tat (Idle-Akt/Absicht innerhalb
## TAT_FRISCH_MS) > Laufweg > Fallback „hier".
static func tat_key(zustand: Dictionary) -> String:
	if bool(zustand.get("schlaeft", false)):
		return "home.suche.schlaeft"
	var frisch := _frischste_tat(zustand.get("akt", {}), zustand.get("absicht", {}))
	if not frisch.is_empty():
		return "home.suche.akt.%s" % str(frisch["id"])
	if bool(zustand.get("unterwegs", false)):
		return "home.suche.unterwegs"
	return "home.suche.hier"


## PURE: die frischere von zwei Taten — sofern sie ins Frischefenster passt.
static func _frischste_tat(akt: Dictionary, absicht: Dictionary) -> Dictionary:
	var best := {}
	for kandidat: Dictionary in [akt, absicht]:
		if kandidat.is_empty() or int(kandidat.get("alter_ms", TAT_FRISCH_MS + 1)) > TAT_FRISCH_MS:
			continue
		if int(kandidat.get("alter_ms", 0)) < 0:
			continue
		if best.is_empty() or int(kandidat["alter_ms"]) < int(best["alter_ms"]):
			best = kandidat
	return best


## PURE: Was tut der Such-Chip? "fokus" = Kamera zurückholen + Tat-Bubble,
## "bau" = nur Bubble (die Baukamera zeigt ohnehin den ganzen Raum),
## "still" = nichts (kein Gooby im Raum — prüft der Aufrufer, home_entry).
static func suche_reaktion(hat_gooby: bool, build_aktiv: bool) -> String:
	if not hat_gooby:
		return "still"
	return "bau" if build_aktiv else "fokus"


## Consumer des HUD-Chips `where_is_gooby_pressed` (vorher totes Signal):
## Kamera zurück zu Gooby (die öffentliche Rig-API `set_build_mode(false)`
## bricht einen freien Schwenk ab — follow_target IST Gooby, der Schwenk
## gleitet also direkt zu ihm), dazu eine knuffige Tat-Bubble; danach kommt
## Gooby ein Stück zum Spieler und lebt normal weiter. Der Raum (Parent,
## RoomBase) wird duck-typed angesprochen — kein harter Typ-Zyklus.
func wo_ist_gooby() -> void:
	var room := get_parent()
	if room == null or not room.has_method("say"):
		return
	var build_aktiv: bool = room.has_method("is_build_mode_active") and room.is_build_mode_active()
	match suche_reaktion(true, build_aktiv):
		"bau":
			room.say(I18nService.t("home.suche.baumodus"))
		"fokus":
			if room.has_method("camera_rig") and room.camera_rig() != null:
				room.camera_rig().set_build_mode(false)
			room.say(I18nService.t(_tat_text_key(room)))
			come_to_camera()
		_:
			pass


## Text-Key der Tat-Bubble: Kern-Entscheidung ist PURE (tat_key), hier wird
## nur der Ist-Zustand eingesammelt. Unbekannte Akt-Keys (z. B. neue
## Soul-Pack-Akte ohne Suchtext) fallen weich auf „hier" zurück.
func _tat_text_key(room: Node) -> String:
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var key := tat_key(_tat_zustand(room, now_ms))
	return key if I18nService.has_key(key) else "home.suche.hier"


## Ist-Zustand für die Tat-Bubble: Schlaf aus dem GameState, Laufweg von
## Gooby selbst, jüngster Idle-Akt/Absicht aus den Cooldown-Büchern des
## Seelen-Runners (duck-typed gelesen — fehlt der Runner, greift der
## Fallback).
func _tat_zustand(room: Node, now_ms: int) -> Dictionary:
	var zustand := {
		"schlaeft": false,
		"unterwegs": is_walking(),
		"akt": {},
		"absicht": {},
	}
	var gs: Object = room.game_state() if room.has_method("game_state") else null
	if gs != null and gs.has_method("get_value"):
		zustand["schlaeft"] = Sleep.is_sleeping(_dict_of(gs.get_value("gooby", {})))
	var runner := room.get_node_or_null("GoobyReactions")
	if runner == null:
		return zustand
	var idle: Variant = runner.get("_idle_cooldowns")
	if idle is Dictionary:
		zustand["akt"] = juengster_akt(idle, GoobyReactions.IDLE_ACT_COOLDOWN_MS, now_ms)
	var seele := runner.get_node_or_null("SeeleRunner")
	if seele != null:
		var intents: Variant = seele.get("_intent_cooldowns")
		if intents is Dictionary:
			zustand["absicht"] = juengster_akt(intents, SoulIntent.COOLDOWN_MS, now_ms)
	return zustand


static func _dict_of(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


## Nach der Gooby-Suche: ein Stück auf den Spieler (die Kamera) zukommen und
## danach normal weiterleben (Wandern wieder an). Spiegel der Gruß-
## Annäherung des Seelen-Runners — bewusst OHNE Laune-Gate: wer aktiv nach
## ihm sucht, zu dem kommt Gooby immer.
func come_to_camera(distanz := KOMM_HER_DISTANZ) -> void:
	set_wander_enabled(true)
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var richtung := camera.global_position - global_position
	richtung.y = 0.0
	if richtung.length() < KOMM_HER_MIN:
		return
	walk_to(global_position + richtung.normalized() * distanz, 4.0)


## Clip-Proxy auf den W1b-Rig (DoorTransition ruft Clips per Duck-Typing).
func play_clip(clip: String) -> void:
	rig.play_clip(clip)


## Skriptbarer Lauf (Tür-Reise): läuft zur Position, feuert `arrived`.
## Awaitbar; bricht nach `timeout_s` ab (Navmesh-Lücken nie deadlocken).
func walk_to(world_pos: Vector3, timeout_s := 6.0) -> void:
	_scripted = true
	_start_walking(world_pos)
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while _walking and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_stop_walking()
	_scripted = false
	arrived.emit()


## Laufenden Skript-Lauf sofort abbrechen (W4-P3: responsiver Tür-Skip —
## das awaitende walk_to kehrt im nächsten Frame zurück).
func cancel_walk() -> void:
	_stop_walking()


## Gooby aufs Bett snappen (Schlaf-Pose): Wander/Walk stoppen, Position auf
## Möbel-Origin + leichter Y-Lift, Rig-Yaw entlang der Bettlänge.
## Sleep-Clip ist eine Liegepose — Ausrichtung `furniture.rotation.y + PI/2`
## (Kopf/Fuß entlang der langen Bettkante; unsicher bei Sonder-Meshes).
func lie_on_bed(furniture: Node3D) -> void:
	cancel_walk()
	set_wander_enabled(false)
	if furniture == null or not is_instance_valid(furniture):
		return
	const BED_Y_LIFT := 0.15
	global_position = furniture.global_position + Vector3(0.0, BED_Y_LIFT, 0.0)
	if rig != null:
		rig.rotation.y = furniture.global_rotation.y + PI / 2.0


## Aktuelle Grid-Zelle (für Blockade-Checks der Türen).
func current_cell() -> Vector2i:
	return GridData.cell_of(global_position)


## BODEN-IST-LAVA-Gag (Doc F §6): Panik, Sprung an die Decke, Hold,
## Plumps zurück. Awaitbar; Bubble-Texte macht RoomBase.
## Reduced Motion (W4-P3 POLISH-16): Instant-Pfad ohne Bounce-Tweens.
func spidergooby_gag(hold_s := 2.2) -> void:
	set_wander_enabled(false)
	var floor_pos := global_position
	rig.set_emotion("scared")
	rig.play_clip("hop")
	if _reduced_motion():
		global_position.y = CEILING_Y
		rig.rotation.z = PI
		rig.set_emotion("ecstatic")
		# W13C (Request CLIPS): oben echt festkrallen statt hop-Nachlauf —
		# der Clip ist „hängend" gebaut, der Z-Flip dreht ihn an die Decke.
		rig.play_clip(GoobyRig.CLIP_CEILING_CLING)
		await get_tree().create_timer(minf(hold_s, 0.8)).timeout
		global_position.y = floor_pos.y
		rig.rotation.z = 0.0
	else:
		var up := create_tween()
		up.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		up.tween_property(self, "global_position:y", CEILING_Y, 0.45)
		up.parallel().tween_property(rig, "rotation:z", PI, 0.45)
		await up.finished
		rig.set_emotion("ecstatic")
		# W13C (Request CLIPS): ceiling_cling-Loop während des Decken-Holds.
		rig.play_clip(GoobyRig.CLIP_CEILING_CLING)
		await get_tree().create_timer(hold_s).timeout
		var down := create_tween()
		down.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		down.tween_property(self, "global_position:y", floor_pos.y, 0.5)
		down.parallel().tween_property(rig, "rotation:z", 0.0, 0.4)
		await down.finished
	rig.set_emotion("happy")
	rig.play_clip("idle")
	set_wander_enabled(true)


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()


func _physics_process(delta: float) -> void:
	if _walking:
		_step_walk(delta)
		return
	if not _wander_enabled or _scripted or grid == null:
		return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = _rng.randf_range(WANDER_WAIT_MIN, WANDER_WAIT_MAX)
		var akt := waehle_idle_akt(_rng.randf())
		if akt != IDLE_AKT_WANDER:
			_spiele_idle_clip(akt)
			return
		var spot := _pick_idle_spot()
		if spot != Vector3.INF:
			_start_walking(spot)


## W13C PURE: gewichteter Idle-Akt für einen Roll 0..1 — "wander" (Streifzug
## wie bisher) oder einer der Idle-Variety-Clips (je ~5 %).
static func waehle_idle_akt(roll: float) -> String:
	var total := 0.0
	for eintrag: Dictionary in IDLE_AKTE:
		total += float(eintrag["gewicht"])
	var r := clampf(roll, 0.0, 0.999999) * total
	var summe := 0.0
	for eintrag: Dictionary in IDLE_AKTE:
		summe += float(eintrag["gewicht"])
		if r < summe:
			return str(eintrag["akt"])
	return IDLE_AKT_WANDER


## W13C: Idle-Variety-Clip an Ort und Stelle — der Rig kehrt über
## play_clip_for selbst in den move-State zurück, das Wandern pausiert nur
## über den normalen _wander_timer.
func _spiele_idle_clip(clip: String) -> void:
	if rig == null:
		return
	rig.play_clip_for(clip, IDLE_CLIP_DAUER_S)


## Freie-Standplatz-Suche (Doc F §7): 12 Samples aus freien Grid-Zellen,
## erreichbar (BFS) und nicht der letzte Spot.
func _pick_idle_spot() -> Vector3:
	var free := grid.free_cells()
	if free.is_empty():
		return Vector3.INF
	var from := current_cell()
	for _i in IDLE_SPOT_SAMPLES:
		var cell: Vector2i = free[_rng.randi_range(0, free.size() - 1)]
		if cell == _last_cell or grid.blocked.has(cell):
			continue
		if not grid.is_reachable(from, cell):
			continue
		_last_cell = cell
		return GridData.world_center(cell, Vector2i.ONE, 0)
	return Vector3.INF


func _start_walking(world_pos: Vector3) -> void:
	_target = world_pos
	_compute_path()
	_walking = true
	rig.set_locomotion(1.0)


func _stop_walking() -> void:
	_walking = false
	rig.set_locomotion(0.0)


## Pfad übers Grid planen (statt Navmesh — s. Kopf): BFS von der eigenen
## Zelle zur Zielzelle, dann String-Pulling. Kommt die BFS nicht bis zum
## Ziel (Zelle belegt/abgeschnitten), endet der Pfad an der nächsten
## erreichbaren Zelle — _step_walk stoppt dort, statt Möbel zu pflügen.
## Leerer Pfad = noch kein Grid; _step_walk fragt dann per PATH_RETRY_S-Takt
## nach und läuft solange gerade aufs Ziel zu.
func _compute_path() -> void:
	_path_index = 0
	_path_retry = PATH_RETRY_S
	_path = PackedVector3Array()
	if grid == null:
		return
	var start_cell := _nearest_walkable(GridData.cell_of(global_position))
	var ziel_cell := GridData.cell_of(_target)
	var cells := _grid_path(start_cell, ziel_cell)
	if cells.is_empty():
		return
	var pts := PackedVector3Array()
	pts.append(_xz(global_position))
	for cell: Vector2i in cells:
		pts.append(GridData.world_center(cell, Vector2i.ONE, 0))
	# Zielzelle erreicht → das exakte Ziel innerhalb der Zelle anfahren.
	if cells[cells.size() - 1] == ziel_cell:
		pts.append(_xz(_target))
	_path = _string_pulling(pts)


## Nächste begehbare Zelle (Ring-Suche) — falls Gooby z. B. per Baumodus
## knapp in eine Möbel-Zelle geschoben wurde.
func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if grid.walkable(cell):
		return cell
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var kandidat := cell + Vector2i(dx, dy)
				if grid.walkable(kandidat):
					return kandidat
	return cell


## BFS über begehbare Zellen (4er-Nachbarschaft, wie GridData.is_reachable).
## Liefert die Zellfolge von `from_cell` bis `to_cell` — oder, wenn das Ziel
## nicht erreichbar ist, bis zur erreichbaren Zelle mit dem kleinsten
## Restabstand. Leer nur, wenn schon die Startzelle unbegehbar ist.
func _grid_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if not grid.walkable(from_cell):
		return []
	var parent := {from_cell: from_cell}
	var frontier: Array[Vector2i] = [from_cell]
	var lese := 0
	var best := from_cell
	var best_d := (to_cell - from_cell).length_squared()
	var found := from_cell == to_cell
	while lese < frontier.size() and not found:
		var cell: Vector2i = frontier[lese]
		lese += 1
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if parent.has(next) or not grid.walkable(next):
				continue
			parent[next] = cell
			var d := (to_cell - next).length_squared()
			if d < best_d:
				best_d = d
				best = next
			if next == to_cell:
				found = true
				break
			frontier.append(next)
	var ende := to_cell if found else best
	var out: Array[Vector2i] = []
	var cur := ende
	while cur != from_cell:
		out.push_front(cur)
		cur = parent[cur]
	out.push_front(from_cell)
	return out


## String-Pulling: Zwischenpunkte überspringen, solange die Direktlinie
## (inkl. seitlichem KOERPER_RADIUS) durch begehbare Zellen führt — macht
## aus BFS-Treppen weiche Diagonalen. Der direkte Folgepunkt wird immer
## akzeptiert (garantierter Fortschritt).
func _string_pulling(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.is_empty():
		return out
	out.append(pts[0])
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _segment_frei(pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out


func _segment_frei(a: Vector3, b: Vector3) -> bool:
	var d := _xz(b - a)
	var laenge := d.length()
	if laenge < 0.001:
		return true
	var dir := d / laenge
	var seite := Vector3(-dir.z, 0.0, dir.x) * KOERPER_RADIUS
	var steps := int(ceilf(laenge / LOS_SCHRITT))
	for s in steps + 1:
		var p: Vector3 = a + dir * (laenge * float(s) / float(steps))
		if not grid.walkable(GridData.cell_of(p)):
			return false
		if not grid.walkable(GridData.cell_of(p + seite)):
			return false
		if not grid.walkable(GridData.cell_of(p - seite)):
			return false
	return true


static func _xz(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _step_walk(delta: float) -> void:
	var to_target := _xz(_target - global_position)
	if to_target.length() <= ARRIVE_DIST:
		_stop_walking()
		return
	if _path.size() < 2:
		_path_retry -= delta
		if _path_retry <= 0.0:
			_compute_path()
	# Erreichte Wegpunkte rein in XZ abhaken (nie in 3D vergleichen — genau
	# der 3D-Vergleich hat den alten Agent stallen lassen, s. Kopf).
	while (
		_path_index < _path.size()
		and _xz(_path[_path_index] - global_position).length() <= WAYPOINT_DIST
	):
		_path_index += 1
	var to_next := to_target
	if _path_index < _path.size():
		to_next = _xz(_path[_path_index] - global_position)
	elif _path.size() >= 2:
		# Pfadende erreicht, Ziel aber weiter weg (Zielzelle belegt oder
		# abgeschnitten): hier stehen bleiben statt Möbel zu pflügen.
		_stop_walking()
		return
	var step := to_next.normalized() * SPEED * clampf(speed_mult, 0.25, 1.0) * delta
	if step.length() > to_next.length():
		step = to_next
	global_position += step
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(to_next.x, to_next.z), 10.0 * delta)
	rig.set_locomotion(1.0)

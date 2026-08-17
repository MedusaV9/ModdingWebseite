extends SceneTree
## Asset-Ausrichtungs-Audit (W18, User-Feedback „alle Assets richtig rotiert
## und richtig rum") — KEIN Test, ein Dev-Werkzeug wie perf_probe.gd.
##
## Alle Platzierungen entstehen in diesem Projekt PROZEDURAL zur Laufzeit
## (die .tscn-Dateien enthalten keine Transforms) — deshalb mountet dieses
## Skript jede Welt-Szene headless (Muster scripts/dev/perf_probe.gd) und
## prüft dann jeden sichtbaren Node3D bzw. jedes Modell-Wurzel-AABB auf:
##   1. Spiegelung / negative Scale (Basis-Determinante < 0) + NaN/degeneriert
##   2. Kipp-Winkel: Up-Vektor der Welt-Basis vs. +Y für Kategorien, die
##      aufrecht stehen müssen (Bäume, Häuser, Möbel, NPCs, Fahrzeuge, …)
##   3. „Auf dem Kopf": Kipp-Winkel > 135°
##   4. Krumme Yaw-Winkel bei Gebäuden (Abweichung vom 15°-Raster)
##   5. Boden-Kontakt: Modell-Unterkante vs. beste Stand-Referenz
##      (Terrain-Orakel RanchGelaende.hoehe bzw. flache Stütz-AABBs darunter)
## Konvention (Godot): Up = +Y, Front = -Z; WeltStreu rotiert NUR um Y.
## Absichtlich Gekipptes (Rutschen, Rampen, Felsen, Rotoren, liegende Deko)
## steht auf der Ausnahmeliste. MultiMesh-Instanzen sind headless nicht
## rücklesbar (Dummy-Renderer) und werden gezählt, aber nicht geprüft —
## deren Transform-Quelle WeltStreu ist per test_world_streu.gd abgedeckt.
##
## Aufruf (Repo-Wurzel; max. EINE Godot-Instanz und kein `godot --import`
## parallel, siehe AGENTS.md):
##   bash tools/ci/run_godot_isolated.sh godot --headless --audio-driver Dummy \
##     --path GOOBY-GODOT --script res://tools/audit/orientation_audit.gd
## Env-Schalter:
##   GOOBY_AUDIT_OUT     Ziel-Markdown (Default /tmp/gooby-godot/artifacts/
##                       orientation_findings.md). Daneben entsteht IMMER
##                       ein maschinenlesbares <gleicher Name>.json
##                       ({befunde, statistik}).
##   GOOBY_AUDIT_SCENES  Komma-Liste von Szenen-Id-SUBSTRINGS (z. B.
##                       "ranch,city" oder "home/kueche"); leer/ungesetzt =
##                       alle Szenen der SZENEN-Liste unten.
## Ausgabe: Befunde in drei Graden (SICHER / WAHRSCHEINLICH / PRÜFEN), je
## mit Ist-Transform, Erwartung und Fix-Vorschlag (Fix-Ort ist das
## Builder-Skript der Szene, nie die .tscn). Exit-Code ist immer 0 —
## Report-Werkzeug, kein Gate; Auswertung über die Befundliste.

const OUT_STANDARD := "/tmp/gooby-godot/artifacts/orientation_findings.md"
const SETTLE_FRAMES := 30
const READY_TIMEOUT_MS := 20000

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Alle Welt-Szenen mit 3D-Platzierung. `terrain` = RanchGelaende-Höhenfeld
## als Boden-Orakel (hügelig — flache Stütz-AABBs reichen dort nicht).
const SZENEN: Array[Dictionary] = [
	{"id": "home/wohnzimmer", "pfad": "res://scenes/home/wohnzimmer.tscn"},
	{"id": "home/kueche", "pfad": "res://scenes/home/kueche.tscn"},
	{"id": "home/bad", "pfad": "res://scenes/home/bad.tscn"},
	{"id": "home/schlafzimmer", "pfad": "res://scenes/home/schlafzimmer.tscn"},
	{"id": "home/garten", "pfad": "res://scenes/home/garten.tscn"},
	{"id": "city", "pfad": "res://scenes/city/city_scene.tscn"},
	{"id": "ort/autohaus", "pfad": "res://scenes/city/orte/autohaus.tscn"},
	{"id": "ort/baumarkt", "pfad": "res://scenes/city/orte/baumarkt.tscn"},
	{"id": "ort/flughafen", "pfad": "res://scenes/city/orte/flughafen.tscn"},
	{"id": "ort/goobyman", "pfad": "res://scenes/city/orte/goobyman.tscn"},
	{"id": "ort/goobytheke", "pfad": "res://scenes/city/orte/goobytheke.tscn"},
	{"id": "ort/gouhbus", "pfad": "res://scenes/city/orte/gouhbus.tscn"},
	{"id": "ort/post", "pfad": "res://scenes/city/orte/post.tscn"},
	{"id": "ort/pow", "pfad": "res://scenes/city/orte/pow.tscn"},
	{"id": "ort/raumstation", "pfad": "res://scenes/city/orte/raumstation.tscn"},
	{"id": "ort/rehwei", "pfad": "res://scenes/city/orte/rehwei.tscn"},
	{"id": "ort/tierarzt", "pfad": "res://scenes/city/orte/tierarzt.tscn"},
	{"id": "ort/wochenmarkt", "pfad": "res://scenes/city/orte/wochenmarkt.tscn"},
	{"id": "urlaub/strand", "pfad": "res://scenes/city/urlaub/urlaub_strand.tscn"},
	{"id": "urlaub/berge", "pfad": "res://scenes/city/urlaub/urlaub_berge.tscn"},
	{"id": "urlaub/stadt", "pfad": "res://scenes/city/urlaub/urlaub_stadt.tscn"},
	{"id": "park/funkelpark", "pfad": "res://scenes/park/funkelpark.tscn"},
	{"id": "ranch/hof", "pfad": "res://scenes/ranch/ranch_hof.tscn"},
	{"id": "ranch/fahrt", "pfad": "res://scenes/ranch/ranch_fahrt.tscn"},
	{"id": "ranch/bau_hof", "pfad": "res://scenes/ranch/dorf/ranch_bau_hof.tscn"},
	{"id": "ranch/hufingen", "pfad": "res://scenes/ranch/dorf/hufingen.tscn", "terrain": true},
	{"id": "ranch/region", "pfad": "res://scenes/ranch/welt/ranch_region.tscn", "terrain": true},
]

## Kipp-Schwellen in Grad (statisch aufrecht).
const KIPP_PRUEFEN := 7.0
const KIPP_WAHRSCHEINLICH := 25.0
const KIPP_SICHER := 135.0
## Kipp-Schwelle dynamischer Objekte (nur grobe Fälle melden).
const KIPP_DYNAMISCH := 45.0
## Yaw-Raster für Gebäude + Toleranz in Grad.
const YAW_RASTER := 15.0
const YAW_TOLERANZ := 2.0
## Boden-Kontakt: Schwebe-/Einsink-Schwellen (m bzw. relativ zur Höhe).
const SCHWEBE_PRUEFEN := 0.15
const SCHWEBE_WAHRSCHEINLICH := 0.4
const SCHWEBE_SICHER := 1.0
const SCHWEBE_DYNAMISCH := 0.6
const EINSINK_PRUEFEN := 0.25
const EINSINK_WAHRSCHEINLICH := 0.45
const EINSINK_SICHER := 0.7
## Mindesthöhe (m) für den Boden-Kontakt-Check (Kleinkram steht auf Möbeln).
const MIN_HOEHE_BODENCHECK := 0.4
## Stütz-AABB-Filter: Höhenfeld-artige Riesen-Meshes aussortieren.
const STUETZE_MAX_HOEHE := 6.0
const STUETZE_MAX_SPANNE := 120.0
## „Plattenartige" Stützen (dünne Böden/Platten) dürfen Einsinken melden.
const PLATTE_MAX_DICKE := 0.6
## Möbel-artige (kleine) dicke Stützen: Unterkante darin = „innen" (Regal).
const MOEBEL_MAX_SPANNE := 4.0

## Kategorien per Namens-Heuristik (Node-Name + GLB-Dateiname, lowercase;
## Endung "_" = exakter Wort-Treffer statt Substring, s. _matcht()).
## aufrecht: muss mit Up = +Y stehen (Kipp-Check + Boden-Kontakt).
static var aufrecht: PackedStringArray = (
	(
		"baum tree tanne pine birke birch palme palm busch hecke hedge blume flower farn fern_"
		+ " pilz mushroom kaktus cactus crop pflanze plant haus house building gebaeude huette hut"
		+ " shed scheune barn stall turm tower kirche church windrad windmill muehle laden shop"
		+ " kiosk theke counter laterne lantern streetlight fackel torch zaun fence gate schild"
		+ " sign wegweiser bank_ parkbank sitzbank bench stuhl chair hocker stool sofa couch sessel"
		+ " tisch table desk bett bed schrank cabinet cupboard regal shelf bookcase kommode dresser"
		+ " ofen oven herd_ stove kuehlschrank fridge waschbecken sink toilet badewanne bathtub"
		+ " dusche shower brunnen fountain statue denkmal fahnenmast flagpole briefkasten mailbox"
		+ " hydrant ampel trafficlight npc gooby figur pferd horse pony kuh cow schaf sheep huhn"
		+ " chicken hund dog katze cat_ reh_ deer bear auto car_ taxi van bus_ truck traktor tractor"
		+ " vogelscheuche werkbank werkstatt gewaechshaus trog eingang ticketschalter marktstand"
		+ " stand_ kasse boot boat truhe chest"
	)
	. split(" ")
)
## ausnahmen: absichtlich gekippt/frei rotiert — kein Aufrecht-/Boden-Check.
static var ausnahmen: PackedStringArray = (
	(
		"rutsche slide rampe ramp liegend liegt umgekippt gefallen fallen kipp schraeg stein rock"
		+ " fels boulder wolke cloud girlande garland ast_ branch wurzel root ball_ kugel reifen"
		+ " tire propeller rotor fluegel blade rad_ wheel riesenrad ferris gondel karussell"
		+ " teller coaster strecke stuetzen cart schaukel swing wippe seesaw kran crane leiter"
		+ " ladder haengematte hammock flagge flag_ fahne banner segel sail schirm umbrella surf"
		+ " ski sled schlitten paddel ruder pfeil arrow dach roof balken beam muschel shell seil"
		+ " rope kette chain wasserfall funkel irrlicht partikel particle fx nebel fog himmel"
		+ " sky sonne sun_ mond moon stern star sturm storm tuer door deckel lid_ klappe haube"
		+ " luke hatch ente_ duck schwan swan hoehle alt_ ruine verfallen liege"
	)
	. split(" ")
)
## dynamisch: bewegt sich im Spiel (Verkehr, NPCs, Tiere) — grobe Schwellen.
static var dynamisch: PackedStringArray = (
	(
		"verkehr fussgaenger besucher npc gooby pferd horse pony reiter auto car_ taxi van vogel"
		+ " bird biene bee schmetterling butterfly boot boat fisch fish wildtier scooter kart"
		+ " huhn chicken hund dog katze cat_"
	)
	. split(" ")
)
## haengend: hängt an Decke/Wand — Aufrecht-Check ja, Boden-Kontakt nein.
static var haengend: PackedStringArray = (
	(
		"decke ceiling haenge pendel kronleuchter chandelier wand wall bild poster regenrinne"
		+ " fenster window tuer door glas tafel"
	)
	. split(" ")
)
## gebaeude_raster: Yaw sollte auf einem 15°-Raster liegen (Stadt = Grid).
static var gebaeude_raster: PackedStringArray = (
	(
		"haus house building gebaeude scheune barn stall shed werkstatt gewaechshaus kirche"
		+ " church turm tower laden shop"
	)
	. split(" ")
)
## moebel_traeger: Descendants davon stehen AUF Möbeln — kein Boden-Check.
static var moebel_traeger: PackedStringArray = (
	(
		"tisch table desk regal shelf schrank theke counter kommode werkbank bett bed sideboard"
		+ " ablage bord"
	)
	. split(" ")
)
## fahrzeug: steht in der Stadt per Konvention auf CityCarFeel.ROAD_Y.
static var fahrzeug: PackedStringArray = (
	"auto car_ taxi van_ suv sedan hatchback truck delivery police bus_".split(" ")
)

var _befunde: Array[Dictionary] = []
var _statistik: Array[Dictionary] = []
var _seq := 0
var _aktive_szene_id := ""


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	root.theme = ThemeService.theme()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	var filter := OS.get_environment("GOOBY_AUDIT_SCENES")
	for eintrag in SZENEN:
		if not _szene_gewollt(str(eintrag["id"]), filter):
			continue
		await _audit_szene(eintrag)
	var out_pfad := OS.get_environment("GOOBY_AUDIT_OUT")
	if out_pfad.is_empty():
		out_pfad = OUT_STANDARD
	_schreibe_report(out_pfad)
	quit(0)


func _szene_gewollt(id: String, filter: String) -> bool:
	if filter.strip_edges().is_empty():
		return true
	for teil in filter.split(","):
		if not teil.strip_edges().is_empty() and id.contains(teil.strip_edges()):
			return true
	return false


## ------------------------------------------------------------ Szenen-Mount


func _audit_szene(eintrag: Dictionary) -> void:
	var id := str(eintrag["id"])
	var pfad := str(eintrag["pfad"])
	_aktive_szene_id = id
	print("== Audit %s (%s)" % [id, pfad])
	var packed: PackedScene = load(pfad)
	if packed == null:
		_statistik.append({"id": id, "fehler": "Szene lädt nicht"})
		return
	var gs := _frisches_gs()
	var szene: Node = packed.instantiate()
	if "game_state_override" in szene:
		szene.set("game_state_override", gs)
	if "stunde_override" in szene:
		szene.set("stunde_override", 12.0)
	if "wetter_override" in szene:
		szene.set("wetter_override", "sonne")
	root.add_child(szene)
	await _warte_auf_aufbau(szene)
	var stats := _pruefe_baum(szene, eintrag.get("terrain", false) == true)
	stats["id"] = id
	_statistik.append(stats)
	print(
		(
			"   Nodes=%d Meshes=%d MultiMesh=%d(Instanzen=%d) Wurzeln=%d Befunde=%d"
			% [
				stats["nodes"],
				stats["meshes"],
				stats["multimesh"],
				stats["mm_instanzen"],
				stats["wurzeln"],
				stats["befunde"],
			]
		)
	)
	await _teardown(szene, gs)


func _frisches_gs() -> Node:
	_seq += 1
	var dir := "user://orientation_audit/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	CityState.register_slice()
	HomeState.register_slice()
	RanchState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", 30)
	gs.set_value("economy.coins", 99999)
	return gs


func _warte_auf_aufbau(szene: Node) -> void:
	var bereit := [false]
	if szene.has_signal("ready_for_reveal"):
		szene.connect("ready_for_reveal", func() -> void: bereit[0] = true)
	else:
		bereit[0] = true
	var deadline := Time.get_ticks_msec() + READY_TIMEOUT_MS
	while not bereit[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	for _i in SETTLE_FRAMES:
		await process_frame


func _teardown(szene: Node, gs: Node) -> void:
	PanelStack.clear()
	szene.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	CityState.reset_for_tests()
	RanchState.reset_for_tests()
	HomeState.reset_for_tests()


## ------------------------------------------------------------ Baum-Prüfung


## Sammelt Meshes/Wurzeln in einem Durchlauf und prüft dann jede Kategorie-
## Wurzel. `terrain` = RanchGelaende.hoehe als zusätzliches Boden-Orakel.
func _pruefe_baum(szene: Node, terrain: bool) -> Dictionary:
	var meshes: Array[Dictionary] = []
	var wurzeln: Array[Dictionary] = []
	var stats := {"nodes": 0, "meshes": 0, "multimesh": 0, "mm_instanzen": 0, "befunde": 0}
	var vorher := _befunde.size()
	_sammle(szene, szene, "", false, false, false, meshes, wurzeln, stats)
	for eintrag in wurzeln:
		_pruefe_wurzel(szene, eintrag, meshes, terrain)
	stats["wurzeln"] = wurzeln.size()
	stats["befunde"] = _befunde.size() - vorher
	return stats


## DFS: `ahnen_label` ist die VOLLE Label-Kette der Vorfahren (Ausnahmen wie
## „Karussell" oder „ruine" vererben sich auf alle Kinder); Wurzel = erster
## Treffer einer Stand-Kategorie im Pfad (verschachtelte Treffer zählen
## nicht doppelt). `in_glb` = Node liegt INNERHALB eines instanzierten GLB —
## seine Pose ist im Asset authored, nicht von der Szene gesetzt (Befunde
## werden heruntergestuft, Wurzel-Kandidat ist nur die GLB-Wurzel selbst).
func _sammle(
	szene: Node,
	node: Node,
	ahnen_label: String,
	in_wurzel: bool,
	auf_moebel: bool,
	in_glb: bool,
	meshes: Array[Dictionary],
	wurzeln: Array[Dictionary],
	stats: Dictionary
) -> void:
	var kette := ahnen_label
	var ist_wurzel := false
	if node is Node3D:
		stats["nodes"] = int(stats["nodes"]) + 1
		var label := _label(node)
		kette = (ahnen_label + " " + label) if not ahnen_label.is_empty() else label
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				stats["meshes"] = int(stats["meshes"]) + 1
				meshes.append(
					{"node": mi, "aabb": mi.global_transform * mi.mesh.get_aabb(), "label": label}
				)
		if node is MultiMeshInstance3D:
			var mmi := node as MultiMeshInstance3D
			stats["multimesh"] = int(stats["multimesh"]) + 1
			if mmi.multimesh != null:
				stats["mm_instanzen"] = int(stats["mm_instanzen"]) + mmi.multimesh.instance_count
		var kandidat := not in_wurzel and not in_glb
		if kandidat and not _matcht(kette, ausnahmen) and _matcht(label, aufrecht):
			ist_wurzel = true
			wurzeln.append({"node": node, "label": kette, "auf_moebel": auf_moebel})
		_pruefe_basis(szene, node as Node3D, label, kette, in_glb, ist_wurzel)
	var moebel := auf_moebel or (node is Node3D and _matcht(kette, moebel_traeger))
	var glb := in_glb or node.scene_file_path.to_lower().ends_with(".glb")
	for kind in node.get_children():
		_sammle(szene, kind, kette, in_wurzel or ist_wurzel, moebel, glb, meshes, wurzeln, stats)


## Label = Node-Name + GLB-/Szenen-Dateiname, lowercase, plus normalisierte
## Token-Form (" wort "-Ränder) für exakte Wort-Treffer.
func _label(node: Node) -> String:
	var roh := str(node.name).to_lower()
	if node.scene_file_path != "":
		roh += " " + node.scene_file_path.get_file().get_basename().to_lower()
	var tokens := ""
	for i in roh.length():
		var c := roh[i]
		tokens += c if c >= "a" and c <= "z" else " "
	return roh + " | " + tokens + " |"


## Keyword-Match: Endung "_" = exakter Wort-Treffer (" wort "), sonst Substring.
func _matcht(label: String, liste: PackedStringArray) -> bool:
	for wort in liste:
		if wort.ends_with("_"):
			if label.contains(" %s " % wort.trim_suffix("_")):
				return true
		elif label.contains(wort):
			return true
	return false


## ---------------------------------------------------- Checks pro Node3D


## Basis-Checks für JEDEN Node3D: NaN/degeneriert, Spiegelung, Kipp-Winkel.
## Der Kipp-Check greift nur, wenn das EIGENE Label (Name + Dateiname) eine
## Aufrecht-Kategorie trifft — anonyme Bauteile (@MeshInstance3D@…) erben
## die Kategorie NICHT (Brillen-Tori, gedrehte Accessoire-Primitive von
## Builder-Skripten sind authored, keine Platzierungsfehler). `in_glb`
## stuft Kipp-/Spiegel-Befunde auf PRÜFEN herunter — die Pose ist dann im
## GLB authored (z. B. offene Waschmaschinen-Klappe). Der Yaw-Raster-Check
## läuft nur für WURZEL-Nodes der Stadt (Grid) — Dorf/Ranch organisch.
func _pruefe_basis(
	szene: Node,
	node: Node3D,
	eigen_label: String,
	voll_label: String,
	in_glb: bool,
	ist_wurzel: bool
) -> void:
	if not node.is_inside_tree() or not node.visible:
		return
	if (
		node is Camera3D
		or node is Light3D
		or node is AudioStreamPlayer3D
		or node is RayCast3D
		or node is GPUParticles3D
		or node is CPUParticles3D
		or node is BoneAttachment3D
	):  # Folgt der Skeleton-Bone-Pose (-90° X ist Bone-Konvention).
		return
	var basis := node.global_transform.basis
	if not _basis_endlich(basis):
		_melde(
			szene,
			node,
			"NaN-Transform",
			"SICHER",
			"Basis enthält NaN/Inf",
			"gültige Basis",
			"Transform-Zuweisung im Builder prüfen (Division durch 0?)"
		)
		return
	var det := basis.determinant()
	if absf(det) < 1e-8:
		_melde(
			szene,
			node,
			"Degenerierte Scale",
			"SICHER",
			"det(Basis) ≈ 0 (%s)" % _fmt_basis(basis),
			"Scale > 0 auf allen Achsen",
			"Scale-Zuweisung im Builder prüfen"
		)
		return
	if det < 0.0:
		_melde(
			szene,
			node,
			"Spiegelung / negative Scale",
			"PRÜFEN" if in_glb else "SICHER",
			(
				"det(Basis) = %.3f, scale = %s%s"
				% [det, _fmt_v(basis.get_scale()), _glb_hinweis(in_glb)]
			),
			"det > 0 (keine Achsen-Spiegelung)",
			"Negative Scale-Komponente entfernen; Spiegel-Optik ggf. per Rotation lösen"
		)
	if _matcht(voll_label, ausnahmen) or not _matcht(eigen_label, aufrecht):
		return
	var kipp := _kipp_grad(basis)
	var euler := basis.get_euler()
	var grad_v := Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))
	var rot_txt := "rot = %s°, Kipp = %.1f°" % [_fmt_v(grad_v), kipp]
	var fix := "Rotation auf (0°, %.1f°, 0°) setzen" % grad_v.y
	if kipp > KIPP_SICHER:
		_melde(
			szene,
			node,
			"Auf dem Kopf / extrem gekippt",
			"PRÜFEN" if in_glb else "SICHER",
			rot_txt + _glb_hinweis(in_glb),
			"Up-Vektor = +Y (aufrechte Kategorie)",
			fix
		)
	elif _matcht(voll_label, dynamisch):
		if kipp > KIPP_DYNAMISCH:
			_melde(
				szene,
				node,
				"Stark gekippt (dynamisches Objekt)",
				"PRÜFEN" if in_glb else "WAHRSCHEINLICH",
				rot_txt + _glb_hinweis(in_glb),
				"annähernd aufrecht (bewegtes Objekt)",
				fix
			)
	elif kipp > KIPP_WAHRSCHEINLICH:
		var zusatz := ""
		if absf(kipp - 90.0) < 2.0 or absf(kipp - 180.0) < 2.0:
			zusatz = " — exakt ±90°/180°: riecht nach Achsen-/Import-Fehler"
		_melde(
			szene,
			node,
			"Stark gekippt",
			"PRÜFEN" if in_glb else "WAHRSCHEINLICH",
			rot_txt + zusatz + _glb_hinweis(in_glb),
			"Up-Vektor = +Y (aufrechte Kategorie)",
			fix
		)
	elif kipp > KIPP_PRUEFEN and not in_glb:
		_melde(
			szene,
			node,
			"Leicht schief",
			"PRÜFEN",
			rot_txt,
			"Up-Vektor = +Y (oder bewusste Deko-Neigung)",
			fix
		)
	elif _matcht(voll_label, gebaeude_raster) and ist_wurzel and _aktive_szene_id == "city":
		var rest := absf(fposmod(grad_v.y + YAW_RASTER / 2.0, YAW_RASTER) - YAW_RASTER / 2.0)
		if rest > YAW_TOLERANZ:
			_melde(
				szene,
				node,
				"Krummer Gebäude-Yaw",
				"PRÜFEN",
				"yaw = %.1f° (%.1f° neben dem %.0f°-Raster)" % [grad_v.y, rest, YAW_RASTER],
				"Yaw auf 15°-Raster (Stadt-Grid / Ortsplan)",
				"Yaw auf %.0f° runden" % (roundf(grad_v.y / YAW_RASTER) * YAW_RASTER)
			)


func _glb_hinweis(in_glb: bool) -> String:
	if in_glb:
		return " — GLB-interne Pose (im Asset authored, nicht von der Szene gesetzt)"
	return ""


## Kipp-Winkel der Welt-Basis gegen +Y in Grad (0 = perfekt aufrecht).
func _kipp_grad(basis: Basis) -> float:
	var up := basis.y.normalized()
	return rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))


func _basis_endlich(basis: Basis) -> bool:
	return basis.x.is_finite() and basis.y.is_finite() and basis.z.is_finite()


## ---------------------------------------------------- Boden-Kontakt


## Boden-Kontakt einer Kategorie-Wurzel: Unterkante des Mesh-Verbunds vs.
## beste Stand-Referenz (Terrain-Orakel oder höchste flache Stütze darunter).
func _pruefe_wurzel(
	szene: Node, eintrag: Dictionary, meshes: Array[Dictionary], terrain: bool
) -> void:
	var node: Node = eintrag["node"]
	var label := str(eintrag["label"])
	if bool(eintrag["auf_moebel"]) or _matcht(label, haengend):
		return
	var aabb := _verbund_aabb(node, meshes)
	if aabb.size == Vector3.ZERO or aabb.size.y < MIN_HOEHE_BODENCHECK:
		return
	var unten := aabb.position.y
	var mitte := aabb.get_center()
	var stuetzen := _stuetz_kandidaten(node, aabb, meshes)
	if bool(stuetzen["innen"]):
		return  # Unterkante steckt im Innenraum eines Objekts (Regal, Truhe …).
	var referenzen: Array[float] = stuetzen["kandidaten"]
	if terrain:
		referenzen.append(RanchGelaende.hoehe(mitte.x, mitte.z))
	if _aktive_szene_id == "city" and _matcht(label, fahrzeug):
		# Verkehrs- und Parkautos stehen per Konvention auf der Fahrbahnhöhe
		# (city_kulisse/_baue_verkehr addieren CityCarFeel.ROAD_Y).
		referenzen.append(CityCarFeel.ROAD_Y)
	if referenzen.is_empty():
		return
	# Wohlwollende Referenz: die Stand-Höhe, die den kleinsten Fehler ergibt.
	var ref := referenzen[0]
	for kandidat in referenzen:
		if absf(unten - kandidat) < absf(unten - ref):
			ref = kandidat
	var spalt := unten - ref
	var ist_dynamisch := _matcht(label, dynamisch)
	var hoehe := aabb.size.y
	var ist := (
		"Unterkante y = %.2f, Referenz y = %.2f, Spalt = %.2f m (H = %.1f m)"
		% [unten, ref, spalt, hoehe]
	)
	if spalt > 0.0:
		var grad := ""
		if ist_dynamisch:
			if spalt > SCHWEBE_DYNAMISCH:
				grad = "WAHRSCHEINLICH"
		elif spalt > SCHWEBE_SICHER:
			grad = "SICHER"
		elif spalt > SCHWEBE_WAHRSCHEINLICH:
			grad = "WAHRSCHEINLICH"
		elif spalt > SCHWEBE_PRUEFEN:
			grad = "PRÜFEN"
		if grad != "":
			_melde(
				szene,
				node,
				"Schwebt über dem Boden",
				grad,
				ist,
				"Unterkante auf Stand-Referenz (±%.2f m)" % SCHWEBE_PRUEFEN,
				"Y um %.2f m senken (auf y = %.2f)" % [spalt, ref]
			)
	elif not ist_dynamisch:
		var tiefe := -spalt
		var grad := ""
		if tiefe > EINSINK_SICHER * hoehe:
			grad = "SICHER"
		elif tiefe > EINSINK_WAHRSCHEINLICH * hoehe:
			grad = "WAHRSCHEINLICH"
		elif tiefe > maxf(0.15, EINSINK_PRUEFEN * hoehe):
			grad = "PRÜFEN"
		if grad != "":
			_melde(
				szene,
				node,
				"Versunken im Boden",
				grad,
				ist,
				"Unterkante nahe Stand-Referenz (Einsenken « Objekthöhe)",
				"Y um %.2f m heben (auf y = %.2f)" % [tiefe, ref]
			)


## Welt-AABB aller sichtbaren Mesh-Descendants der Wurzel.
func _verbund_aabb(wurzel: Node, meshes: Array[Dictionary]) -> AABB:
	var out := AABB()
	var leer := true
	for eintrag in meshes:
		var mi: Node = eintrag["node"]
		if mi == wurzel or wurzel.is_ancestor_of(mi):
			if leer:
				out = eintrag["aabb"]
				leer = false
			else:
				out = out.merge(eintrag["aabb"])
	return out


## Stütz-Kandidaten der Wurzel-AABB: Oberkanten aller überdeckenden Meshes
## unter der Unterkante (beliebig dick) plus PLATTENARTIGE Oberkanten knapp
## darüber (Einsink-Nachweis). `innen` = die Unterkante steckt im vertikalen
## Bereich eines DICKEN überdeckenden Meshes (Bär im Regal, Buch im Schrank)
## — dort ist keine Stand-Höhe ablesbar (Regalböden verschwinden im
## verschmolzenen Mesh-AABB), der Check wird übersprungen. Als „innen"
## zählt eine Stütze, deren Oberkante nahe der Objekt-Oberkante liegt ODER
## die möbel-klein ist (MOEBEL_MAX_SPANNE) — Raum-/Wand-Meshes nicht.
func _stuetz_kandidaten(wurzel: Node, aabb: AABB, meshes: Array[Dictionary]) -> Dictionary:
	var kandidaten: Array[float] = []
	var innen := false
	var unten := aabb.position.y
	var oben_max := aabb.position.y + aabb.size.y
	for eintrag in meshes:
		var mi: Node = eintrag["node"]
		if mi == wurzel or wurzel.is_ancestor_of(mi):
			continue
		var s: AABB = eintrag["aabb"]
		var riesig := s.size.x > STUETZE_MAX_SPANNE or s.size.z > STUETZE_MAX_SPANNE
		if s.size.y > STUETZE_MAX_HOEHE and riesig:
			continue  # Höhenfeld-artiges Riesen-Mesh: Terrain-Orakel zuständig.
		if not _footprint_deckt(s, aabb):
			continue
		var oben := s.position.y + s.size.y
		if oben <= unten + 0.05:
			kandidaten.append(oben)
		elif s.size.y <= PLATTE_MAX_DICKE and oben <= oben_max:
			kandidaten.append(oben)
		elif (
			s.position.y < unten - 0.05
			and (
				oben < oben_max + 0.5
				or (s.size.x <= MOEBEL_MAX_SPANNE and s.size.z <= MOEBEL_MAX_SPANNE)
			)
		):
			innen = true
	return {"kandidaten": kandidaten, "innen": innen}


## XZ-Überdeckung: Stütze enthält das Zentrum ODER ≥ 25 % der Grundfläche.
func _footprint_deckt(stuetze: AABB, objekt: AABB) -> bool:
	var mitte := objekt.get_center()
	var sx0 := stuetze.position.x
	var sx1 := stuetze.position.x + stuetze.size.x
	var sz0 := stuetze.position.z
	var sz1 := stuetze.position.z + stuetze.size.z
	if mitte.x >= sx0 and mitte.x <= sx1 and mitte.z >= sz0 and mitte.z <= sz1:
		return true
	var ox0 := objekt.position.x
	var ox1 := objekt.position.x + objekt.size.x
	var oz0 := objekt.position.z
	var oz1 := objekt.position.z + objekt.size.z
	var breite := maxf(0.0, minf(sx1, ox1) - maxf(sx0, ox0))
	var tiefe := maxf(0.0, minf(sz1, oz1) - maxf(sz0, oz0))
	var flaeche := maxf(objekt.size.x * objekt.size.z, 0.0001)
	return breite * tiefe / flaeche >= 0.25


## ---------------------------------------------------- Befunde + Report


func _melde(
	szene: Node,
	node: Node3D,
	check: String,
	grad: String,
	ist: String,
	erwartung: String,
	fix: String
) -> void:
	var t := node.global_transform
	var euler := t.basis.get_euler()
	var grad_v := Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))
	(
		_befunde
		. append(
			{
				"szene": str(szene.scene_file_path),
				"pfad": str(szene.get_path_to(node)),
				"klasse": node.get_class(),
				"check": check,
				"grad": grad,
				"ist": ist,
				"erwartung": erwartung,
				"fix": fix,
				"transform":
				(
					"pos = %s, rot = %s°, scale = %s"
					% [_fmt_v(t.origin), _fmt_v(grad_v), _fmt_v(t.basis.get_scale())]
				),
			}
		)
	)


func _fmt_v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _fmt_basis(basis: Basis) -> String:
	return "[%s %s %s]" % [_fmt_v(basis.x), _fmt_v(basis.y), _fmt_v(basis.z)]


func _grad_rang(grad: String) -> int:
	match grad:
		"SICHER":
			return 0
		"WAHRSCHEINLICH":
			return 1
	return 2


func _schreibe_report(pfad: String) -> void:
	DirAccess.make_dir_recursive_absolute(pfad.get_base_dir())
	_befunde.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if _grad_rang(str(a["grad"])) != _grad_rang(str(b["grad"])):
				return _grad_rang(str(a["grad"])) < _grad_rang(str(b["grad"]))
			return str(a["szene"]) + str(a["pfad"]) < str(b["szene"]) + str(b["pfad"])
	)
	var zaehler := {"SICHER": 0, "WAHRSCHEINLICH": 0, "PRÜFEN": 0}
	for b in _befunde:
		zaehler[str(b["grad"])] = int(zaehler[str(b["grad"])]) + 1
	var f := FileAccess.open(pfad, FileAccess.WRITE)
	f.store_line("# Asset-Ausrichtungs-Audit — Befundliste")
	f.store_line("")
	f.store_line(
		(
			"Erzeugt von `tools/audit/orientation_audit.gd` (headless, %s)."
			% Time.get_datetime_string_from_system()
		)
	)
	f.store_line("")
	f.store_line("## Aufruf")
	f.store_line("")
	f.store_line("```bash")
	f.store_line("bash tools/ci/run_godot_isolated.sh godot --headless --audio-driver Dummy \\")
	f.store_line("  --path GOOBY-GODOT --script res://tools/audit/orientation_audit.gd")
	f.store_line("```")
	f.store_line("")
	f.store_line("Env: `GOOBY_AUDIT_OUT` (Ziel-Markdown, daneben .json), `GOOBY_AUDIT_SCENES`")
	f.store_line("(Komma-Liste von Id-Substrings, z. B. `ranch,city`). Max. EINE Godot-")
	f.store_line("Instanz, kein `godot --import` parallel (AGENTS.md).")
	f.store_line("")
	f.store_line("## Methodik + Grenzen")
	f.store_line("")
	f.store_line("- Alle Platzierungen entstehen PROZEDURAL (die .tscn enthalten keine")
	f.store_line("  Transforms) — Fix-Ort ist also das Builder-Skript der Szene (z. B.")
	f.store_line("  `scripts/city/orte/<ort>.gd`, `scripts/city/city_kulisse.gd`), nicht")
	f.store_line("  die .tscn-Datei.")
	f.store_line("- Checks: Spiegelung/negative Scale, NaN, Kipp-Winkel gegen +Y für")
	f.store_line("  Aufrecht-Kategorien (Eigen-Label; Ausnahmen: absichtlich Gekipptes),")
	f.store_line("  Gebäude-Yaw-Raster (nur Stadt), Boden-Kontakt (Unterkante vs. Stütz-")
	f.store_line("  AABBs bzw. RanchGelaende.hoehe; Stadt-Fahrzeuge: CityCarFeel.ROAD_Y).")
	f.store_line("- Nicht prüfbar: MultiMesh-Instanz-Transforms (headless Dummy-Renderer;")
	f.store_line("  Quelle WeltStreu ist über test_world_streu.gd abgedeckt), Posen in")
	f.store_line("  Skeleton/BoneAttachment3D, GLB-interne Posen (nur PRÜFEN-Hinweis).")
	f.store_line("")
	f.store_line("## Szenen-Statistik")
	f.store_line("")
	f.store_line("| Szene | Node3D | Meshes | MultiMesh (Instanzen) | Wurzeln | Befunde |")
	f.store_line("|---|---|---|---|---|---|")
	for s in _statistik:
		if s.has("fehler"):
			f.store_line("| %s | FEHLER: %s | | | | |" % [s["id"], s["fehler"]])
			continue
		(
			f
			. store_line(
				(
					"| %s | %d | %d | %d (%d) | %d | %d |"
					% [
						s["id"],
						s["nodes"],
						s["meshes"],
						s["multimesh"],
						s["mm_instanzen"],
						s["wurzeln"],
						s["befunde"],
					]
				)
			)
		)
	f.store_line("")
	f.store_line(
		(
			"Befunde: **%d SICHER**, **%d WAHRSCHEINLICH**, **%d PRÜFEN**."
			% [zaehler["SICHER"], zaehler["WAHRSCHEINLICH"], zaehler["PRÜFEN"]]
		)
	)
	f.store_line("")
	f.store_line("## Befunde")
	for b in _befunde:
		f.store_line("")
		f.store_line("### [%s] %s — `%s`" % [b["grad"], b["check"], b["pfad"]])
		f.store_line("- Szene: `%s` (%s)" % [b["szene"], b["klasse"]])
		f.store_line("- Ist: %s" % b["ist"])
		f.store_line("- Ist-Transform: %s" % b["transform"])
		f.store_line("- Erwartung: %s" % b["erwartung"])
		f.store_line("- Fix-Vorschlag: %s" % b["fix"])
	f.close()
	var jf := FileAccess.open(pfad.get_basename() + ".json", FileAccess.WRITE)
	jf.store_string(JSON.stringify({"befunde": _befunde, "statistik": _statistik}, "\t", false))
	jf.close()
	print("Report: %s (+ .json), Befunde: %d" % [pfad, _befunde.size()])

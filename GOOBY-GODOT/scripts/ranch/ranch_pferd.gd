class_name RanchPferd
extends Node3D
## Das Gooby-Ranch-Pferd — seit RW-2 das GLB-Modell aus der Blender-
## Pipeline (assets/ranch/pferd/pferd.glb + fohlen.glb, 13 Knochen,
## 9 Animationen, Ruecken 1,42 m, Blick -Z, Boden y=0). Der RANCH-2-
## Modell-VERTRAG (RANCH2-needs.md §2) bleibt unangetastet:
## set_farbe/set_gait/tick/head_pivot/equip/body_height/phase.
##
## Fellfarben laufen als Palette-Rezept: das GLB nutzt eine 4x4-Zellen-
## Palette (UVs auf Zellmitten, ranch_stil.py) — set_farbe/set_aussehen
## erzeugen pro Farbkombi EINE winzige 4x4-ImageTexture (static-Cache)
## und tauschen nur das Material. Abzeichen (Blesse/Stern/Schnippe/
## Socken/Schecken) sind kleine Overlay-Meshes an BoneAttachments;
## Glitzer ist ein Emission-Schimmer; Fohlen/Jaehrling nutzen das
## Fohlen-GLB, Groesse skaliert den ganzen Knoten (set_aussehen).
##
## `_beine` sind seit dem GLB-Umbau PROXY-Knoten: sie rechnen die alte
## prozedurale Beinphase weiter (Tests + Hufschlag-Sync lesen sie), die
## sichtbare Beinanimation kommt aus dem AnimationPlayer des GLB.
##
## VIS-2 Bodenkontakt pro Huf: die Lauf-Clips tauchen die Hufe ein paar
## Zentimeter unter y=0 und am Hang/Brueckendeck liegt der Boden unter
## den Hufen hoeher als unter der Koerpermitte (die Reiter setzen den
## Knoten auf die MITTEN-Hoehe). `_halte_hufe_ueber_boden` misst deshalb
## jeden Frame die vier Huf-Punkte gegen den Boden (set_bodenkontakt-
## Callback oder die eigene Standflaeche) und hebt das sichtbare Rig
## (plus Sattel/Decke) gerade so weit an, dass kein Huf mehr eintaucht —
## Anheben sofort (kein sichtbares Clipping), Absenken weich gedaempft.
##
##   var pferd := RanchPferd.neu(Color("#D9A066"), Color("#8A5A33"))
##   add_child(pferd)
##   pferd.set_gangart(RanchPferd.GANG_TRAB)

const GANG_IDLE := "idle"
const GANG_SCHRITT := "schritt"
const GANG_TRAB := "trab"
const GANG_GALOPP := "galopp"
const GANG_TOELT := "toelt"

## Frequenz (Hz) + Proxy-Bein-Amplitude (rad) je Gangart (phase()/Tests).
const GANG_PROFILE := {
	GANG_IDLE: {"hz": 0.45, "bein": 0.0},
	GANG_SCHRITT: {"hz": 1.2, "bein": 0.3},
	GANG_TRAB: {"hz": 2.1, "bein": 0.5},
	GANG_GALOPP: {"hz": 2.9, "bein": 0.85},
	GANG_TOELT: {"hz": 2.8, "bein": 0.4},
}
## RANCH-2-Gangart-Ids ("stand"...) → meine Profile.
const GAIT_ALIAS := {
	"stand": GANG_IDLE,
	"schritt": GANG_SCHRITT,
	"trab": GANG_TRAB,
	"galopp": GANG_GALOPP,
	"toelt": GANG_TOELT,
}
## GLB-Clip je Gangart (Tölt reitet den Trab-Clip mit flacherem Takt).
const ANIM_JE_GANGART := {
	GANG_IDLE: "idle",
	GANG_SCHRITT: "schritt",
	GANG_TRAB: "trab",
	GANG_GALOPP: "galopp",
	GANG_TOELT: "trab",
}
const AKTIONEN: Array[String] = ["sprung", "fressen", "kopfschuetteln", "schlafen"]

## Fellfarben-Ids (RanchPlaySlices.FELLFARBEN + Gen-Farben aus
## RanchRassen.FARBE_TABELLE) → [Fell, Mähne] im Gooby-Pastell.
const FELL := {
	"braun": [Color("#B98A5E"), Color("#6E4B2E")],
	"schwarz": [Color("#6B6470"), Color("#3E3944")],
	"weiss": [Color("#F2E9DC"), Color("#C9B79C")],
	"fuchs": [Color("#D98E5F"), Color("#8A4A2E")],
	"palomino": [Color("#D9A066"), Color("#8A5A33")],
	"schecke": [Color("#C98BB9"), Color("#8A5A7A")],
	"apricot": [Color("#EFB98A"), Color("#B4744A")],
	"rauchgrau": [Color("#9A93A6"), Color("#5C5566")],
}
## Feste Detail-Farben der Palette-Zellen (ranch_stil.py PALETTE).
const HUF_FARBE := Color("#6B5A52")
const WANGEN_ROSA := Color("#F9C6CF")
const AUGEN_INK := Color("#3A2E2E")
const AUGEN_WEISS := Color("#FFFFFF")
const MUND_FARBE := Color("#4A2B33")
const OHR_INNEN := Color("#F6A8B8")
const WEISS_FARBE := Color("#FDFDF7")
const AKZENT_TEAL := Color("#5FA8A0")
## Abzeichen-Weiss (Blesse/Stern/Schnippe/Socken) + Schecken-Flecken.
const ABZEICHEN_WEISS := Color("#F7F1E4")

## Rücken-Oberkante (Sattel-Auflage) in Metern — für body_height/Gear.
const RUECKEN_Y := 1.42

## VIS-2 Bodenkontakt: Huf-tragende Knochen des GLB-Skeletts.
const HUF_KNOCHEN: Array[String] = ["leg.FL", "leg.FR", "leg.BL", "leg.BR"]
## Sicherheitsabstand (m) der Hufsohle ueber dem Boden — deckt die flach
## liegenden Brueckenplanken ab (Deckkurve vs. Plankenoberkante ≤ ~3 cm).
const HUF_EPSILON := 0.02
## Obergrenze (m) fuer die Anhebung — Kliff-Kanten heben das Rig nicht
## ins Absurde, dort klemmt ohnehin die Begehbarkeits-Pruefung der Welt.
const HUF_LIFT_MAX := 0.4
## Absenk-Daempfung (1/s): Anheben ist sofort, Absenken federt weich nach.
const HUF_SENK_RATE := 5.0

## Skalen je Alters-Phase (RanchHorseBreeding.PHASEN) + GLB-Wahl.
const ALTER_SKALA := {"fohlen": 0.55, "jaehrling": 0.75, "jungpferd": 0.90, "ausgewachsen": 1.0}
const FOHLEN_ALTER: Array[String] = ["fohlen", "jaehrling"]
## Das Fohlen-GLB ist bereits klein gebaut (~0,62 der Pferd-Masse) —
## Restskala, damit ALTER_SKALA die SICHTBARE Endgroesse beschreibt.
const FOHLEN_GLB_MASSSTAB := 0.62

const PFERD_SZENE: PackedScene = preload("res://assets/ranch/pferd/pferd.glb")
const FOHLEN_SZENE: PackedScene = preload("res://assets/ranch/pferd/fohlen.glb")

static var _material_cache: Dictionary = {}
static var _fell_cache: Dictionary = {}

var farbe := Color("#D9A066")
var maehne_farbe := Color("#8A5A33")
var gangart := GANG_IDLE
## Sichtbare Individuen-Merkmale (set_aussehen).
var glitzer := false
var schecke := false
var stimm_pitch := 1.0

var _zeit := 0.0
var _blinzel_zeit := 0.0
var _extern_tick_ms := -10000
var _variante := "pferd"
var _groesse := 1.0
var _alter := "ausgewachsen"
var _abzeichen: Dictionary = {}
var _traechtig := false
var _rig: Node3D
var _skelett: Skeleton3D
var _mesh: MeshInstance3D
var _anim: AnimationPlayer
var _kopf: Node3D
var _beine: Array[Node3D] = []
var _gear: Dictionary = {}
var _gear_farben: Dictionary = {}
var _gear_basis_y: Dictionary = {}
## VIS-2 Bodenkontakt: Callable(x, z) -> float (Welt-Bodenhoehe) oder leer
## (= eigene Standflaeche als Ebene), Huf-Anker in Knochen-Koordinaten
## und die aktuell angewandte Rig-Anhebung (lokale Einheiten).
var _boden_cb := Callable()
var _huf_anker: Array[Dictionary] = []
var _huf_lift := 0.0


## Fabrik: Pferd mit Fell- und Mähnenfarbe (Pack-Daten) bauen.
static func neu(fell: Color, maehne: Color) -> RanchPferd:
	var pferd := RanchPferd.new()
	pferd.farbe = fell
	pferd.maehne_farbe = maehne
	return pferd


## Geteiltes Pastell-Material pro Farbe (ein Material je Farbton im Spiel).
## Bestand fuer Props/Boeden vieler Konsumenten — bleibt unveraendert.
static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _material_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.92
		_material_cache[key] = mat
	return _material_cache[key]


func _ready() -> void:
	_baue_pferd()
	_auto_bodenkontakt()


## Selbstläufer-Animation — pausiert, solange ein externer Treiber
## (RANCH-2-Reit-Controller) über tick() die Phase übernimmt. Der
## Huf-Bodenkontakt läuft NICHT hier, sondern nach jedem Skelett-Update
## (skeleton_updated in _baue_huf_anker): _process liefe einen Frame VOR
## dem AnimationPlayer und die Korrektur hinkte der Pose hinterher
## (Rest-Clipping im schnellen Galopp-Takt).
func _process(delta: float) -> void:
	if Time.get_ticks_msec() - _extern_tick_ms > 500:
		if _anim != null and _anim.speed_scale != 1.0:
			_anim.speed_scale = 1.0
		update_gang(delta)


func set_gangart(gang: String) -> void:
	if not GANG_PROFILE.has(gang) or gang == gangart:
		return
	gangart = gang
	_spiele_gangart()


## ------------------------------------------- RANCH-2-Vertrag (Modell-API)


## Fellfarbe per Id setzen (RanchPlaySlices.FELLFARBEN) — tauscht nur das
## Palette-Material, kein Umbau; Gear bleibt unberührt.
func set_farbe(id: String) -> void:
	var paar: Array = FELL.get(id, FELL["braun"])
	farbe = paar[0]
	maehne_farbe = paar[1]
	_wende_farben_an()


## Gangart per RANCH-2-Id ("stand"|"schritt"|"trab"|"galopp"|"toelt").
func set_gait(id: String) -> void:
	set_gangart(str(GAIT_ALIAS.get(id, id)))


## Individuum anwenden (RW-2): Pferde-Dict aus dem Save (RanchRassen-
## Felder). Setzt Farbe/Abzeichen/Groesse/Alter/Glitzer/Stimme und baut
## bei Bedarf um (Fohlen-GLB). Gear überlebt.
func set_aussehen(pferd: Dictionary) -> void:
	var paar: Array = FELL.get(str(pferd.get("farbe", "braun")), FELL["braun"])
	farbe = paar[0]
	maehne_farbe = paar[1]
	var gene: Dictionary = pferd.get("gene") if pferd.get("gene") is Dictionary else {}
	schecke = RanchRassen.ist_schecke(gene)
	glitzer = RanchRassen.ist_glitzer(gene)
	_abzeichen = pferd.get("abzeichen") if pferd.get("abzeichen") is Dictionary else {}
	_groesse = clampf(_num(pferd.get("groesse"), 1.0), 0.4, 1.6)
	_alter = str(pferd.get("alter", "ausgewachsen"))
	if not ALTER_SKALA.has(_alter):
		_alter = "ausgewachsen"
	_traechtig = bool(pferd.get("traechtig", false))
	stimm_pitch = clampf(_num(pferd.get("stimmPitch"), 1.0), 0.6, 1.4)
	_zeit = _num(pferd.get("phasenOffset"), 0.0) / maxf(0.05, float(GANG_PROFILE[gangart]["hz"]))
	var variante_neu := "fohlen" if FOHLEN_ALTER.has(_alter) else "pferd"
	if _rig == null:
		_variante = variante_neu
		return
	if variante_neu != _variante:
		_variante = variante_neu
		_neu_bauen()
		return
	_wende_aussehen_an()


## VIS-2: Bodenkontakt pro Huf einschalten. `hoehe_cb` = Callable(x, z)
## -> float mit der WELT-Bodenhoehe unter einem Huf (z. B.
## RanchKarte.reit_hoehe — kennt auch das Haengebruecken-Deck); leere
## Callable = Ebene durch die eigene Standflaeche (fängt die Lauf-Clip-
## Eintauchtiefe auf flachem Boden ab, laeuft immer). Korrigiert NUR die
## sichtbare Rig-Hoehe — Node-Position/Vertrags-API bleiben unberuehrt.
func set_bodenkontakt(hoehe_cb: Callable) -> void:
	_boden_cb = hoehe_cb


## VIS-2 Mess-/Test-Hook: kleinster aktueller Huf-Abstand zum Boden in
## Welt-Metern (negativ = ein Huf taucht ein). INF ohne Rig/Anker.
func huf_bodenabstand_min() -> float:
	if _huf_anker.is_empty() or _skelett == null:
		return INF
	var abstand := INF
	for anker: Dictionary in _huf_anker:
		var punkt := _huf_welt(anker)
		abstand = minf(abstand, punkt.y - _boden_unter(punkt))
	return abstand


## Externer Animations-Treiber (Reit-Controller): `tempo` (m/s) staucht/
## streckt die Schrittfrequenz relativ zum Gangart-Zieltempo — dieselbe
## Semantik wie horse_stub.tick.
func tick(delta: float, tempo: float = -1.0) -> void:
	_extern_tick_ms = Time.get_ticks_msec()
	var mult := 1.0
	if tempo >= 0.0 and gangart != GANG_IDLE:
		var ziel := RanchRideFeel.zieltempo(_ride_id())
		if ziel > 0.01:
			mult = clampf(tempo / ziel, 0.35, 1.25)
	if _anim != null:
		_anim.speed_scale = mult
	update_gang(delta * mult)


## Kopf-Knoten fürs Kopfnicken beim Reiten (Proxy am head-Knochen:
## Offsets von aussen addieren sich auf die GLB-Animation).
func head_pivot() -> Node3D:
	return _kopf


## Einmalige GLB-Aktion abspielen: "sprung" | "fressen" |
## "kopfschuetteln" | "schlafen" — danach kehrt die Gangart zurueck
## (fressen/schlafen loopen, bis die Gangart neu gesetzt wird).
func spiele_aktion(id: String) -> void:
	if _anim == null or not AKTIONEN.has(id):
		return
	var name := _anim_name(id)
	if name != "":
		_anim.play(name, 0.2)


## Ausrüstung anlegen/abnehmen (farbe null = abnehmen) — Gear-Meshes von
## RANCH-2 (RanchGearMeshes), Positionen auf die GLB-Proportionen gelegt.
func equip(slot: String, gear_farbe: Variant) -> void:
	if _gear.has(slot):
		(_gear[slot] as Node3D).queue_free()
		_gear.erase(slot)
	_gear_farben.erase(slot)
	_gear_basis_y.erase(slot)
	if not (gear_farbe is String):
		return
	var aufsatz := RanchGearMeshes.build(slot, gear_farbe)
	if aufsatz == null:
		return
	match slot:
		"sattel":
			aufsatz.position = Vector3(0.0, RUECKEN_Y + 0.06 + _huf_lift, 0.05)
			_gear_basis_y[slot] = RUECKEN_Y + 0.06
			add_child(aufsatz)
		"decke":
			aufsatz.position = Vector3(0.0, RUECKEN_Y + 0.02 + _huf_lift, 0.05)
			_gear_basis_y[slot] = RUECKEN_Y + 0.02
			add_child(aufsatz)
		"halfter":
			if _kopf == null:
				aufsatz.free()
				return
			aufsatz.position = Vector3(0.0, -0.02, -0.34)
			aufsatz.rotation.y = PI
			_kopf.add_child(aufsatz)
		_:
			aufsatz.free()
			return
	_gear[slot] = aufsatz
	_gear_farben[slot] = gear_farbe


## Sitzhöhe (Sattel-Oberkante) für den Gooby-Sitz.
func body_height() -> float:
	return (RUECKEN_Y + 0.12) * _gesamt_skala()


## Aktuelle Schrittphase (0..1) — Reit-Controller synct Kopfnicken/Hufe.
func phase() -> float:
	return fposmod(_zeit * float(GANG_PROFILE[gangart]["hz"]), 1.0)


## Ein Animations-Schritt (Proxys + Blinzeln; Tests rufen es direkt).
## Die sichtbare Skelett-Animation laeuft im AnimationPlayer des GLB.
func update_gang(dt: float) -> void:
	_zeit += dt
	_blinzel_zeit += dt
	var profil: Dictionary = GANG_PROFILE[gangart]
	var omega := TAU * float(profil["hz"])
	var phase_rad := _zeit * omega
	var amp := float(profil["bein"])
	for i in _beine.size():
		if gangart == GANG_IDLE:
			_beine[i].rotation.x = lerpf(_beine[i].rotation.x, 0.0, minf(1.0, dt * 6.0))
			continue
		# Trab: Diagonalpaare (0+3 vs. 1+2). Galopp: vorn vs. hinten.
		var versatz := 0.0
		if gangart == GANG_TRAB or gangart == GANG_TOELT:
			versatz = 0.0 if (i == 0 or i == 3) else PI
		else:
			versatz = 0.0 if i < 2 else PI * 0.62
		_beine[i].rotation.x = sin(phase_rad + versatz) * amp
	_blinzle()


func _ride_id() -> String:
	for id: String in GAIT_ALIAS:
		if str(GAIT_ALIAS[id]) == gangart:
			return id
	return "stand"


## Umbau (Varianten-Wechsel Pferd↔Fohlen): Gear + Rig neu.
func _neu_bauen() -> void:
	var gear_kopie := _gear_farben.duplicate()
	for slot: String in _gear:
		(_gear[slot] as Node3D).queue_free()
	_gear = {}
	_gear_farben = {}
	if _rig != null:
		_rig.queue_free()
	for bein in _beine:
		bein.queue_free()
	_rig = null
	_skelett = null
	_mesh = null
	_anim = null
	_kopf = null
	_beine = []
	_huf_anker = []
	_huf_lift = 0.0
	_baue_pferd()
	for slot: String in gear_kopie:
		equip(slot, gear_kopie[slot])


## Blinzeln: alle ~3,4 s klappt der augen_zu-Shapekey kurz zu.
func _blinzle() -> void:
	if _mesh == null:
		return
	var zyklus := fmod(_blinzel_zeit, 3.4)
	_mesh.set("blend_shapes/augen_zu", 1.0 if zyklus > 3.25 else 0.0)


## ------------------------------------------------------------- Bau-Helfer


func _baue_pferd() -> void:
	var szene := FOHLEN_SZENE if _variante == "fohlen" else PFERD_SZENE
	_rig = szene.instantiate()
	_rig.name = "Rig"
	add_child(_rig)
	_skelett = _finde_knoten(_rig, "Skeleton3D") as Skeleton3D
	_mesh = _finde_knoten(_rig, "MeshInstance3D") as MeshInstance3D
	_anim = _finde_knoten(_rig, "AnimationPlayer") as AnimationPlayer
	_entferne_blinzel_tracks()
	_baue_kopf_proxy()
	_baue_bein_proxys()
	_baue_huf_anker()
	_wende_aussehen_an()
	_spiele_gangart()


## Kopf-Proxy: BoneAttachment am head-Knochen; das Kind `_kopf` wird in
## Ruhepose auf die RanchPferd-Achsen ausgerichtet (Anker-Vertrag: -Z =
## Blickrichtung), erbt aber jede Kopf-Animation des Skeletts.
func _baue_kopf_proxy() -> void:
	_kopf = Node3D.new()
	_kopf.name = "Kopf"
	if _skelett == null:
		add_child(_kopf)
		return
	var idx := _skelett.find_bone("head")
	if idx < 0:
		add_child(_kopf)
		return
	var anker := BoneAttachment3D.new()
	anker.name = "KopfAnker"
	_skelett.add_child(anker)
	anker.bone_name = "head"
	var ruhe := _skelett.get_bone_global_rest(idx)
	_kopf.basis = ruhe.basis.inverse()
	anker.add_child(_kopf)


## Vier unsichtbare Proxy-Beine: Bestandstests + Hufschlag-Sync lesen
## deren rotation.x; ausserdem Anker fuer die Socken-Abzeichen.
func _baue_bein_proxys() -> void:
	for pos: Vector3 in [
		Vector3(-0.26, 0.44, -0.42),
		Vector3(0.26, 0.44, -0.42),
		Vector3(-0.28, 0.44, 0.5),
		Vector3(0.28, 0.44, 0.5),
	]:
		var bein := Node3D.new()
		bein.position = pos
		add_child(bein)
		_beine.append(bein)


## VIS-2: Huf-Anker in Knochen-Koordinaten — die Hufsohle liegt in
## Ruhepose direkt unter dem Bein-Knochen auf der Mesh-Unterkante
## (GLB-Vertrag: Boden y=0, AABB-Minimum ≈ Hufsohle). Die Wache haengt
## am skeleton_updated-Signal: sie laeuft damit im selben Frame NACH der
## Animation (in _process hinkte sie einen Frame hinterher).
func _baue_huf_anker() -> void:
	_huf_anker = []
	if _skelett == null or _mesh == null or _mesh.mesh == null:
		return
	var sohle_y := _mesh.mesh.get_aabb().position.y
	for knochen in HUF_KNOCHEN:
		var idx := _skelett.find_bone(knochen)
		if idx < 0:
			continue
		var ruhe := _skelett.get_bone_global_rest(idx)
		var sohle := Vector3(ruhe.origin.x, sohle_y, ruhe.origin.z)
		_huf_anker.append({"bone": idx, "lokal": ruhe.affine_inverse() * sohle})
	if not _huf_anker.is_empty():
		_skelett.skeleton_updated.connect(_nach_skelett_update)


func _nach_skelett_update() -> void:
	_halte_hufe_ueber_boden(get_process_delta_time())


## VIS-2 Bodenkontakt-Wache: misst pro Frame die vier Hufsohlen gegen den
## Boden und hebt das sichtbare Rig (plus Sattel/Decke) um die groesste
## Eindringtiefe an. Anheben sofort (kein sichtbares Clipping), Absenken
## mit HUF_SENK_RATE gedaempft (kein Zappeln im Galopp-Takt).
func _halte_hufe_ueber_boden(delta: float) -> void:
	if _huf_anker.is_empty() or _rig == null or not is_inside_tree():
		return
	var skala := maxf(global_basis.y.length(), 0.001)
	var lift_welt := _huf_lift * skala
	var noetig := 0.0
	for anker: Dictionary in _huf_anker:
		var punkt := _huf_welt(anker)
		var ohne_lift := punkt.y - lift_welt
		noetig = maxf(noetig, _boden_unter(punkt) + HUF_EPSILON - ohne_lift)
	var ziel: float = clampf(noetig, 0.0, HUF_LIFT_MAX) / skala
	if ziel >= _huf_lift:
		_huf_lift = ziel
	else:
		_huf_lift = lerpf(_huf_lift, ziel, minf(1.0, delta * HUF_SENK_RATE))
	_rig.position.y = _huf_lift
	for slot: String in _gear_basis_y:
		var aufsatz: Node3D = _gear.get(slot)
		if aufsatz != null:
			aufsatz.position.y = float(_gear_basis_y[slot]) + _huf_lift


## Welt-Position der Hufsohle eines Ankers (aktuelle Skelett-Pose).
func _huf_welt(anker: Dictionary) -> Vector3:
	var pose := _skelett.get_bone_global_pose(int(anker["bone"]))
	return _skelett.global_transform * (pose * (anker["lokal"] as Vector3))


## Bodenhoehe (Welt) unter einem Huf-Punkt: Gelaende-Callback oder die
## eigene Standflaeche (Ebene durch den Fusspunkt des Knotens).
func _boden_unter(punkt: Vector3) -> float:
	if _boden_cb.is_valid():
		return _num(_boden_cb.call(punkt.x, punkt.z), global_position.y)
	return global_position.y


## VIS-2 Auto-Verdrahtung: haengt das Pferd unter dem freien Welt-Reiter
## (RanchWeltReiter, Duck-Typing — VIS-1-Datei bleibt unberuehrt), liefert
## RanchKarte.reit_hoehe die Bodenhoehe inklusive Haengebruecken-Deck.
func _auto_bodenkontakt() -> void:
	if _boden_cb.is_valid():
		return
	var knoten := get_parent()
	while knoten != null:
		if knoten.has_method("springe_zu") and knoten.has_method("aktuelle_zone"):
			_boden_cb = Callable(RanchKarte, "reit_hoehe")
			return
		knoten = knoten.get_parent()


## Farbe + Abzeichen + Skala in einem Rutsch (nach Bau/set_aussehen).
func _wende_aussehen_an() -> void:
	_wende_farben_an()
	_baue_abzeichen()
	scale = Vector3.ONE * _gesamt_skala()


func _wende_farben_an() -> void:
	if _mesh != null:
		_mesh.set_surface_override_material(0, _fell_material(farbe, maehne_farbe, glitzer))


func _gesamt_skala() -> float:
	var basis: float = ALTER_SKALA.get(_alter, 1.0)
	if _variante == "fohlen":
		basis /= FOHLEN_GLB_MASSSTAB
	return basis * _groesse


## Abzeichen-Overlays neu bauen: Blesse/Stern/Schnippe am Kopf, Socken
## an den Bein-Knochen, Schecken-Flecken + Traechtig-Bauch am Rumpf.
func _baue_abzeichen() -> void:
	if _skelett == null:
		return
	var alte: Array = []
	for kind in _skelett.get_children():
		if kind is BoneAttachment3D and str(kind.name).begins_with("Abzeichen"):
			alte.append(kind)
	for kind: Node in alte:
		kind.free()
	var weiss := ABZEICHEN_WEISS
	var kopf := _abzeichen_anker("head")
	if kopf != null:
		if bool(_abzeichen.get("blesse", false)):
			_overlay(kopf, Vector3(0.0, 0.1, -0.28), Vector3(0.08, 0.3, 0.18), weiss)
		if bool(_abzeichen.get("stern", false)):
			_overlay(kopf, Vector3(0.0, 0.19, -0.25), Vector3(0.1, 0.1, 0.1), weiss)
		if bool(_abzeichen.get("schnippe", false)):
			_overlay(kopf, Vector3(0.0, -0.04, -0.44), Vector3(0.09, 0.07, 0.08), weiss)
	var socken: Array = _abzeichen.get("socken") if _abzeichen.get("socken") is Array else []
	var bein_namen: Array[String] = ["leg.FL", "leg.FR", "leg.BL", "leg.BR"]
	for i in mini(socken.size(), 4):
		if int(_num(socken[i], 0.0)) != 1:
			continue
		var bein := _abzeichen_anker(bein_namen[i])
		if bein != null:
			_overlay(bein, Vector3(0.0, -0.62, 0.0), Vector3(0.13, 0.2, 0.13), weiss)
	var rumpf := _abzeichen_anker("body")
	if rumpf == null:
		return
	if schecke:
		_overlay(rumpf, Vector3(0.3, 0.05, -0.2), Vector3(0.3, 0.34, 0.42), weiss)
		_overlay(rumpf, Vector3(-0.32, -0.1, 0.25), Vector3(0.26, 0.3, 0.34), weiss)
		_overlay(rumpf, Vector3(0.12, 0.18, 0.35), Vector3(0.24, 0.2, 0.3), weiss)
	if _traechtig:
		_overlay(rumpf, Vector3(0.0, -0.28, 0.05), Vector3(0.52, 0.44, 0.64) * 1.12, farbe)


## BoneAttachment fuer Abzeichen: Kind ist auf RanchPferd-Achsen gedreht
## (Ruhepose), Positionen unten sind also im Pferd-Raum um den Knochen.
func _abzeichen_anker(knochen: String) -> Node3D:
	var idx := _skelett.find_bone(knochen)
	if idx < 0:
		return null
	var anker := BoneAttachment3D.new()
	anker.name = "Abzeichen_%s" % knochen.replace(".", "_")
	_skelett.add_child(anker)
	anker.bone_name = knochen
	var traeger := Node3D.new()
	traeger.basis = _skelett.get_bone_global_rest(idx).basis.inverse()
	anker.add_child(traeger)
	return traeger


func _overlay(parent: Node3D, pos: Vector3, groesse: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = groesse
	mi.material_override = RanchPferd.material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Gangart-Clip abspielen (weicher 0,25-s-Blend).
func _spiele_gangart() -> void:
	if _anim == null:
		return
	var name := _anim_name(str(ANIM_JE_GANGART.get(gangart, "idle")))
	if name != "" and _anim.current_animation != name:
		_anim.play(name, 0.25)


## Clip-Name defensiv: der Importer strippt das "-loop"-Suffix.
func _anim_name(basis: String) -> String:
	if _anim.has_animation(basis):
		return basis
	if _anim.has_animation(basis + "-loop"):
		return basis + "-loop"
	return ""


## Blend-Shape-Tracks aus den Gangart-Loops werfen (sie keyframen
## augen_zu konstant auf 0 und wuerden das manuelle Blinzeln
## ueberschreiben). schlafen/blinzeln behalten ihre Augen-Kurven.
func _entferne_blinzel_tracks() -> void:
	if _anim == null:
		return
	for basis: Variant in ["idle", "schritt", "trab", "galopp"]:
		var name := _anim_name(str(basis))
		if name == "":
			continue
		var anim := _anim.get_animation(name)
		for i in range(anim.get_track_count() - 1, -1, -1):
			if String(anim.track_get_path(i)).contains("augen_zu"):
				anim.remove_track(i)


## ---------------------------------------------------- Palette-Material


## Material pro Farbkombi (static-Cache): 4x4-Palette-Textur im Layout
## von ranch_stil.py (Zeile 0: fell/fell_hell/maehne/huf, Zeile 1:
## wange/auge/glanz/nuestern, Zeile 2: mund/ohr/weiss/akzent, Zeile 3:
## fell). Die UVs des GLB liegen auf Zellmitten — jede 4x4-Textur mit
## Nearest-Filter trifft exakt. BEWUSSTE Abweichung vom eingebetteten
## GLB-Material: dessen Palette ist doppelt encodiert (zu dunkel);
## hier stehen die Design-sRGB-Pastelltoene direkt — gleiche Pipeline
## wie RanchPferd.material() der restlichen Ranch-Optik.
static func _fell_material(fell: Color, maehne: Color, funkeln: bool) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [fell.to_html(), maehne.to_html(), funkeln]
	if _fell_cache.has(key):
		return _fell_cache[key]
	var zellen: Array = [
		[fell, fell.lerp(Color("#FFF6E8"), 0.62), maehne, HUF_FARBE],
		[WANGEN_ROSA, AUGEN_INK, AUGEN_WEISS, fell.darkened(0.12)],
		[MUND_FARBE, OHR_INNEN, WEISS_FARBE, AKZENT_TEAL],
		[fell, fell, fell, fell],
	]
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	for y in 4:
		for x in 4:
			img.set_pixel(x, y, zellen[y][x])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.92
	mat.metallic = 0.0
	if funkeln:
		mat.emission_enabled = true
		mat.emission = fell.lerp(Color("#FFF2FF"), 0.55)
		mat.emission_energy_multiplier = 0.18
	_fell_cache[key] = mat
	return mat


## Erster Knoten einer Klasse im GLB-Teilbaum (Importer-Layout defensiv).
static func _finde_knoten(wurzel: Node, klasse: String) -> Node:
	if wurzel.is_class(klasse):
		return wurzel
	for kind in wurzel.get_children():
		var treffer := _finde_knoten(kind, klasse)
		if treffer != null:
			return treffer
	return null


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback

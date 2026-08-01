class_name GoobyGespraech
extends Node
## W14/VOICE Mini-Dialoge: Wenn Gooby einen Soul-Moment sagt, erscheinen
## zwei Antwort-Chips beim Spieler. Die Antwort stupst die Laune, landet als
## kleiner Eintrag im Soul-Slice und triggert eine Follow-up-Line — maximal
## MAX_EBENEN tief, komplett datengetrieben über
## content/soul/data/gespraeche.json (Schema s. dort im "kommentar"-Feld).
##
## Aufteilung wie im Soul-Kern üblich: die BAUM-NAVIGATION ist pur (Statics,
## Zufall kommt als roll herein — headless testbar), nur die Chips-UI und
## das Aussprechen leben im Node. Angedockt wird NUR über den öffentlichen
## SeeleRunner-Hook stoss_gruss (der die Id JEDES Betreten-Moments sieht) —
## keine Semantik-Änderung bestehender Momente.
##
## Bubbles: neue Lines laufen über den W14/UIKERN-Vertrag
## AcBubble.show_bubble(layer, text, opts) mit opts.stil ("gooby"/"witz").
## Solange AcBubble noch nicht gelandet ist, fällt zeige_linie auf den
## vorhandenen room.say-Weg zurück (Gebrabbel bleibt in beiden Fällen synchron).

const PFAD := "res://content/soul/data/gespraeche.json"
## Maximal zwei Chip-Ebenen — danach ist das Gespräch immer zu Ende.
const MAX_EBENEN := 2
## Chips verschwinden von selbst, wenn der Spieler nicht antwortet (nie nerven).
const CHIP_TIMEOUT_S := 12.0
## Kleine Atempause zwischen Follow-up-Line und den Ebene-2-Chips.
const EBENE2_PAUSE_S := 2.4
## G4/P23 (HUD-Report H1): Luft zwischen Chip-Zeile und Safe-Area-Unterkante
## bzw. Chip-Abstand — Design-px, skalieren mit f.
const CHIP_RAND_GAP := 16.0
const CHIP_SEPARATION := 10.0

## Der SeeleRunner (bewusst untypisiert — kein Klassen-Zyklus).
var seele: Node = null

var _gespraeche: Array = []
var _ebene := 0
var _panel: Control = null
var _timeout: SceneTreeTimer = null


## Komponente erzeugen und an den SeeleRunner hängen (idempotent).
static func attach_to(seele_node: Node) -> GoobyGespraech:
	var existing := seele_node.get_node_or_null("GoobyGespraech")
	if existing is GoobyGespraech:
		return existing
	var gespraech := GoobyGespraech.new()
	gespraech.name = "GoobyGespraech"
	seele_node.add_child(gespraech)
	gespraech.seele = seele_node
	gespraech._gespraeche = lade()
	return gespraech


# ── Pure Baum-Navigation ──────────────────────────────────────────────────────


## Gespräche aus dem Content-JSON laden ([] bei kaputter Datei — nie crashen).
static func lade() -> Array:
	if not FileAccess.file_exists(PFAD):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PFAD))
	if not (parsed is Dictionary):
		push_error("GoobyGespraech: Datei kaputt/kein Objekt: %s" % PFAD)
		return []
	var liste: Variant = (parsed as Dictionary).get("gespraeche", [])
	return liste if liste is Array else []


## Gespräch zu einer Moment-Id ({} = keins angedockt).
static func fuer_anlass(gespraeche: Array, anlass_id: String) -> Dictionary:
	for gespraech: Variant in gespraeche:
		if not (gespraech is Dictionary):
			continue
		var anlaesse: Variant = (gespraech as Dictionary).get("anlass", [])
		if anlaesse is Array and (anlaesse as Array).has(anlass_id):
			return gespraech
	return {}


## Antwort-Chips einer Ebene (Gespräch selbst oder ein "weiter"-Knoten).
static func antworten(ebene: Dictionary) -> Array:
	var liste: Variant = ebene.get("antworten", [])
	return liste if liste is Array else []


## Follow-up-Key einer Antwort — Variante deterministisch über roll (0..1).
static func folge_key(antwort: Dictionary, roll: float) -> String:
	var keys: Variant = antwort.get("folge_keys", [])
	if not (keys is Array) or (keys as Array).is_empty():
		return ""
	var liste := keys as Array
	return str(liste[int(clampf(roll, 0.0, 0.999999) * liste.size())])


## Nächste Chip-Ebene einer Antwort ({} = Gespräch zu Ende).
static func naechste_ebene(antwort: Dictionary) -> Dictionary:
	var weiter: Variant = antwort.get("weiter", {})
	return weiter if weiter is Dictionary else {}


## Antwort im Soul-Slice verbuchen (pure: gibt die NEUE gespraeche-Map
## zurück) — Gooby erinnert sich, WIE du zuletzt geantwortet hast.
static func merke_antwort(
	gefuehrt: Dictionary, gespraech_id: String, antwort: Dictionary, now_ms: int
) -> Dictionary:
	var out := gefuehrt.duplicate(true)
	var alt: Variant = out.get(gespraech_id, {})
	var anzahl := int((alt as Dictionary).get("anzahl", 0)) if alt is Dictionary else 0
	out[gespraech_id] = {
		"antwort": str(antwort.get("id", "")),
		"erinnerung": str(antwort.get("erinnerung", "")),
		"beiMs": now_ms,
		"anzahl": anzahl + 1,
	}
	return out


## Basis-Platzhalter für alle W14-Lines (Spiegel von SoulService._base_args,
## hier öffentlich, damit Gespräch UND Linien-Kommentare sie teilen).
static func text_args(slice: Dictionary, ctx: Dictionary) -> Dictionary:
	var player_name := str(ctx.get("player_name", ""))
	return {
		"name": player_name,
		"namek": (", " + player_name) if not player_name.is_empty() else "",
		"gooby": str(ctx.get("nickname", "Gooby")),
		"tage": SoulTriggers.days_known(int(slice.get("firstMetAt", 0)), int(ctx.get("now_ms", 0))),
	}


# ── Gesprächs-Ablauf (Node) ───────────────────────────────────────────────────


func aktiv() -> bool:
	return _panel != null and is_instance_valid(_panel)


## Öffentlicher Einstieg (SeeleRunner.stoss_gruss ruft mit JEDER Betreten-
## Moment-Id): passt ein Gespräch und würfelt die Chance, erscheinen die
## Ebene-1-Chips. true = Gespräch läuft.
func starte(anlass_id: String) -> bool:
	if aktiv() or seele == null or _ui_layer() == null:
		return false
	var gespraech := fuer_anlass(_gespraeche, anlass_id)
	if gespraech.is_empty():
		return false
	var rng: RandomNumberGenerator = seele.runner.rng
	if rng.randf() >= float(gespraech.get("chance", 1.0)):
		return false
	_ebene = 1
	_zeige_chips(gespraech)
	return true


## Line über den W14/UIKERN-Vertrag anzeigen UND brabbeln lassen (synchron
## wie bisher: Bubble + GoobyVoice). Fallback ohne (kompilierendes)
## AcBubble: der vorhandene room.say-Weg über runner._say.
func zeige_linie(text: String, emotion: String, stil: String) -> void:
	if text.is_empty() or seele == null:
		return
	var runner: Node = seele.runner
	var ac := _ac_bubble_script()
	if ac != null and ac.can_instantiate() and _ui_layer() != null:
		ac.call("show_bubble", _ui_layer(), text, {"speaker_3d": runner.gooby, "stil": stil})
		seele.sagt(text, emotion)
		return
	runner._say(text, emotion)


## Kleiner sichtbarer Wetter-FX zur Wetter-Line (W14: Wetter-Kommentare
## bekommen einen Funken Sichtbarkeit) — reine CPU-Partikel, kein Asset.
func wetter_fx(typ: String) -> void:
	if seele == null or not bool(seele.runner.visuals_enabled):
		return
	var gooby: Node3D = seele.runner.gooby
	var room: Node = seele.runner.room
	if gooby == null or room == null:
		return
	var farben := {
		"sonne": Color(1.0, 0.85, 0.3),
		"wolken": Color(0.85, 0.87, 0.92),
		"niesel": Color(0.55, 0.7, 0.95),
		"regen": Color(0.45, 0.62, 0.95),
		"gewitter": Color(0.95, 0.9, 0.5),
		"nebel": Color(0.8, 0.8, 0.85),
		"schnee": Color(0.98, 0.98, 1.0),
	}
	if not farben.has(typ):
		return
	var particles := CPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 1.4
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.direction = Vector3.UP if typ == "sonne" else Vector3.DOWN
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 1.1
	particles.gravity = Vector3(0.0, -0.6 if typ != "sonne" else 0.2, 0.0)
	particles.spread = 55.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.02
	mesh.height = 0.04
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farben[typ]
	mat.emission_enabled = true
	mat.emission = farben[typ]
	mesh.material = mat
	particles.mesh = mesh
	particles.position = gooby.global_position + Vector3(0.0, 1.1, 0.0)
	room.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _ui_layer() -> CanvasLayer:
	if seele == null or seele.runner == null:
		return null
	var room: Node = seele.runner.room
	if room == null or not room.has_method("ui_layer"):
		return null
	return room.ui_layer()


## G4/P23 (HUD-Report H1/H3) — Chips auf den UIKERN-Vertrag: SquishButton in
## AcChip-Optik (Squish + Tap-Haptik zentral), physischer 44-pt-Floor über
## ScreenShell, Position aus Safe-Area + UiAnchors-Bottom-Zone (über Goobys
## Bubble rutschen, eigenes Rect reservieren) statt der fixen −132/−72-
## Offsets. Pop-In ist reduced-motion-gated (UiMotion springt dann sofort).
func _zeige_chips(ebene: Dictionary) -> void:
	var layer := _ui_layer()
	if layer == null:
		return
	_chips_weg()
	var panel := PanelContainer.new()
	panel.name = "GoobyGespraechChips"
	panel.theme = ThemeService.theme()
	# Die AC-Optik tragen die Chips selbst — das Panel ist reine Geometrie.
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	for antwort: Variant in antworten(ebene):
		if not (antwort is Dictionary):
			continue
		var chip := SquishButton.new()
		chip.theme_type_variation = &"AcChip"
		chip.text = I18nService.t(str((antwort as Dictionary).get("label_key", "")))
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(_on_antwort.bind(antwort as Dictionary))
		row.add_child(chip)
	layer.add_child(panel)
	_panel = panel
	_chips_positionieren()
	var vp := panel.get_viewport()
	if vp != null and not vp.size_changed.is_connected(_chips_positionieren):
		vp.size_changed.connect(_chips_positionieren)
	UiMotion.pop_in(panel)
	# Nicht antworten ist okay — die Chips gehen von allein wieder.
	_timeout = get_tree().create_timer(CHIP_TIMEOUT_S)
	_timeout.timeout.connect(_on_chip_timeout)


## Geometrie-Pass der Chip-Zeile (initial + bei Rotation): Schriften und
## Separation × f, Touch-Floor je Chip, dann unten mittig IN der Safe-Area
## andocken und per UiAnchors über belegte Bottom-Rects (Sprechblase)
## rutschen — anschließend die eigene Fläche reservieren, damit Bubbles/
## Toasts ihrerseits ausweichen.
func _chips_positionieren() -> void:
	if _panel == null or not is_instance_valid(_panel) or not _panel.is_inside_tree():
		return
	var m := ScreenShell.metrics(_panel.get_viewport())
	var f: float = m["f"]
	ScreenShell.scale_fonts(_panel, f)
	var row := _panel.get_child(0) as HBoxContainer
	row.add_theme_constant_override("separation", int(CHIP_SEPARATION * f))
	for chip in row.get_children():
		if chip is Control:
			ScreenShell.touch_target(chip as Control, m)
	var groesse := _panel.get_combined_minimum_size()
	var canvas: Vector2 = m["canvas"]
	var insets: Dictionary = m["insets"]
	var unten := canvas.y - float(insets["bottom"]) - CHIP_RAND_GAP * f
	var ziel := Vector2((canvas.x - groesse.x) / 2.0, unten - groesse.y)
	var rect := Rect2(ziel, groesse)
	rect = UiAnchors.dodge(
		rect, UiAnchors.occupied_rects(UiAnchors.ZONE_BOTTOM, _panel), UiAnchors.ZONE_BOTTOM
	)
	rect.position.x = maxf(rect.position.x, float(insets["left"]) + CHIP_RAND_GAP * f)
	_panel.size = groesse
	_panel.position = rect.position
	UiAnchors.reserve(UiAnchors.ZONE_BOTTOM, _panel)


func _on_chip_timeout() -> void:
	_timeout = null
	_chips_weg()
	_ebene = 0


func _chips_weg() -> void:
	if _panel != null and is_instance_valid(_panel):
		# H1: Bottom-Zone wieder freigeben, sonst weichen Bubbles einem
		# toten Rect aus, bis der Prune greift.
		UiAnchors.release(UiAnchors.ZONE_BOTTOM, _panel)
		_panel.queue_free()
	_panel = null


func _on_antwort(antwort: Dictionary) -> void:
	_chips_weg()
	if seele == null:
		return
	var runner: Node = seele.runner
	var rng: RandomNumberGenerator = runner.rng
	var now_ms: int = runner._now_ms()
	# Antwort wirkt: Laune-Stups (gedeckelt über SoulMood.bump, bewusst ohne
	# Gefühls-Kopplung — das Follow-up spricht selbst) + Slice-Eintrag.
	var laune := float(antwort.get("laune", 0.0))
	if not is_zero_approx(laune):
		seele._stoss_wert(laune)
	var gespraech_id := _aktuelles_gespraech_id(antwort)
	SoulState.mutate(
		runner.gs,
		func(s: Dictionary) -> void:
			s["gespraeche"] = merke_antwort(s.get("gespraeche", {}), gespraech_id, antwort, now_ms)
	)
	AudioDirector.try_play(self, "ui_confirm")
	# Follow-up-Line (Variante per Roll) — Bubble + Gebrabbel synchron.
	var key := folge_key(antwort, rng.randf())
	if not key.is_empty():
		var ctx: Dictionary = runner._ctx(0)
		var slice := SoulState.slice_of(runner.gs)
		zeige_linie(
			I18nService.t(key, text_args(slice, ctx)),
			str(antwort.get("emotion", "happy")),
			str(antwort.get("stil", "gooby"))
		)
	# Ebene 2 (Maximum): nach einer Atempause die nächsten Chips.
	var weiter := naechste_ebene(antwort)
	if weiter.is_empty() or _ebene >= MAX_EBENEN:
		_ebene = 0
		return
	_ebene += 1
	var pause := get_tree().create_timer(EBENE2_PAUSE_S)
	pause.timeout.connect(_zeige_chips.bind(weiter))


## Id des Gespräches, zu dem eine Antwort gehört (für den Slice-Eintrag —
## über die label_key-Domäne rekonstruiert, damit auch Ebene-2-Antworten
## beim richtigen Gespräch landen).
func _aktuelles_gespraech_id(antwort: Dictionary) -> String:
	var teile := str(antwort.get("label_key", "")).split(".")
	return teile[1] if teile.size() >= 2 else ""


## Den W14/UIKERN-AcBubble finden, sobald er gelandet ist (Parallel-Vertrag;
## Lookup über die globale Klassenliste statt Preload — kein harter Bruch,
## solange die Datei noch fehlt).
static func _ac_bubble_script() -> Script:
	for eintrag: Dictionary in ProjectSettings.get_global_class_list():
		if str(eintrag.get("class", "")) == "AcBubble":
			return load(str(eintrag.get("path", "")))
	return null

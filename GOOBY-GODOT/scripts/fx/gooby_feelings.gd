class_name GoobyFeelings
extends Node3D
## FEEL-AC — Emotions-Player ÜBER dem GoobyRig (Animal-Crossing-Inszenierung).
## Hängt als Kind am Rig (läuft im Frame NACH ihm) und spielt die 12
## FeelEmotions-Pakete voll aus:
##  - GESICHT über rig.set_expression_override (Mix auf den vorhandenen
##    emotion_*-Shapekeys — der Rig-Vertrag bleibt unangetastet),
##  - EXTRA-Shapekeys (mouth_open, eye_size-Boost) mit Snapshot/Restore —
##    Spieler-Morphs kommen exakt zurück,
##  - KÖRPERPOSE (Ohren/Kopf/Arme) über dieselbe Override-API,
##  - BEWEGUNG (Zusammenzucken, Hüpfen, Zittern, Stampfen, …) als Tweens
##    auf dem Rig-Transform — Basis wird IMMER restauriert,
##  - EMOTE-SYMBOL über dem Kopf (EmoteSymbol, Pop-in/out),
##  - TON (SfxMap-Id) und DAUER aus dem Def,
##  - starke Emotionen zusätzlich über die MomentRegie (Zoom/Zeitlupe/
##    Farbakzent — sparsam per Cooldown).
## Reduced Motion: Bewegungs-Beats entfallen, Zustand (Gesicht/Pose/Symbol)
## bleibt — die Emotion bleibt lesbar.

signal gefuehl_beendet(id: String)

## Einblend-Tempo der Extra-Shapekeys (wie Rig-Emotionen: ~0,25 s).
const EXTRA_RAMPE_PRO_S := 4.0
## Abstand Symbol ↔ Scheitel (Ohrenspitzen).
const KOPF_MARGE_M := 0.22
## Fallback/Grenzen für die Symbolhöhe über dem Rig-Ursprung.
const SYMBOL_HOEHE_FALLBACK_M := 1.4
const SYMBOL_HOEHE_MIN_M := 1.1
const SYMBOL_HOEHE_MAX_M := 1.9

var rig: GoobyRig = null
## Tests: −1 = AppSettings fragen, 0 = aus, 1 = an.
var reduced_motion_override := -1

var _aktiv := ""
var _rest_s := 0.0
var _symbol: EmoteSymbol = null
var _regie: MomentRegie = null
var _extra_snapshot: Dictionary = {}
var _extra_ziel: Dictionary = {}
var _extra_fortschritt := 0.0
var _beweg_tween: Tween = null
var _basis: Transform3D = Transform3D.IDENTITY


## Schicht erzeugen und ans Rig hängen (idempotent).
static func attach_to(target_rig: GoobyRig) -> GoobyFeelings:
	var existing := target_rig.get_node_or_null("GoobyFeelings")
	if existing is GoobyFeelings:
		return existing
	var layer := GoobyFeelings.new()
	layer.name = "GoobyFeelings"
	target_rig.add_child(layer)
	layer.setup(target_rig)
	return layer


func setup(target_rig: GoobyRig) -> void:
	rig = target_rig
	_regie = MomentRegie.new()
	_regie.name = "MomentRegie"
	add_child(_regie)


## Emotion voll inszenieren (true = angenommen). Läuft bereits eine, wird
## sie sauber beendet (Restore) und die neue startet sofort.
func zeige(id: String) -> bool:
	if rig == null or not FeelEmotions.kennt(id):
		if rig != null:
			push_warning("GoobyFeelings.zeige: unbekannte Emotion '%s'" % id)
		return false
	if not _aktiv.is_empty():
		_beende(false)
	var def := FeelEmotions.def_of(id)
	_aktiv = id
	_rest_s = float(def["dauer_s"])
	rig.set_expression_override(def["gesicht"], def["pose"])
	_starte_extras(def["extra"])
	_zeige_symbol(str(def["symbol"]))
	var sfx := str(def["sfx"])
	if not sfx.is_empty():
		AudioDirector.try_play(self, sfx)
	_basis = rig.transform
	if not _reduziert():
		_starte_bewegung(str(def["bewegung"]), _rest_s)
	if bool(def["stark"]) and _regie != null:
		_regie.inszeniere(rig, def["farbe"])
	return true


## Laufende Emotion vorzeitig beenden (Restore inklusive).
func beende() -> void:
	if not _aktiv.is_empty():
		_beende(true)


func aktiv() -> bool:
	return not _aktiv.is_empty()


func aktuelle() -> String:
	return _aktiv


func symbol_node() -> EmoteSymbol:
	return _symbol


func regie() -> MomentRegie:
	return _regie


func rest_s() -> float:
	return _rest_s


func _process(delta: float) -> void:
	if _aktiv.is_empty():
		return
	if _extra_fortschritt < 1.0:
		_extra_fortschritt = minf(_extra_fortschritt + EXTRA_RAMPE_PRO_S * delta, 1.0)
	# Extra-Kanäle NACH dem Rig schreiben (Kind läuft im selben Frame später).
	for shape: String in _extra_ziel:
		var von := float(_extra_snapshot.get(shape, 0.0))
		_setze_shape(shape, lerpf(von, float(_extra_ziel[shape]), _extra_fortschritt))
	_rest_s -= delta
	if _rest_s <= 0.0:
		_beende(true)


# ── Innenleben ────────────────────────────────────────────────────────────────


func _beende(melden: bool) -> void:
	var id := _aktiv
	_aktiv = ""
	_rest_s = 0.0
	rig.clear_expression_override()
	for shape: String in _extra_snapshot:
		_setze_shape(shape, float(_extra_snapshot[shape]))
	_extra_snapshot = {}
	_extra_ziel = {}
	if _symbol != null and is_instance_valid(_symbol):
		_symbol.verschwinde()
	_symbol = null
	_stoppe_bewegung()
	if melden:
		gefuehl_beendet.emit(id)


func _starte_extras(extra: Dictionary) -> void:
	_extra_snapshot = {}
	_extra_ziel = {}
	_extra_fortschritt = 0.0
	for shape: String in extra:
		var aktuell := _lese_shape(shape)
		_extra_snapshot[shape] = aktuell
		var ziel := float(extra[shape])
		if shape == "eye_size":
			# Boost RELATIV zum Spieler-Morph (Restore = exakter Snapshot).
			ziel = clampf(aktuell + ziel, -1.2, 1.2)
		_extra_ziel[shape] = ziel


func _zeige_symbol(symbol: String) -> void:
	if symbol.is_empty():
		return
	_symbol = EmoteSymbol.erzeuge(symbol, _reduziert())
	_symbol.position = Vector3(0.0, _symbol_hoehe_m(), 0.0)
	add_child(_symbol)


## Scheitelhöhe aus der Mesh-AABB (geklammert) — das Symbol sitzt knapp
## über den Ohrenspitzen, egal welche Morphs der Spieler gewählt hat.
func _symbol_hoehe_m() -> float:
	var hoehe := SYMBOL_HOEHE_FALLBACK_M
	var mesh: MeshInstance3D = rig._mesh
	if mesh != null and mesh.is_inside_tree() and is_inside_tree():
		var aabb := mesh.get_aabb()
		var oben_welt := (mesh.global_transform * (aabb.position + aabb.size)).y
		hoehe = oben_welt - global_position.y + KOPF_MARGE_M
	return clampf(hoehe, SYMBOL_HOEHE_MIN_M, SYMBOL_HOEHE_MAX_M)


func _lese_shape(shape: String) -> float:
	var mesh: MeshInstance3D = rig._mesh
	if mesh == null:
		return 0.0
	var idx := mesh.find_blend_shape_by_name(shape)
	if idx < 0:
		return 0.0
	return mesh.get_blend_shape_value(idx)


func _setze_shape(shape: String, wert: float) -> void:
	var mesh: MeshInstance3D = rig._mesh
	if mesh == null:
		return
	var idx := mesh.find_blend_shape_by_name(shape)
	if idx >= 0:
		mesh.set_blend_shape_value(idx, wert)


# ── Bewegungs-Beats (immer Basis-restaurierend) ───────────────────────────────


func _starte_bewegung(art: String, dauer_s: float) -> void:
	_stoppe_bewegung()
	if art.is_empty():
		return
	# W13C (Request CLIPS): „tanzen" ist ein ECHTER Rig-Clip (P1 dance,
	# 1,2 s = 2 Beats), kein Transform-Tween — play_clip_for kehrt nach
	# dauer_s selbst nach „move" zurück; VOR create_tween(), weil ein
	# Tweener-loser Tween sonst Laufzeit-Fehler wirft.
	if art == "tanzen":
		rig.play_clip_for(GoobyRig.CLIP_DANCE, dauer_s)
		return
	_beweg_tween = create_tween()
	var t := _beweg_tween
	match art:
		"zucken":
			t.set_parallel(true)
			t.tween_property(rig, "position", _basis.origin + Vector3(0, 0.12, -0.2), 0.09)
			t.tween_property(rig, "scale:y", 1.14, 0.09)
			t.set_parallel(false)
			t.tween_property(rig, "position", _basis.origin + Vector3(0, 0.0, -0.12), 0.1)
			t.tween_property(rig, "scale:y", 0.88, 0.07)
			t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(rig, "scale:y", 1.0, 0.25)
			t.tween_property(rig, "position", _basis.origin, 0.3)
		"huepfen":
			for _i in 3:
				t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				t.tween_property(rig, "position:y", _basis.origin.y + 0.16, 0.18)
				t.set_ease(Tween.EASE_IN)
				t.tween_property(rig, "position:y", _basis.origin.y, 0.16)
				t.tween_property(rig, "scale:y", 0.92, 0.05)
				t.tween_property(rig, "scale:y", 1.0, 0.08)
		"wippen":
			for _i in 2:
				t.tween_property(rig, "position:y", _basis.origin.y + 0.05, 0.22)
				t.tween_property(rig, "position:y", _basis.origin.y, 0.2)
		"aufrichten":
			t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(rig, "scale:y", 1.08, 0.16)
			t.parallel().tween_property(rig, "position:y", _basis.origin.y + 0.05, 0.16)
			t.tween_interval(maxf(dauer_s - 0.7, 0.2))
			t.tween_property(rig, "scale:y", 1.0, 0.25)
			t.parallel().tween_property(rig, "position:y", _basis.origin.y, 0.25)
		"abwenden":
			t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(rig, "rotation:y", _basis.basis.get_euler().y + 0.55, 0.35)
			t.tween_interval(maxf(dauer_s - 1.0, 0.2))
			t.tween_property(rig, "rotation:y", _basis.basis.get_euler().y, 0.4)
		"stampfen":
			for _i in 2:
				t.tween_property(rig, "scale:y", 0.85, 0.09)
				t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				t.tween_property(rig, "scale:y", 1.0, 0.14)
				t.tween_interval(0.12)
		"sacken":
			t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(rig, "scale:y", 0.95, 0.7)
			t.tween_interval(maxf(dauer_s - 1.3, 0.2))
			t.tween_property(rig, "scale:y", 1.0, 0.5)
		"nicken":
			for _i in 2:
				t.tween_property(rig, "rotation:x", 0.08, 0.5)
				t.tween_property(rig, "rotation:x", 0.0, 0.45)
		"neigen":
			t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(rig, "rotation:z", 0.14, 0.3)
			t.tween_interval(maxf(dauer_s - 0.9, 0.2))
			t.tween_property(rig, "rotation:z", 0.0, 0.35)
		"strecken":
			t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(rig, "scale", Vector3.ONE * 1.07, 0.3)
			t.tween_interval(maxf(dauer_s - 0.9, 0.2))
			t.tween_property(rig, "scale", Vector3.ONE, 0.3)
		"zittern":
			var zyklen := maxi(int((dauer_s - 0.4) / 0.14), 2)
			t.set_loops(zyklen)
			t.tween_property(rig, "position:x", _basis.origin.x + 0.02, 0.07)
			t.tween_property(rig, "position:x", _basis.origin.x - 0.02, 0.07)
		"schweben":
			for _i in 2:
				t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				t.tween_property(rig, "rotation:z", 0.06, 0.7)
				t.tween_property(rig, "rotation:z", -0.06, 0.7)
		_:
			push_warning("GoobyFeelings: unbekannte Bewegung '%s'" % art)


func _stoppe_bewegung() -> void:
	if _beweg_tween != null and _beweg_tween.is_valid():
		_beweg_tween.kill()
	_beweg_tween = null
	if rig == null:
		return
	# Basis exakt zurück (weich, kurz) — nie in schiefer Pose hängen bleiben.
	var zurueck := create_tween()
	zurueck.set_parallel(true)
	zurueck.tween_property(rig, "position", _basis.origin, 0.18)
	zurueck.tween_property(rig, "scale", _basis.basis.get_scale(), 0.18)
	zurueck.tween_property(rig, "rotation", _basis.basis.get_euler(), 0.18)


func _reduziert() -> bool:
	if reduced_motion_override >= 0:
		return reduced_motion_override == 1
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()

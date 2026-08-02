class_name HudSichtbarkeit
extends Node
## G7-P50 HUD-DYNAMIK: das HUD WEICHT dynamisch, statt Fremd-UI zu überdecken
## (User-Screenshots vom echten iPhone: „Knopf-Salat" im Baumodus, Blätter
## kollidieren optisch mit Status-Leisten/Kacheln):
## - Baumodus: alle HUD-Teile GLEITEN animiert aus dem Bild (Kacheln
##   staffeln zur nahen Kante raus, Status-Spalte nach links, TopBar nach
##   oben), beim Verlassen federn sie zurück (Stil RUTSCH).
## - Offene Blätter (PanelSheet): das HUD blendet weich aus und kommt erst
##   beim Schließen des LETZTEN Blatts zurück (Stil BLENDE). ZÄHLER statt
##   Bool — zwei Blätter nacheinander/verschachtelt bleiben robust, ebenso
##   „Blatt während Baumodus" (zwei unabhängige Verdeckungs-Gründe, ODER).
## - Eingaben sind während der Verdeckung deaktiviert (Buttons disabled +
##   mouse_filter IGNORE); Reduced Motion = sofort statt Tween.
##
## Hook-Entscheidung (bewusst OHNE fremde Hunks): BuildMode besitzt bereits
## `opened`/`closed`, PanelSheet bereits `opened`/`closed` — dieser Helfer
## findet beide SELBST über `SceneTree.node_added` und abonniert die
## Signale; `tree_exiting` fängt Nodes ab, die OFFEN freigegeben werden
## (sonst bliebe das HUD nach einem Raumwechsel im Baumodus verschluckt).
## Das HUD-eigene Status-Sheet (Kind des HUD) zählt NICHT — es würde sonst
## mit dem HUD verschwinden.
##
## Layout-Verzahnung: `Hud.apply_layout` setzt Teil-Sichtbarkeiten selbst
## (Dock vs. Cockpit) — deshalb ruft das HUD `vor_layout()` (Tween kappen,
## Ruhelage herstellen) und `nach_layout()` (Verdeckung erneut erzwingen,
## Soll-Sichtbarkeit des frischen Layouts merken) um jeden Layout-Pass.

enum Stil { RUTSCH, BLENDE }

## Ausblenden zügig (Web --dur-pop), Einblenden federnd etwas länger
## (Web --dur-sheet) — beides im 150–250-ms-Fenster des Pakets.
const DAUER_AUS := 0.18
const DAUER_EIN := 0.24
## Kachel-Staffelung: kurze Einzel-Blenden, versetzt gestartet.
const KACHEL_BLENDE := 0.12
const KACHEL_STAFFEL := 0.015
## Rutsch-Reserve über die Teilgröße hinaus (deckt Safe-Area + Schatten).
const RUTSCH_LUFT := 80.0
## Meta-Schlüssel-Präfix gegen Doppel-Verbindungen (pro Helfer-Instanz —
## Tests fahren mehrere HUDs nacheinander im selben Baum hoch).
const VERBUNDEN_META_PREFIX := "_hud_dyn_"

var _hud: Control
## Teil → Rutsch-Richtung (Vector2), gestellt vom HUD in setup().
var _teile: Dictionary = {}
## Interaktive Controls, die bei Verdeckung gesperrt werden.
var _eingaben: Array[Control] = []
## Aktions-Kacheln für die Staffel-Blende (Dock-/Cockpit-Knöpfe).
var _kacheln: Array[Control] = []
var _aktive_baumodi: Array[Node] = []
var _offene_blaetter: Array[Node] = []
var _verdeckt := false
## Sichtbarkeit, die das LAYOUT für jedes Teil will (Snapshot vor dem
## Verstecken bzw. nach jedem Layout-Pass) — Rotation im verdeckten
## Zustand darf beim Zurückkommen kein falsches Teil einblenden.
var _soll_sichtbar: Dictionary = {}
## Offsets der Teile vor einem Rutsch-Tween (Ruhelage-Wiederherstellung).
var _offset_backup: Dictionary = {}
var _filter_backup: Dictionary = {}
var _tween: Tween


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


## Verdrahtung durch das HUD: Wurzel (für den Eigen-Sheet-Ausschluss),
## Teile mit Rutsch-Richtungen, sperrbare Eingaben, Staffel-Kacheln.
func setup(
	hud: Control, teile: Dictionary, eingaben: Array[Control], kacheln: Array[Control]
) -> void:
	_hud = hud
	_teile = teile
	_eingaben = eingaben
	_kacheln = kacheln


func verdeckt() -> bool:
	return _verdeckt


func bau_aktiv() -> bool:
	return not _aktive_baumodi.is_empty()


func blatt_zaehler() -> int:
	return _offene_blaetter.size()


## VOR jedem Layout-Pass des HUD: laufende Bewegung kappen und die
## Ruhelage-Offsets herstellen, damit das Layout nie mit halb
## verschobenen Teilen rechnet.
func vor_layout() -> void:
	_kill_tween()
	_stelle_offsets_wieder_her()


## NACH jedem Layout-Pass: apply_layout blendet Dock/Spalte selbst wieder
## ein — bei Verdeckung sofort erneut verstecken (und die frische
## Soll-Sichtbarkeit fürs spätere Zurückkommen merken).
func nach_layout() -> void:
	if _verdeckt:
		_merke_soll_sichtbarkeit()
		_verstecke_sofort()
	else:
		_normalisiere_optik()


func _on_node_added(node: Node) -> void:
	if node is BuildMode:
		_verbinde_baumodus(node)
	elif node is PanelSheet:
		_verbinde_blatt(node)


func _verbinde_baumodus(bau: Node) -> void:
	var meta := StringName(VERBUNDEN_META_PREFIX + str(get_instance_id()))
	if bau.has_meta(meta):
		return
	bau.set_meta(meta, true)
	bau.opened.connect(_on_bau_geoeffnet.bind(bau))
	bau.closed.connect(_on_bau_geschlossen.bind(bau))
	bau.tree_exiting.connect(_on_bau_geschlossen.bind(bau))


func _verbinde_blatt(blatt: Node) -> void:
	var meta := StringName(VERBUNDEN_META_PREFIX + str(get_instance_id()))
	if blatt.has_meta(meta):
		return
	blatt.set_meta(meta, true)
	blatt.opened.connect(_on_blatt_geoeffnet.bind(blatt))
	blatt.closed.connect(_on_blatt_geschlossen.bind(blatt))
	blatt.tree_exiting.connect(_on_blatt_geschlossen.bind(blatt))


func _on_bau_geoeffnet(bau: Node) -> void:
	if not _aktive_baumodi.has(bau):
		_aktive_baumodi.append(bau)
	_apply(Stil.RUTSCH)


func _on_bau_geschlossen(bau: Node) -> void:
	_aktive_baumodi.erase(bau)
	_apply(Stil.RUTSCH)


func _on_blatt_geoeffnet(blatt: Node) -> void:
	# HUD-eigenes Status-Sheet hängt UNTER dem HUD — nicht zählen, sonst
	# blendet das HUD sich (und damit das Blatt) selbst aus.
	if _hud != null and _hud.is_ancestor_of(blatt):
		return
	if not _offene_blaetter.has(blatt):
		_offene_blaetter.append(blatt)
	_apply(Stil.BLENDE)


func _on_blatt_geschlossen(blatt: Node) -> void:
	_offene_blaetter.erase(blatt)
	_apply(Stil.BLENDE)


## Effektiver Zustand = Baumodus ODER ≥1 offenes Blatt. Nur ÜBERGÄNGE
## animieren — der Stil des Auslösers bestimmt die Animation.
func _apply(stil: int) -> void:
	var ziel := bau_aktiv() or blatt_zaehler() > 0
	if ziel == _verdeckt:
		return
	_verdeckt = ziel
	if ziel:
		_verstecke(stil)
	else:
		_zeige(stil)


func _verstecke(stil: int) -> void:
	_merke_soll_sichtbarkeit()
	_setze_eingaben(false)
	if ThemeService.is_reduced_motion(self):
		_verstecke_sofort()
		return
	var tween := _frischer_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var kachel_eltern := _kachel_eltern()
	for teil: Control in _teile:
		if not teil.visible:
			continue
		if stil == Stil.RUTSCH:
			_sichere_offsets(teil)
			var ziel: Vector2 = teil.position + (_teile[teil] as Vector2) * _rutsch_weite(teil)
			tween.tween_property(teil, "position", ziel, DAUER_AUS)
			# Der Kachel-Container verblasst NICHT als Block — sonst
			# schluckt sein Fade die Staffelung der Einzel-Kacheln.
			if kachel_eltern.has(teil):
				continue
		tween.tween_property(teil, "modulate:a", 0.0, DAUER_AUS)
	if stil == Stil.RUTSCH:
		# Kacheln staffeln raus (User-Wunsch: „Buttons verschwinden" —
		# sichtbar nacheinander statt als ein Block).
		for i in _kacheln.size():
			var blende := tween.tween_property(_kacheln[i], "modulate:a", 0.0, KACHEL_BLENDE)
			blende.set_delay(float(i) * KACHEL_STAFFEL)
	tween.chain().tween_callback(_nach_ausblenden)


func _zeige(stil: int) -> void:
	_setze_eingaben(true)
	_stelle_offsets_wieder_her()
	for teil: Control in _teile:
		if _soll_sichtbar.has(teil):
			teil.visible = _soll_sichtbar[teil]
	if ThemeService.is_reduced_motion(self):
		_normalisiere_optik()
		return
	var tween := _frischer_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var kachel_eltern := _kachel_eltern()
	for teil: Control in _teile:
		if not teil.visible:
			continue
		if stil == Stil.RUTSCH:
			_sichere_offsets(teil)
			var rest := teil.position
			teil.position = rest + (_teile[teil] as Vector2) * _rutsch_weite(teil)
			tween.tween_property(teil, "position", rest, DAUER_EIN)
			if kachel_eltern.has(teil):
				continue
		teil.modulate.a = 0.0
		var blende := tween.tween_property(teil, "modulate:a", 1.0, DAUER_EIN / 2.0)
		blende.set_trans(Tween.TRANS_LINEAR)
	if stil == Stil.RUTSCH:
		for i in _kacheln.size():
			_kacheln[i].modulate.a = 0.0
			var kachel := tween.tween_property(_kacheln[i], "modulate:a", 1.0, KACHEL_BLENDE)
			kachel.set_delay(float(i) * KACHEL_STAFFEL)
			kachel.set_trans(Tween.TRANS_LINEAR)
	tween.chain().tween_callback(_nach_einblenden)


## Eltern-Container der Staffel-Kacheln (Dock/Cockpit-Spalte) — die rutschen
## nur, ihre Deckkraft gehört den Einzel-Kacheln.
func _kachel_eltern() -> Dictionary:
	var eltern := {}
	for kachel in _kacheln:
		if kachel.get_parent() != null:
			eltern[kachel.get_parent()] = true
	return eltern


## Rutsch-Distanz: Teilgröße entlang der Richtung + Reserve — das Teil
## verlässt den Canvas sicher (inkl. Safe-Area/Schattenluft).
func _rutsch_weite(teil: Control) -> float:
	var richtung: Vector2 = _teile[teil]
	return absf(richtung.x) * teil.size.x + absf(richtung.y) * teil.size.y + RUTSCH_LUFT


func _merke_soll_sichtbarkeit() -> void:
	for teil: Control in _teile:
		_soll_sichtbar[teil] = teil.visible


func _verstecke_sofort() -> void:
	for teil: Control in _teile:
		teil.visible = false
	_normalisiere_optik()


## Deckkraft-Reste aus gekappten Tweens abräumen (Teile UND Kacheln).
func _normalisiere_optik() -> void:
	for teil: Control in _teile:
		teil.modulate.a = 1.0
	for kachel in _kacheln:
		kachel.modulate.a = 1.0


func _nach_ausblenden() -> void:
	_stelle_offsets_wieder_her()
	_verstecke_sofort()


func _nach_einblenden() -> void:
	_stelle_offsets_wieder_her()
	_normalisiere_optik()


func _sichere_offsets(teil: Control) -> void:
	if not _offset_backup.has(teil):
		_offset_backup[teil] = [
			teil.offset_left, teil.offset_top, teil.offset_right, teil.offset_bottom
		]


func _stelle_offsets_wieder_her() -> void:
	for teil: Control in _offset_backup:
		var offsets: Array = _offset_backup[teil]
		teil.offset_left = offsets[0]
		teil.offset_top = offsets[1]
		teil.offset_right = offsets[2]
		teil.offset_bottom = offsets[3]
	_offset_backup.clear()


## Eingaben sperren/freigeben: Buttons disabled + mouse_filter IGNORE
## (Status-Kapseln sind PanelContainer mit gui_input — nur der Filter
## greift dort). Fokus wird beim Sperren sauber abgegeben.
func _setze_eingaben(aktiv: bool) -> void:
	for ctl in _eingaben:
		if ctl is BaseButton:
			(ctl as BaseButton).disabled = not aktiv
		if aktiv:
			if _filter_backup.has(ctl):
				ctl.mouse_filter = _filter_backup[ctl]
		else:
			if not _filter_backup.has(ctl):
				_filter_backup[ctl] = ctl.mouse_filter
			ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if aktiv:
		_filter_backup.clear()
	elif _hud != null and _hud.is_inside_tree():
		_hud.get_viewport().gui_release_focus()


func _frischer_tween() -> Tween:
	_kill_tween()
	_tween = create_tween().set_parallel()
	return _tween


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

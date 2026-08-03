class_name HudIconBuehne
extends Control
## G8/IDEA-J2 — Icon-Bühne: der STRUKTURELLE Fix für die Querformat-HUD-
## Labels (PT4-B4 „Albu/IGohb/Garde/Gestal/Arcad“). Im Cockpit (quer) sind
## die Kacheln ICON-ONLY — die Beschriftung wandert in NAMENSSCHILDER
## (Frost-Pills, `namensschild.gd`) auf einer Schilder-Schiene LINKS neben
## dem Kachel-Block:
##  (a) Namensschild-Parade beim ersten Quer-Layout einer Session: alle
##      Schilder gleiten gestaffelt heraus, stehen ~1,5 s, gleiten zurück
##      (Reduced Motion: einmal statisch zeigen, dann weg).
##  (b) Langdruck auf einer Kachel (~0,4 s, `langdruck_geste.gd`): das
##      Schild der Kachel erscheint, solange gehalten wird; der Release
##      wird geschluckt (öffnet KEINE App). Kurzer Tap bleibt ein Tap.
##  (c) Dauerschilder, solange der Coachmark „Deine Knöpfe“ auf die Spalte
##      zeigt — kompakt über die gepflegten `hud.<id>.kurz`-Strings.
##
## Anbindung (hud.gd bleibt unter Budget): `HudIconBuehne.anbringen(hud,
## buttons, spalte)` hängt die Bühne als eigenes Overlay ins HUD und
## verdrahtet die Kachel-Events selbst; hud.gd ruft nur `nach_layout()`,
## `dauerschilder()`, `dauerschild_breite()` und `schluckt_tap()`.
## Schilder sind mouse_filter-IGNORE und KEINE Buttons — Tippflächen- und
## Überlapp-Wachen (fb3_ui_audit) bleiben unberührt; die Schienen-Geometrie
## selbst ist PURE Logik (`rest_plan`/`entzerre`, headless testbar) und
## kollisionsfrei per Konstruktion.

## Luft zwischen Schilder-Schiene und Kachel-Block (Design-px × f).
const LUFT_PX := 10.0
## Einschub-Weg der Parade (Schild gleitet Richtung Schiene, Design-px × f).
const EINSCHUB_PX := 28.0
## Vertikale Luft zwischen den zwei Schildern einer 2-Spalten-Zeile.
const SLOT_LUFT_PX := 4.0
## Mindest-Luft der Entzerrung (Schilder kollidieren NIE, Canvas-px).
const MIN_LUFT_PX := 2.0
## Rand zur Safe-Area (EDGE_PAD-Parität mit hud.gd).
const RAND_PX := 8.0
## Parade-Choreografie (Sekunden).
const EIN_S := 0.24
const STEH_S := 1.5
const AUS_S := 0.2
const STAFFEL_S := 0.12
## Reduced Motion: einmal statisch zeigen, dann räumen.
const RM_STEH_S := 2.6
## Geduld der Parade-Anbahnung: der erste Quer-Moment einer Session ist
## selten „sauber“ (Tagesbonus-Popup/Guide-Tour verdecken kurz) — solange
## pollt die Bühne, statt die Einmal-Chance zu verschenken.
const PARADE_WARTE_S := 12.0
## Langdruck-Wackeltoleranz in PUNKTEN (physisch skaliert, iOS-üblich ~10 pt).
const SLOP_PT := 10.0
## Icon-Wachstum: Innenluft ums Icon und Deckel (SVGs rastern mit 96 px —
## darüber würde die Vergrößerung matschig).
const ICON_LUFT_PX := 6.0
const ICON_DECKEL_PX := 96.0

## Session-Flag: die Parade läuft EINMAL pro Sitzung (statisch, kein Save).
static var _parade_gezeigt := false

var _hud: Control
var _knoepfe: Dictionary = {}
var _spalte: GridContainer
var _geste := HudLangdruckGeste.new()
var _halte_id: StringName = &""
var _lang_schild: HudNamensschild
var _parade_schilder: Array[HudNamensschild] = []
var _dauer_schilder: Array[HudNamensschild] = []
var _dauer_an := false
var _dauer_breite := 0.0
var _tween: Tween


## Bühne erzeugen und ins HUD hängen (idempotent unnötig — hud._ready ruft
## genau einmal). Verdrahtet gui_input ALLER Kacheln für den Langdruck und
## hört auf die HUD-Sichtbarkeit (Parade erst, wenn das HUD wirklich zu
## sehen ist — home_entry blendet es nach dem Onboarding ein).
static func anbringen(hud: Control, knoepfe: Dictionary, spalte: GridContainer) -> HudIconBuehne:
	var buehne := HudIconBuehne.new()
	buehne.name = "IconBuehne"
	buehne._hud = hud
	buehne._knoepfe = knoepfe
	buehne._spalte = spalte
	hud.add_child(buehne)
	for id: StringName in knoepfe:
		var btn: Button = knoepfe[id]
		btn.set_meta("j2_id", String(id))
		btn.gui_input.connect(buehne._on_kachel_input.bind(id))
	hud.visibility_changed.connect(buehne._on_hud_sichtbarkeit)
	return buehne


# ── PURE Logik (deterministisch, headless testbar) ───────────────────────────


## Kachel-Beschriftung beider Layouts (von hud._apply_button_label gerufen):
## Hochkant unverändert (Label in der Kachel, P50-Autoshrink, Ellipsis nur
## als bewusster letzter Ausweg). QUER = Icon-Bühne: KEIN Label in der
## Kachel, Icon mittig und auf die freie Fläche gewachsen — Ellipsis kann
## dort strukturell nicht mehr entstehen (die Wache prüft genau das).
static func beschrifte(
	btn: Button, id: StringName, portrait: bool, f: float, basis_px: int, breite: float
) -> void:
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.clip_text = true
	if not portrait:
		btn.text = ""
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		btn.add_theme_constant_override("icon_max_width", icon_px(btn, f))
		return
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.text = I18nService.t("hud." + String(id))
	var wunsch := int(maxf(float(basis_px) * f, 10.0))
	var fit := HudLabelFit.passende_groesse(btn.get_theme_font("font"), btn.text, wunsch, breite)
	btn.add_theme_font_size_override("font_size", int(fit["px"]))
	btn.text_overrun_behavior = (
		TextServer.OVERRUN_NO_TRIMMING if bool(fit["passt"]) else TextServer.OVERRUN_TRIM_ELLIPSIS
	)


## Icon-Deckel für icon-only Kacheln: wächst auf die Innenfläche der Kachel
## (custom_minimum_size minus StyleBox-Ränder minus Luft), nie kleiner als
## die alte 22×f-Referenz und nie über den SVG-Raster-Deckel.
static func icon_px(btn: Button, f: float) -> int:
	var innen := btn.custom_minimum_size.x
	var stil := btn.get_theme_stylebox("normal")
	if stil != null:
		innen -= stil.get_content_margin(SIDE_LEFT) + stil.get_content_margin(SIDE_RIGHT)
	var alt := maxf(HudLayoutLogic.LANDSCAPE_ICON * f, 16.0)
	return int(maxf(alt, minf(innen - 2.0 * ICON_LUFT_PX, ICON_DECKEL_PX)))


## Ruhelagen der Schilder auf der Schiene links vom Kachel-Block.
## `zellen` = Kachel-Rechtecke (row-major wie im Grid), `spalten` = Grid-
## Spaltenzahl, `groessen` = Schildgrößen in gleicher Reihenfolge. Alle
## Schilder enden rechtsbündig an der Schiene (Blockkante − Luft); bei
## 2 Spalten teilt sich eine Zeile in oben (linke Kachel) und unten
## (rechte Kachel) — Lesereihenfolge = Grid-Reihenfolge.
static func rest_plan(
	zellen: Array, spalten: int, groessen: Array, luft: float, slot_luft: float
) -> Array[Rect2]:
	var block_links := block_kante(zellen)
	var out: Array[Rect2] = []
	for i in zellen.size():
		var zelle: Rect2 = zellen[i]
		var groesse: Vector2 = groessen[i]
		var x := block_links - luft - groesse.x
		var mitte := zelle.position.y + zelle.size.y / 2.0
		var y := mitte - groesse.y / 2.0
		if spalten >= 2:
			if i % spalten == 0:
				y = mitte - slot_luft * 0.5 - groesse.y
			else:
				y = mitte + slot_luft * 0.5
		out.append(Rect2(Vector2(x, y), groesse))
	return out


## Entzerrungs-Pass: Schilder von oben nach unten mit Mindest-Luft
## auseinanderschieben, dann von unten in die Grenze zurückklemmen —
## danach überlappt per Konstruktion KEIN Schild ein anderes (die
## UI-Wache misst das zusätzlich nach).
static func entzerre(rects: Array[Rect2], min_luft: float, grenze: Rect2) -> Array[Rect2]:
	var out := rects.duplicate()
	for i in out.size():
		var r: Rect2 = out[i]
		r.position.x = maxf(r.position.x, grenze.position.x)
		if i > 0:
			var vorher: Rect2 = out[i - 1]
			r.position.y = maxf(r.position.y, vorher.end.y + min_luft)
		out[i] = r
	for i in range(out.size() - 1, -1, -1):
		var r: Rect2 = out[i]
		var deckel := grenze.end.y
		if i < out.size() - 1:
			var nachher: Rect2 = out[i + 1]
			deckel = nachher.position.y - min_luft
		r.position.y = minf(r.position.y, deckel - r.size.y)
		out[i] = r
	return out


## Linke Kante des Kachel-Blocks (Schienen-Anker).
static func block_kante(zellen: Array) -> float:
	var links := INF
	for zelle: Rect2 in zellen:
		links = minf(links, zelle.position.x)
	return links


## Staffel-Verzug des i-ten Parade-Schilds (deterministisch).
static func parade_verzug(i: int) -> float:
	return float(i) * STAFFEL_S


## Gesamtdauer der Parade (letztes Schild komplett raus) — für Flows/Tests.
static func parade_dauer(anzahl: int) -> float:
	if anzahl <= 0:
		return 0.0
	return parade_verzug(anzahl - 1) + EIN_S + STEH_S + AUS_S


static func parade_schon_gezeigt() -> bool:
	return _parade_gezeigt


## Session-Flag setzen (Wachen/Audits, die KEINE Parade wollen).
static func parade_abhaken() -> void:
	_parade_gezeigt = true


## Session-Flag zurücksetzen (deterministische Tests).
static func parade_reset_fuer_tests() -> void:
	_parade_gezeigt = false


# ── Bühnen-Betrieb ────────────────────────────────────────────────────────────


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _process(_delta: float) -> void:
	if _geste.gedrueckt() and _geste.tick(Time.get_ticks_msec()):
		_lang_zeigen(_halte_id)
	# Weiche-Wache: verschwindet die Cockpit-Spalte (Baumodus/Blatt/Layout),
	# haben freischwebende Schilder nichts mehr zu suchen.
	var spalte_weg := _spalte == null or not _spalte.is_visible_in_tree()
	if _sichtbar_irgendwas() and (spalte_weg or _verdeckt()):
		_parade_abbrechen()
		_lang_verbergen()
		_dauer_raeumen()
	elif _dauer_an and _dauer_schilder.is_empty() and not spalte_weg and not _verdeckt():
		if _quer():
			_dauer_neu_legen()
	if not _geste.gedrueckt() and not _sichtbar_irgendwas() and not _dauer_an:
		set_process(false)


## Vom HUD nach JEDEM Layout-Pass gerufen: Geste/Schilder auf den frischen
## Stand bringen; im Quer-Fall Dauerschilder neu legen bzw. die Parade
## anstoßen (verzögert — der Grid-Container sortiert erst im Folgeframe).
func nach_layout(portrait: bool) -> void:
	_geste.zuruecksetzen()
	_geste.slop_px = SLOP_PT * UiScale.touch_px_per_pt(get_viewport())
	_lang_verbergen()
	_parade_abbrechen()
	if portrait:
		_dauer_raeumen()
		return
	if _dauer_an:
		_dauer_neu_legen.call_deferred()
	else:
		_parade_pruefen()


## Coachmark-Modus (c): Dauerschilder an/aus. Beim Abschalten (Coachmark
## „Alles klar!“) folgt die Parade als Abschieds-Runde — so sieht der
## Erst-Nutzer beide Stufen genau einmal.
func dauerschilder(an: bool) -> void:
	if _dauer_an == an:
		return
	_dauer_an = an
	_parade_abbrechen()
	_lang_verbergen()
	if an:
		_dauer_neu_legen()
	else:
		_dauer_raeumen()
		_parade_pruefen()


## Platzbedarf der Dauerschild-Schiene (breitestes Schild + Luft) — der
## Coachmark rückt um genau so viel nach links (hud._position_coachmark).
func dauerschild_breite() -> float:
	return _dauer_breite if _dauer_an else 0.0


## Muss dieser Kachel-Tap geschluckt werden? (Release NACH einem Langdruck
## — hud._on_action_pressed fragt VOR dem action_pressed-Emit.)
func schluckt_tap(id: StringName) -> bool:
	return id == _halte_id and _geste.schluckt_tap()


## Parade (a) starten — läuft einmal pro Session, nur im Querformat.
func parade_starten() -> void:
	if _parade_gezeigt or _dauer_an or not _quer() or not is_inside_tree():
		return
	if not _parade_schilder.is_empty():
		return
	var lage := _zellen_lage()
	var ids: Array = lage["ids"]
	if ids.is_empty():
		return
	HudIconBuehne._parade_gezeigt = true
	var zellen: Array = lage["zellen"]
	var spalten: int = lage["spalten"]
	var f := UiScale.for_viewport(get_viewport())
	var grenze := _grenze()
	var luft := LUFT_PX * f
	var verf := block_kante(zellen) - luft - grenze.position.x
	var groessen: Array = []
	for i in ids.size():
		var id: StringName = ids[i]
		var schild := HudNamensschild.bauen("Paradeschild%s" % String(id).capitalize(), f)
		add_child(schild)
		schild.beschrifte(id, f, verf, false)
		_parade_schilder.append(schild)
		groessen.append(schild.size)
	var rests := entzerre(
		rest_plan(zellen, spalten, groessen, luft, SLOT_LUFT_PX * f), MIN_LUFT_PX, grenze
	)
	_parade_animieren(rests, EINSCHUB_PX * f)
	set_process(true)


func parade_laeuft() -> bool:
	return not _parade_schilder.is_empty()


func _parade_animieren(rests: Array[Rect2], einschub: float) -> void:
	if UiMotion.reduced(self):
		# Reduced Motion: einmal STATISCH zeigen, dann räumen — kein Gleiten.
		for i in _parade_schilder.size():
			var rest_rm: Rect2 = rests[i]
			_parade_schilder[i].position = rest_rm.position
			_parade_schilder[i].modulate.a = 1.0
		_tween = create_tween()
		_tween.tween_interval(RM_STEH_S)
		_tween.finished.connect(_parade_aufraeumen)
		return
	_tween = create_tween().set_parallel(true)
	for i in _parade_schilder.size():
		var schild := _parade_schilder[i]
		var rest: Rect2 = rests[i]
		var verzug := parade_verzug(i)
		schild.position = rest.position + Vector2(einschub, 0.0)
		schild.modulate.a = 0.0
		(
			_tween
			. tween_property(schild, "position:x", rest.position.x, EIN_S)
			. set_delay(verzug)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
		_tween.tween_property(schild, "modulate:a", 1.0, EIN_S * 0.6).set_delay(verzug)
		var raus := verzug + EIN_S + STEH_S
		(
			_tween
			. tween_property(schild, "position:x", rest.position.x + einschub * 0.7, AUS_S)
			. set_delay(raus)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
		_tween.tween_property(schild, "modulate:a", 0.0, AUS_S).set_delay(raus)
	_tween.finished.connect(_parade_aufraeumen)


## Parade-Vorbedingungen POLLEN (bis PARADE_WARTE_S): frühestens im Folge-
## frame (Grid sortiert deferred), und Verdeckungen (Tagesbonus/Guide-Tour)
## dürfen den Einmal-Moment nur VERSCHIEBEN, nicht fressen. Hochkant,
## erledigte Parade oder Coachmark-Dauerschilder beenden das Warten.
func _parade_pruefen() -> void:
	if _parade_gezeigt:
		return
	# Frühester Start im ÜBERNÄCHSTEN Frame: der GridContainer sortiert
	# deferred, vorher lügen die Kachel-Rechtecke.
	await get_tree().process_frame
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + int(PARADE_WARTE_S * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not is_inside_tree() or _parade_gezeigt or _dauer_an or not _quer():
			return
		if _parade_faellig():
			parade_starten()
			return
		await get_tree().process_frame


func _parade_faellig() -> bool:
	if _parade_gezeigt or _dauer_an or not _quer():
		return false
	if not is_visible_in_tree() or _spalte == null or not _spalte.is_visible_in_tree():
		return false
	if _verdeckt():
		return false
	# Solange der Coachmark offen ist, gelten die Dauerschilder (c) — die
	# Parade folgt nach dem „Alles klar!“.
	return _hud.get("_coachmark") == null


func _parade_aufraeumen() -> void:
	for schild in _parade_schilder:
		if is_instance_valid(schild):
			schild.queue_free()
	_parade_schilder.clear()


func _parade_abbrechen() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_parade_aufraeumen()


# ── Langdruck (b) ─────────────────────────────────────────────────────────────


func _on_kachel_input(event: InputEvent, id: StringName) -> void:
	if not _quer():
		return
	var war_gedrueckt := _geste.gedrueckt()
	var war_aktiv := _geste.aktiv()
	_geste.verarbeite(event, Time.get_ticks_msec())
	if not war_gedrueckt and _geste.gedrueckt():
		_halte_id = id
		set_process(true)
	if war_aktiv and not _geste.aktiv():
		# Release nach echtem Langdruck: Schild zu; das Schluck-Flag frisst
		# den pressed-Emit im SELBEN Event-Lauf, danach verfällt es.
		_lang_verbergen()
		_schluck_verfall.call_deferred()
	elif war_gedrueckt and not _geste.gedrueckt() and not _geste.aktiv():
		# Abbruch vor der Schwelle (Wisch/Release): nichts zeigen.
		_lang_verbergen()


func _lang_zeigen(id: StringName) -> void:
	if _dauer_an or not _quer() or not is_inside_tree():
		return
	_parade_abbrechen()
	_lang_verbergen()
	var btn: Button = _knoepfe.get(id)
	if btn == null or not btn.is_visible_in_tree():
		return
	var f := UiScale.for_viewport(get_viewport())
	var grenze := _grenze()
	var lage := _zellen_lage()
	var zellen: Array = lage["zellen"]
	if zellen.is_empty():
		return
	var luft := LUFT_PX * f
	var kante := block_kante(zellen)
	var schild := HudNamensschild.bauen("Langdruckschild", f)
	add_child(schild)
	schild.beschrifte(id, f, kante - luft - grenze.position.x, false)
	var ursprung := get_global_rect().position
	var kachel := Rect2(btn.get_global_rect().position - ursprung, btn.get_global_rect().size)
	var y := kachel.get_center().y - schild.size.y / 2.0
	schild.position = Vector2(
		maxf(kante - luft - schild.size.x, grenze.position.x),
		clampf(y, grenze.position.y, grenze.end.y - schild.size.y)
	)
	_lang_schild = schild
	UiMotion.pop_in(schild)
	AudioDirector.try_play(self, "ui_tick")


func _lang_verbergen() -> void:
	if _lang_schild != null and is_instance_valid(_lang_schild):
		_lang_schild.queue_free()
	_lang_schild = null


func _schluck_verfall() -> void:
	_geste.schluck_verfallen()


# ── Dauerschilder (c, Coachmark-Modus) ────────────────────────────────────────


func _dauer_neu_legen() -> void:
	_dauer_raeumen()
	if not _dauer_an or not _quer() or not is_inside_tree():
		return
	var lage := _zellen_lage()
	var ids: Array = lage["ids"]
	if ids.is_empty():
		return
	var zellen: Array = lage["zellen"]
	var f := UiScale.for_viewport(get_viewport())
	var grenze := _grenze()
	var luft := LUFT_PX * f
	var verf := block_kante(zellen) - luft - grenze.position.x
	var spalten: int = lage["spalten"]
	var groessen: Array = []
	var breit := 0.0
	for i in ids.size():
		var id: StringName = ids[i]
		var schild := HudNamensschild.bauen("Dauerschild%s" % String(id).capitalize(), f)
		add_child(schild)
		# Kurzform BEVORZUGT (J2: „Fallback wo ein Schild dauerhaft nötig
		# ist“) — kompakte Schiene, der Coachmark behält Platz.
		schild.beschrifte(id, f, verf, true)
		_dauer_schilder.append(schild)
		groessen.append(schild.size)
		breit = maxf(breit, schild.size.x)
	var rests := entzerre(
		rest_plan(zellen, spalten, groessen, luft, SLOT_LUFT_PX * f), MIN_LUFT_PX, grenze
	)
	for i in _dauer_schilder.size():
		var rest: Rect2 = rests[i]
		_dauer_schilder[i].position = rest.position
		_dauer_schilder[i].modulate.a = 1.0
	_dauer_breite = breit + luft
	set_process(true)


func _dauer_raeumen() -> void:
	for schild in _dauer_schilder:
		if is_instance_valid(schild):
			schild.queue_free()
	_dauer_schilder.clear()
	_dauer_breite = 0.0


## Sichtbare Dauerschilder (für die UI-Wache: Kollisions-Messung).
func dauer_schilder() -> Array[HudNamensschild]:
	return _dauer_schilder


# ── Geometrie-Sicht auf die Cockpit-Spalte ────────────────────────────────────


## Kachel-Rechtecke in Bühnen-Koordinaten, row-major wie im Grid (die
## Grid-Kinder SIND die Anzeige-Reihenfolge — hud._fit_landscape_column
## hängt sie bereits verschränkt um).
func _zellen_lage() -> Dictionary:
	var ids: Array = []
	var zellen: Array = []
	var ursprung := get_global_rect().position
	for kind in _spalte.get_children():
		var btn := kind as Button
		if btn == null or not btn.visible or not btn.has_meta("j2_id"):
			continue
		ids.append(StringName(str(btn.get_meta("j2_id"))))
		var rect := btn.get_global_rect()
		zellen.append(Rect2(rect.position - ursprung, rect.size))
	return {"ids": ids, "zellen": zellen, "spalten": maxi(_spalte.columns, 1)}


## Safe-Area-Grenze in Bühnen-Koordinaten (Schilder bleiben im Bild).
func _grenze() -> Rect2:
	var vp := get_viewport()
	var canvas := Vector2(vp.get_visible_rect().size)
	var roh: Variant = _hud.get("safe_area_override")
	var override_rect: Rect2 = roh if roh is Rect2 else Rect2()
	var insets := UiScale.safe_insets_canvas(vp, override_rect)
	var links := float(insets["left"]) + RAND_PX
	var oben := float(insets["top"]) + RAND_PX
	var rechts := canvas.x - float(insets["right"]) - RAND_PX
	var unten := canvas.y - float(insets["bottom"]) - RAND_PX
	var ursprung := get_global_rect().position
	return Rect2(Vector2(links, oben) - ursprung, Vector2(rechts - links, unten - oben))


func _quer() -> bool:
	return int(_hud.get("current_layout")) == HudLayoutLogic.Layout.LANDSCAPE


func _verdeckt() -> bool:
	if _hud == null or not _hud.has_method("sichtbarkeit"):
		return false
	var maschine: Variant = _hud.call("sichtbarkeit")
	return maschine != null and bool(maschine.call("verdeckt"))


func _sichtbar_irgendwas() -> bool:
	if _lang_schild != null and is_instance_valid(_lang_schild):
		return true
	return not _parade_schilder.is_empty() or not _dauer_schilder.is_empty()


func _on_hud_sichtbarkeit() -> void:
	if _hud.is_visible_in_tree():
		if _dauer_an:
			_dauer_neu_legen.call_deferred()
		else:
			_parade_pruefen()
		return
	_parade_abbrechen()
	_lang_verbergen()
	_dauer_raeumen()

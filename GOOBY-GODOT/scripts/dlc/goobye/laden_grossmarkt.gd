class_name GoobyeLadenGrossmarkt
extends Node
## Szenen-Glue der Großmarkt-Fahrt (W19 Welle B, Doc §4.2) — die Laden-Szene
## bleibt schlank (gdlint-1000-Zeilen-Kante, Muster GoobyeLadenLeben):
## EIN Knopf in der Bottom-Leiste ist Bestell-Sheet, Fahrt-Status und
## „Alles ausladen“ in einem. Alle Regeln rechnet die PURE GoobyeTransport;
## hier lebt nur UI-Verdrahtung. Der Fahrt-Fortschritt ist eine reine
## Funktion der injizierten Uhr — der Puls hier liest nur ab (kein Tick-
## Zustand, App zu/auf ändert nichts).
##
## Kühl-Kapazität (§4.3, Welle B c): das Bestell-Sheet zeigt die
## Kühlplatz-Zeile und verkauft Kühlmodule (GoobyeKuehl) gleich mit.
##
## Lieferwagen (W19 Welle C, §7.1): das Bestell-Sheet bietet den
## „Goo und Bye“-Firmenwagen ab Laden-Level 5 an (darunter ein ehrlicher
## Gate-Hinweis); der Kauf ist atomar (GoobyeTransport.kaufe_lieferwagen)
## und mündet in den Übergabe-Story-Beat (Van-Vorfahrt + Onkel-Alwin-Karte).
##
## Kisten-Drag-ASMR (W19 Welle C, §4.2): bei Ankunft erscheinen Kisten-Chips
## (eine je Ware) + Sackkarre ADDITIV im Laden-UI — jeder Drop piept im
## Warengruppen-Ton, der LETZTE Chip löst das atomare Ausladen aus. Der
## „Alles ausladen!“-Leisten-Knopf bleibt unverändert der Sofort-Weg
## (Welle-B-Wächter-Flow tippt ihn direkt).

const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")

## Status-Puls (Sekunden): öfter wäre Verschwendung — die Fahrt dauert
## Minuten, der Text zeigt ganze Sekunden.
const PULS_SEC := 0.25

## Übergabe-Vorfahrt (Sekunden): kurz und warm, kein Sitzkino.
const VAN_FAHRT_SEC := 1.6

## Kisten-Ritual (§4.2): maximal gleichzeitige Chips (eine je Ware) —
## was darüber liegt, nimmt der letzte Drop bzw. der Alles-Knopf mit.
const RITUAL_MAX_CHIPS := 6

## Übergabe-Karte: Basis-Breite (Design-px) — Wert = laden_scene.KARTE_BASIS.
const KARTE_BASIS := 380.0
## Van-Vorfahrt relativ zum Tür-Anker: Start rechts außerhalb, Halt vor
## der Ladenfront (x fest in Diorama-Mitte, z knapp vor der Türlinie).
const VAN_START := Vector3(3.6, 0.0, 0.5)
const VAN_HALT_X := 0.3

## Kontrakt zur Szene (konfig-Dictionary in anbauen):
##   gs, leiste (Container), sheet_host (Node), toast (Callable(text)),
##   ist_einraeumen (Callable() -> bool), nach_ausladen (Callable(korb)),
##   kuehl_belegt (Callable() -> int),
##   story ({ui: Control, metrics: Callable() -> Dictionary,
##           tuer_pos: Vector3} — Übergabe-Karte + Van-Vorfahrt, Welle C)
var gs: Object = null
var toast := Callable()
var ist_einraeumen := Callable()
var nach_ausladen := Callable()
var kuehl_belegt := Callable()

## Öffentlich für Tests: Leisten-Knopf, offenes Sheet, aktueller Korb,
## Übergabe-Overlay (nur während des Story-Beats gesetzt), Ritual-Teile
## (Kisten-Chips + Sackkarre — nur bei Ankunft gebaut).
var knopf: SquishButton
var sheet: PanelSheet
var korb: Dictionary = {}
var uebergabe_overlay: Control
var ritual_chips: Array[Control] = []
var sackkarre: Control

var _sheet_host: Node
var _ui: Control
var _metrics_cb := Callable()
## Tür-Anker der Van-Vorfahrt (INF = keine Bahn, nackte Tests).
var _van_tuer := Vector3.INF
var _van: Node3D
var _puls := 0.0
var _anzahl_labels: Dictionary = {}
var _kosten_label: Label
var _kofferraum_label: Label
var _kuehl_label: Label


## Kisten-Chip des Ausladen-Rituals (§4.2): folgt dem Finger, landet auf
## der Sackkarre (Signal `abgelegt`) oder federt zurück an seinen Platz.
## Maus-Events reichen: iOS-Touch kommt emuliert als Maus an — exakt wie
## der Playtest-Wisch der Harness.
class KistenChip:
	extends PanelContainer

	signal abgelegt(chip: KistenChip)

	var ware_id := ""
	var zone: Control

	var _zieht := false
	var _heim := Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		var knopf_ev := event as InputEventMouseButton
		if knopf_ev != null and knopf_ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if knopf_ev.pressed:
				_zieht = true
				_heim = position
			elif _zieht:
				_zieht = false
				_ablegen_oder_zurueck()
		elif event is InputEventMouseMotion and _zieht:
			accept_event()
			position += (event as InputEventMouseMotion).relative

	func _ablegen_oder_zurueck() -> void:
		if zone != null and zone.get_global_rect().intersects(get_global_rect()):
			abgelegt.emit(self)
			return
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "position", _heim, 0.25)


## Glue bauen und in die Szene hängen (Knopf landet in der Leiste).
static func anbauen(szene: Node3D, konfig: Dictionary) -> GoobyeLadenGrossmarkt:
	var glue := GoobyeLadenGrossmarkt.new()
	glue.name = "GrossmarktGlue"
	glue.gs = konfig.get("gs")
	glue.toast = konfig.get("toast", Callable())
	glue.ist_einraeumen = konfig.get("ist_einraeumen", Callable())
	glue.nach_ausladen = konfig.get("nach_ausladen", Callable())
	glue.kuehl_belegt = konfig.get("kuehl_belegt", Callable())
	glue._sheet_host = konfig.get("sheet_host")
	var story: Variant = konfig.get("story", {})
	if story is Dictionary:
		glue._ui = (story as Dictionary).get("ui")
		glue._metrics_cb = (story as Dictionary).get("metrics", Callable())
		glue._van_tuer = (story as Dictionary).get("tuer_pos", Vector3.INF)
	szene.add_child(glue)
	glue._baue_knopf(konfig.get("leiste"))
	glue.aktualisiere()
	return glue


func _process(delta: float) -> void:
	_puls += delta
	if _puls < PULS_SEC:
		return
	_puls = 0.0
	aktualisiere()


## Knopf-Zustand aus Fahrt-Status + Tag-Phase neu ableiten (idempotent);
## das Kisten-Ritual (§4.2) hängt am selben Puls: Ankunft baut es auf,
## alles andere räumt es ab.
func aktualisiere() -> void:
	if knopf == null:
		return
	var einraeumen := not ist_einraeumen.is_valid() or bool(ist_einraeumen.call())
	var status := GoobyeTransport.status_von(gs)
	if status.is_empty():
		_ritual_abbauen()
		knopf.text = I18nService.t("dlc_goobye.grossmarkt.knopf")
		knopf.disabled = not einraeumen
		return
	if str(status["phase"]) == GoobyeTransport.PHASE_DA:
		_ritual_aufbauen()
		knopf.text = I18nService.t("dlc_goobye.grossmarkt.ausladen")
		knopf.disabled = not einraeumen
		return
	_ritual_abbauen()
	knopf.text = I18nService.t(
		"dlc_goobye.grossmarkt.status_" + str(status["phase"]),
		{"rest": _zeit_rest(int(status["rest_ms"]))}
	)
	knopf.disabled = true


## ------------------------------------------------------------ Bestell-Sheet


## Knopf-Tap: je nach Fahrt-Zustand Sheet öffnen ODER ausladen.
func _on_knopf() -> void:
	var status := GoobyeTransport.status_von(gs)
	if status.is_empty():
		_zeige_sheet()
		return
	if str(status["phase"]) == GoobyeTransport.PHASE_DA:
		_ausladen()


## Bestell-Sheet (§4.2/§2.5): ±-Stepper je Ware, Kofferraum-/Kühl-Zeile,
## gepinnter Fuß mit Kosten + „Losfahren!“ (B4-Muster: CTA nie unter der
## Falz). Eigenes frisches PanelSheet je Öffnung (GoobyeOffer-Muster) —
## das geteilte Szenen-Sheet gehört dem Welle-A-Nachschub.
func _zeige_sheet() -> void:
	if _sheet_host == null:
		return
	korb = {}
	_anzahl_labels = {}
	sheet = PanelSheetScene.instantiate()
	sheet.theme = ThemeService.theme()
	_sheet_host.add_child(sheet)
	sheet.closed.connect(sheet.queue_free)
	sheet.set_title(I18nService.t("dlc_goobye.grossmarkt.titel"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var hinweis := Label.new()
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("dlc_goobye.grossmarkt.hinweis")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hinweis)
	_kofferraum_label = Label.new()
	_kofferraum_label.name = "KofferraumZeile"
	_kofferraum_label.theme_type_variation = &"HeadlineLabel"
	box.add_child(_kofferraum_label)
	if not GoobyeTransport.lieferwagen_frei(gs):
		box.add_child(_baue_lieferwagen_zeile())
	box.add_child(_baue_kuehl_zeile())
	for ware: Dictionary in GoobyeKatalog.waren():
		box.add_child(_baue_waren_zeile(ware))
	sheet.add_content(box)
	sheet.add_footer(_baue_fuss())
	_zeilen_aktualisieren()
	sheet.open()


## Lieferwagen-Zeile (Welle C, §7.1): ab Laden-Level 5 kaufbar — darunter
## steht der ehrliche Gate-Hinweis mit dem aktuellen Laden-Level (kein
## grauer Rätsel-Knopf, §2.5: gute Defaults, nie Bestrafung).
func _baue_lieferwagen_zeile() -> Control:
	var zeile := HBoxContainer.new()
	zeile.name = "LieferwagenZeile"
	zeile.add_theme_constant_override("separation", 10)
	var links := Label.new()
	links.text = I18nService.t(
		"dlc_goobye.grossmarkt.lieferwagen_zeile", {"kisten": GoobyeTransport.KISTEN_LIEFERWAGEN}
	)
	links.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	links.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(links)
	if GoobyeLevel.level_fuer(gs) >= GoobyeTransport.LIEFERWAGEN_LEVEL:
		var kaufen := SquishButton.new()
		kaufen.name = "LieferwagenKaufen"
		kaufen.theme_type_variation = &"BtnGhost"
		kaufen.text = I18nService.t(
			"dlc_goobye.grossmarkt.lieferwagen_kaufen", {"preis": GoobyeTransport.LIEFERWAGEN_PREIS}
		)
		kaufen.focus_mode = Control.FOCUS_NONE
		kaufen.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
		kaufen.pressed.connect(_lieferwagen_kaufen)
		zeile.add_child(kaufen)
	else:
		var gate := Label.new()
		gate.name = "LieferwagenGate"
		gate.theme_type_variation = &"CaptionLabel"
		gate.text = (
			I18nService
			. t(
				"dlc_goobye.grossmarkt.lieferwagen_gate",
				{
					"ziel": GoobyeTransport.LIEFERWAGEN_LEVEL,
					"level": GoobyeLevel.level_fuer(gs),
					"name": I18nService.t(GoobyeLevel.name_key(GoobyeLevel.level_fuer(gs))),
				}
			)
		)
		gate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		zeile.add_child(gate)
	return zeile


## Kühlplatz-Zeile (§4.3): Stand links, Modul-Kauf rechts (atomar).
func _baue_kuehl_zeile() -> Control:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	_kuehl_label = Label.new()
	_kuehl_label.name = "KuehlZeile"
	_kuehl_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kuehl_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(_kuehl_label)
	var kaufen := SquishButton.new()
	kaufen.name = "KuehlmodulKaufen"
	kaufen.theme_type_variation = &"BtnGhost"
	kaufen.text = I18nService.t("dlc_goobye.kuehl.modul_kaufen", {"preis": GoobyeKuehl.MODUL_PREIS})
	kaufen.focus_mode = Control.FOCUS_NONE
	kaufen.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	kaufen.pressed.connect(_kuehlmodul_kaufen)
	zeile.add_child(kaufen)
	return zeile


## Waren-Zeile: Name + Einkaufspreis links, −/Anzahl/+ rechts (Stepper in
## der Daumen-Zone, Touch-Floor 44 pt — §2.5).
func _baue_waren_zeile(ware: Dictionary) -> Control:
	var ware_id := str(ware["id"])
	var zeile := HBoxContainer.new()
	zeile.name = "Zeile_" + ware_id
	zeile.add_theme_constant_override("separation", 8)
	var links := Label.new()
	links.text = (
		I18nService
		. t(
			"dlc_goobye.nachschub.zeile",
			{
				"name": I18nService.t(str(ware.get("name_key", ""))),
				"preis": GoobyePreis.einkaufspreis(ware),
			}
		)
	)
	links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	links.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(links)
	zeile.add_child(_stepper_knopf("Minus_" + ware_id, "−", _korb_aendern.bind(ware_id, -1)))
	var anzahl := Label.new()
	anzahl.name = "Anzahl_" + ware_id
	anzahl.custom_minimum_size = Vector2(44.0, 0.0)
	anzahl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anzahl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(anzahl)
	_anzahl_labels[ware_id] = anzahl
	zeile.add_child(_stepper_knopf("Plus_" + ware_id, "+", _korb_aendern.bind(ware_id, 1)))
	return zeile


func _stepper_knopf(knopf_name: String, text: String, aktion: Callable) -> SquishButton:
	var b := SquishButton.new()
	b.name = knopf_name
	b.theme_type_variation = &"BtnGhost"
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(AcTokens.TOUCH_FLOOR, AcTokens.TOUCH_FLOOR)
	b.pressed.connect(aktion)
	return b


## Gepinnter Fuß: Kosten-Zeile + „Losfahren!“.
func _baue_fuss() -> Control:
	var fuss := VBoxContainer.new()
	fuss.name = "BestellFuss"
	fuss.add_theme_constant_override("separation", 8)
	_kosten_label = Label.new()
	_kosten_label.name = "BestellKosten"
	_kosten_label.theme_type_variation = &"CaptionLabel"
	_kosten_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fuss.add_child(_kosten_label)
	var losfahren := SquishButton.new()
	losfahren.name = "Losfahren"
	losfahren.theme_type_variation = &"BtnLeaf"
	losfahren.text = I18nService.t("dlc_goobye.grossmarkt.losfahren")
	losfahren.focus_mode = Control.FOCUS_NONE
	losfahren.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	losfahren.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	losfahren.pressed.connect(_losfahren)
	fuss.add_child(losfahren)
	return fuss


## ±-Stepper: Kapazität deckelt beim Plus (Kofferraum-Gefühl §4.2).
func _korb_aendern(ware_id: String, richtung: int) -> void:
	var bisher := int(korb.get(ware_id, 0))
	if richtung > 0:
		if GoobyeTransport.kisten_im_korb(korb) >= GoobyeTransport.kapazitaet_fuer(gs):
			AudioDirector.try_play(self, "ui_error")
			_toast(I18nService.t("dlc_goobye.grossmarkt.kofferraum_voll"))
			return
		korb[ware_id] = bisher + 1
		AudioDirector.try_play(self, "ui_chip", GoobyeKatalog.ton_fuer(ware_id))
	else:
		if bisher <= 0:
			return
		if bisher == 1:
			korb.erase(ware_id)
		else:
			korb[ware_id] = bisher - 1
		AudioDirector.try_play(self, "ui_back")
	_zeilen_aktualisieren()


## Anzeige-Zeilen (Kofferraum/Kühl/Anzahl/Kosten) neu beschriften.
func _zeilen_aktualisieren() -> void:
	var kisten := GoobyeTransport.kisten_im_korb(korb)
	if _kofferraum_label != null:
		_kofferraum_label.text = (
			I18nService
			. t(
				"dlc_goobye.grossmarkt.kofferraum",
				{
					"kisten": kisten,
					"kapazitaet": GoobyeTransport.kapazitaet_fuer(gs),
					"auto": _auto_name(),
				}
			)
		)
	if _kuehl_label != null:
		var belegt := int(kuehl_belegt.call()) if kuehl_belegt.is_valid() else 0
		_kuehl_label.text = (
			I18nService
			. t(
				"dlc_goobye.kuehl.zeile",
				{
					"belegt": belegt,
					"kapazitaet": GoobyeKuehl.kapazitaet(GoobyeKuehl.module_von(gs)),
				}
			)
		)
	for ware_id: String in _anzahl_labels:
		(_anzahl_labels[ware_id] as Label).text = str(int(korb.get(ware_id, 0)))
	if _kosten_label != null:
		_kosten_label.text = I18nService.t(
			"dlc_goobye.grossmarkt.kosten",
			{"kosten": GoobyeTransport.kosten(korb), "kisten": kisten}
		)


## „Losfahren!“: ATOMARE Bestellung (GoobyeTransport) — der Ausgang klingt,
## nicht der Druck (AUDIO-GRAMMATIK, Muster GoobyeOffer).
func _losfahren() -> void:
	match GoobyeTransport.bestelle(gs, korb):
		GoobyeTransport.RESULT_OK:
			AudioDirector.try_play(self, "ui_buy")
			Haptics.success(self)
			_toast(I18nService.t("dlc_goobye.grossmarkt.bestellt_toast"))
			if sheet != null:
				sheet.close()
				sheet = null
			aktualisiere()
		GoobyeTransport.RESULT_LEER:
			AudioDirector.try_play(self, "ui_error")
			_toast(I18nService.t("dlc_goobye.grossmarkt.korb_leer"))
		GoobyeTransport.RESULT_ZU_VIEL:
			AudioDirector.try_play(self, "ui_error")
			_toast(I18nService.t("dlc_goobye.grossmarkt.kofferraum_voll"))
		GoobyeTransport.RESULT_UNTERWEGS:
			AudioDirector.try_play(self, "ui_error")
			_toast(I18nService.t("dlc_goobye.grossmarkt.schon_unterwegs"))
		_:
			AudioDirector.try_play(self, "ui_error")
			Haptics.warn(self)
			_toast(I18nService.t("dlc_goobye.grossmarkt.zu_teuer"))


## Kühlmodul kaufen (§4.3) — atomar über GoobyeKuehl.
func _kuehlmodul_kaufen() -> void:
	match GoobyeKuehl.kaufe_modul(gs):
		GoobyeKuehl.RESULT_OK:
			AudioDirector.try_play(self, "ui_buy")
			Haptics.success(self)
			_toast(
				I18nService.t("dlc_goobye.kuehl.modul_gekauft", {"je": GoobyeKuehl.STUECK_JE_MODUL})
			)
			_zeilen_aktualisieren()
		_:
			AudioDirector.try_play(self, "ui_error")
			_toast(I18nService.t("dlc_goobye.kuehl.modul_zu_teuer"))


## ------------------------------------------------------------ Lieferwagen


## Lieferwagen kaufen (Welle C, §7.1): atomar über GoobyeTransport —
## nur RESULT_OK startet den Übergabe-Story-Beat.
func _lieferwagen_kaufen() -> void:
	match GoobyeTransport.kaufe_lieferwagen(gs):
		GoobyeTransport.RESULT_OK:
			AudioDirector.try_play(self, "ui_buy")
			Haptics.success(self)
			if sheet != null:
				sheet.close()
				sheet = null
			_zeige_uebergabe()
			aktualisiere()
		GoobyeTransport.RESULT_GESPERRT:
			AudioDirector.try_play(self, "ui_error")
			_toast(
				I18nService.t(
					"dlc_goobye.grossmarkt.lieferwagen_gesperrt",
					{"ziel": GoobyeTransport.LIEFERWAGEN_LEVEL}
				)
			)
		GoobyeTransport.RESULT_SCHON_DA:
			AudioDirector.try_play(self, "ui_back")
		_:
			AudioDirector.try_play(self, "ui_error")
			Haptics.warn(self)
			_toast(I18nService.t("dlc_goobye.grossmarkt.zu_teuer"))


## Übergabe-Moment (§7.1 „schaltet frei“ + §1.3-Wärme): der Firmenwagen
## fährt vor der Ladenfront vor, dazu die Onkel-Alwin-Karte mit drei
## warmen Sprüchen. Ohne ui/van_bahn-Kontrakt (nackte Tests) bleibt der
## Kauf trotzdem komplett — Story ist Zuckerguss, nie Zustand.
func _zeige_uebergabe() -> void:
	_van_vorfahren()
	if _ui == null:
		return
	var teile := GoobyeLadenBausteine.karte_overlay(
		_ui, _metrics(), "UebergabeOverlay", KARTE_BASIS
	)
	uebergabe_overlay = teile["overlay"]
	var box: VBoxContainer = teile["box"]
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("dlc_goobye.uebergabe.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	for key: String in ["zeile1", "zeile2", "zeile3"]:
		var zeile := Label.new()
		zeile.text = I18nService.t("dlc_goobye.uebergabe." + key)
		zeile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(zeile)
	var weiter := SquishButton.new()
	weiter.name = "UebergabeWeiter"
	weiter.theme_type_variation = &"BtnLeaf"
	weiter.text = I18nService.t("dlc_goobye.uebergabe.knopf")
	weiter.focus_mode = Control.FOCUS_NONE
	weiter.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	weiter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	weiter.pressed.connect(_uebergabe_schliessen)
	box.add_child(weiter)
	ScreenShell.scale_fonts(uebergabe_overlay, float(_metrics()["f"]))
	UiMotion.pop_in(teile["karte"])


func _uebergabe_schliessen() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	Haptics.success(self)
	if uebergabe_overlay != null:
		uebergabe_overlay.queue_free()
		uebergabe_overlay = null
	_van_abfahren()


## Van-Vorfahrt: von rechts (Tür-Seite) vor die Ladenfront — reine
## Inszenierung als Kind der 3D-Szene, Tür-Anker kommt per Kontrakt.
func _van_vorfahren() -> void:
	var szene := get_parent()
	if not _van_tuer.is_finite() or not (szene is Node3D):
		return
	_van = GoobyeLadenBausteine.lieferwagen_modell(0.9)
	_van.position = _van_tuer + VAN_START
	# Vorfahrt läuft in −X (delivery_cutscene-Konvention: Wurzel fährt +X).
	_van.rotation.y = PI
	(szene as Node3D).add_child(_van)
	var tween := _van.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var halt := Vector3(VAN_HALT_X, 0.0, _van_tuer.z + VAN_START.z)
	tween.tween_property(_van, "position", halt, VAN_FAHRT_SEC)
	tween.tween_callback(AudioDirector.try_play.bind(self, "ui_confirm"))


func _van_abfahren() -> void:
	if _van == null or not is_instance_valid(_van):
		return
	var ziel: Vector3 = _van.position + Vector3(-8.0, 0.0, 0.0)
	var tween := _van.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_van, "position", ziel, VAN_FAHRT_SEC)
	tween.tween_callback(_van.queue_free)
	_van = null


func _metrics() -> Dictionary:
	if _metrics_cb.is_valid():
		return _metrics_cb.call()
	return ScreenShell.metrics(get_viewport())


## ------------------------------------------------------------ Ausladen


## „Alles ausladen“ (§4.2): kleine Klonk-Inszenierung (Gebrabbel-Pieps in
## Warengruppen-Tönen) statt Drag-Ritual — Welle B startet bewusst simpel.
func _ausladen() -> void:
	var ergebnis := GoobyeTransport.ausladen(gs)
	if not bool(ergebnis["ok"]):
		AudioDirector.try_play(self, "ui_error")
		return
	Haptics.success(self)
	if nach_ausladen.is_valid():
		nach_ausladen.call(ergebnis["warenkorb"])
	_klonk_choreo(ergebnis["warenkorb"])
	_toast(I18nService.t("dlc_goobye.grossmarkt.ausgeladen", {"kisten": int(ergebnis["kisten"])}))
	aktualisiere()


## Bis zu 6 Kisten-Pieps hintereinander (Ton = Warengruppe, §1.2).
func _klonk_choreo(ausgeladen: Dictionary) -> void:
	var toene: Array[float] = []
	for ware_id: String in ausgeladen:
		for _n in int(ausgeladen[ware_id]):
			if toene.size() >= 6:
				break
			toene.append(GoobyeKatalog.ton_fuer(ware_id))
	if toene.is_empty():
		return
	var tween := create_tween()
	for ton: float in toene:
		tween.tween_callback(AudioDirector.try_play.bind(self, "ui_chip", ton))
		tween.tween_interval(0.12)


## ------------------------------------------------------------ Kisten-Ritual


## Ritual aufbauen (§4.2, idempotent): eine Kiste je bestellter Ware links,
## die Sackkarre rechts in der Daumen-Zone. Alles ADDITIV im Laden-UI —
## der Leisten-Knopf bleibt der Sofort-Weg.
func _ritual_aufbauen() -> void:
	if _ui == null or not ritual_chips.is_empty():
		return
	var fahrt := GoobyeTransport.unterwegs_von(gs)
	var ladung: Dictionary = fahrt.get("warenkorb", {})
	if ladung.is_empty():
		return
	var m := _metrics()
	var canvas: Vector2 = m["canvas"]
	var f: float = m["f"]
	sackkarre = _baue_sackkarre(m)
	var ware_ids: Array = ladung.keys()
	ware_ids.sort()
	for i in mini(ware_ids.size(), RITUAL_MAX_CHIPS):
		var ware_id := str(ware_ids[i])
		var chip := KistenChip.new()
		chip.name = "Kiste_" + ware_id
		chip.theme_type_variation = &"AcCard"
		chip.ware_id = ware_id
		chip.zone = sackkarre
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var text := Label.new()
		text.text = (
			I18nService
			. t(
				"dlc_goobye.grossmarkt.kiste",
				{
					"menge": int(ladung[ware_id]),
					"name": I18nService.t(str(GoobyeKatalog.ware(ware_id).get("name_key", ""))),
				}
			)
		)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(text)
		chip.custom_minimum_size = Vector2(AcTokens.TOUCH_FLOOR * 1.6, AcTokens.TOUCH_FLOOR)
		chip.position = Vector2(
			canvas.x * 0.10 + (i % 2) * AcTokens.TOUCH_FLOOR * 1.8 * f,
			canvas.y * 0.42 + floorf(i / 2.0) * (AcTokens.TOUCH_FLOOR + 10.0) * f
		)
		chip.abgelegt.connect(_kiste_abgelegt)
		ScreenShell.scale_fonts(chip, f)
		_ui.add_child(chip)
		ritual_chips.append(chip)


func _baue_sackkarre(m: Dictionary) -> Control:
	var canvas: Vector2 = m["canvas"]
	var f: float = m["f"]
	var karre := PanelContainer.new()
	karre.name = "Sackkarre"
	karre.theme_type_variation = &"AcCard"
	karre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("dlc_goobye.grossmarkt.sackkarre")
	box.add_child(titel)
	var hinweis := Label.new()
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("dlc_goobye.grossmarkt.sackkarre_hinweis")
	box.add_child(hinweis)
	karre.add_child(box)
	karre.position = Vector2(canvas.x * 0.62, canvas.y * 0.44)
	ScreenShell.scale_fonts(karre, f)
	_ui.add_child(karre)
	return karre


## Ein Chip ist gelandet: Warengruppen-Piep + Karre hüpft; der LETZTE
## Chip löst das atomare Ausladen aus (Save ändert sich erst dann).
func _kiste_abgelegt(chip: KistenChip) -> void:
	AudioDirector.try_play(self, "ui_chip", GoobyeKatalog.ton_fuer(chip.ware_id))
	ritual_chips.erase(chip)
	chip.queue_free()
	if sackkarre != null:
		var tween := sackkarre.create_tween()
		tween.tween_property(sackkarre, "scale", Vector2(1.08, 0.92), 0.08)
		tween.tween_property(sackkarre, "scale", Vector2.ONE, 0.12)
	if ritual_chips.is_empty():
		_ausladen()


func _ritual_abbauen() -> void:
	for chip in ritual_chips:
		if is_instance_valid(chip):
			chip.queue_free()
	ritual_chips.clear()
	if sackkarre != null:
		if is_instance_valid(sackkarre):
			sackkarre.queue_free()
		sackkarre = null


## ------------------------------------------------------------ Helfer


func _baue_knopf(leiste: Container) -> void:
	knopf = SquishButton.new()
	knopf.name = "Grossmarkt"
	knopf.theme_type_variation = &"BtnTeal"
	knopf.text = I18nService.t("dlc_goobye.grossmarkt.knopf")
	knopf.focus_mode = Control.FOCUS_NONE
	knopf.pressed.connect(_on_knopf)
	if leiste != null:
		leiste.add_child(knopf)


func _auto_name() -> String:
	if GoobyeTransport.lieferwagen_frei(gs):
		return I18nService.t("dlc_goobye.grossmarkt.lieferwagen")
	return str(AutoKatalog.aktives_auto(gs).get("name_de", ""))


func _toast(text: String) -> void:
	if toast.is_valid():
		toast.call(text)


func _zeit_rest(rest_ms: int) -> String:
	var sekunden := int(ceil(float(maxi(0, rest_ms)) / 1000.0))
	return "%d:%02d" % [sekunden / 60, sekunden % 60]

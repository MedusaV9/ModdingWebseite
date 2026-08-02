class_name McGoobySchichtScene
extends Control
## McGooby-Schicht (Welle A+B, Doc §2.2): VOR dem Kauf die freie
## Probeschicht der Welle A — EINE Station, Burger braten, deterministisch
## aus dem Tages-Seed (McGoobySchichtLogic), Kassensturz (McGoobyAbrechnung),
## Erststart-Intro (Doc §1.3), MinigamePauseModal. NACH der Schicht trägt
## die Ende-Karte den Angebots-Block („Schicht geschafft → Angebot“,
## Doc §6.2): ein Knopf öffnet das McGoobyOffer-Sheet; der Kauf startet die
## VOLLE Schicht in place (kein Routen-Remount).
##
## Welle B (G6/MCGOOBY-B), nur mit gekauftem Laden: mehrstufige
## Bestell-Zettel über die interaktiven Stationen (McGoobySchichtPlan) —
## Grill-Tap, Fritteuse HALTEN & im goldenen Fenster loslassen mit
## Salz-Moment, Getränke-Zapfen mit Becher-Größen + Sprudel-Gag. Dazu die
## Stations-Pills-Zeile (McGoobyStationenUi, IM Spalten-Fluss — Playtest-
## Befund B2: Pills dürfen nie Slots verdecken) und die McGooby-Bühne
## (McGoobyBuehne, 1×/Schicht, Kunden-Jubel = Trinkgeld-Regen).
##
## Route `mcgooby_schicht` — registriert sich selbst (Muster ChessScene).

signal ready_for_reveal

const Economy := preload("res://scripts/logic/economy.gd")

const ROUTE := &"mcgooby_schicht"
const ROUTES := {ROUTE: "res://scripts/dlc/mcgooby/schicht_scene.tscn"}

## Patty-Zustandsfarben (Parodie mit Herz: Kohle ist ein Gag, kein Fail).
const FARBE_ROH := Color("#E8A18B")
const FARBE_GOLDBRAUN := Color("#E8C25A")
const FARBE_KOHLE := Color("#54382A")
const FARBE_TEXT_HELL := Color("#FFF3DC")
const FARBE_TEXT_DUNKEL := Color("#6B4A2B")

## Wunschgröße des Patty-Knopfs (Design-px, skaliert mit f; nie unter Floor).
const PATTY_BASIS := 168.0
## Karten-Wunschbreite der Intro-/Ende-Overlays (Design-px).
const KARTE_BASIS := 360.0

## Tests/Screenshots: GameState-Double statt /root/GameState.
var gs_override: Object = null
## Tests: fester Seed statt Tages-Seed (0 = Tages-Seed).
var seed_override := 0
## Tests: Navigation abschaltbar.
var auto_navigate := true

var _gs: Object = null
var _voll := false
var _bal: Dictionary = {}
var _menu: Array = []
var _folge: Array[Dictionary] = []
var _folge_voll: Array[Dictionary] = []
var _runde := 0
var _laeuft := false
var _pausiert := false
var _bestellung_idx := 0
var _position_idx := 0
var _aufgabe_idx := 0
var _patty_idx := 0
var _patty_zeit := 0.0
var _patty_aktiv := false
var _patty_timing: Dictionary = {}
var _patty_zustand := McGoobySchichtLogic.ZUSTAND_ROH
var _haelt := false
var _salz_aktiv := false
var _salz_zeit := 0.0
var _salz_treffer := 0
var _buehne_trinkgeld := 0
var _punkte := 0
var _perfekt_gesamt := 0
var _bestellung_punkte := 0
var _bestellung_fehlerfrei := true
var _ergebnisse: Array[Dictionary] = []
var _kasse: Dictionary = {}
var _m: Dictionary = {}

var _rows: VBoxContainer
var _back: Button
var _pause_btn: Button
var _punkte_label: Label
var _bestellung_label: Label
var _gericht_label: Label
var _patty_label: Label
var _callout: Label
var _patty_btn: Button
var _garbar: ProgressBar
var _stationen_block: VBoxContainer
var _stationen_ui: McGoobyStationenUi
var _hilfe_label: Label
var _buehne_knopf: Button
var _buehne_ui: McGoobyBuehne
var _intro_overlay: Control
var _intro_karte: PanelContainer
var _intro_knopf: Button
var _ende_overlay: Control
var _ende_karte: PanelContainer
var _ende_zeilen: VBoxContainer
var _angebot_box: VBoxContainer
var _angebot_knopf: Button
var _nochmal_knopf: Button
var _feierabend_knopf: Button
var _pause_modal: MinigamePauseModal


static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeService.theme()
	register_routes()
	McGoobyState.register_slice()
	_gs = gs_override if gs_override != null else get_node_or_null("/root/GameState")
	_voll = McGoobyState.ist_gekauft(_gs)
	_bal = McGoobyKatalog.balance()
	_menu = McGoobyKatalog.rezepte_fuer("grill")
	_build_ui()
	_modus_anwenden()
	_apply_metrics()
	get_viewport().size_changed.connect(_apply_metrics)
	if McGoobyState.ist_intro_gesehen(_gs):
		_starte_schicht()
	else:
		_zeige_intro()
	ready_for_reveal.emit()


func receive_params(params: Dictionary) -> void:
	seed_override = int(params.get("seed", seed_override))


func _process(delta: float) -> void:
	if not _laeuft or _pausiert:
		return
	if _buehne_ui != null and _buehne_ui.laeuft():
		return
	if _voll:
		_process_voll(delta)
		return
	if not _patty_aktiv:
		return
	_patty_zeit += delta
	var timing := _patty_timing
	var zustand := McGoobySchichtLogic.zustand(_patty_zeit, timing)
	if zustand != _patty_zustand:
		_patty_zustand = zustand
		# Brutzel-Feedback: der Zustandswechsel „ploppt“ hörbar (mg_good).
		if zustand == McGoobySchichtLogic.ZUSTAND_GOLDBRAUN:
			AudioDirector.try_play(self, "mg_good")
	_patty_visualisieren()
	# Liegengelassene Pattys lösen sich nach dem Nachlauf freundlich selbst
	# auf (Röstaroma-Spezial, halbe Punkte — nie ein Fail-State, Doc §4.2).
	var ende := (
		float(timing.get("gar_sec", 4.0))
		+ float(timing.get("fenster_sec", 1.4))
		+ float(timing.get("nachlauf_sec", 2.0))
	)
	if _patty_zeit >= ende:
		_werte_patty(McGoobySchichtLogic.bewerte_liegengelassen(_bal))


## Voll-Schicht-Takt (Welle B): Salz-Fenster tickt immer; Halte-Aufgaben
## garen NUR mit Griff (Korb im Öl / Hahn offen — losgelassen steht die
## Zeit), Tap-Aufgaben braten wie in der Demo von allein weiter.
func _process_voll(delta: float) -> void:
	if _salz_aktiv:
		_salz_zeit += delta
		_aufgabe_visualisieren()
		if _salz_zeit > McGoobySchichtPlan.salz_fenster_sec(_bal):
			AudioDirector.try_play(self, "ui_tick")
			_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.salz_vorbei"))
			_salz_beenden()
		return
	if not _patty_aktiv:
		return
	var aufgabe := aufgabe_aktuell()
	var halten := str(aufgabe.get("art", "")) == McGoobySchichtPlan.ART_HALTEN
	if halten and not _haelt:
		return
	_patty_zeit += delta
	var zustand := McGoobySchichtLogic.zustand(_patty_zeit, _patty_timing)
	if zustand != _patty_zustand:
		_patty_zustand = zustand
		if zustand == McGoobySchichtLogic.ZUSTAND_GOLDBRAUN:
			AudioDirector.try_play(self, "mg_good")
			# Sprudel-Gag (Doc §2.2): der Becher meldet sich hörbar zu Wort.
			if str(aufgabe.get("station", "")) == "getraenke":
				_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.sprudelt"))
	_patty_visualisieren()
	var ende := (
		float(_patty_timing.get("gar_sec", 4.0))
		+ float(_patty_timing.get("fenster_sec", 1.4))
		+ float(_patty_timing.get("nachlauf_sec", 2.0))
	)
	if _patty_zeit >= ende:
		_werte_aufgabe(McGoobySchichtLogic.bewerte_liegengelassen(_bal))


## ---------------------------------------------------------------- Test-API


func ist_intro_offen() -> bool:
	return _intro_overlay != null and _intro_overlay.visible


func ist_ende_offen() -> bool:
	return _ende_overlay != null and _ende_overlay.visible


func ist_am_laufen() -> bool:
	return _laeuft and not _pausiert


func ist_voll_modus() -> bool:
	return _voll


func bestellung_aktuell() -> Dictionary:
	var quelle: Array[Dictionary] = _folge_voll if _voll else _folge
	if _bestellung_idx >= 0 and _bestellung_idx < quelle.size():
		return quelle[_bestellung_idx]
	return {}


## Aktuelle Voll-Schicht-Aufgabe ({art, station, salz, becher}; {} = keine).
func aufgabe_aktuell() -> Dictionary:
	var aufgaben := _aufgaben_der_position()
	if _aufgabe_idx >= 0 and _aufgabe_idx < aufgaben.size():
		return aufgaben[_aufgabe_idx]
	return {}


## Tests: Timing-Fenster der aktiven Aufgabe (Kopie — inkl. Becher-Faktor).
func aufgabe_timing() -> Dictionary:
	return _patty_timing.duplicate(true)


func schicht_ergebnis() -> Dictionary:
	return _kasse.duplicate(true)


## Tests: Brat-/Halte-Zeit der aktiven Aufgabe pinnen (statt Frames abzuwarten).
func patty_zeit_setzen(t_sec: float) -> void:
	_patty_zeit = maxf(0.0, t_sec)
	_patty_zustand = McGoobySchichtLogic.zustand(_patty_zeit, _patty_timing)
	_patty_visualisieren()


## Tests: Salz-Fenster-Zeit pinnen (Ablauf bleibt Sache von _process_voll).
func salz_zeit_setzen(t_sec: float) -> void:
	_salz_zeit = maxf(0.0, t_sec)


func salz_ist_aktiv() -> bool:
	return _salz_aktiv


func patty_knopf() -> Button:
	return _patty_btn


func buehne() -> McGoobyBuehne:
	return _buehne_ui


func buehne_knopf() -> Button:
	return _buehne_knopf


func stationen_pills() -> Array[Button]:
	return _stationen_ui.pills() if _stationen_ui != null else []


func angebot_knopf() -> Button:
	return _angebot_knopf


## ---------------------------------------------------------------- Aufbau


func _build_ui() -> void:
	var wallpaper := AcWallpaper.new()
	wallpaper.name = "Wallpaper"
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wallpaper)

	_rows = VBoxContainer.new()
	_rows.name = "Spalte"
	_rows.add_theme_constant_override("separation", 12)
	add_child(_rows)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_rows.add_child(header)
	_back = SquishButton.new()
	_back.name = "Zurueck"
	_back.theme_type_variation = &"BtnGhost"
	_back.text = I18nService.t("dlc_mcgooby.zurueck")
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(_on_back_pressed)
	header.add_child(_back)
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("dlc_mcgooby.titel")
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(titel)
	_pause_btn = SquishButton.new()
	_pause_btn.name = "Pause"
	_pause_btn.theme_type_variation = &"BtnGhost"
	_pause_btn.text = I18nService.t("dlc_mcgooby.schicht.pause")
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.pressed.connect(_on_pause_pressed)
	header.add_child(_pause_btn)

	_punkte_label = Label.new()
	_punkte_label.name = "Punkte"
	_punkte_label.theme_type_variation = &"CaptionLabel"
	_punkte_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(_punkte_label)

	var karte := PanelContainer.new()
	karte.name = "BestellKarte"
	karte.theme_type_variation = &"AcCard"
	_rows.add_child(karte)
	var karte_box := VBoxContainer.new()
	karte_box.add_theme_constant_override("separation", 4)
	karte.add_child(karte_box)
	_bestellung_label = Label.new()
	_bestellung_label.name = "Bestellung"
	_bestellung_label.theme_type_variation = &"CaptionLabel"
	karte_box.add_child(_bestellung_label)
	_gericht_label = Label.new()
	_gericht_label.name = "Gericht"
	_gericht_label.theme_type_variation = &"TitleLabel"
	_gericht_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	karte_box.add_child(_gericht_label)
	_patty_label = Label.new()
	_patty_label.name = "PattyZaehler"
	_patty_label.theme_type_variation = &"CaptionLabel"
	karte_box.add_child(_patty_label)

	# Stations-Pills + Bühnen-Knopf + Gesten-Hilfezeile (Welle B) — EIGENE
	# Zeile im Spalten-Fluss (Playtest-Befund B2: nie Slots überlagern).
	var stationen_teile := McGoobySchichtOverlays.stationen_block(_rows)
	_stationen_block = stationen_teile["block"]
	_stationen_ui = stationen_teile["stationen"]
	_stationen_ui.hilfe_gewuenscht.connect(_on_pill_hilfe)
	_buehne_knopf = stationen_teile["buehne_knopf"]
	_buehne_knopf.pressed.connect(_on_buehne_pressed)
	_hilfe_label = stationen_teile["hilfe"]

	# Mittig + Daumenzone: die Grill-Gruppe zentriert im Rest-Raum.
	var mitte := CenterContainer.new()
	mitte.name = "Mitte"
	mitte.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_child(mitte)
	var grill_box := VBoxContainer.new()
	grill_box.add_theme_constant_override("separation", 14)
	grill_box.alignment = BoxContainer.ALIGNMENT_CENTER
	mitte.add_child(grill_box)
	_callout = Label.new()
	_callout.name = "Callout"
	_callout.theme_type_variation = &"HeadlineLabel"
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.text = " "
	grill_box.add_child(_callout)
	_patty_btn = SquishButton.new()
	_patty_btn.name = "PattyKnopf"
	_patty_btn.focus_mode = Control.FOCUS_NONE
	_patty_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_patty_btn.pressed.connect(_on_patty_tap)
	_patty_btn.button_down.connect(_on_aktion_down)
	_patty_btn.button_up.connect(_on_aktion_up)
	grill_box.add_child(_patty_btn)
	_garbar = ProgressBar.new()
	_garbar.name = "GarBalken"
	_garbar.min_value = 0.0
	_garbar.max_value = 1.0
	_garbar.show_percentage = false
	_garbar.custom_minimum_size = Vector2(0.0, 10.0)
	grill_box.add_child(_garbar)

	var intro_teile := McGoobySchichtOverlays.intro(self)
	_intro_overlay = intro_teile["overlay"]
	_intro_karte = intro_teile["karte"]
	_intro_knopf = intro_teile["knopf"]
	_intro_knopf.pressed.connect(_on_intro_bestaetigt)

	var ende_teile := McGoobySchichtOverlays.ende(self)
	_ende_overlay = ende_teile["overlay"]
	_ende_karte = ende_teile["karte"]
	_ende_zeilen = ende_teile["zeilen"]
	_angebot_box = ende_teile["angebot_box"]
	_angebot_knopf = ende_teile["angebot_knopf"]
	_angebot_knopf.pressed.connect(_on_angebot_pressed)
	_nochmal_knopf = ende_teile["nochmal"]
	_nochmal_knopf.pressed.connect(_on_nochmal_pressed)
	_feierabend_knopf = ende_teile["feierabend"]
	_feierabend_knopf.pressed.connect(_on_feierabend_pressed)

	_buehne_ui = McGoobyBuehne.new()
	_buehne_ui.auftritt_fertig.connect(_on_buehne_fertig)
	add_child(_buehne_ui)

	_pause_modal = MinigamePauseModal.new()
	_pause_modal.name = "PauseModal"
	_pause_modal.hint_key = "dlc_mcgooby.schicht.hilfe"
	_pause_modal.resume_requested.connect(_on_resume)
	_pause_modal.restart_requested.connect(_on_restart)
	_pause_modal.quit_requested.connect(_on_quit)
	add_child(_pause_modal)


## Demo ↔ Voll-Modus umschalten (nach Kauf in place, Muster _nach_kauf).
func _modus_anwenden() -> void:
	_stationen_block.visible = _voll
	_pause_modal.hint_key = (
		"dlc_mcgooby.schicht.hilfe_voll" if _voll else "dlc_mcgooby.schicht.hilfe"
	)


## ---------------------------------------------------------------- Ablauf


func _zeige_intro() -> void:
	_intro_overlay.visible = true
	UiMotion.pop_in(_intro_karte)


func _on_intro_bestaetigt() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	McGoobyState.setze_intro_gesehen(_gs)
	_intro_overlay.visible = false
	_starte_schicht()


func _starte_schicht() -> void:
	if _voll:
		_folge_voll = McGoobySchichtPlan.plan(
			_basis_seed() + _runde, McGoobyKatalog.rezepte_interaktiv(), _bal
		)
		_laeuft = not _folge_voll.is_empty()
	else:
		_folge = McGoobySchichtLogic.bestell_folge(_basis_seed() + _runde, _menu, _bal)
		_laeuft = not _folge.is_empty()
	_ende_overlay.visible = false
	_ergebnisse = []
	_kasse = {}
	_punkte = 0
	_perfekt_gesamt = 0
	_salz_treffer = 0
	_buehne_trinkgeld = 0
	_salz_aktiv = false
	_haelt = false
	_bestellung_idx = -1
	_pausiert = false
	_buehne_ui.reset()
	_buehne_knopf_aktualisieren()
	_punkte_anzeigen()
	_callout.text = " "
	if _laeuft:
		_naechste_bestellung()
	else:
		push_warning("McGooby: kein Rezept im Menü — Schicht startet nicht.")


func _naechste_bestellung() -> void:
	_bestellung_idx += 1
	_bestellung_punkte = 0
	_bestellung_fehlerfrei = true
	# Bestellglocken-„Pling“ (Doc §2.2.6) aus dem Bestand: gvz_wave-Glocke.
	AudioDirector.try_play(self, "gvz_wave")
	if _voll:
		_position_idx = 0
		_aufgabe_idx = -1
		_naechste_aufgabe()
		return
	_patty_idx = 0
	_bestellung_anzeigen()
	_naechster_patty()


func _naechster_patty() -> void:
	_patty_idx += 1
	_patty_zeit = 0.0
	_patty_zustand = McGoobySchichtLogic.ZUSTAND_ROH
	_patty_timing = McGoobyKatalog.timing("grill", _rezept_aktuell())
	_patty_aktiv = true
	# Brutzel-Start: der Patty landet raschelnd-zischend auf dem Grill.
	AudioDirector.try_play(self, "ranch_heu")
	_bestellung_anzeigen()
	_patty_visualisieren()


## Nächste Aufgabe der vollen Schicht: Posten-Warteschlange abarbeiten,
## dann nächster Posten, dann Bestellung fertig (Welle-B-Walker).
func _naechste_aufgabe() -> void:
	_aufgabe_idx += 1
	if _aufgabe_idx >= _aufgaben_der_position().size():
		if _position_idx + 1 < _positionen_aktuell().size():
			_position_idx += 1
			_aufgabe_idx = -1
			_naechste_aufgabe()
		else:
			_bestellung_fertig()
		return
	_patty_zeit = 0.0
	_patty_zustand = McGoobySchichtLogic.ZUSTAND_ROH
	_patty_timing = McGoobySchichtPlan.timing_fuer(aufgabe_aktuell(), _rezept_aktuell())
	_patty_aktiv = true
	_haelt = false
	AudioDirector.try_play(self, "ranch_heu")
	_stationen_ui.aktiviere(str(aufgabe_aktuell().get("station", "")))
	_anzeige_voll()
	_patty_visualisieren()


## Demo-Tap (pressed, Welle A unverändert) — die volle Schicht läuft über
## button_down/button_up (_on_aktion_down/_on_aktion_up).
func _on_patty_tap() -> void:
	if _voll:
		return
	if not _laeuft or _pausiert or not _patty_aktiv:
		return
	var wertung := McGoobySchichtLogic.bewerte_tap(_patty_zeit, _patty_timing, _bal)
	if str(wertung["wertung"]) == McGoobySchichtLogic.WERTUNG_ROH:
		# Zu früh ist keine Strafe: sanfter Tick, der Patty brät weiter.
		AudioDirector.try_play(self, "ui_tick")
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.roh"))
		return
	_werte_patty(wertung)


## Voll-Modus, Druck-Moment: Salz-Tap, Halte-Beginn oder Grill-Tap (am
## DRUCK bewertet — fairer für Timing-Fenster als der Loslass-Moment).
func _on_aktion_down() -> void:
	if not _voll or not _laeuft or _pausiert or _buehne_ui.laeuft():
		return
	if _salz_aktiv:
		_salz_tippen()
		return
	if not _patty_aktiv:
		return
	if str(aufgabe_aktuell().get("art", "")) == McGoobySchichtPlan.ART_HALTEN:
		# Korb ins Öl / Hahn auf: ab jetzt läuft die Gar-Zeit.
		_haelt = true
		AudioDirector.try_play(self, "ranch_heu")
		_patty_visualisieren()
		return
	var wertung := McGoobySchichtLogic.bewerte_tap(_patty_zeit, _patty_timing, _bal)
	if str(wertung["wertung"]) == McGoobySchichtLogic.WERTUNG_ROH:
		AudioDirector.try_play(self, "ui_tick")
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.roh"))
		return
	_werte_aufgabe(wertung)


## Voll-Modus, Loslass-Moment einer Halte-Aufgabe: im goldenen Fenster =
## „Perfekt!“, zu früh = nichts Schlimmes (Korb darf wieder rein, die
## Zeit steht solange), zu spät = Röstaroma/Schaumkrone.
func _on_aktion_up() -> void:
	if not _haelt:
		return
	_haelt = false
	if not _voll or not _laeuft or _pausiert or not _patty_aktiv:
		return
	var aufgabe := aufgabe_aktuell()
	var wertung := McGoobySchichtLogic.bewerte_tap(_patty_zeit, _patty_timing, _bal)
	if str(wertung["wertung"]) == McGoobySchichtLogic.WERTUNG_ROH:
		AudioDirector.try_play(self, "ui_tick")
		var key := "zu_leer" if str(aufgabe.get("station", "")) == "getraenke" else "zu_blass"
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht." + key))
		_patty_visualisieren()
		return
	_werte_aufgabe(wertung)


func _werte_patty(wertung: Dictionary) -> void:
	_patty_aktiv = false
	var punkte := int(wertung["punkte"])
	_punkte += punkte
	_bestellung_punkte += punkte
	if str(wertung["wertung"]) == McGoobySchichtLogic.WERTUNG_PERFEKT:
		_perfekt_gesamt += 1
		AudioDirector.try_play(self, "mg_perfect")
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.perfekt"))
	else:
		_bestellung_fehlerfrei = false
		AudioDirector.try_play(self, "mg_spill")
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.roestaroma"))
	_punkte_anzeigen()
	var bestellung := bestellung_aktuell()
	if _patty_idx < int(bestellung.get("patties", 1)):
		_naechster_patty()
	else:
		_bestellung_fertig()


## Voll-Modus-Wertung einer Aufgabe; Fritteuse-Aufgaben mit Salz-Schritt
## öffnen danach den Salz-Moment (Doc §2.2 #3) statt direkt weiterzugehen.
func _werte_aufgabe(wertung: Dictionary) -> void:
	var aufgabe := aufgabe_aktuell()
	_patty_aktiv = false
	_haelt = false
	var punkte := int(wertung["punkte"])
	_punkte += punkte
	_bestellung_punkte += punkte
	if str(wertung["wertung"]) == McGoobySchichtLogic.WERTUNG_PERFEKT:
		_perfekt_gesamt += 1
		AudioDirector.try_play(self, "mg_perfect")
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.perfekt"))
	else:
		_bestellung_fehlerfrei = false
		AudioDirector.try_play(self, "mg_spill")
		# Sprudel-Gag: Getränke schäumen über statt zu verkohlen.
		var key := (
			"uebergesprudelt" if str(aufgabe.get("station", "")) == "getraenke" else "roestaroma"
		)
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht." + key))
	_punkte_anzeigen()
	if bool(aufgabe.get("salz", false)):
		_salz_starten()
	else:
		_naechste_aufgabe()


## ---------------------------------------------------------------- Salz


func _salz_starten() -> void:
	_salz_aktiv = true
	_salz_zeit = 0.0
	AudioDirector.try_play(self, "ui_open")
	_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.salz_jetzt"))
	_patty_visualisieren()


## Salz-Tap: im Fenster = Glitzersalz-Bonus, danach passiert NICHTS
## Schlimmes (kein Fail — nur kein Bonus, Doc §2.2 #3).
func _salz_tippen() -> void:
	var wertung := McGoobySchichtPlan.salz_bewerten(_salz_zeit, _bal)
	if bool(wertung["getroffen"]):
		var punkte := int(wertung["punkte"])
		_punkte += punkte
		_bestellung_punkte += punkte
		_salz_treffer += 1
		AudioDirector.try_play(self, "mg_perfect")
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.glitzersalz"))
		_punkte_anzeigen()
	else:
		AudioDirector.try_play(self, "ui_tick")
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.salz_vorbei"))
	_salz_beenden()


func _salz_beenden() -> void:
	_salz_aktiv = false
	_naechste_aufgabe()


## ---------------------------------------------------------------- Bühne


## Maskottchen-Auftritt (1×/Schicht): Show + Kunden-Jubel; der Bonus ist
## TRINKGELD (Kassensturz-Zeile), nie Punkte — die Goldwerte bleiben rein.
func _on_buehne_pressed() -> void:
	if not _voll or not _laeuft or _pausiert:
		return
	if _buehne_ui.laeuft() or _buehne_ui.schon_aufgetreten():
		return
	McGoobyState.buehne_verbuchen(_gs)
	_buehne_trinkgeld = maxi(0, int(_bal.get("buehne_trinkgeld", 6)))
	_buehne_ui.starte_auftritt()
	_buehne_knopf_aktualisieren()


func _on_buehne_fertig() -> void:
	AudioDirector.try_play(self, "ui_coins")
	_callout_zeigen(I18nService.t("dlc_mcgooby.buehne.trinkgeld", {"betrag": _buehne_trinkgeld}))


func _buehne_knopf_aktualisieren() -> void:
	if _buehne_knopf == null:
		return
	_buehne_knopf.disabled = not _laeuft or _buehne_ui.schon_aufgetreten()


## ---------------------------------------------------------------- Ende


func _bestellung_fertig() -> void:
	var bonus := int(_bal.get("bestellung_fertig_bonus", 15))
	_punkte += bonus
	_bestellung_punkte += bonus
	_ergebnisse.append({"punkte": _bestellung_punkte, "fehlerfrei": _bestellung_fehlerfrei})
	# Münz-Einnahme-Moment: die Kasse klimpert pro fertiger Bestellung.
	AudioDirector.try_play(self, "ui_coins")
	_punkte_anzeigen()
	var gesamt := _folge_voll.size() if _voll else _folge.size()
	if _bestellung_idx + 1 < gesamt:
		_naechste_bestellung()
	else:
		_schicht_ende()


func _schicht_ende() -> void:
	_laeuft = false
	_patty_aktiv = false
	_salz_aktiv = false
	_haelt = false
	_kasse = McGoobyAbrechnung.abrechnung(_ergebnisse, _bal, _buehne_trinkgeld)
	AudioDirector.try_play(self, "mg_win")
	_muenzen_gutschreiben(int(_kasse.get("muenzen", 0)))
	McGoobyState.schicht_verbuchen(_gs, _punkte)
	_buehne_knopf_aktualisieren()
	_ende_fuellen()
	_ende_overlay.visible = true
	UiMotion.pop_in(_ende_karte)


func _ende_fuellen() -> void:
	for kind in _ende_zeilen.get_children():
		kind.queue_free()
	_ende_zeile("punkte", str(int(_kasse.get("punkte", 0))))
	_ende_zeile("perfekt", str(_perfekt_gesamt))
	if _salz_treffer > 0:
		_ende_zeile("salz", str(_salz_treffer))
	_ende_zeile("trinkgeld", str(int(_kasse.get("trinkgeld", 0))))
	if int(_kasse.get("buehne_trinkgeld", 0)) > 0:
		_ende_zeile("buehne", str(int(_kasse.get("buehne_trinkgeld", 0))))
	_ende_zeile("muenzen", str(int(_kasse.get("muenzen", 0))))
	# Welle B: der Übergang „Schicht geschafft → Angebot“ (Doc §6.2) lebt
	# als Block AUF der Ende-Karte — kein Auto-Overlay, damit „Nochmal“/
	# „Feierabend“ direkt tippbar bleiben (Playtest-Flow-Kontrakt).
	_angebot_box.visible = not McGoobyState.ist_gekauft(_gs)


func _ende_zeile(key: String, wert: String) -> void:
	McGoobySchichtOverlays.ende_zeile(_ende_zeilen, key, wert)


## Angebots-Knopf der Ende-Karte: öffnet das Kauf-Sheet; nach dem Kauf
## startet die VOLLE Schicht in place (kein Routen-Remount nötig).
func _on_angebot_pressed() -> void:
	AudioDirector.try_play(self, "ui_open")
	McGoobyOffer.zeige(self, _gs, _nach_kauf)


func _nach_kauf() -> void:
	_voll = McGoobyState.ist_gekauft(_gs)
	_modus_anwenden()
	_apply_metrics()
	_runde += 1
	_starte_schicht()


## ---------------------------------------------------------------- Anzeige


func _bestellung_anzeigen() -> void:
	var bestellung := bestellung_aktuell()
	_bestellung_label.text = I18nService.t(
		"dlc_mcgooby.schicht.bestellung",
		{"nr": int(bestellung.get("nr", 0)), "gesamt": _folge.size()}
	)
	_gericht_label.text = McGoobyKatalog.text_von(_rezept_aktuell(), "name")
	_patty_label.text = I18nService.t(
		"dlc_mcgooby.schicht.patty", {"nr": _patty_idx, "gesamt": int(bestellung.get("patties", 1))}
	)


## Zettel-Anzeige der vollen Schicht: Bestellung → Posten → Schritt
## (+ Becher-Größe bei Zapf-Aufgaben) + Gesten-Hilfezeile der Station.
func _anzeige_voll() -> void:
	var bestellung := bestellung_aktuell()
	_bestellung_label.text = I18nService.t(
		"dlc_mcgooby.schicht.bestellung",
		{"nr": int(bestellung.get("nr", 0)), "gesamt": _folge_voll.size()}
	)
	_gericht_label.text = (
		I18nService
		. t(
			"dlc_mcgooby.schicht.posten",
			{
				"nr": _position_idx + 1,
				"gesamt": _positionen_aktuell().size(),
				"gericht": McGoobyKatalog.text_von(_rezept_aktuell(), "name"),
			}
		)
	)
	var aufgabe := aufgabe_aktuell()
	var station := str(aufgabe.get("station", ""))
	var teile: Array[String] = [
		I18nService.t(
			"dlc_mcgooby.schicht.aufgabe",
			{"nr": _aufgabe_idx + 1, "gesamt": _aufgaben_der_position().size()}
		),
		McGoobyKatalog.text_von(McGoobyKatalog.station(station), "name"),
	]
	var becher := str(aufgabe.get("becher", ""))
	if not becher.is_empty():
		teile.append(I18nService.t("dlc_mcgooby.schicht.becher." + becher))
	_patty_label.text = " · ".join(teile)
	_hilfe_label.text = McGoobyStationenUi.geste_von(station)


func _punkte_anzeigen() -> void:
	_punkte_label.text = I18nService.t("dlc_mcgooby.schicht.punkte", {"punkte": _punkte})


func _callout_zeigen(text: String) -> void:
	_callout.text = text
	UiMotion.bounce(_callout)


func _patty_visualisieren() -> void:
	if _patty_btn == null:
		return
	if _voll:
		_aufgabe_visualisieren()
		return
	var farbe := FARBE_ROH
	var text_farbe := FARBE_TEXT_DUNKEL
	var hinweis := I18nService.t("dlc_mcgooby.schicht.roh")
	match _patty_zustand:
		McGoobySchichtLogic.ZUSTAND_GOLDBRAUN:
			farbe = FARBE_GOLDBRAUN
			hinweis = I18nService.t("dlc_mcgooby.schicht.goldbraun")
		McGoobySchichtLogic.ZUSTAND_KOHLE:
			farbe = FARBE_KOHLE
			text_farbe = FARBE_TEXT_HELL
			hinweis = I18nService.t("dlc_mcgooby.schicht.kohle")
	McGoobyStationenUi.stil_anwenden(_patty_btn, farbe, text_farbe, hinweis)
	_garbar.value = McGoobySchichtLogic.fortschritt(_patty_zeit, _patty_timing)


## Aktions-Knopf-Gesicht der vollen Schicht (Stil aus McGoobyStationenUi);
## der Balken zeigt beim Salz-Moment das ablaufende Fenster (Countdown).
func _aufgabe_visualisieren() -> void:
	var stil := McGoobyStationenUi.stil_fuer(aufgabe_aktuell(), _patty_zustand, _haelt, _salz_aktiv)
	McGoobyStationenUi.stil_anwenden(
		_patty_btn, stil["farbe"], stil["text_farbe"], str(stil["text"])
	)
	if _salz_aktiv:
		var fenster := McGoobySchichtPlan.salz_fenster_sec(_bal)
		_garbar.value = 1.0 - clampf(_salz_zeit / fenster, 0.0, 1.0)
	else:
		_garbar.value = McGoobySchichtLogic.fortschritt(_patty_zeit, _patty_timing)


func _apply_metrics() -> void:
	if not is_inside_tree():
		return
	_m = ScreenShell.metrics(get_viewport())
	var f := float(_m["f"])
	ScreenShell.content_frame(_rows, _m)
	ScreenShell.touch_target(_back, _m)
	ScreenShell.touch_target(_pause_btn, _m)
	for knopf: Button in [
		_intro_knopf, _nochmal_knopf, _feierabend_knopf, _angebot_knopf, _buehne_knopf
	]:
		if knopf != null:
			ScreenShell.touch_target(knopf, _m)
	if _stationen_ui != null:
		_stationen_ui.apply_metrics(_m)
	if _buehne_ui != null:
		_buehne_ui.apply_metrics(_m)
	var patty_seite := maxf(float(_m["floor_px"]), PATTY_BASIS * f)
	_patty_btn.custom_minimum_size = Vector2(patty_seite, patty_seite)
	_garbar.custom_minimum_size = Vector2(patty_seite, 10.0 * f)
	for karte: PanelContainer in [_intro_karte, _ende_karte]:
		if karte != null:
			karte.custom_minimum_size.x = ScreenShell.card_width(_m, KARTE_BASIS)
	ScreenShell.scale_fonts(self, f)
	_patty_visualisieren()


## ---------------------------------------------------------------- Steuerung


func _on_pause_pressed() -> void:
	if _pause_modal.is_open():
		return
	AudioDirector.try_play(self, "ui_open")
	_pausiert = true
	_pause_modal.open()


func _on_resume() -> void:
	_pausiert = false


func _on_restart() -> void:
	_pausiert = false
	_starte_schicht()


func _on_quit() -> void:
	_navigiere_zurueck()


func _on_nochmal_pressed() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	_runde += 1
	_starte_schicht()


func _on_feierabend_pressed() -> void:
	AudioDirector.try_play(self, "ui_back")
	_navigiere_zurueck()


func _on_back_pressed() -> void:
	AudioDirector.try_play(self, "ui_back")
	_navigiere_zurueck()


## Pill-Tap: die Gesten-Hilfe der Station in die Hilfezeile heben.
func _on_pill_hilfe(station_id: String) -> void:
	_hilfe_label.text = McGoobyStationenUi.geste_von(station_id)
	UiMotion.bounce(_hilfe_label)


func _navigiere_zurueck() -> void:
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	if router.has_method("handle_back_request") and router.handle_back_request():
		return
	if router.has_method("goto"):
		router.goto(&"home", {})


## ---------------------------------------------------------------- Intern


func _rezept_aktuell() -> Dictionary:
	if _voll:
		var positionen := _positionen_aktuell()
		if _position_idx >= 0 and _position_idx < positionen.size():
			var position: Dictionary = positionen[_position_idx]
			return McGoobyKatalog.rezept(str(position.get("rezept_id", "")))
		return {}
	return McGoobyKatalog.rezept(str(bestellung_aktuell().get("rezept_id", "")))


func _positionen_aktuell() -> Array:
	var raw: Variant = bestellung_aktuell().get("positionen", [])
	return raw if raw is Array else []


func _aufgaben_der_position() -> Array:
	var positionen := _positionen_aktuell()
	if _position_idx >= 0 and _position_idx < positionen.size():
		var raw: Variant = (positionen[_position_idx] as Dictionary).get("aufgaben", [])
		return raw if raw is Array else []
	return []


func _basis_seed() -> int:
	if seed_override != 0:
		return seed_override
	# Tages-Seed wie MarktSim (Doc §4.1: gleicher Tag = gleicher Kundenstrom).
	return Time.get_date_string_from_system().hash()


func _muenzen_gutschreiben(betrag: int) -> void:
	if _gs == null or betrag <= 0:
		return
	if _gs.has_method("update"):
		_gs.update(_muenzen_update.bind(betrag))
	elif _gs.has_method("set_value"):
		var coins := int(_gs.get_value("economy.coins", 0))
		_gs.set_value("economy.coins", coins + betrag)


## Münzen über den EINEN Geld-Pfad (Economy.award) verbuchen.
func _muenzen_update(state: Dictionary, betrag: int) -> void:
	if state.get("economy") is Dictionary:
		Economy.award(state["economy"], betrag, "mcgooby")

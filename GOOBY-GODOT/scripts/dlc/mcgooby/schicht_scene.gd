class_name McGoobySchichtScene
extends Control
## McGooby-Schicht (Welle A+B+C, Doc §2.2 #1–#4): VIER Stationen mit
## Tab-Wechsel unten in der Daumen-Zone. Grill = taktiles Wenden im goldenen
## Timing-Fenster; Belegstation = Zutaten in Ticket-Reihenfolge aufs
## Brötchen wischen (McGoobyStationBelegen); Fritteuse = Korb im goldenen
## Fenster ziehen (McGoobyStationFritteuse, Möhren-Fenster enger); Shake-
## Bar = Becher halten und kreisen, bis die Flausch-Krone steht
## (McGoobyStationShake — die Rühr-Zeit läuft NUR, solange gehalten wird).
## 2–4 Kunden-Bestellungen nacheinander (deterministisch aus dem Tages-
## Seed, McGoobySchichtLogic — Welle C zieht aus ALLEN Rezepten; Grill-/
## Fritteusen-Timer laufen weiter, egal welcher Tab offen ist: DAS ist die
## Jonglage), „Perfekt!“-Ketten-Callout über Stationen hinweg (Doc §2.2.5),
## Bestellglocke + Brutzel-Feedback aus BESTEHENDEN SfxMap-Ids, Schicht-
## Ende-Karte mit Kassensturz (McGoobyAbrechnung) + Laden-Rang-Fortschritt
## (McGoobyFortschritt, Welle C). Beim Erststart erzählt eine Dialog-Karte
## den Eröffnungs-Hook (Doc §1.3); der Haken wird im additiven Save-Slice
## `mcgooby` gemerkt (McGoobyState). Jederzeit pausierbar
## (MinigamePauseModal-Muster).
##
## Demo-Gate Welle B: VOR dem Kauf ist die Schicht die kostenlose
## Probeschicht — genau EINE pro lokalem Tag (McGoobyState.schicht_erlaubt,
## Zeit injiziert). Ist die Demo verbraucht, zeigt die Szene die
## Sperre-Karte („Für heute Feierabend“) mit Angebots-Abzweig; nach dem
## Kauf gibt es keine Sperre und der „Noch eine Schicht“-Knopf kehrt zurück.
##
## Route `mcgooby_schicht` — der DLC-Hub (P24) verweist per Katalog-Eintrag
## hierher; die Route registriert sich selbst (Muster ChessScene/DlcScreen),
## der Hub muss nur `register_routes()` + `goto()`.

signal ready_for_reveal

const Economy := preload("res://scripts/logic/economy.gd")

const ROUTE := &"mcgooby_schicht"
const ROUTES := {ROUTE: "res://scripts/dlc/mcgooby/schicht_scene.tscn"}

## Wunschgröße des Patty-Knopfs (Design-px, skaliert mit f; nie unter Floor).
const PATTY_BASIS := 168.0
## Karten-Wunschbreite der Intro-/Ende-Overlays (Design-px).
const KARTE_BASIS := 360.0

## Stations-Phasen einer Bestellung (Doc §2.2, Reihenfolge = Rezept-Plan).
const PHASE_GRILL := "grill"
const PHASE_BELEGEN := "belegen"
const PHASE_FRITTEUSE := "fritteuse"
const PHASE_SHAKE := "shake"

## Tests/Screenshots: GameState-Double statt /root/GameState.
var gs_override: Object = null
## Tests: fester Seed statt Tages-Seed (0 = Tages-Seed).
var seed_override := 0
## Tests: Navigation abschaltbar.
var auto_navigate := true

var _gs: Object = null
var _bal: Dictionary = {}
var _menu: Array = []
var _folge: Array[Dictionary] = []
var _runde := 0
var _laeuft := false
var _pausiert := false
var _bestellung_idx := 0
## Generischer Runden-Timer der AKTIVEN Timing-Station (Grill/Fritteuse/
## Shake teilen ihn — die _patty_*-Namen bleiben als stabile Griffe der
## Tests/Playtest-Flows aus Welle A/B erhalten).
var _patty_idx := 0
var _patty_zeit := 0.0
var _patty_aktiv := false
var _patty_timing: Dictionary = {}
var _patty_zustand := McGoobySchichtLogic.ZUSTAND_ROH
## W18/4: steht gerade der Früh-Tap-Hinweis „noch roh!“ im Callout? Der
## gilt nur, solange die Runde WIRKLICH im Start-Zustand ist.
var _callout_roh_offen := false
var _punkte := 0
var _perfekt_gesamt := 0
var _bestellung_punkte := 0
var _bestellung_fehlerfrei := true
var _ergebnisse: Array[Dictionary] = []
var _kasse: Dictionary = {}
var _m: Dictionary = {}
## Stations-Phasen-Plan der aktuellen Bestellung (Welle C: phasen_von).
var _phasen: Array[String] = []
var _phase_idx := 0
var _phase := PHASE_GRILL
var _station_aktiv := PHASE_GRILL
## Runden-Beschriftungen der aktiven Timing-Phase (Aktions-Ids: wenden,
## frittieren, glitzersalz, mixen … — Anzahl = Runden der Phase).
var _runden_aktionen: Array[String] = []
var _belegen_ticket: Array[String] = []
var _belegen_platziert := 0
## Shake-Bar (Welle C): Rühr-Zeit läuft nur, solange der Becher gehalten wird.
var _shake_ruehrt := false
## „Perfekt!“-Kette über Stationen hinweg (reißt bei Röstaroma/Fehlgriff).
var _kette := 0

var _rows: VBoxContainer
var _back: Button
var _pause_btn: Button
var _punkte_label: Label
var _bestellung_label: Label
var _gericht_label: Label
var _patty_label: Label
var _callout: Label
var _grill_box: VBoxContainer
var _patty_btn: Button
var _garbar: ProgressBar
var _frit_box: VBoxContainer
var _frit_btn: Button
var _frit_balken: ProgressBar
var _frit_hinweis: Label
var _shake_box: VBoxContainer
var _shake_btn: Button
var _shake_balken: ProgressBar
var _shake_hinweis: Label
var _belegen_box: VBoxContainer
var _belegen_status: Label
var _belegen_turm: Label
var _belegen_hinweis: Label
var _zutaten_leiste: HBoxContainer
var _tab_knoepfe: Dictionary = {}
## Stations-Griffe der Timing-Stationen (Phase → Knopf/Balken, Welle C).
var _stations_knoepfe: Dictionary = {}
var _stations_balken: Dictionary = {}
## Stations-Deko-Controls (W20, McGoobySchichtDeko — für _apply_metrics).
var _dekos: Array[McGoobySchichtDeko] = []
var _intro_overlay: Control
var _intro_karte: PanelContainer
var _intro_knopf: Button
var _ende_overlay: Control
var _ende_karte: PanelContainer
var _ende_zeilen: VBoxContainer
var _nochmal_knopf: Button
var _demo_hinweis: Label
var _ende_angebot_knopf: Button
var _feierabend_knopf: Button
var _sperre_overlay: Control
var _sperre_karte: PanelContainer
var _sperre_angebot_knopf: Button
var _sperre_feierabend_knopf: Button
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
	_bal = McGoobyKatalog.balance()
	# Welle C: ALLE 10 Rezepte sind bestellbar (bestell_folge mischt fair).
	_menu = McGoobyKatalog.rezepte()
	_build_ui()
	_apply_metrics()
	get_viewport().size_changed.connect(_apply_metrics)
	# Demo-Gate (Welle B): VOR dem Kauf genau EINE Probeschicht pro Tag —
	# ist sie verbraucht, gibt es die Sperre-Karte statt Intro/Schicht.
	if not McGoobyState.schicht_erlaubt(_gs, McGoobyState.heute_tag(_gs)):
		_zeige_sperre()
	elif McGoobyState.ist_intro_gesehen(_gs):
		_starte_schicht()
	else:
		_zeige_intro()
	ready_for_reveal.emit()


func receive_params(params: Dictionary) -> void:
	seed_override = int(params.get("seed", seed_override))


func _process(delta: float) -> void:
	if not _laeuft or _pausiert or not _patty_aktiv:
		return
	# Shake-Bar rührt sich NICHT von allein (Welle C): die Rühr-Zeit läuft
	# nur, solange der Becher gehalten wird — Grill/Fritteuse garen weiter.
	if _phase == PHASE_SHAKE and not _shake_ruehrt:
		return
	_patty_zeit += delta
	var timing := _patty_timing
	var zustand := McGoobySchichtLogic.runde_zustand(_phase, _patty_zeit, _patty_timing)
	if zustand != _patty_zustand:
		var frueher := _patty_zustand
		_patty_zustand_setzen(zustand)
		# Brutzel-Feedback: der Sprung ins goldene Fenster „ploppt“ hörbar.
		if frueher == str(_skin()["start"]):
			AudioDirector.try_play(self, "mg_good")
	_runde_visualisieren()
	# Vergessene Runden lösen sich nach dem Nachlauf freundlich selbst auf
	# (Röstaroma/Knusper-Deluxe/Schaum, halbe Punkte — nie ein Fail-State,
	# Doc §4.2; die Shake-Krone überschäumt nur beim aktiven Weiterrühren).
	var ende := (
		float(timing.get("gar_sec", 4.0))
		+ float(timing.get("fenster_sec", 1.4))
		+ float(timing.get("nachlauf_sec", 2.0))
	)
	if _patty_zeit >= ende:
		_werte_runde(McGoobySchichtLogic.runde_vergessen(_phase, _bal))


## ---------------------------------------------------------------- Test-API


func ist_intro_offen() -> bool:
	return _intro_overlay != null and _intro_overlay.visible


func ist_ende_offen() -> bool:
	return _ende_overlay != null and _ende_overlay.visible


func ist_sperre_offen() -> bool:
	return _sperre_overlay != null and _sperre_overlay.visible


func ist_am_laufen() -> bool:
	return _laeuft and not _pausiert


## Stations-Phase der aktuellen Bestellung (PHASE_GRILL/PHASE_BELEGEN).
func phase_aktuell() -> String:
	return _phase


## Welche Station der Spieler gerade ansieht (Tab-Zustand).
func station_aktiv() -> String:
	return _station_aktiv


func belegen_ticket() -> Array[String]:
	return _belegen_ticket.duplicate()


func belegen_platziert() -> int:
	return _belegen_platziert


## Zutaten-Knöpfe der Leiste in Anzeige-Reihenfolge (Tests wischen darüber).
func zutaten_knoepfe() -> Array[Button]:
	var out: Array[Button] = []
	for kind in _zutaten_leiste.get_children():
		if kind is Button:
			out.append(kind)
	return out


func bestellung_aktuell() -> Dictionary:
	if _bestellung_idx >= 0 and _bestellung_idx < _folge.size():
		return _folge[_bestellung_idx]
	return {}


func schicht_ergebnis() -> Dictionary:
	return _kasse.duplicate(true)


## Timing-Fenster der AKTIVEN Runde (Tests pinnen darüber die Fenster-Mitte
## der jeweiligen Station — Fritteuse/Shake haben andere gar_sec).
func timing_aktuell() -> Dictionary:
	return _patty_timing.duplicate(true)


## Aktions-Id der aktiven Timing-Runde („wenden“, „frittieren“, „mixen“ …).
func runde_aktion_aktuell() -> String:
	if _patty_idx >= 1 and _patty_idx <= _runden_aktionen.size():
		return _runden_aktionen[_patty_idx - 1]
	return ""


## Tests: Runden-Zeit der aktiven Timing-Station pinnen (statt Frames
## abzuwarten) — gilt für Grill, Fritteuse UND Shake-Bar (Welle C).
func patty_zeit_setzen(t_sec: float) -> void:
	_patty_zeit = maxf(0.0, t_sec)
	_patty_zustand_setzen(McGoobySchichtLogic.runde_zustand(_phase, _patty_zeit, _patty_timing))
	_runde_visualisieren()


## Timing-Knopf der AKTIVEN Station (Grill-Patty, Fritten-Korb, Shake-
## Becher) — stabiler Griff der Tests/Flows über alle Timing-Stationen.
func patty_knopf() -> Button:
	return stations_knopf(_phase)


func stations_knopf(station_id: String) -> Button:
	return _stations_knoepfe.get(station_id, _patty_btn)


## ---------------------------------------------------------------- Aufbau


func _build_ui() -> void:
	# Grundgerüst (Kopfzeile/Bestellkarte/Stationen-Mitte) aus dem CI-Split
	# (McGoobySchichtUiTeile) — hier passiert NUR Ref-Merken + Verdrahten.
	var grund := McGoobySchichtUiTeile.grundgeruest(self)
	_rows = grund["rows"]
	_back = grund["back"]
	_back.pressed.connect(_on_back_pressed)
	_pause_btn = grund["pause"]
	_pause_btn.pressed.connect(_on_pause_pressed)
	_punkte_label = grund["punkte"]
	_bestellung_label = grund["bestellung"]
	_gericht_label = grund["gericht"]
	_patty_label = grund["patty"]
	_callout = grund["callout"]
	var stationen_box: VBoxContainer = grund["stationen"]

	# Die drei Timing-Stationen teilen sich die timing_box-Optik (Welle C);
	# der Shake-Becher rührt per Halten (button_down/up).
	var grill := McGoobySchichtUiTeile.timing_box("GrillBox", "PattyKnopf", "GarBalken")
	_grill_box = grill["box"]
	_patty_btn = grill["knopf"]
	_garbar = grill["balken"]
	(grill["hinweis"] as Label).text = McGoobyKatalog.text_von(
		McGoobyKatalog.station(PHASE_GRILL), "geste"
	)
	_patty_btn.pressed.connect(_on_runden_tap.bind(PHASE_GRILL))
	stationen_box.add_child(_grill_box)

	_belegen_box = _baue_belegen_box()
	stationen_box.add_child(_belegen_box)

	var frit := McGoobySchichtUiTeile.timing_box("FritteuseBox", "KorbKnopf", "FritBalken")
	_frit_box = frit["box"]
	_frit_btn = frit["knopf"]
	_frit_balken = frit["balken"]
	_frit_hinweis = frit["hinweis"]
	_frit_hinweis.text = McGoobyKatalog.text_von(McGoobyKatalog.station(PHASE_FRITTEUSE), "geste")
	_frit_btn.pressed.connect(_on_runden_tap.bind(PHASE_FRITTEUSE))
	stationen_box.add_child(_frit_box)
	var shake := McGoobySchichtUiTeile.timing_box("ShakeBox", "BecherKnopf", "KroneBalken")
	_shake_box = shake["box"]
	_shake_btn = shake["knopf"]
	_shake_balken = shake["balken"]
	_shake_hinweis = shake["hinweis"]
	_shake_hinweis.text = I18nService.t("dlc_mcgooby.schicht.shake_hinweis")
	_shake_btn.button_down.connect(_on_shake_halten.bind(true))
	_shake_btn.button_up.connect(_on_shake_halten.bind(false))
	_shake_btn.pressed.connect(_on_runden_tap.bind(PHASE_SHAKE))
	stationen_box.add_child(_shake_box)

	# Stabile Griffe der Timing-Stationen (Tests/Flows + Visualisierung).
	_stations_knoepfe = {
		PHASE_GRILL: _patty_btn, PHASE_FRITTEUSE: _frit_btn, PHASE_SHAKE: _shake_btn
	}
	_stations_balken = {
		PHASE_GRILL: _garbar, PHASE_FRITTEUSE: _frit_balken, PHASE_SHAKE: _shake_balken
	}

	# Stations-Deko (W20): je Station 1–2 prozedurale Szenen-Details über
	# dem großen Knopf — die Tabs unterscheiden sich damit auch optisch.
	var boxen := {
		PHASE_GRILL: _grill_box,
		PHASE_BELEGEN: _belegen_box,
		PHASE_FRITTEUSE: _frit_box,
		PHASE_SHAKE: _shake_box,
	}
	for station_id: String in boxen:
		_dekos.append(McGoobySchichtDeko.haenge_oben(boxen[station_id], station_id))

	var tabs := McGoobySchichtUiTeile.tabs_leiste(_rows)
	_tab_knoepfe = tabs["knoepfe"]
	for station_id: String in _tab_knoepfe:
		(_tab_knoepfe[station_id] as Button).pressed.connect(_on_tab_pressed.bind(station_id))

	_intro_overlay = _baue_intro_overlay()
	_ende_overlay = _baue_ende_overlay()
	_sperre_overlay = _baue_sperre_overlay()
	wechsle_station(PHASE_GRILL)
	_belegen_anzeigen()

	_pause_modal = MinigamePauseModal.new()
	_pause_modal.name = "PauseModal"
	_pause_modal.hint_key = "dlc_mcgooby.schicht.hilfe"
	_pause_modal.resume_requested.connect(_on_resume)
	_pause_modal.restart_requested.connect(_on_restart)
	_pause_modal.quit_requested.connect(_on_quit)
	add_child(_pause_modal)


## Overlays/Belegen-Box kommen aus McGoobySchichtUiTeile (CI-Split, Muster
## GoobyeLadenUiTeile) — hier passiert NUR noch Ref-Merken + Verdrahten.
func _baue_intro_overlay() -> Control:
	var teile := McGoobySchichtUiTeile.intro_overlay(self)
	_intro_karte = teile["karte"]
	_intro_knopf = teile["knopf"]
	_intro_knopf.pressed.connect(_on_intro_bestaetigt)
	return teile["overlay"]


func _baue_ende_overlay() -> Control:
	var teile := McGoobySchichtUiTeile.ende_overlay(self)
	_ende_karte = teile["karte"]
	_ende_zeilen = teile["zeilen"]
	_nochmal_knopf = teile["nochmal"]
	_nochmal_knopf.pressed.connect(_on_nochmal_pressed)
	_demo_hinweis = teile["demo_hinweis"]
	_ende_angebot_knopf = teile["angebot"]
	_ende_angebot_knopf.pressed.connect(_on_angebot_pressed)
	_feierabend_knopf = teile["feierabend"]
	_feierabend_knopf.pressed.connect(_on_feierabend_pressed)
	return teile["overlay"]


## Belegstation (Doc §2.2 #2): Ticket-Turm + Zutaten-Leiste. Sichtbar wird
## sie über den Belegen-Tab; ohne aktives Ticket ruft freundlich der Grill.
func _baue_belegen_box() -> VBoxContainer:
	var teile := McGoobySchichtUiTeile.belegen_box()
	_belegen_status = teile["status"]
	_belegen_turm = teile["turm"]
	_belegen_hinweis = teile["hinweis"]
	_zutaten_leiste = teile["leiste"]
	return teile["box"]


## Sperre-Karte des Demo-Gates (Welle B): die Tages-Probeschicht ist
## verbraucht — ehrlicher Hinweis, Angebots-Abzweig (falls freigeschaltet)
## und Feierabend-Knopf. Nach dem Kauf erscheint sie nie.
func _baue_sperre_overlay() -> Control:
	var teile := McGoobySchichtUiTeile.sperre_overlay(self)
	_sperre_karte = teile["karte"]
	_sperre_angebot_knopf = teile["angebot"]
	_sperre_angebot_knopf.pressed.connect(_on_angebot_pressed)
	_sperre_feierabend_knopf = teile["feierabend"]
	_sperre_feierabend_knopf.pressed.connect(_on_feierabend_pressed)
	return teile["overlay"]


## ---------------------------------------------------------------- Ablauf


func _zeige_intro() -> void:
	_intro_overlay.visible = true
	UiMotion.pop_in(_intro_karte)


## Demo-Gate-Sperre (Welle B): heute schon probiert — Angebot nur zeigen,
## wenn der Kauf überhaupt freigeschaltet ist (Level-Gate, Doc §6.2).
func _zeige_sperre() -> void:
	_laeuft = false
	_sperre_angebot_knopf.visible = (
		not McGoobyState.ist_gekauft(_gs) and McGoobyState.ist_freigeschaltet(_gs)
	)
	_sperre_overlay.visible = true
	UiMotion.pop_in(_sperre_karte)


func _on_intro_bestaetigt() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	McGoobyState.setze_intro_gesehen(_gs)
	_intro_overlay.visible = false
	_starte_schicht()


func _starte_schicht() -> void:
	_folge = McGoobySchichtLogic.bestell_folge(_basis_seed() + _runde, _menu, _bal)
	_ende_overlay.visible = false
	_ergebnisse = []
	_kasse = {}
	_punkte = 0
	_perfekt_gesamt = 0
	_kette = 0
	_bestellung_idx = -1
	_laeuft = not _folge.is_empty()
	_pausiert = false
	_punkte_anzeigen()
	_callout.text = " "
	_callout_roh_offen = false
	if _laeuft:
		# Demo-Stempel des Tages (idempotent, nach Kauf No-op) — der
		# Pause-Neustart derselben Schicht bleibt dadurch erlaubt.
		McGoobyState.demo_verbuchen(_gs, McGoobyState.heute_tag(_gs))
		_naechste_bestellung()
	else:
		push_warning("McGooby: leeres Menü — Schicht startet nicht.")


func _naechste_bestellung() -> void:
	_bestellung_idx += 1
	_bestellung_punkte = 0
	_bestellung_fehlerfrei = true
	_patty_idx = 0
	_patty_aktiv = false
	_belegen_ticket = []
	_belegen_platziert = 0
	# Stations-Plan des Rezepts (Welle C): Phasen in Arbeits-Reihenfolge.
	_phasen = McGoobySchichtLogic.phasen_von(_rezept_aktuell())
	_phase_idx = -1
	_belegen_anzeigen()
	# Bestellglocken-„Pling“ (Doc §2.2.6) aus dem Bestand: gvz_wave-Glocke.
	AudioDirector.try_play(self, "gvz_wave")
	_naechste_phase()


## Nächste Stations-Phase der Bestellung starten (Welle C): Grill/
## Fritteuse/Shake sind Timing-Runden, Belegen der Zutaten-Turm. Phasen
## ohne Arbeit (leeres Ticket/keine Aktionen) werden freundlich
## übersprungen; nach der letzten Phase ist die Bestellung fertig.
func _naechste_phase() -> void:
	_phase_idx += 1
	if _phase_idx >= _phasen.size():
		_bestellung_fertig()
		return
	var station := _phasen[_phase_idx]
	var bestellung := bestellung_aktuell()
	match station:
		PHASE_BELEGEN:
			_belegen_ticket = McGoobyStationBelegen.ticket_von(_rezept_aktuell())
			if _belegen_ticket.is_empty():
				_naechste_phase()
				return
			_phase = PHASE_BELEGEN
			_belegen_platziert = 0
			_baue_zutaten_leiste()
			_belegen_anzeigen()
		PHASE_GRILL:
			_runden_aktionen = []
			for _i in int(bestellung.get("patties", 0)):
				_runden_aktionen.append("wenden")
			if _runden_aktionen.is_empty():
				_naechste_phase()
				return
			_phase = PHASE_GRILL
			_patty_idx = 0
			_naechste_runde()
		PHASE_FRITTEUSE, PHASE_SHAKE:
			var logik := (
				McGoobyStationFritteuse if station == PHASE_FRITTEUSE else McGoobyStationShake
			)
			_runden_aktionen = logik.aktionen_von(_rezept_aktuell())
			if _runden_aktionen.is_empty():
				_naechste_phase()
				return
			_phase = station
			_patty_idx = 0
			_naechste_runde()
		_:
			_naechste_phase()
			return
	_bestellung_anzeigen()
	# Der Blick folgt der Arbeit (Cooking-Mama-Führung): die neue Station
	# klappt auf, ihr Tab hüpft — zurückwechseln bleibt jederzeit frei
	# (und die Timer der anderen Stationen laufen weiter: Jonglage).
	wechsle_station(_phase)
	if _tab_knoepfe.has(_phase):
		UiMotion.bounce(_tab_knoepfe[_phase])


## Nächste Timing-Runde der aktiven Phase (Grill-Patty, Fritten-Korb,
## Shake-Becher) — Skin/Timing kommen von der Station, der Runden-Timer
## ist geteilt (_patty_*, stabile Test-/Flow-Griffe).
func _naechste_runde() -> void:
	_patty_idx += 1
	_patty_zeit = 0.0
	_patty_zustand = str(_skin()["start"])
	_patty_timing = McGoobyKatalog.timing(_phase, _rezept_aktuell())
	_patty_aktiv = true
	_shake_ruehrt = false
	# Brutzel-/Blubber-Start: die Runde landet raschelnd auf der Station.
	AudioDirector.try_play(self, "ranch_heu")
	_bestellung_anzeigen()
	_runde_visualisieren()


## Timing-Tap der Stations-Knöpfe (Grill wenden, Korb ziehen, Kreisen
## stoppen — pressed feuert beim Loslassen, die Halte-Geste stimmt).
func _on_runden_tap(station_id: String) -> void:
	if not _laeuft or _pausiert or not _patty_aktiv or _phase != station_id:
		return
	var wertung := McGoobySchichtLogic.runde_bewerten(_phase, _patty_zeit, _patty_timing, _bal)
	if str(wertung["wertung"]) == str(_skin()["start"]):
		# Zu früh ist keine Strafe: sanfter Tick, die Runde läuft weiter.
		AudioDirector.try_play(self, "ui_tick")
		var skin: Dictionary = _skin()
		var text_key: String = (skin["texte"] as Dictionary)[str(skin["start"])]
		_callout_zeigen(I18nService.t("dlc_mcgooby." + text_key), true)
		return
	_werte_runde(wertung)


## Shake-Bar (Welle C): Halten = kreisen — die Rühr-Zeit läuft in _process
## nur bei _shake_ruehrt (Grill/Fritteuse garen derweil weiter).
func _on_shake_halten(haelt: bool) -> void:
	_shake_ruehrt = haelt and _laeuft and not _pausiert and _phase == PHASE_SHAKE


func _werte_runde(wertung: Dictionary) -> void:
	_patty_aktiv = false
	_shake_ruehrt = false
	_punkte_verbuchen(int(wertung["punkte"]))
	if str(wertung["wertung"]) == McGoobySchichtLogic.WERTUNG_PERFEKT:
		_perfekt_gesamt += 1
		_kette += 1
		AudioDirector.try_play(self, "mg_perfect")
		_callout_zeigen(_kette_text(I18nService.t("dlc_mcgooby.schicht.perfekt")))
	else:
		_bestellung_fehlerfrei = false
		_kette = 0
		AudioDirector.try_play(self, "mg_spill")
		_callout_zeigen(I18nService.t("dlc_mcgooby." + str(_skin()["spaet_callout"])))
	_punkte_anzeigen()
	if _patty_idx < _runden_aktionen.size():
		_naechste_runde()
	else:
		_naechste_phase()


## Ein Wisch aus der Zutaten-Leiste (Tap = barrierefreie Geste, §2.2.7).
func _on_zutat_gewischt(zutat_id: String) -> void:
	if not _laeuft or _pausiert or _phase != PHASE_BELEGEN:
		return
	var wertung := McGoobyStationBelegen.bewerte_wisch(
		_belegen_ticket, _belegen_platziert, zutat_id, _bal
	)
	_punkte_verbuchen(int(wertung["punkte"]))
	if str(wertung["wertung"]) == McGoobyStationBelegen.WERTUNG_RICHTIG:
		_belegen_platziert = int(wertung["platziert"])
		_kette += 1
		AudioDirector.try_play(self, "mg_good")
		_callout_zeigen(_kette_text(I18nService.t("dlc_mcgooby.schicht.passt")))
	else:
		_bestellung_fehlerfrei = false
		_kette = 0
		AudioDirector.try_play(self, "mg_spill")
		_callout_zeigen(I18nService.t("dlc_mcgooby.schicht.falsch"))
	_punkte_anzeigen()
	_belegen_anzeigen()
	_bestellung_anzeigen()
	if McGoobyStationBelegen.ist_fertig(_belegen_ticket, _belegen_platziert):
		_naechste_phase()


func _bestellung_fertig() -> void:
	_phase = PHASE_GRILL
	_punkte_verbuchen(int(_bal.get("bestellung_fertig_bonus", 15)))
	_ergebnisse.append({"punkte": _bestellung_punkte, "fehlerfrei": _bestellung_fehlerfrei})
	# Münz-Einnahme-Moment: die Kasse klimpert pro fertiger Bestellung.
	AudioDirector.try_play(self, "ui_coins")
	_punkte_anzeigen()
	if _bestellung_idx + 1 < _folge.size():
		_naechste_bestellung()
	else:
		_schicht_ende()


## Punkte-Buchung an EINER Stelle: die Bestellung fällt nie unter 0
## (burger_build-Grammatik — Malusse knabbern, sie bestrafen nicht),
## der Schicht-Zähler bewegt sich um exakt dieselbe Differenz.
func _punkte_verbuchen(delta: int) -> void:
	var neu := maxi(0, _bestellung_punkte + delta)
	_punkte += neu - _bestellung_punkte
	_bestellung_punkte = neu


## „Perfekt!“-Kette über Stationen hinweg (Doc §2.2.5-Gefühl): ab der
## zweiten fehlerfreien Aktion in Folge zeigt der Callout die Kette.
func _kette_text(basis: String) -> String:
	if _kette >= 2:
		return I18nService.t("dlc_mcgooby.schicht.kette", {"n": _kette})
	return basis


func _schicht_ende() -> void:
	_laeuft = false
	_patty_aktiv = false
	_shake_ruehrt = false
	_kasse = McGoobyAbrechnung.abrechnung(_ergebnisse, _bal)
	AudioDirector.try_play(self, "mg_win")
	_muenzen_gutschreiben(int(_kasse.get("muenzen", 0)))
	# Rang VOR der Verbuchung merken (W20): nur ein ECHTER Aufstieg dieser
	# Schicht darf feiern — Alt-Saves bekommen kein Nachhol-Konfetti.
	var rang_vorher := McGoobyFortschritt.sterne(_gs)
	McGoobyState.schicht_verbuchen(_gs, _punkte, int(_kasse.get("fehlerfreie", 0)) == _folge.size())
	# Kassensturz + Laden-Rang (Welle C) füllt der CI-Split — die Schicht
	# ist zu diesem Zeitpunkt schon verbucht, der Rang also aktuell.
	McGoobySchichtUiTeile.ende_fuellen(_ende_zeilen, _kasse, _perfekt_gesamt, _gs)
	# Demo-Variante (Welle B): die Tages-Probeschicht ist verbraucht —
	# „Noch eine Schicht“ weicht dem ehrlichen Hinweis + Angebots-Abzweig.
	var demo := _gs != null and not McGoobyState.ist_gekauft(_gs)
	_nochmal_knopf.visible = not demo
	_demo_hinweis.visible = demo
	_ende_angebot_knopf.visible = demo and McGoobyState.ist_freigeschaltet(_gs)
	_ende_overlay.visible = true
	UiMotion.pop_in(_ende_karte)
	# Rang-Aufstiegs-Beat (W20 Top-10 #1): genau EINMAL pro erreichter
	# Stufe (Save-Latch rangGefeiert) — der Beat legt sich als letztes
	# Szenen-Kind ÜBER die Ende-Karte (kein CanvasLayer nötig, s. Feier).
	var aufstieg := McGoobyFortschritt.aufstieg_pruefen(_gs, rang_vorher)
	if bool(aufstieg["feiern"]):
		McGoobyRangFeier.zeige_in(self, int(aufstieg["stern"]))


## ---------------------------------------------------------------- Anzeige


func _bestellung_anzeigen() -> void:
	var bestellung := bestellung_aktuell()
	_bestellung_label.text = I18nService.t(
		"dlc_mcgooby.schicht.bestellung",
		{"nr": int(bestellung.get("nr", 0)), "gesamt": _folge.size()}
	)
	_gericht_label.text = McGoobyKatalog.text_von(_rezept_aktuell(), "name")
	match _phase:
		PHASE_BELEGEN:
			_patty_label.text = I18nService.t(
				"dlc_mcgooby.schicht.turm",
				{"platziert": _belegen_platziert, "gesamt": _belegen_ticket.size()}
			)
		PHASE_FRITTEUSE, PHASE_SHAKE:
			_patty_label.text = (
				I18nService
				. t(
					"dlc_mcgooby.schicht.schritt",
					{
						"nr": _patty_idx,
						"gesamt": _runden_aktionen.size(),
						"aktion": I18nService.t("dlc_mcgooby.aktion." + runde_aktion_aktuell()),
					}
				)
			)
		_:
			_patty_label.text = I18nService.t(
				"dlc_mcgooby.schicht.patty",
				{"nr": _patty_idx, "gesamt": int(bestellung.get("patties", 1))}
			)


func _punkte_anzeigen() -> void:
	_punkte_label.text = I18nService.t("dlc_mcgooby.schicht.punkte", {"punkte": _punkte})


## ------------------------------------------------------- Belegstation-UI


## Zutaten-Leiste zum aktuellen Ticket neu bestücken (jede Zutat EINMAL,
## Erst-Auftauch-Reihenfolge — McGoobyStationBelegen.leiste, ohne RNG).
func _baue_zutaten_leiste() -> void:
	for kind in _zutaten_leiste.get_children():
		# Sofort AUS dem Baum nehmen: mit queue_free allein stünden die
		# alten Namen bis zum Frame-Ende im Weg und Godot benennte die
		# neuen Knöpfe um (@Button@…) — Zutat_<id> wäre nicht mehr findbar.
		_zutaten_leiste.remove_child(kind)
		kind.queue_free()
	for zutat_id: String in McGoobyStationBelegen.leiste(_belegen_ticket):
		var knopf := SquishButton.new()
		knopf.name = "Zutat_" + zutat_id
		knopf.theme_type_variation = &"BtnTeal"
		knopf.text = _zutat_name(zutat_id)
		knopf.focus_mode = Control.FOCUS_NONE
		knopf.pressed.connect(_on_zutat_gewischt.bind(zutat_id))
		_zutaten_leiste.add_child(knopf)
		if not _m.is_empty():
			ScreenShell.touch_target(knopf, _m)


## Belegstation-Anzeige: Ticket-Turm (✔ platziert, ▶ als Nächstes) oder —
## ohne aktives Ticket — der freundliche „Grill ruft“-Hinweis.
func _belegen_anzeigen() -> void:
	if _belegen_box == null:
		return
	var offen := _phase == PHASE_BELEGEN
	_belegen_status.visible = offen
	_belegen_turm.visible = offen
	_zutaten_leiste.visible = offen
	_belegen_hinweis.visible = not offen
	if not offen:
		return
	_belegen_status.text = I18nService.t(
		"dlc_mcgooby.schicht.turm",
		{"platziert": _belegen_platziert, "gesamt": _belegen_ticket.size()}
	)
	var teile: PackedStringArray = PackedStringArray()
	for i in _belegen_ticket.size():
		var zutat := _zutat_name(_belegen_ticket[i])
		if i < _belegen_platziert:
			teile.append("✔ " + zutat)
		elif i == _belegen_platziert:
			teile.append("▶ " + zutat)
		else:
			teile.append(zutat)
	_belegen_turm.text = " · ".join(teile)


func _zutat_name(zutat_id: String) -> String:
	return I18nService.t("dlc_mcgooby.zutat." + zutat_id)


## roh_hinweis: Früh-Tap-Callout, der nur für den ROHEN Patty gilt und beim
## nächsten Zustandswechsel geräumt wird (W18/4: „noch roh!“ stand sonst
## dauerhaft über dem längst goldbraunen/verkohlten Patty).
func _callout_zeigen(text: String, roh_hinweis := false) -> void:
	_callout_roh_offen = roh_hinweis
	_callout.text = text
	UiMotion.bounce(_callout)


## Zustandswechsel an EINER Stelle (Prozess-Tick + Test-API patty_zeit_setzen):
## sobald die Runde nicht mehr im Start-Zustand ist, hat der Früh-Tap-
## Hinweis gelogen — Callout leeren statt ihn stehen zu lassen (W18/4).
func _patty_zustand_setzen(zustand: String) -> void:
	if zustand == _patty_zustand:
		return
	_patty_zustand = zustand
	if _callout_roh_offen and zustand != str(_skin()["start"]):
		_callout_roh_offen = false
		_callout.text = " "


## ------------------------------------------- Timing-Runden (Welle C)


## Anzeige-Skin der aktiven Timing-Station (Grill als Fallback — auch
## während der Belegen-Phase zeigt der Grill-Tab den letzten Stand).
func _skin() -> Dictionary:
	return McGoobySchichtUiTeile.skin(_phase)


## Knopf + Balken der aktiven Timing-Station nachziehen — der geteilte
## Skin (McGoobySchichtUiTeile.RUNDEN_SKIN) macht Grill, Fritteuse und
## Shake-Bar zu EINER Visualisierungs-Strecke.
func _runde_visualisieren() -> void:
	var knopf := patty_knopf()
	if knopf == null:
		return
	McGoobySchichtUiTeile.runde_stil_anwenden(knopf, _phase, _patty_zustand)
	var balken: ProgressBar = _stations_balken.get(_phase, _garbar)
	if balken != null:
		balken.value = McGoobySchichtLogic.runde_fortschritt(_phase, _patty_zeit, _patty_timing)


func _apply_metrics() -> void:
	if not is_inside_tree():
		return
	_m = ScreenShell.metrics(get_viewport())
	var f := float(_m["f"])
	ScreenShell.content_frame(_rows, _m)
	ScreenShell.touch_target(_back, _m)
	ScreenShell.touch_target(_pause_btn, _m)
	for knopf: Button in [
		_intro_knopf,
		_nochmal_knopf,
		_ende_angebot_knopf,
		_feierabend_knopf,
		_sperre_angebot_knopf,
		_sperre_feierabend_knopf,
	]:
		if knopf != null:
			ScreenShell.touch_target(knopf, _m)
	for tab: Button in _tab_knoepfe.values():
		ScreenShell.touch_target(tab, _m)
	for zutat in _zutaten_leiste.get_children():
		if zutat is Button:
			ScreenShell.touch_target(zutat, _m)
	var patty_seite := maxf(float(_m["floor_px"]), PATTY_BASIS * f)
	for timing_knopf: Button in [_patty_btn, _frit_btn, _shake_btn]:
		timing_knopf.custom_minimum_size = Vector2(patty_seite, patty_seite)
	for balken: ProgressBar in [_garbar, _frit_balken, _shake_balken]:
		balken.custom_minimum_size = Vector2(patty_seite, 10.0 * f)
	var karten_breite := ScreenShell.card_width(_m, KARTE_BASIS)
	_belegen_turm.custom_minimum_size.x = karten_breite
	for hinweis: Label in [_frit_hinweis, _shake_hinweis]:
		hinweis.custom_minimum_size.x = karten_breite
	for karte: PanelContainer in [_intro_karte, _ende_karte, _sperre_karte]:
		if karte != null:
			karte.custom_minimum_size.x = karten_breite
	for deko: McGoobySchichtDeko in _dekos:
		deko.skaliere(f)
	ScreenShell.scale_fonts(self, f)
	_runde_visualisieren()


## ---------------------------------------------------------------- Steuerung


## Stations-Wechsel per Tab-Tap (Doc §2.2) — reine Ansichtssache: die
## Phasen-Logik läuft unabhängig weiter (der Patty brät auch, während man
## am Belegen-Tab steht — DAS ist die Jonglage).
func wechsle_station(station_id: String) -> void:
	if not _tab_knoepfe.has(station_id):
		return
	_station_aktiv = station_id
	_grill_box.visible = station_id == PHASE_GRILL
	_belegen_box.visible = station_id == PHASE_BELEGEN
	_frit_box.visible = station_id == PHASE_FRITTEUSE
	_shake_box.visible = station_id == PHASE_SHAKE
	for id: String in _tab_knoepfe:
		var tab: Button = _tab_knoepfe[id]
		tab.theme_type_variation = &"BtnTeal" if id == station_id else &"BtnGhost"


func _on_tab_pressed(station_id: String) -> void:
	if station_id == _station_aktiv:
		return
	AudioDirector.try_play(self, "ui_chip")
	wechsle_station(station_id)


## Angebots-Abzweig aus Sperre-/Ende-Karte: das Kauf-Sheet legt sich über
## die Szene (McGoobyOffer prüft Level/Kaufstand selbst — fail-closed).
func _on_angebot_pressed() -> void:
	AudioDirector.try_play(self, "ui_open")
	McGoobyOffer.zeige(self, _gs)


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
	return McGoobyKatalog.rezept(str(bestellung_aktuell().get("rezept_id", "")))


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

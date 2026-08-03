class_name MarktStandSheet
extends VBoxContainer
## W15/MARKT — UI des EIGENEN Marktstands (Doc D §6.3), das Samstags-Ritual:
##   1. BESTÜCKEN (vor Marktbeginn): Lager-Auswahl mit Mengen (Garten-Ernte,
##      Selbstgebautes, Souvenirs) + PREIS-SLIDER je Ware (±50 % um den
##      Basiswert) + Nachfrage-Vorschau des Tages.
##   2. MARKTTAG: ZUSCHAUEN (komprimiertes Replay der deterministischen
##      MarktSim — Verkaufs-Pling + Münz-Float, die Kunden-Goobys draußen
##      hüpfen über die Signale mit) ODER direkt das Ergebnis abholen.
##   3. ABRECHNUNGS-KARTE: verkauft/übrig/Erlös/Beste Ware; Unverkauftes
##      liegt danach wieder im Lager.
##
## Zustand/Buchung kommen komplett aus MarktStand/MarktSim (pure Logik) —
## dieses Sheet ist reine Anzeige, Muster MarktSheet/BaumarktSheet.

signal replay_gestartet
signal verkauf_gezeigt(ware_id: String, preis: int)
signal replay_beendet
signal abgeholt(erloes: int)

## Replay-Takt pro Kunden-Event (Reduced Motion springt).
const REPLAY_SCHRITT_S := 0.4
const SLIDER_BREITE := 150.0

var gs: Object
## Tests/Screenshots frieren die Zeit ein (< 0 = echte Systemzeit).
var zeit_override := -1
## Erste-Male-Karte zeigen (setzt der Ort beim ersten Besuch).
var erstes_mal := false

var _replay_laeuft := false
## Beim letzten Refresh eingebuchte Kräuterkasten-Bünde (Kopf-Hinweis).
var _kraeuter_ertrag := 0


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func unix_s() -> int:
	if zeit_override >= 0:
		return zeit_override
	return int(Time.get_unix_time_from_system())


func aktualisiere() -> void:
	if _replay_laeuft:
		return
	# Craft-Synergie (W15/MARKT): fällige Kräuterkasten-Bünde JETZT
	# einbuchen — sie liegen damit sofort im Lager-Angebot unten.
	_kraeuter_ertrag = KraeuterKasten.schoepfe(gs, unix_s())
	for kind in get_children():
		kind.queue_free()
	var status := MarktStand.status(gs, unix_s())
	_baue_kopf(status)
	match status:
		MarktStand.STATUS_LEER, MarktStand.STATUS_WARTET:
			_baue_bestuecken()
		MarktStand.STATUS_LAEUFT, MarktStand.STATUS_FERTIG:
			_baue_markttag(status)


## ------------------------------------------------------------------ Kopf


func _baue_kopf(status: String) -> void:
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t("markt.stand.titel"), "HeadlineLabel")
	var tag := str(MarktStand.slice_von(gs).get("tag", ""))
	if tag.is_empty():
		tag = MarktStand.naechster_markt_tag(unix_s())
	var modifikator := MarktSim.tagesmodifikator(MarktSim.tages_seed(tag))
	var geliebt := str(modifikator.get("ware", ""))
	if not geliebt.is_empty():
		CitySheetBausteine.label(
			karte,
			I18nService.t(
				"markt.stand.nachfrage",
				{"ware": MarktWaren.anzeigename(geliebt, I18nService.get_locale())}
			),
			"CaptionLabel"
		)
	CitySheetBausteine.label(karte, I18nService.t("markt.status.%s" % status), "CaptionLabel")
	CitySheetBausteine.label(karte, _tages_kommentar(tag), "CaptionLabel")
	if _kraeuter_ertrag > 0:
		CitySheetBausteine.label(
			karte, I18nService.t("markt.kraeuter.ertrag", {"n": _kraeuter_ertrag}), "CaptionLabel"
		)
	if erstes_mal:
		var erste := CitySheetBausteine.karte(self)
		CitySheetBausteine.label(erste, I18nService.t("markt.erste_male.titel"), "HeadlineLabel")
		CitySheetBausteine.label(erste, I18nService.t("markt.erste_male.text"), "CaptionLabel")
	CitySheetBausteine.coins_zeile(self, _coins())


## Markt-Kommentar des Tages (deterministische Rotation über den Tages-Seed;
## dieselben 3 Lines stehen der SeeleRunner.kommentar-API als Kategorie
## "markt.stand" offen — s. >> MARKT→VOICE im Handoff).
func _tages_kommentar(tag: String) -> String:
	var n := posmod(MarktSim.tages_seed(tag), 3) + 1
	return I18nService.t("markt.kommentar.%d" % n)


## ------------------------------------------------------------- Bestücken


func _baue_bestuecken() -> void:
	var slots: Array = MarktStand.slice_von(gs)["slots"]
	if not slots.is_empty():
		CitySheetBausteine.label(self, I18nService.t("markt.stand.slots"), "HeadlineLabel")
		for slot: Dictionary in slots:
			_baue_slot_zeile(slot)
		CitySheetBausteine.label(
			self,
			I18nService.t("markt.stand.slots_frei", {"n": MarktStand.SLOT_MAX - slots.size()}),
			"CaptionLabel"
		)
	CitySheetBausteine.label(self, I18nService.t("markt.lager.titel"), "HeadlineLabel")
	var angebot := MarktWaren.angebot(gs, I18nService.get_locale())
	if angebot.is_empty() and slots.is_empty():
		CitySheetBausteine.label(self, I18nService.t("markt.lager.leer"))
		return
	var liste := CitySheetBausteine.scroll_liste(self, CitySheetBausteine.LISTE_HOEHE_KURZ)
	for eintrag: Dictionary in angebot:
		_baue_lager_zeile(liste, eintrag)


## Slot-Zeile: Name ×Menge, Preis-Slider (±50 % um den Basiswert) und
## Runter-Knopf (alles zurück ins Lager).
func _baue_slot_zeile(slot: Dictionary) -> void:
	var ware := str(slot["ware"])
	var faktor := float(slot["faktor"])
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 8)
	add_child(zeile)
	var texte := VBoxContainer.new()
	texte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(texte)
	var name_label := Label.new()
	name_label.text = (
		I18nService
		. t(
			"markt.slot.zeile",
			{
				"name": MarktWaren.anzeigename(ware, I18nService.get_locale()),
				"n": int(slot["menge"]),
			}
		)
	)
	texte.add_child(name_label)
	var preis_label := Label.new()
	preis_label.theme_type_variation = "CaptionLabel"
	preis_label.text = _preis_text(ware, faktor)
	texte.add_child(preis_label)
	var slider := HSlider.new()
	slider.min_value = MarktStand.FAKTOR_MIN
	slider.max_value = MarktStand.FAKTOR_MAX
	slider.step = 0.05
	slider.value = faktor
	slider.custom_minimum_size = Vector2(SLIDER_BREITE, 0.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(
		func(wert: float) -> void:
			MarktStand.set_faktor(gs, unix_s(), ware, wert)
			preis_label.text = _preis_text(ware, MarktStand.clamp_faktor(wert))
	)
	zeile.add_child(slider)
	var runter := Button.new()
	runter.theme_type_variation = "GhostButton"
	runter.text = I18nService.t("markt.slot.runter")
	runter.pressed.connect(
		func() -> void:
			MarktStand.entnehme(gs, unix_s(), ware, int(slot["menge"]))
			AudioDirector.try_play(self, "ui_back")
			aktualisiere()
	)
	zeile.add_child(runter)


func _baue_lager_zeile(liste: Control, eintrag: Dictionary) -> void:
	var id := str(eintrag["id"])
	var vorrat := int(eintrag["vorrat"])
	# Bestücken ist KEIN Kauf: Druck stumm (""), der Ausgang klingt in
	# _bestuecke (ui_chip/ui_error) — Outcome schlägt Press (W16 F1).
	var zeile := CitySheetBausteine.kauf_zeile(
		liste,
		"%s — %d ᴳ" % [str(eintrag["name"]), int(eintrag["basis"])],
		I18nService.t("markt.lager.vorrat", {"n": vorrat}),
		I18nService.t("markt.lager.plus_eins"),
		vorrat > 0,
		func() -> void: _bestuecke(id, 1),
		""
	)
	if vorrat <= 1:
		return
	var alle := Button.new()
	alle.theme_type_variation = "PrimaryButton"
	alle.text = I18nService.t("markt.lager.plus_alle", {"n": vorrat})
	alle.custom_minimum_size = Vector2(CitySheetBausteine.KNOPF_ZWEIT_BREITE, 0.0)
	alle.pressed.connect(func() -> void: _bestuecke(id, vorrat))
	zeile.add_child(alle)


func _bestuecke(ware_id: String, menge: int) -> void:
	var slots: Array = MarktStand.slice_von(gs)["slots"]
	var index := -1
	for i in slots.size():
		if str((slots[i] as Dictionary)["ware"]) == ware_id:
			index = i
	var faktor := 1.0 if index < 0 else float((slots[index] as Dictionary)["faktor"])
	var res := MarktStand.bestuecke(gs, unix_s(), ware_id, menge, faktor)
	if not bool(res["ok"]):
		AudioDirector.try_play(self, "ui_error")
		return
	AudioDirector.try_play(self, "ui_chip")
	aktualisiere()


func _preis_text(ware: String, faktor: float) -> String:
	return I18nService.t(
		"markt.slot.preis",
		{"preis": MarktSim.stueckpreis(ware, faktor), "basis": MarktWaren.basis(ware)}
	)


## -------------------------------------------------------------- Markttag


func _baue_markttag(status: String) -> void:
	CitySheetBausteine.label(self, I18nService.t("markt.markttag.%s" % status), "CaptionLabel")
	var reihe := HBoxContainer.new()
	reihe.add_theme_constant_override("separation", 10)
	add_child(reihe)
	var zuschauen := Button.new()
	zuschauen.theme_type_variation = "AccentButton"
	zuschauen.text = I18nService.t("markt.replay.knopf")
	zuschauen.pressed.connect(_starte_replay)
	reihe.add_child(zuschauen)
	var holen := Button.new()
	holen.theme_type_variation = "PrimaryButton"
	holen.text = I18nService.t("markt.abholen.knopf")
	holen.pressed.connect(_hole_ergebnis)
	reihe.add_child(holen)


## Komprimiertes Replay: Kunden-Events der deterministischen Sim nacheinander
## zeigen (Pling + Münz-Float), danach buchen und die Abrechnung zeigen.
func _starte_replay() -> void:
	if _replay_laeuft:
		return
	var sim := MarktStand.ergebnis(gs)
	if sim.is_empty():
		return
	_replay_laeuft = true
	replay_gestartet.emit()
	for kind in get_children():
		kind.queue_free()
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t("markt.replay.laeuft"), "HeadlineLabel")
	var zeilen := VBoxContainer.new()
	zeilen.add_theme_constant_override("separation", 4)
	karte.add_child(zeilen)
	var schritt := 0.05 if ThemeService.is_reduced_motion(self) else REPLAY_SCHRITT_S
	for event: Dictionary in sim["events"]:
		await get_tree().create_timer(schritt).timeout
		if not is_inside_tree():
			return
		_zeige_event(zeilen, event)
	await get_tree().create_timer(schritt * 2.0).timeout
	_replay_laeuft = false
	replay_beendet.emit()
	if is_inside_tree():
		_hole_ergebnis()


func _zeige_event(zeilen: VBoxContainer, event: Dictionary) -> void:
	var ware := MarktWaren.anzeigename(str(event["ware"]), I18nService.get_locale())
	var zeile := Label.new()
	zeile.theme_type_variation = "CaptionLabel"
	if bool(event["gekauft"]):
		zeile.text = (I18nService.t(
			"markt.replay.kauf", {"name": ware, "preis": int(event["preis"])}
		))
		AudioDirector.try_play(self, "ui_coins")
		_muenz_float(int(event["preis"]))
		verkauf_gezeigt.emit(str(event["ware"]), int(event["preis"]))
	else:
		zeile.text = I18nService.t("markt.replay.vorbei", {"name": ware})
	zeilen.add_child(zeile)
	# Nur die letzten Ereignisse behalten — das Sheet soll nicht mitwachsen.
	while zeilen.get_child_count() > 6:
		zeilen.get_child(0).free()


## Kleiner Münz-Float („+12 ᴳ“ schwebt hoch und verblasst).
func _muenz_float(preis: int) -> void:
	var schwebe := Label.new()
	schwebe.text = "+%d ᴳ" % preis
	schwebe.theme_type_variation = "HeadlineLabel"
	schwebe.z_index = 10
	add_child(schwebe)
	schwebe.position = Vector2(size.x * 0.5 + randf() * 60.0 - 30.0, size.y * 0.4)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(schwebe, "position:y", schwebe.position.y - 48.0, 0.7)
	tween.tween_property(schwebe, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(schwebe.queue_free)


## -------------------------------------------------------------- Abrechnung


func _hole_ergebnis() -> void:
	var karte := MarktStand.abholen(gs, unix_s())
	if karte.is_empty():
		aktualisiere()
		return
	abgeholt.emit(int(karte["erloes"]))
	# J1 Beute-Flug: der Markt-Erlös reist vom Sheet zur Börse (Münz-
	# EINNAHME klingt am Serienende als ui_coins, §3-Grammatik); ohne
	# Erlös bleibt der bisherige Abhol-Klang.
	if not BeuteFlug.fliegen(self, self, int(karte["erloes"])):
		AudioDirector.try_play(self, "ui_buy")
	zeige_abrechnung(karte)


## Abrechnungs-Karte (auch von Tests/Screenshots direkt mit einer fertigen
## Karte aufrufbar): verkauft/übrig/Erlös je Ware, Summe, Beste Ware.
func zeige_abrechnung(karte: Dictionary) -> void:
	for kind in get_children():
		kind.queue_free()
	var box := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(box, I18nService.t("markt.abrechnung.titel"), "HeadlineLabel")
	for zeile: Dictionary in karte["zeilen"]:
		(
			CitySheetBausteine
			. label(
				box,
				(
					I18nService
					. t(
						"markt.abrechnung.zeile",
						{
							"name":
							MarktWaren.anzeigename(str(zeile["ware"]), I18nService.get_locale()),
							"verkauft": int(zeile["verkauft"]),
							"uebrig": int(zeile["uebrig"]),
							"erloes": int(zeile["erloes"]),
						}
					)
				)
			)
		)
	if int(karte["erloes"]) <= 0:
		CitySheetBausteine.label(box, I18nService.t("markt.abrechnung.nichts"), "CaptionLabel")
	else:
		CitySheetBausteine.label(
			box,
			I18nService.t("markt.abrechnung.summe", {"erloes": int(karte["erloes"])}),
			"HeadlineLabel"
		)
	var beste := str(karte.get("beste_ware", ""))
	if not beste.is_empty():
		CitySheetBausteine.label(
			box,
			I18nService.t(
				"markt.abrechnung.beste",
				{"name": MarktWaren.anzeigename(beste, I18nService.get_locale())}
			),
			"CaptionLabel"
		)
	CitySheetBausteine.label(box, I18nService.t("markt.abrechnung.rueck"), "CaptionLabel")
	var ok := Button.new()
	ok.theme_type_variation = "PrimaryButton"
	ok.text = I18nService.t("markt.abrechnung.ok")
	ok.pressed.connect(aktualisiere)
	add_child(ok)


func _coins() -> int:
	if gs == null:
		return 0
	return int(gs.get_value("economy.coins", 0))

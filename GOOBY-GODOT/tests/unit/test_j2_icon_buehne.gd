extends TestCase
## G8/IDEA-J2 „Icon-Bühne + Namensschilder“ — Unit-Wachen für die PURE
## Logik hinter dem Querformat-Labelfix (PT4-B4):
## (a) Langdruck-Geste: ~0,4-s-Schwelle als Einmal-Impuls, Release davor
##     bleibt ein normaler Tap, Emulations-Zwillinge (DEVICE_ID_EMULATION)
##     zählen nicht, Wackeln vor der Schwelle bricht ab, Wandern danach
##     nicht, zweiter Finger prellt ab, Schluck-Flag ist einmalig.
## (b) Parade-Plan: Schienen-Geometrie (rest_plan/entzerre) deterministisch,
##     rechtsbündig an der Blockkante, 2-Spalten-Zeilen teilen sich in
##     oben/unten, Entzerrung erzwingt Mindest-Luft + Grenze; Takt-Formeln.
## (c) Kurzform-Pfad: kurzform_wahl bevorzugt den lesbaren vollen Namen,
##     fällt bewusst auf die gepflegte Kurzform, meldet den Notfall ehrlich.
## (d) Strings: hud.<id>.kurz existiert für alle zehn Kacheln in DE UND EN
##     (Parität), nie länger als der volle Name; Namensschild-Node wählt
##     Voll-/Kurzform wie versprochen.

const SLOP := HudLangdruckGeste.SLOP_PX_DEFAULT
const SCHWELLE := HudLangdruckGeste.SCHWELLE_MS

# ── Event-Bau-Helfer (physisch = device 0, Zwilling = DEVICE_ID_EMULATION) ───


func _maus(gedrueckt: bool, pos: Vector2, emuliert := false) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = gedrueckt
	ev.position = pos
	if emuliert:
		ev.device = InputEvent.DEVICE_ID_EMULATION
	return ev


func _touch(gedrueckt: bool, finger: int, pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = finger
	ev.pressed = gedrueckt
	ev.position = pos
	return ev


func _zug(finger: int, pos: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = finger
	ev.position = pos
	return ev


# ── (a) Langdruck-Geste ──────────────────────────────────────────────────────


func test_langdruck_schwelle_ist_einmal_impuls() -> void:
	var geste := HudLangdruckGeste.new()
	geste.verarbeite(_maus(true, Vector2(10, 10)), 1000)
	assert_true(geste.gedrueckt(), "Druck registriert")
	assert_false(geste.tick(1000 + SCHWELLE - 1), "1 ms vor der Schwelle: kein Impuls")
	assert_false(geste.aktiv(), "vor der Schwelle nicht aktiv")
	assert_true(geste.tick(1000 + SCHWELLE), "genau an der Schwelle: Impuls")
	assert_true(geste.aktiv(), "nach der Schwelle aktiv")
	assert_false(geste.tick(1000 + SCHWELLE + 50), "Impuls feuert nur EINMAL")
	geste.verarbeite(_maus(false, Vector2(10, 10)), 1000 + SCHWELLE + 100)
	assert_false(geste.gedrueckt(), "Release beendet die Geste")
	assert_true(geste.schluckt_tap(), "Release NACH Langdruck schluckt den Tap")
	assert_false(geste.schluckt_tap(), "Schluck-Flag ist einmalig")


func test_langdruck_kurzer_tap_schluckt_nichts() -> void:
	var geste := HudLangdruckGeste.new()
	geste.verarbeite(_maus(true, Vector2(10, 10)), 2000)
	assert_false(geste.tick(2100), "vor der Schwelle kein Impuls")
	geste.verarbeite(_maus(false, Vector2(10, 10)), 2200)
	assert_false(geste.gedrueckt(), "kurzer Tap ist vorbei")
	assert_false(geste.schluckt_tap(), "normaler Tap wird NICHT geschluckt")
	assert_false(geste.tick(2000 + SCHWELLE + 500), "nichts hängt nach")


func test_langdruck_emulations_zwillinge_zaehlen_nicht() -> void:
	var geste := HudLangdruckGeste.new()
	geste.verarbeite(_maus(true, Vector2(5, 5), true), 1000)
	assert_false(geste.gedrueckt(), "emulierter Druck startet KEINE Geste")
	geste.verarbeite(_maus(true, Vector2(5, 5)), 1000)
	geste.verarbeite(_maus(false, Vector2(5, 5), true), 1100)
	assert_true(geste.gedrueckt(), "emulierter Release beendet den echten Druck nicht")
	assert_true(geste.tick(1000 + SCHWELLE), "Schwelle läuft auf der physischen Familie")


func test_langdruck_wackeln_bricht_ab_wandern_danach_nicht() -> void:
	var geste := HudLangdruckGeste.new()
	geste.verarbeite(_touch(true, 0, Vector2.ZERO), 1000)
	geste.verarbeite(_zug(0, Vector2(SLOP, 0.0)), 1100)
	assert_false(geste.gedrueckt(), "Wackeln über der Toleranz VOR der Schwelle = Wisch")
	assert_false(geste.tick(1000 + SCHWELLE), "abgebrochene Geste feuert nie")
	geste.verarbeite(_touch(true, 0, Vector2.ZERO), 3000)
	geste.verarbeite(_zug(0, Vector2(SLOP * 0.5, 0.0)), 3100)
	assert_true(geste.gedrueckt(), "Wackeln UNTER der Toleranz bleibt ein Halten")
	assert_true(geste.tick(3000 + SCHWELLE), "Impuls trotz Mini-Wackler")
	geste.verarbeite(_zug(0, Vector2(SLOP * 3.0, 0.0)), 3600)
	assert_true(geste.aktiv(), "NACH der Schwelle darf der Finger wandern")
	geste.verarbeite(_touch(false, 0, Vector2(SLOP * 3.0, 0.0)), 3700)
	assert_true(geste.schluckt_tap(), "gewanderter Langdruck schluckt den Release-Tap")


func test_langdruck_zweiter_finger_und_reset() -> void:
	var geste := HudLangdruckGeste.new()
	geste.verarbeite(_touch(true, 0, Vector2.ZERO), 1000)
	geste.verarbeite(_touch(true, 1, Vector2(50, 0)), 1100)
	geste.verarbeite(_touch(false, 1, Vector2(50, 0)), 1150)
	assert_true(geste.gedrueckt(), "Kinder-Doppelgriff: der erste Finger behält Vorrang")
	assert_true(geste.tick(1000 + SCHWELLE), "Schwelle läuft auf Finger 0 weiter")
	geste.zuruecksetzen()
	assert_false(geste.gedrueckt(), "Reset räumt das Halten")
	assert_false(geste.aktiv(), "Reset räumt den Langdruck")
	assert_false(geste.schluckt_tap(), "Reset lässt kein Schluck-Flag zurück")
	geste.verarbeite(_maus(true, Vector2.ZERO), 5000)
	assert_true(geste.tick(5000 + SCHWELLE), "nach Reset startet eine frische Geste")
	geste.verarbeite(_maus(false, Vector2.ZERO), 5000 + SCHWELLE + 10)
	geste.schluck_verfallen()
	assert_false(geste.schluckt_tap(), "schluck_verfallen räumt ein liegengebliebenes Flag")


# ── (b) Parade-Plan (Schienen-Geometrie + Takt) ──────────────────────────────


func test_parade_plan_einspaltig_rechtsbuendig_deterministisch() -> void:
	var zellen: Array = [
		Rect2(1000, 100, 72, 64), Rect2(1000, 180, 72, 64), Rect2(1000, 260, 72, 64)
	]
	var groessen: Array = [Vector2(60, 24), Vector2(80, 24), Vector2(50, 24)]
	assert_almost(HudIconBuehne.block_kante(zellen), 1000.0, 0.001, "Blockkante = linkeste Zelle")
	var plan := HudIconBuehne.rest_plan(zellen, 1, groessen, 10.0, 4.0)
	assert_eq(plan.size(), 3, "je Kachel ein Schild-Platz")
	for i in plan.size():
		var rest: Rect2 = plan[i]
		var zelle: Rect2 = zellen[i]
		var groesse: Vector2 = groessen[i]
		assert_almost(rest.end.x, 1000.0 - 10.0, 0.001, "Schild %d endet an der Schiene" % i)
		var mitte := zelle.position.y + zelle.size.y / 2.0
		assert_almost(rest.position.y, mitte - groesse.y / 2.0, 0.001, "Schild %d mittig" % i)
	var nochmal := HudIconBuehne.rest_plan(zellen, 1, groessen, 10.0, 4.0)
	for i in plan.size():
		assert_eq(nochmal[i], plan[i], "Plan ist deterministisch (Lauf 2, Schild %d)" % i)


func test_parade_plan_zweispaltig_teilt_zeile() -> void:
	var zellen: Array = [Rect2(1000, 100, 72, 64), Rect2(1080, 100, 72, 64)]
	var groessen: Array = [Vector2(60, 20), Vector2(44, 20)]
	var plan := HudIconBuehne.rest_plan(zellen, 2, groessen, 10.0, 4.0)
	var mitte := 100.0 + 32.0
	assert_almost(plan[0].position.y, mitte - 2.0 - 20.0, 0.001, "linke Kachel → oberer Slot")
	assert_almost(plan[1].position.y, mitte + 2.0, 0.001, "rechte Kachel → unterer Slot")
	for i in plan.size():
		var rest: Rect2 = plan[i]
		assert_almost(rest.end.x, 990.0, 0.001, "beide Schilder enden an der Schiene")
	var schnitt: Rect2 = plan[0].intersection(plan[1])
	assert_true(schnitt.size.y <= 0.0, "Slots einer Zeile überlappen nicht")


func test_entzerre_erzwingt_luft_und_grenze() -> void:
	var grenze := Rect2(900, 90, 300, 400)
	var eng: Array[Rect2] = [
		Rect2(930, 100, 60, 24), Rect2(890, 110, 80, 24), Rect2(930, 112, 50, 24)
	]
	var frei := HudIconBuehne.entzerre(eng, 2.0, grenze)
	for i in frei.size():
		var rect: Rect2 = frei[i]
		assert_true(rect.position.x >= 900.0 - 0.001, "Schild %d bleibt rechts der Grenze" % i)
		assert_true(rect.position.y >= 90.0 - 0.001, "Schild %d unter der Oberkante" % i)
		assert_true(rect.end.y <= 490.0 + 0.001, "Schild %d über der Unterkante" % i)
		if i > 0:
			var vorher: Rect2 = frei[i - 1]
			assert_true(
				rect.position.y >= vorher.end.y + 2.0 - 0.001,
				"Mindest-Luft zwischen Schild %d und %d" % [i - 1, i]
			)
	# Enge Grenze: die Rückklemm-Runde schiebt von unten hoch, Luft bleibt.
	var knapp := HudIconBuehne.entzerre(eng, 2.0, Rect2(900, 90, 300, 84))
	for i in knapp.size():
		var rect: Rect2 = knapp[i]
		assert_true(rect.end.y <= 174.0 + 0.001, "knappe Grenze hält Schild %d" % i)
		if i > 0:
			var vorher: Rect2 = knapp[i - 1]
			var schnitt := rect.intersection(vorher)
			assert_false(
				schnitt.size.x > 0.0 and schnitt.size.y > 0.0,
				"auch geklemmt kollidieren %d/%d nicht" % [i - 1, i]
			)


func test_parade_takt_formeln() -> void:
	assert_almost(HudIconBuehne.parade_verzug(0), 0.0, 1e-6, "erstes Schild ohne Verzug")
	assert_almost(
		HudIconBuehne.parade_verzug(4), 4.0 * HudIconBuehne.STAFFEL_S, 1e-6, "Staffel linear"
	)
	assert_almost(HudIconBuehne.parade_dauer(0), 0.0, 1e-6, "leere Parade dauert nichts")
	var eine := HudIconBuehne.EIN_S + HudIconBuehne.STEH_S + HudIconBuehne.AUS_S
	assert_almost(HudIconBuehne.parade_dauer(1), eine, 1e-6, "Solo-Schild: rein, stehen, raus")
	assert_almost(
		HudIconBuehne.parade_dauer(10),
		HudIconBuehne.parade_verzug(9) + eine,
		1e-6,
		"10er-Parade endet mit dem letzten Schild"
	)


# ── (c) Kurzform-Pfad ────────────────────────────────────────────────────────


func test_kurzform_wahl_bevorzugt_lesbaren_vollnamen() -> void:
	var font := ThemeService.font(700)
	assert_true(font != null, "Baloo-2-Font lädt")
	var breit := HudLabelFit.text_breite(font, "Garderobe", 12) + 4.0
	var wahl := HudLabelFit.kurzform_wahl(font, "Garderobe", "Mode", 12, breit)
	assert_eq(str(wahl["text"]), "Garderobe", "voller Name gewinnt bei Platz")
	assert_eq(int(wahl["px"]), 12, "Wunschgröße bleibt")
	assert_true(bool(wahl["passt"]), "und passt")


func test_kurzform_wahl_faellt_auf_kurzform() -> void:
	var font := ThemeService.font(700)
	var eng := HudLabelFit.text_breite(font, "Garderobe", HudLabelFit.KURZ_AB_PX) - 1.0
	assert_true(
		HudLabelFit.text_breite(font, "Mode", 12) <= eng,
		"Vorbedingung: „Mode“ passt in die enge Schiene"
	)
	var wahl := HudLabelFit.kurzform_wahl(font, "Garderobe", "Mode", 12, eng)
	assert_eq(str(wahl["text"]), "Mode", "unter KURZ_AB_PX übernimmt die Kurzform")
	assert_true(bool(wahl["passt"]), "Kurzform passt")
	assert_eq(int(wahl["px"]), 12, "Kurzform darf in Wunschgröße stehen")


func test_kurzform_wahl_ohne_kurzform_und_notfall() -> void:
	var font := ThemeService.font(700)
	var eng := HudLabelFit.text_breite(font, "Garderobe", HudLabelFit.KURZ_AB_PX) - 1.0
	var ohne := HudLabelFit.kurzform_wahl(font, "Garderobe", "", 12, eng)
	assert_eq(str(ohne["text"]), "Garderobe", "ohne Kurzform bleibt der volle Name")
	assert_true(int(ohne["px"]) < HudLabelFit.KURZ_AB_PX, "… kleiner geschrumpft")
	assert_true(bool(ohne["passt"]), "… aber lesbar eingepasst")
	var winzig := HudLabelFit.text_breite(font, "Mode", HudLabelFit.MIN_PX) - 1.0
	var notfall := HudLabelFit.kurzform_wahl(font, "Garderobe", "Mode", 12, winzig)
	assert_eq(str(notfall["text"]), "Mode", "Notfall zeigt die Kurzform …")
	assert_false(bool(notfall["passt"]), "… und meldet ehrlich passt=false")


# ── (d) Kurz-Strings (DE/EN-Parität) + Namensschild-Node ─────────────────────


func test_kurz_strings_de_en_paritaet() -> void:
	I18nService.reset_cache()
	var tabellen := {"de": I18nService.table("de"), "en": I18nService.table("en")}
	for action in Hud.ACTIONS:
		var id := String(action["id"])
		for locale: String in tabellen:
			var tabelle: Dictionary = tabellen[locale]
			var voll_key := "hud.%s" % id
			var kurz_key := "hud.%s.kurz" % id
			assert_true(tabelle.has(voll_key), "%s: voller Name in %s" % [id, locale])
			assert_true(tabelle.has(kurz_key), "%s: Kurzform in %s (Parität)" % [id, locale])
			var voll := str(tabelle.get(voll_key, ""))
			var kurz := str(tabelle.get(kurz_key, ""))
			assert_true(kurz.length() > 0, "%s: Kurzform in %s nicht leer" % [id, locale])
			assert_true(
				kurz.length() <= voll.length(),
				"%s: Kurzform „%s“ nie länger als „%s“ (%s)" % [id, kurz, voll, locale]
			)


func test_namensschild_waehlt_voll_und_kurzform() -> void:
	var schild := HudNamensschild.bauen("Testschild", 1.0)
	tree.root.add_child(schild)
	await wait_frames(1)
	assert_true(schild.is_in_group(HudNamensschild.GRUPPE), "Schild meldet sich in der Gruppe")
	assert_eq(
		schild.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Schild schluckt keine Taps (IGNORE)"
	)
	var voll := I18nService.t("hud.wardrobe")
	var kurz := HudNamensschild.kurz_text(&"wardrobe")
	assert_true(kurz != "", "wardrobe hat eine gepflegte Kurzform")
	schild.beschrifte(&"wardrobe", 1.0, 400.0, false)
	assert_eq(schild.text_anzeige(), voll, "breite Schiene → voller Name")
	var font := ThemeService.font(700)
	var eng := HudLabelFit.text_breite(font, voll, HudLabelFit.KURZ_AB_PX) - 1.0
	schild.beschrifte(&"wardrobe", 1.0, eng, false)
	assert_eq(schild.text_anzeige(), kurz, "enge Schiene → Kurzform")
	schild.beschrifte(&"wardrobe", 1.0, 400.0, true)
	assert_eq(schild.text_anzeige(), kurz, "kurz_zuerst (Dauerschild) → Kurzform trotz Platz")
	schild.queue_free()
	await wait_frames(1)

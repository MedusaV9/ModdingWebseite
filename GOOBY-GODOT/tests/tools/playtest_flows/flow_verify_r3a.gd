extends "res://tests/tools/playtest_flows/flow_pt4_basis.gd"
## VERIFY-PT R3 Kombi-Flow (a) — W18/R3-Nachmessung: R2-Features im
## ZUSAMMENSPIEL statt einzeln. Kette wie ein echter Spielertag:
##  1. Onboarding-Kette (Bonus VOR Guide — PT4-B7/PT1-B6-Serialisierung),
##  2. Morgen-Sequenz mit gepinnter Uhr (8 Uhr, Save 3 Tage alt): Klammer
##     spielt VOR dem Tagesbonus (IDEA-SEELE Idee 1),
##  3. Stimmungs-Herz-Tap → „So geht’s Goobster“-Blatt (Idee 2),
##  4. Tagesquest-Blatt ZWEIMAL öffnen (G8-B2-Fix: zweites Blatt gefüllt)
##     mit HUD-Weiche (P50) hin und zurück,
##  5. Baumodus: HUD-Weiche + „Was nun?“-Karte weicht (W14-Regel) +
##     Bett-Bauquest erfüllen,
##  6. Arcade: Kachel-Grid per Wisch scrollen (FIX-7/DragScroll), Kachel
##     NACH dem Scrollen tippen (starHopper, Reihe ganz unten),
##  7. Runde mit REKORD-Versuch: gesäter Easy-Bestwert 1 → Banner
##     „NEUER REKORD!“ + goldene Score-Pill (G8-IDEE A2).
## Diagnose nebenbei: _veil_census-Sonden (nach Onboarding, im Baumodus,
## am Schluss) loggen jeden grossflächigen Schleier/STOP-Fänger samt
## CanvasLayer — Beleg-Sammlung für den r3_pt4_geschichten-Dim-Befund.
## Aufruf: tools/ci/run_playtest.sh flow_verify_r3a

const MS_H := 3_600_000
const MS_TAG := 86_400_000
## A2-Probe: gesäter Easy-Bestwert (Rekord fällt bei Score 2 = 20 m,
## deterministisch vor der ersten Meteor-Reihe — s. flow_pt3_star_hopper).
const REKORD_SAAT_BEST := 1

## Scroll-Referenz der Arcade-Wisch-Probe (-1 = noch nicht gemessen).
var _scroll_referenz := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_census_schritt("nach_onboarding"))
	liste.append_array(_kapitel_morgen())
	liste.append_array(_kapitel_herz())
	liste.append_array(_kapitel_quest_blatt())
	liste.append_array(_kapitel_baumodus())
	liste.append_array(_kapitel_arcade_rekord())
	return liste


# ── Kapitel 2: Morgen-Sequenz (gepinnte Uhr, Muster flow_idea_seele) ─────────


func _kapitel_morgen() -> Array[Dictionary]:
	return [
		{
			"name": "morgen_vorbereiten",
			"aktion": "tue",
			"funktion": _morgen_vorbereiten,
			"erwartung": "Uhr auf 8 Uhr gepinnt, Save 3 Tage alt, Bonus-Tag offen",
		},
		{
			"name": "morgen_starten",
			"aktion": "tue",
			"funktion": _morgen_starten,
			"erwartung": "MorgenSequenz geplant (Ritual fällig) und angestoßen",
		},
		{
			"name": "klammer_vor_bonus",
			"aktion": "warte_bis",
			"bedingung": _klammer_ohne_bonus,
			"timeout_s": 30.0,
			"erwartung": "Aufwach-Gruß sichtbar, Tagesbonus wartet (Kette statt Stapel)",
		},
		{"name": "klammer_ansehen", "aktion": "warte", "sekunden": 0.5},
		{
			"name": "bonus_nach_klammer",
			"aktion": "warte_bis",
			"bedingung": _popup_da,
			"timeout_s": 30.0,
			"erwartung": "Tagesbonus folgt NACH der Aufwach-Klammer",
		},
		{
			"name": "bonus_spaeter",
			"aktion": "tipp_text",
			"text": "Später",
			"erwarte": {"bedingung": _popup_weg},
			"timeout_s": 15.0,
		},
	]


# ── Kapitel 3: Stimmungs-Herz ────────────────────────────────────────────────


func _kapitel_herz() -> Array[Dictionary]:
	return [
		{
			"name": "herz_am_chip",
			"aktion": "warte_bis",
			"bedingung": _herz_da,
			"timeout_s": 15.0,
			"erwartung": "Stimmungs-Herz sitzt am Gooby-Chip",
		},
		{
			"name": "herz_tippen",
			"aktion": "tipp_name",
			"node": "StimmungsHerz",
			"erwarte": {"name": "LauneSatz"},
			"timeout_s": 20.0,
		},
		{"name": "herz_blatt_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "herz_blatt_warm",
			"aktion": "tue",
			"funktion": _stimmungs_blatt_ok,
			"erwartung": "Blatt: Titel + Laune-Satz + Warum-Zeile + Tipp-Mulde",
		},
		{
			"name": "herz_blatt_schliessen",
			"aktion": "tipp_pos",
			"pos": Vector2(80.0, 80.0),
			"erwarte": {"bedingung": _herz_blatt_zu},
			"timeout_s": 15.0,
		},
	]


# ── Kapitel 4: Tagesquest-Blatt zweimal (B2-Fix + P50-Weiche) ────────────────


func _kapitel_quest_blatt() -> Array[Dictionary]:
	return [
		{
			"name": "quest_blatt_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnQuests",
			"erwarte": {"klasse": "DailyQuestPanel"},
			"timeout_s": 60.0,
		},
		{"name": "quest_blatt_setzen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "hud_weicht_dem_blatt",
			"aktion": "warte_bis",
			"bedingung": hud_weicht,
			"timeout_s": 12.0,
		},
		{
			"name": "quest_blatt_zuwischen",
			"aktion": "wisch",
			"von_funktion": blatt_griff_pos,
			"nach_funktion": blatt_wisch_ziel,
			"dauer_s": 0.45,
			"erwarte": {"weg_klasse": "DailyQuestPanel"},
			"timeout_s": 20.0,
		},
		{
			"name": "hud_zurueck_nach_blatt",
			"aktion": "warte_bis",
			"bedingung": hud_da,
			"timeout_s": 12.0,
		},
		{
			"name": "quest_blatt_wieder_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnQuests",
			"erwarte": {"klasse": "DailyQuestPanel"},
			"timeout_s": 20.0,
		},
		{"name": "quest_blatt_wieder_setzen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "quest_blatt_wieder_gefuellt",
			"aktion": "tue",
			"funktion": _zweites_blatt_gefuellt,
			"erwartung": "Blatt zeigt beim zweiten Öffnen wieder Quests (B2-Fix)",
		},
		{
			"name": "quest_blatt_dim_tap_zu",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.06, 0.10),
			"erwarte": {"bedingung": kein_blatt_offen},
			"timeout_s": 20.0,
		},
		{
			"name": "hud_zurueck_nach_dim_tap",
			"aktion": "warte_bis",
			"bedingung": hud_da,
			"timeout_s": 12.0,
		},
	]


# ── Kapitel 5: Baumodus (P50-Weiche + Karten-Weiche + Bett-Quest) ────────────


func _kapitel_baumodus() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "baumodus_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnBau",
			"erwarte": {"text": "Fertig"},
			"timeout_s": 60.0,
		},
		{
			"name": "hud_weicht_im_baumodus",
			"aktion": "warte_bis",
			"bedingung": hud_weicht,
			"timeout_s": 12.0,
		},
		{
			"name": "karte_weicht_im_baumodus",
			"aktion": "warte_bis",
			"bedingung": _karte_weicht,
			"timeout_s": 12.0,
			"erwartung": "„Was nun?“-Karte duckt sich im Baumodus (W14-Regel)",
		},
	]
	liste.append_array(_census_schritt("im_baumodus"))
	liste.append_array(bett_platzieren_schritte())
	return liste


# ── Kapitel 6+7: Arcade-Scroll + Kachel-Tap + Rekord-Runde ───────────────────


func _kapitel_arcade_rekord() -> Array[Dictionary]:
	return [
		{
			"name": "rekord_bestwert_saeen",
			"aktion": "tue",
			"funktion": _rekord_bestwert_saeen,
			"erwartung": "niedriger Easy-Bestwert (%d) für die Rekord-Probe" % REKORD_SAAT_BEST,
		},
		{
			"name": "arcade_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnArcade",
			"erwarte": {"route": "arcade"},
			"timeout_s": 90.0,
		},
		{"name": "arcade_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "scroll_stand_vorher",
			"aktion": "tue",
			"funktion": _scroll_stand_merken,
			"pflicht": false,
		},
		{
			"name": "grid_runterwischen",
			"aktion": "wisch",
			"von_rel": Vector2(0.5, 0.75),
			"nach_rel": Vector2(0.5, 0.3),
			"dauer_s": 0.6,
		},
		{"name": "wisch_wirken_lassen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "wisch_hat_gescrollt",
			"aktion": "tue",
			"funktion": _scroll_bewegt,
			"erwartung": "Touch-Wisch bewegt das Arcade-Grid (FIX-7/DragScroll)",
		},
		{
			"name": "star_hopper_anrollen",
			"aktion": "tue",
			"funktion": _anrollen.bind("Tile_starHopper"),
			"pflicht": false,
		},
		{"name": "anroll_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "kachel_nach_scroll_tippen",
			"aktion": "tipp_name",
			"node": "Tile_starHopper",
			"erwarte": {"route": "mg_pregame"},
			"timeout_s": 90.0,
		},
		{"name": "pregame_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "leicht_waehlen",
			"aktion": "tipp_text",
			"text": "Leicht",
			"timeout_s": 20.0,
			"pflicht": false,
		},
		{
			"name": "spiel_starten",
			"aktion": "tipp_text",
			"text": "Spielen!",
			"erwarte": {"route": "mg_host"},
			"timeout_s": 120.0,
		},
		{
			"name": "runde_beginnt",
			"aktion": "warte_bis",
			"bedingung": _runde_laeuft,
			"timeout_s": 90.0,
		},
		{
			"name": "rekord_banner_zuendet",
			"aktion": "warte_bis",
			"bedingung": _rekord_banner_da,
			"timeout_s": 90.0,
			"erwartung": "Banner „NEUER REKORD!“ nach Überholen der Saat (A2)",
		},
		{
			"name": "rekord_pill_golden",
			"aktion": "tue",
			"funktion": _rekord_pill_pruefen,
			"erwartung": "Score-Pill Rekord-Gold (Stufe 2), Trigger einmalig",
		},
		{"name": "rekord_moment_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "pause_oeffnen",
			"aktion": "tipp_text",
			"text": "Pause",
			"erwarte": {"text": "Beenden"},
			"timeout_s": 30.0,
		},
		{
			"name": "runde_beenden",
			"aktion": "tipp_text",
			"text": "Beenden",
			"erwarte": {"route": "arcade"},
			"timeout_s": 90.0,
		},
		{
			"name": "zurueck_nach_hause",
			"aktion": "tipp_text",
			"text": "Zurück",
			"erwarte": {"route": "home/living"},
			"timeout_s": 120.0,
		},
		{
			"name": "census_abschluss",
			"aktion": "tue",
			"funktion": _veil_census.bind("abschluss"),
			"pflicht": false,
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
	]


# ── Morgen-Helfer (Muster flow_idea_seele) ───────────────────────────────────


func _morgen_vorbereiten() -> bool:
	return _uhr_und_save_stellen(8)


## Uhr über den Clock-Offset auf `stunde` LOKAL pinnen (injizierte Zeit),
## Save 3 Tage alt stellen, Ritual-Gate öffnen, Bonus-Tag freimachen.
func _uhr_und_save_stellen(stunde: int) -> bool:
	var gs := game_state()
	if gs == null or not ("clock" in gs):
		return false
	var clock: Variant = gs.clock
	var utc := Time.get_datetime_dict_from_unix_time(int(clock.now_ms() / 1000.0))
	clock.set_utc_offset_minutes((stunde - int(utc["hour"])) * 60 - int(utc["minute"]))
	var heute := str(clock.local_day())
	var gestern := DailyBonus.prev_day(heute)
	var now := int(clock.now_ms())
	gs.update(
		func(s: Dictionary) -> void:
			var soul: Dictionary = s.get("soul", {}) if s.get("soul") is Dictionary else {}
			soul["firstMetAt"] = now - 3 * MS_TAG
			soul["lastVisitAt"] = now - 2 * MS_H
			var celebrated: Dictionary = (
				soul.get("celebrated", {}) if soul.get("celebrated") is Dictionary else {}
			)
			celebrated.erase(MorgenRitual.GATE_KEY)
			soul["celebrated"] = celebrated
			s["soul"] = soul
			s["daily"] = {"lastClaimDay": gestern, "streak": 1}
	)
	print("[R3A] Uhr gestellt: lokal %d Uhr, heute=%s" % [stunde, heute])
	return true


func _morgen_starten() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var hub := RewardHub.find(harness.root)
	if hub == null:
		print("[R3A] kein RewardHub — Home-Entry nicht gefunden")
		return false
	var seq := MorgenSequenz.starten(hub.get_parent(), gs)
	var geplant := bool(seq.get("_ritual_geplant"))
	print("[R3A] MorgenSequenz: ritual_geplant=%s" % geplant)
	if not geplant:
		return false
	seq.call_deferred("_on_ankunft")
	return true


## Serialisierungs-Kern: Gruß-Bubble steht, der Tagesbonus WARTET noch.
func _klammer_ohne_bonus() -> bool:
	var gruss := _text_sichtbar("Guten Morgen")
	var bonus := _popup_da()
	print("[R3A] Klammer: gruss=%s bonus=%s (erwartet: JA/NEIN)" % [gruss, bonus])
	return gruss and not bonus


# ── Herz-/Blatt-Helfer ───────────────────────────────────────────────────────


func _popup_da() -> bool:
	return _sichtbar("DailyBonusPopup")


func _popup_weg() -> bool:
	return not _sichtbar("DailyBonusPopup")


func _herz_da() -> bool:
	return _sichtbar("StimmungsHerz")


func _herz_blatt_zu() -> bool:
	return not _sichtbar("LauneSatz")


## Blatt-Inhalt: Titel mit Spitznamen, Laune-Satz, Warum-Zeile, Tipp-Mulde.
func _stimmungs_blatt_ok() -> bool:
	var titel := _text_sichtbar("geht’s Goobster")
	var laune := _sichtbar("LauneSatz")
	var grund := _sichtbar("Grund1")
	var tipp := _sichtbar("TippBox")
	print("[R3A] Herz-Blatt: titel=%s laune=%s grund=%s tipp=%s" % [titel, laune, grund, tipp])
	return titel and laune and grund and tipp


## B2-Wache (Muster flow_pt4_sheets): lebendiges DailyQuestPanel mit
## Kindern im OFFENEN Blatt — kein queue_free-Zombie.
func _zweites_blatt_gefuellt() -> bool:
	var sheet := blatt()
	var panel := _suche_klasse(harness.root, "DailyQuestPanel")
	if sheet == null or panel == null:
		print("[R3A] B2-Wache: Blatt=%s Panel=%s" % [str(sheet != null), str(panel != null)])
		return false
	var lebendig := not panel.is_queued_for_deletion()
	var kinder := panel.get_child_count()
	var im_blatt := sheet.is_ancestor_of(panel)
	print(
		(
			"[R3A] B2-Wache: Panel lebendig=%s Kinder=%d im offenen Blatt=%s"
			% [str(lebendig), kinder, str(im_blatt)]
		)
	)
	return lebendig and kinder > 0 and im_blatt


## W14-Regel: KEINE sichtbare „Was nun?“-Karte (Gruppe wasnun_karte),
## solange der Baumodus das HUD verdeckt.
func _karte_weicht() -> bool:
	var sichtbare := 0
	for node: Node in harness.get_nodes_in_group(&"wasnun_karte"):
		if node is Control and (node as Control).is_visible_in_tree():
			sichtbare += 1
	print("[R3A] Karten-Weiche: %d sichtbare „Was nun?“-Karten" % sichtbare)
	return sichtbare == 0


# ── Arcade-/Rekord-Helfer (Muster flow_pt3_basis/_star_hopper) ───────────────


func _arcade_scroller() -> ScrollContainer:
	var screen := _suche_klasse(harness.root, "ArcadeScreen")
	if screen == null:
		return null
	var stapel: Array[Node] = [screen]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is ScrollContainer:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


func _scroll_stand_merken() -> bool:
	var scroller := _arcade_scroller()
	if scroller == null:
		print("[R3A] Scroll-Stand: kein ScrollContainer gefunden")
		return true
	_scroll_referenz = scroller.scroll_vertical
	print("[R3A] Scroll-Stand vor dem Wischen: %d" % _scroll_referenz)
	return true


func _scroll_bewegt() -> bool:
	var scroller := _arcade_scroller()
	if scroller == null:
		return false
	print(
		"[R3A] Scroll nach Wisch: %d (Referenz %d)" % [scroller.scroll_vertical, _scroll_referenz]
	)
	return scroller.scroll_vertical > maxi(_scroll_referenz, 0)


## Ziel-Kachel in allen Scroll-Ahnen sichtbar rollen (Grid clippt unten).
func _anrollen(node_name: String) -> bool:
	var ziel := harness.root.find_child(node_name, true, false)
	if not (ziel is Control):
		print("[R3A] anrollen: '%s' nicht im Baum" % node_name)
		return false
	var ahn: Node = ziel.get_parent()
	var gerollt := 0
	while ahn != null:
		if ahn is ScrollContainer:
			(ahn as ScrollContainer).ensure_control_visible(ziel)
			gerollt += 1
		ahn = ahn.get_parent()
	print("[R3A] anrollen: '%s' über %d Scroller geholt" % [node_name, gerollt])
	return true


func _rekord_bestwert_saeen() -> bool:
	var gs := game_state()
	if gs == null or not gs.has_method("update"):
		print("[R3A] Rekord-Saat: kein GameState")
		return false
	gs.update(
		func(state: Dictionary) -> void:
			var legacy: Dictionary = state["minigames"]["legacy"]
			if not (legacy.get("bestByDiff") is Dictionary):
				legacy["bestByDiff"] = {}
			var by_diff: Dictionary = legacy["bestByDiff"]
			if not (by_diff.get("starHopper") is Dictionary):
				by_diff["starHopper"] = {}
			by_diff["starHopper"]["easy"] = REKORD_SAAT_BEST
	)
	print("[R3A] Rekord-Saat: starHopper-Bestwert (Leicht) = %d" % REKORD_SAAT_BEST)
	return true


func _host() -> Control:
	return _suche_klasse(harness.root, "MinigameHost") as Control


func _runde_laeuft() -> bool:
	var h := _host()
	if h == null:
		return false
	var spiel := h.get("_game") as Node
	return spiel != null and bool(spiel.get("running"))


func _rekord_banner_da() -> bool:
	var banner := harness.root.find_child("RekordBanner", true, false)
	return banner is Control and (banner as Control).is_visible_in_tree()


func _rekord_pill_pruefen() -> bool:
	var h := _host()
	if h == null:
		return false
	var anzeige: Node = h.get("_puls_anzeige")
	var stufe := int(anzeige.get("stufe")) if anzeige != null else -1
	var puls: RefCounted = h.get("_puls")
	var einmalig: bool = puls != null and bool(puls.get("rekord_gefeuert"))
	print("[R3A] Rekord-Puls: Pill-Stufe %d, rekord_gefeuert=%s" % [stufe, einmalig])
	return stufe == 2 and einmalig


# ── Diagnose: Schleier-Zählung ───────────────────────────────────────────────


func _census_schritt(etikett: String) -> Array[Dictionary]:
	return [
		{
			"name": "census_%s" % etikett,
			"aktion": "tue",
			"funktion": _veil_census.bind(etikett),
			"pflicht": false,
		},
	]


## Diagnose-Sonde: loggt jede sichtbare, grossflächige ColorRect (>= 40 %
## der Canvas-Fläche) mit effektiver Deckkraft sowie jeden Vollbild-
## STOP-Fänger — plus CanvasLayer-Nummer und Pfad. Antwort auf das
## r3_pt4_geschichten-Rätsel („alles dunkel ausser Toasts, wer dimmt?“).
func _veil_census(etikett: String) -> bool:
	var canvas := harness.root.get_visible_rect().size
	var flaeche := maxf(canvas.x * canvas.y, 1.0)
	var funde := 0
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var node: Node = stapel.pop_back()
		for kind in node.get_children():
			stapel.append(kind)
		if not (node is Control) or not (node as Control).is_visible_in_tree():
			continue
		var ctl := node as Control
		var rect := ctl.get_global_rect()
		var anteil := rect.size.x * rect.size.y / flaeche
		funde += _census_pruefe(etikett, ctl, anteil)
	print("[R3A][census %s] fertig: %d Auffällige" % [etikett, funde])
	return true


## Ein Control gegen die Schleier-Kriterien halten (1 = auffällig, 0 = ok).
func _census_pruefe(etikett: String, ctl: Control, anteil: float) -> int:
	if ctl is ColorRect and anteil >= 0.4:
		var farbe := (ctl as ColorRect).color
		var alpha := farbe.a * ctl.modulate.a * ctl.self_modulate.a
		if alpha > 0.03:
			print(
				(
					(
						"[R3A][census %s] SCHLEIER %s Layer=%d Anteil=%.2f Farbe=%s "
						+ "effAlpha=%.2f Filter=%d"
					)
					% [
						etikett,
						ctl.get_path(),
						_layer_von(ctl),
						anteil,
						str(farbe),
						alpha,
						ctl.mouse_filter,
					]
				)
			)
			return 1
		return 0
	if anteil >= 0.9 and ctl.mouse_filter == Control.MOUSE_FILTER_STOP:
		print(
			(
				"[R3A][census %s] STOP-FÄNGER %s Layer=%d Anteil=%.2f"
				% [etikett, ctl.get_path(), _layer_von(ctl), anteil]
			)
		)
		return 1
	return 0


## Nummer des umschliessenden CanvasLayers (0 = direkt im Viewport).
func _layer_von(node: Node) -> int:
	var ahn: Node = node
	while ahn != null:
		if ahn is CanvasLayer:
			return (ahn as CanvasLayer).layer
		ahn = ahn.get_parent()
	return 0


# ── Sicht-Helfer (Muster flow_idea_seele) ────────────────────────────────────


func _sichtbar(node_name: String) -> bool:
	var node := harness.root.find_child(node_name, true, false) as Control
	return node != null and node.is_visible_in_tree()


func _text_sichtbar(nadel: String) -> bool:
	return _suche_text(harness.root, nadel) != null


func _suche_text(node: Node, nadel: String) -> Control:
	if node is Label:
		var label := node as Label
		if label.is_visible_in_tree() and nadel in label.text:
			return label
	if node is Button:
		var knopf := node as Button
		if knopf.is_visible_in_tree() and nadel in knopf.text:
			return knopf
	for kind in node.get_children():
		var fund := _suche_text(kind, nadel)
		if fund != null:
			return fund
	return null

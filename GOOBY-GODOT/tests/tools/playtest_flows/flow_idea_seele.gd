extends "res://tests/tools/playtest_flows/flow_pt4_basis.gd"
## G8/IDEA-SEELE-Flow: Stimmungs-Herz + Morgen-/Abend-Ritual im ECHTEN Spiel.
## Vier Kapitel:
##  A) Onboarding-Kette SERIALISIERT (der PT4-B7/PT1-B6-Befund): nach dem
##     Onboarding kommt ERST der Tagesbonus (Guide noch nicht da), der Guide
##     erscheint erst NACH dem Abholen — nacheinander statt gestapelt.
##  B) Stimmungs-Herz: sitzt am „Wo ist mein Gooby?“-Chip; Tap → warmes
##     „So geht’s Goobster“-Blatt mit Laune-Satz, Warum-Zeile und Tipp-Mulde.
##  C) Morgen-Klammer: Uhr auf 8 Uhr gepinnt (Clock-Offset — injizierte
##     Zeit!), Save 3 Tage alt gestellt → MorgenSequenz spielt die
##     Aufwach-Klammer (Gruß-Bubble MIT echtem Tagesausblick, Bonus wartet!),
##     DANACH erscheint der Tagesbonus.
##  D) Abend-Bilanz: Uhr auf 21 Uhr, Tagesdaten gesät (14 Streichler,
##     Möhrenfang-Runde, Serie Tag 2) → Bett-Bauquest erfüllen → Bett-Tap →
##     Nachtkarte trägt die Gute-Nacht-Mini-Bilanz.
## Aufruf: tools/ci/run_playtest.sh flow_idea_seele

const MS_H := 3_600_000
const MS_TAG := 86_400_000


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(_kapitel_a_kette())
	liste.append_array(_kapitel_b_herz())
	liste.append_array(_kapitel_c_morgen())
	liste.append_array(_kapitel_d_abend())
	return liste


# ── Kapitel A: Onboarding → Bonus VOR Guide (Serialisierung) ─────────────────


func _kapitel_a_kette() -> Array[Dictionary]:
	return [
		{
			"name": "boot_bis_onboarding",
			"aktion": "warte_bis",
			"klasse": "OnboardingFlow",
			"timeout_s": 240.0,
		},
		{"name": "name_eingeben", "aktion": "eingabe", "node": "NameEdit", "text": "Pionier"},
		{"name": "welcome_weiter", "aktion": "tipp_name", "node": "WelcomeNext"},
		{
			"name": "spitzname_eingeben",
			"aktion": "eingabe",
			"node": "NicknameEdit",
			"text": "Goobster",
		},
		{"name": "spitzname_weiter", "aktion": "tipp_name", "node": "NicknameNext"},
		{"name": "editor_weiter", "aktion": "tipp_name", "node": "EditorNext"},
		{
			"name": "onboarding_fertig",
			"aktion": "tipp_name",
			"node": "DoneButton",
			"erwarte": {"route": "home/living"},
			"timeout_s": 150.0,
		},
		# Serialisierungs-Beweis 1: der Bonus steht, der Guide NOCH NICHT —
		# vorher lagen beide gestapelt übereinander (B6/B7).
		{
			"name": "bonus_vor_guide",
			"aktion": "warte_bis",
			"bedingung": bonus_da_guide_wartet,
			"timeout_s": 45.0,
			"erwartung": "Tagesbonus zuerst, Guide-Tour wartet (keine Stapel)",
		},
		{"name": "bonus_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "bonus_abholen",
			"aktion": "tipp_text",
			"text": "Abholen!",
			"erwarte": {"bedingung": popup_weg},
			"timeout_s": 20.0,
		},
		# Serialisierungs-Beweis 2: ERST jetzt hängt sich die Guide-Tour an.
		{
			"name": "guide_nach_bonus",
			"aktion": "warte_bis",
			"bedingung": guide_da,
			"timeout_s": 20.0,
			"erwartung": "Guide-Tour erscheint NACH dem Bonus-Schließen",
		},
		{"name": "guide_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "guide_beenden",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 12.0,
			"pflicht": false,
		},
		{
			"name": "coachmark_wegtippen",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 6.0,
			"pflicht": false,
		},
	]


# ── Kapitel B: Stimmungs-Herz → „So geht’s Goobster“-Blatt ───────────────────


func _kapitel_b_herz() -> Array[Dictionary]:
	return [
		{
			"name": "herz_am_chip",
			"aktion": "warte_bis",
			"bedingung": herz_da,
			"timeout_s": 15.0,
			"erwartung": "Stimmungs-Herz sitzt am Gooby-Chip",
		},
		{"name": "herz_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "herz_tippen",
			"aktion": "tipp_name",
			"node": "StimmungsHerz",
			"erwarte": {"name": "LauneSatz"},
			"timeout_s": 20.0,
		},
		{"name": "stimmungs_blatt_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "blatt_inhalt_warm",
			"aktion": "tue",
			"funktion": stimmungs_blatt_ok,
			"erwartung": "Blatt: Titel + Laune-Satz + Warum-Zeile + Tipp-Mulde, KEINE Zahlen",
		},
		{
			"name": "blatt_schliessen",
			"aktion": "tipp_pos",
			"pos": Vector2(80.0, 80.0),
			"erwarte": {"bedingung": blatt_zu},
			"timeout_s": 15.0,
		},
	]


# ── Kapitel C: Morgen-Klammer (injizierte Uhr) ───────────────────────────────


func _kapitel_c_morgen() -> Array[Dictionary]:
	return [
		{
			"name": "morgen_vorbereiten",
			"aktion": "tue",
			"funktion": morgen_vorbereiten,
			"erwartung": "Uhr auf 8 Uhr gepinnt, Save 3 Tage alt, Bonus-Tag offen",
		},
		{
			"name": "morgen_starten",
			"aktion": "tue",
			"funktion": morgen_starten,
			"erwartung": "MorgenSequenz geplant (Ritual fällig) und angestoßen",
		},
		# Serialisierungs-Beweis 3: die Klammer spielt (Gruß-Bubble mit echtem
		# Ausblick), der Tagesbonus WARTET noch.
		{
			"name": "klammer_vor_bonus",
			"aktion": "warte_bis",
			"bedingung": klammer_ohne_bonus,
			"timeout_s": 30.0,
			"erwartung": "Aufwach-Gruß sichtbar, Tagesbonus wartet (Kette statt Stapel)",
		},
		{"name": "klammer_ansehen", "aktion": "warte", "sekunden": 0.5},
		# Serialisierungs-Beweis 4: NACH der Klammer kommt der Bonus.
		{
			"name": "bonus_nach_klammer",
			"aktion": "warte_bis",
			"bedingung": popup_da,
			"timeout_s": 30.0,
			"erwartung": "Tagesbonus folgt NACH der Aufwach-Klammer",
		},
		{"name": "bonus_tag2_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "bonus_spaeter",
			"aktion": "tipp_text",
			"text": "Später",
			"erwarte": {"bedingung": popup_weg},
			"timeout_s": 15.0,
		},
	]


# ── Kapitel D: Abend-Bilanz an der Bett-Nachtkarte ───────────────────────────


func _kapitel_d_abend() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "abend_vorbereiten",
			"aktion": "tue",
			"funktion": abend_vorbereiten,
			"erwartung": "Uhr auf 21 Uhr, Tagesdaten gesät (Streichler/Spiel/Serie)",
		},
		{
			"name": "baumodus_fuer_bett",
			"aktion": "tipp_name",
			"node": "BtnBau",
			"erwarte": {"text": "Fertig"},
			"timeout_s": 60.0,
		},
	]
	liste.append_array(bett_platzieren_schritte())
	liste.append_array(
		[
			{"name": "bett_steht", "aktion": "warte", "sekunden": 1.5},
			{
				"name": "bett_antippen",
				"aktion": "tipp_3d",
				"finder": func() -> Node3D: return finde_moebel("bedSingle"),
				"offset": Vector3(0.0, 0.3, 0.0),
				"erwarte": {"text": "Bettzeit"},
				"timeout_s": 30.0,
			},
			{
				"name": "bilanz_in_nachtkarte",
				"aktion": "warte_bis",
				"bedingung": bilanz_da,
				"timeout_s": 15.0,
				"erwartung": "Gute-Nacht-Mini-Bilanz steht in der Nachtkarte",
			},
			{"name": "bilanz_ansehen", "aktion": "warte", "sekunden": 2.0},
			{
				"name": "bilanz_aus_echten_daten",
				"aktion": "tue",
				"funktion": bilanz_ok,
				"erwartung": "Bilanz: 14× gestreichelt, Möhrenfang-Runde, Serie Tag 2",
			},
			{
				"name": "nachtkarte_zu",
				"aktion": "tipp_text",
				"text": "Später",
				"erwarte": {"weg_text": "Bettzeit"},
				"timeout_s": 15.0,
			},
			{"name": "abschluss", "aktion": "warte", "sekunden": 1.5},
		]
	)
	return liste


# ── Bedingungen / Aktionen ───────────────────────────────────────────────────


func popup_da() -> bool:
	return _sichtbar("DailyBonusPopup")


func popup_weg() -> bool:
	return not _sichtbar("DailyBonusPopup")


func guide_da() -> bool:
	return _sichtbar("GuideBeenden")


func herz_da() -> bool:
	return _sichtbar("StimmungsHerz")


func bonus_da_guide_wartet() -> bool:
	var bonus := popup_da()
	var guide := guide_da()
	print("[SEELE] Kette: bonus=%s guide=%s (erwartet: bonus JA, guide NEIN)" % [bonus, guide])
	return bonus and not guide


## Blatt-Inhalt: Titel mit Spitznamen, Laune-Satz, Warum-Zeile, Tipp-Mulde —
## und als Gegenprobe KEIN nacktes Meter (kein "%"-Literal im Blatt).
func stimmungs_blatt_ok() -> bool:
	var titel := _text_sichtbar("geht’s Goobster")
	var laune := _sichtbar("LauneSatz")
	var grund := _sichtbar("Grund1")
	var tipp := _sichtbar("TippBox")
	for zeile in ["LauneSatz", "Grund1", "Tipp1"]:
		var label := harness.root.find_child(zeile, true, false) as Label
		if label != null:
			print("[SEELE] Blatt %s: „%s“" % [zeile, label.text])
	print("[SEELE] Blatt: titel=%s laune=%s grund=%s tipp=%s" % [titel, laune, grund, tipp])
	return titel and laune and grund and tipp


func blatt_zu() -> bool:
	return not _sichtbar("LauneSatz")


## Uhr über den Clock-Offset auf 8 Uhr LOKAL pinnen (injizierte Zeit — die
## OS-Uhr bleibt unberührt), Save 3 Tage alt stellen, Gruß-/Ritual-Gates
## öffnen und den Bonus-Tag freimachen (gestern geclaimt → heute Tag 2).
func morgen_vorbereiten() -> bool:
	return _uhr_und_save_stellen(8)


func abend_vorbereiten() -> bool:
	if not _uhr_und_save_stellen(21):
		return false
	var gs := game_state()
	var heute := str(gs.clock.local_day())
	gs.update(
		func(s: Dictionary) -> void:
			var counters: Dictionary = s["achievements"]["counters"]
			counters["petsToday"] = 14
			counters["petsDay"] = heute
			var legacy: Dictionary = s["minigames"]["legacy"]
			var last_play: Dictionary = legacy.get("lastPlayDay", {})
			last_play["carrotCatch"] = heute
			legacy["lastPlayDay"] = last_play
			s["daily"] = {"lastClaimDay": heute, "streak": 2}
	)
	print("[SEELE] Abend gesät: 14 Streichler, Möhrenfang, Serie 2 (Tag %s)" % heute)
	return true


func morgen_starten() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var hub := RewardHub.find(harness.root)
	if hub == null:
		print("[SEELE] kein RewardHub — Home-Entry nicht gefunden")
		return false
	var seq := MorgenSequenz.starten(hub.get_parent(), gs)
	var geplant := bool(seq.get("_ritual_geplant"))
	print("[SEELE] MorgenSequenz: ritual_geplant=%s" % geplant)
	if not geplant:
		return false
	# Kein Raumwechsel im Spiel — die Ankunft wird direkt angestoßen
	# (im echten Fluss feuert travel_finished denselben Pfad).
	seq.call_deferred("_on_ankunft")
	return true


## Serialisierungs-Kern: Gruß-Bubble steht, der Tagesbonus WARTET noch.
func klammer_ohne_bonus() -> bool:
	var gruss := _text_sichtbar("Guten Morgen")
	var bonus := popup_da()
	print("[SEELE] Klammer: gruss=%s bonus=%s (erwartet: JA/NEIN)" % [gruss, bonus])
	return gruss and not bonus


func bilanz_da() -> bool:
	return _sichtbar("AbendBilanz")


func bilanz_ok() -> bool:
	var titel := _text_sichtbar("Heute war schön")
	var streichler := _text_sichtbar("14× gestreichelt")
	var spiel := _text_sichtbar("Möhrenfang")
	var serie := _text_sichtbar("eurer Serie")
	for i in 3:
		var label := harness.root.find_child("BilanzZeile%d" % (i + 1), true, false) as Label
		if label != null:
			print("[SEELE] Bilanz-Zeile %d: „%s“" % [i + 1, label.text])
	print(
		(
			"[SEELE] Bilanz: titel=%s streichler=%s spiel=%s serie=%s"
			% [titel, streichler, spiel, serie]
		)
	)
	return titel and streichler and spiel and serie


# ── Helfer ───────────────────────────────────────────────────────────────────


## Clock-Offset so setzen, dass die LOKALE Stunde `stunde` ist, und den Save
## für die Morgen-Kette stellen (3 Tage alt, Gates offen, Bonus-Tag frei).
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
	print("[SEELE] Uhr gestellt: lokal %d Uhr, heute=%s" % [stunde, heute])
	return true


## Sichtbares Control mit diesem Node-Namen im Baum?
func _sichtbar(node_name: String) -> bool:
	var node := harness.root.find_child(node_name, true, false) as Control
	return node != null and node.is_visible_in_tree()


## Sichtbares Label/Button, dessen Text die Nadel enthält (Bubble-Prüfung).
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

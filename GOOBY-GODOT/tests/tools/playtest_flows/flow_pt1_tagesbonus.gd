extends "res://tests/tools/playtest_flows/flow_pt1_helfer.gd"
## Flow PT1 (e) „Tagesbonus & Overlay-Verhalten“: EIGENES Onboarding OHNE den
## Auto-Abhol-Schritt der Basis — das Popup (RewardHub-Layer 90) wird hier
## selbst seziert: erscheint nach dem Onboarding (slice_changed-Hook), zeigt
## Titel/Serie/Kalender/Belohnung, „Später“ claimt NICHT (bis Mitternacht
## abholbar), Backdrop-Tap und Escape wirken wie „Später“ (PanelStack-Pfad),
## „Abholen!“ bucht +20 Münzen (Tag 1) und stempelt lastClaimDay — danach
## bietet derselbe Tag NIE wieder an. Zum Schluss Serien-Logik über
## zurückdatierte Saves: Tag 2 (+30) claimen und den Kulanztag (Serie läuft
## trotz Lücke weiter) im Popup sehen.
## Wieder-Anbieten läuft über RewardHub._maybe_offer_daily_bonus (per call —
## exakt der App-Resume-Pfad NOTIFICATION_APPLICATION_RESUMED).
## Aufruf: tools/ci/run_playtest.sh flow_pt1_tagesbonus


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "events_stilllegen",
			"aktion": "tue",
			"funktion": _events_stilllegen,
			"erwartung": "Random-Events liegen für den Lauf auf Cooldown",
		},
	]
	liste.append_array(_onboarding_ohne_abholen())
	liste.append_array(_popup_pruef_schritte())
	liste.append_array(_abweis_schritte())
	liste.append_array(_abhol_schritte())
	liste.append_array(_serien_schritte())
	liste.append_array(_abschluss_schritte())
	return liste


# ---------------------------------------------------------------- Abschnitte


## Onboarding wie flow_basis, aber OHNE tagesbonus_abholen — das Popup
## bleibt stehen und ist hier selbst der Prüfling.
func _onboarding_ohne_abholen() -> Array[Dictionary]:
	return [
		{
			"name": "boot_bis_onboarding",
			"aktion": "warte_bis",
			"klasse": "OnboardingFlow",
			"timeout_s": 180.0,
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
			"timeout_s": 120.0,
		},
	]


## Erscheinen + Inhalt: Titel, Serie Tag 1, Kalender-Chips, +20-Belohnung.
func _popup_pruef_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "popup_erscheint_nach_onboarding",
			"aktion": "warte_bis",
			"bedingung": _popup_da,
			"timeout_s": 45.0,
			"erwartung": "DailyBonusPopup kommt direkt nach dem Onboarding (Layer 90)",
		},
		{"name": "popup_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "popup_inhalt_tag1",
			"aktion": "tue",
			"funktion": _popup_inhalt.bind(1, 20),
			"erwartung": "Titel/Serie: Tag 1/Kalender-Chips/+20 Münzen/Abholen!/Später",
		},
		{"name": "muenzen_merken", "aktion": "tue", "funktion": _merke_muenzen},
	]


## Drei Abweis-Wege: Später-Knopf, Backdrop-Tap, Escape — nie geclaimt.
func _abweis_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "spaeter_tippen",
			"aktion": "tipp_text",
			"text": "Später",
			"erwarte": {"bedingung": _spaeter_ok},
			"timeout_s": 15.0,
			"erwartung": "Später schließt nur — lastClaimDay bleibt leer",
		},
		{
			"name": "wieder_anbieten_eins",
			"aktion": "tue",
			"funktion": _wieder_anbieten,
			"erwarte": {"bedingung": _popup_da},
			"timeout_s": 15.0,
			"erwartung": "App-Resume-Pfad bietet denselben Bonus erneut an",
		},
		{
			"name": "backdrop_tippen",
			"aktion": "tipp_pos",
			"pos": Vector2(60.0, 60.0),
			"erwarte": {"bedingung": _spaeter_ok},
			"timeout_s": 15.0,
			"erwartung": "Tap auf den Schleier = Später (Backdrop-Dismiss-Policy)",
		},
		{
			"name": "wieder_anbieten_zwei",
			"aktion": "tue",
			"funktion": _wieder_anbieten,
			"erwarte": {"bedingung": _popup_da},
			"timeout_s": 15.0,
		},
		{
			"name": "escape_druecken",
			"aktion": "taste",
			"keycode": KEY_ESCAPE,
			"erwarte": {"bedingung": _spaeter_ok},
			"timeout_s": 15.0,
			"erwartung": "Escape → PanelStack.close_top → Später-Semantik",
		},
	]


## Abholen: +20 Münzen (Tag 1), Stempel heute, danach kein Wieder-Anbieten.
func _abhol_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "wieder_anbieten_drei",
			"aktion": "tue",
			"funktion": _wieder_anbieten,
			"erwarte": {"bedingung": _popup_da},
			"timeout_s": 15.0,
		},
		{
			"name": "abholen_tippen",
			"aktion": "tipp_text",
			"text": "Abholen!",
			"erwarte": {"bedingung": _geclaimt.bind(20.0, 1.0)},
			"timeout_s": 20.0,
			"erwartung": "+20 Münzen gebucht, daily.streak=1, lastClaimDay=heute",
		},
		{
			"name": "claim_toast_da",
			"aktion": "warte_bis",
			"text": "bis morgen",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "kein_zweites_angebot",
			"aktion": "tue",
			"funktion": _wieder_anbieten,
		},
		{"name": "angebots_pause", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "heute_bleibt_geclaimt",
			"aktion": "tue",
			"funktion": _popup_weg,
			"erwartung": "Nach dem Claim bietet derselbe Tag NIE wieder an",
		},
	]


## Serien-Logik über zurückdatierte Saves: Tag 2 claimen, Kulanztag ansehen.
func _serien_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "serie_tag2_vorbereiten",
			"aktion": "tue",
			"funktion": _zurueckdatieren.bind(1, 1),
			"erwartung": "daily.lastClaimDay = gestern, streak = 1 (Test-Save-Stellung)",
		},
		{
			"name": "tag2_anbieten",
			"aktion": "tue",
			"funktion": _wieder_anbieten,
			"erwarte": {"bedingung": _popup_da},
			"timeout_s": 15.0,
		},
		{
			"name": "popup_inhalt_tag2",
			"aktion": "tue",
			"funktion": _popup_inhalt.bind(2, 30),
			"erwartung": "Serie: Tag 2 mit +30 Münzen (REWARD_TABLE[1])",
		},
		{"name": "muenzen_merken_tag2", "aktion": "tue", "funktion": _merke_muenzen},
		{
			"name": "tag2_abholen",
			"aktion": "tipp_text",
			"text": "Abholen!",
			"erwarte": {"bedingung": _geclaimt.bind(30.0, 2.0)},
			"timeout_s": 20.0,
			"erwartung": "+30 Münzen gebucht, daily.streak=2",
		},
		{
			"name": "kulanz_vorbereiten",
			"aktion": "tue",
			"funktion": _zurueckdatieren.bind(2, 2),
			"erwartung": "lastClaimDay = vorgestern → EIN verpasster Tag (Kulanz)",
		},
		{
			"name": "kulanz_anbieten",
			"aktion": "tue",
			"funktion": _wieder_anbieten,
			"erwarte": {"bedingung": _popup_da},
			"timeout_s": 15.0,
		},
		{
			"name": "kulanz_hinweis_da",
			"aktion": "tue",
			"funktion": _kulanz_inhalt,
			"erwartung": "Serie: Tag 3 (+40) MIT Kulanz-Zeile 'kein Problem'",
		},
		{
			"name": "kulanz_spaeter",
			"aktion": "tipp_text",
			"text": "Später",
			"erwarte": {"bedingung": _popup_weg},
			"timeout_s": 15.0,
		},
	]


## Aufräumen wie die Basis: Guide-Tour und Coachmark wegtippen, Abschluss.
func _abschluss_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "guide_tour_beenden",
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
		{"name": "abschluss_tagesbonus", "aktion": "warte", "sekunden": 2.0},
	]


# ---------------------------------------------------------------- Bedingungen


func _popup_da() -> bool:
	return control_da("DailyBonusPopup")


func _popup_weg() -> bool:
	return control_weg("DailyBonusPopup")


## Popup-Inhalt eines Serientags: Titel, Serien-Zeile, Kalender, Belohnung.
func _popup_inhalt(serie_tag: int, muenzen: int) -> bool:
	var titel := text_da("Tagesbonus")
	var serie := text_da("Serie: Tag %d" % serie_tag)
	var betrag := text_da("+%d Münzen" % muenzen)
	var knoepfe := text_da("Abholen!") and text_da("Später")
	var chips := control_da("DayChip1") and control_da("DayChip7")
	print(
		(
			"[PT1] Popup-Inhalt: titel=%s serie=%s betrag=%s knoepfe=%s chips=%s"
			% [titel, serie, betrag, knoepfe, chips]
		)
	)
	return titel and serie and betrag and knoepfe and chips


## Kulanztag: Serie Tag 3 (+40) und die Kulanz-Zeile aus daily.kulanz.
func _kulanz_inhalt() -> bool:
	return _popup_inhalt(3, 40) and text_da("kein Problem")


func _merke_muenzen() -> bool:
	var coins := zahl("economy.coins", -1.0)
	return merke("muenzen_vorher", coins) and coins >= 0.0


## Später/Backdrop/Escape: Popup weg, aber HEUTE bleibt unclaimt (der
## Münz-Stand wird nur geloggt — der Mini-Fund könnte nebenher +1 buchen).
func _spaeter_ok() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var last := str(gs.get_value("daily.lastClaimDay", ""))
	print("[PT1] Abweisen: lastClaimDay='%s' coins=%s" % [last, zahl("economy.coins", -1.0)])
	return _popup_weg() and last != _heute()


## Claim-Beweis: Popup weg, Tages-Stempel heute, Serienstand, Münzen >= +N
## (>= statt ==, weil der Seelen-Mini-Fund parallel +1 buchen darf).
func _geclaimt(mindest_plus: float, serie: float) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var coins := zahl("economy.coins", -1.0)
	var vorher := float(wert("muenzen_vorher", -1.0))
	var stempel_ok := str(gs.get_value("daily.lastClaimDay", "")) == _heute()
	var serie_ok := zahl("daily.streak", -1.0) == serie
	print(
		(
			"[PT1] Claim: coins %s→%s (soll >= +%s) stempel=%s serie=%s"
			% [vorher, coins, mindest_plus, stempel_ok, serie_ok]
		)
	)
	return _popup_weg() and stempel_ok and serie_ok and coins >= vorher + mindest_plus


## Wieder-Anbieten über den App-Resume-Pfad: NOTIFICATION_APPLICATION_RESUMED
## ruft intern genau _maybe_offer_daily_bonus (reward_hub.gd) — der direkte
## call() simuliert das Wieder-Reinschauen ohne echtes Fenster-Event.
func _wieder_anbieten() -> bool:
	var hub := RewardHub.find(harness.root)
	if hub == null:
		print("[PT1] kein RewardHub (Gruppe reward_hub) im Baum")
		return false
	hub.call("_maybe_offer_daily_bonus")
	return true


## Test-Save-Stellung für die Serien-Logik: lastClaimDay `tage` zurück,
## Serienstand setzen — danach entscheidet die PURE DailyBonus-Logik.
func _zurueckdatieren(tage: int, serie: int) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var tag := _heute()
	for i in tage:
		tag = DailyBonus.prev_day(tag)
	if tag.is_empty():
		return false
	gs.update(func(s: Dictionary) -> void: s["daily"] = {"lastClaimDay": tag, "streak": serie})
	print("[PT1] daily zurückdatiert: lastClaimDay=%s streak=%d" % [tag, serie])
	return true


## Heutiger lokaler Kalendertag (Spiegel von reward_hub._local_day).
func _heute() -> String:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return str(gs.clock.local_day())
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

extends "res://tests/tools/playtest_flows/flow_pt4_basis.gd"
## PT-4 Flow (d) „Garderobe + Gestalten" (G7-P54-Verifikation):
## Garderobe: Beanie (100 Münzen, mit Start-100 + Tagesbonus-20 bezahlbar)
## KAUFEN → Kauf-Feedback (Karte funkelt, Status „Angelegt", Münzen -100)
## → Tabs Brillen/Fell durchtippen (Fell-Hinweis „nur hier im Shop") →
## ZU-TEUER-Gegenprobe an der Krone (1200): Kopfschütteln, KEIN Kauf.
## Gestalten: Kategorie „Briefkasten" — der User-Befund 1.8. war ein
## ABGESCHNITTENES „Briefkasten"-Label in der Kategorie-Liste → hier
## nachgemessen. Kugel-Briefkasten (150) vormerken (Anprobe + Kaufen-Knopf)
## → Kaufen → „Dafür reichen die Münzen nicht."-Toast (Kauf-Feedback,
## zweiter Pfad). Kategorien Wand (Raum-Chips) als Sichtprobe.
## Aufruf: tools/ci/run_playtest.sh flow_pt4_garderobe


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(
		[
			# ── Garderobe.
			{
				"name": "garderobe_oeffnen",
				"aktion": "tipp_name",
				"node": "BtnWardrobe",
				"erwarte": {"route": "wardrobe"},
				"timeout_s": 60.0,
			},
			{"name": "garderobe_ansehen", "aktion": "warte", "sekunden": 3.0},
			{"name": "muenzen_merken", "aktion": "tue", "funktion": merke_muenzen},
			{
				"name": "beanie_kaufen",
				"aktion": "tipp_name",
				"node": "Item_beanie",
				"erwarte": {"bedingung": beanie_gekauft},
				"timeout_s": 20.0,
			},
			{"name": "kauf_funkeln_ansehen", "aktion": "warte", "sekunden": 1.5},
			{
				"name": "beanie_angelegt",
				"aktion": "warte_bis",
				"bedingung": beanie_angelegt,
				"timeout_s": 10.0,
			},
			{
				"name": "muenzen_abgebucht",
				"aktion": "warte_bis",
				"bedingung": muenzen_um_100_gefallen,
				"timeout_s": 10.0,
			},
			{
				"name": "tab_brillen",
				"aktion": "tipp_text",
				"text": "Brillen",
				"erwarte": {"name": "Item_roundGlasses"},
				"timeout_s": 20.0,
			},
			{
				"name": "tab_fell",
				"aktion": "tipp_text",
				"text": "Fell",
				"erwarte": {"text": "Fellfarben gibt es nur hier"},
				"timeout_s": 20.0,
			},
			{
				"name": "tab_hut_zurueck",
				"aktion": "tipp_text",
				"text": "Hüte",
				"erwarte": {"name": "Item_crown"},
				"timeout_s": 20.0,
			},
			{
				"name": "krone_zu_teuer",
				"aktion": "tipp_name",
				"node": "Item_crown",
				"timeout_s": 15.0,
			},
			{"name": "kopfschuetteln_ansehen", "aktion": "warte", "sekunden": 1.0},
			{
				"name": "krone_nicht_gekauft",
				"aktion": "tue",
				"funktion": krone_nicht_gekauft,
				"erwartung": "Zu-teuer-Kauf ändert weder Besitz noch Münzen",
			},
			{
				"name": "garderobe_zurueck",
				"aktion": "tipp_text",
				"text": "Zurück",
				"erwarte": {"route": "home/living"},
				"timeout_s": 60.0,
			},
			{"name": "wohnzimmer_kurz", "aktion": "warte", "sekunden": 2.0},
			# ── Gestalten.
			{
				"name": "gestalten_oeffnen",
				"aktion": "tipp_name",
				"node": "BtnGestalten",
				"erwarte": {"route": "gestalten"},
				"timeout_s": 60.0,
			},
			{"name": "gestalten_ansehen", "aktion": "warte", "sekunden": 2.5},
			# Lauf 1: „Briefkasten" liegt UNTERM Falz der Kategorie-
			# Spalte (Innen→Haus-Liste scrollt) — erst in Sicht scrollen,
			# sonst tippt tipp_name auf die Rect-Mitte ausserhalb des
			# Sichtfensters und die Kategorie wechselt nie.
			{
				"name": "briefkasten_anscrollen",
				"aktion": "tue",
				"funktion":
				func() -> bool: return liste_anscrollen("KategorieScroll", "Kat_briefkasten"),
				"erwartung": "Kategorie-Spalte scrollt bis „Briefkasten“",
			},
			{"name": "scroll_beruhigen", "aktion": "warte", "sekunden": 0.5},
			{
				"name": "briefkasten_kategorie",
				"aktion": "tipp_name",
				"node": "Kat_briefkasten",
				"erwarte": {"name": "Option_kugel"},
				"timeout_s": 20.0,
			},
			{
				"name": "briefkasten_label_vollstaendig",
				"aktion": "tue",
				"funktion": kategorie_label_vollstaendig,
				"erwartung": "„Briefkasten“-Label passt in seine Kategorie-Zeile (P54)",
			},
			{
				"name": "kugel_vormerken",
				"aktion": "tipp_name",
				"node": "Option_kugel",
				"erwarte": {"name": "KaufButton"},
				"timeout_s": 20.0,
			},
			{
				"name": "farbe_anprobieren",
				"aktion": "tipp_falls_da",
				"node": "Farbe_pink",
				"timeout_s": 8.0,
				"pflicht": false,
			},
			{"name": "anprobe_ansehen", "aktion": "warte", "sekunden": 1.5},
			{
				"name": "kugel_kaufen_zu_teuer",
				"aktion": "tipp_name",
				"node": "KaufButton",
				"erwarte": {"text": "reichen die Münzen nicht"},
				"timeout_s": 15.0,
			},
			# Zurück-Scroll nach oben: „Tapeten & Wände" (Kat_wand) liegt
			# nach dem Briefkasten-Scroll ausser Sicht (Lauf 2).
			{
				"name": "wand_anscrollen",
				"aktion": "tue",
				"funktion": func() -> bool: return liste_anscrollen("KategorieScroll", "Kat_wand"),
				"erwartung": "Kategorie-Spalte scrollt zurück zu „Tapeten & Wände“",
				"pflicht": false,
			},
			{"name": "scroll_beruhigen_2", "aktion": "warte", "sekunden": 0.5},
			{
				"name": "wand_kategorie",
				"aktion": "tipp_name",
				"node": "Kat_wand",
				"erwarte": {"name": "Raum_living"},
				"timeout_s": 20.0,
				"pflicht": false,
			},
			# tipp_text „Zurück" traf hier in Lauf 1 den TEILSTRING-
			# Zwilling „Zurücksetzen" (Reset statt Navigation) — der
			# Gestalten-Kopf-Knopf heißt BackButton, den nehmen wir.
			{
				"name": "gestalten_zurueck",
				"aktion": "tipp_name",
				"node": "BackButton",
				"erwarte": {"route": "home/living"},
				"timeout_s": 60.0,
			},
			{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
		]
	)
	return liste


## Save-Schema laut CosmeticsState: cosmetics.outfits.owned (Array) und
## cosmetics.outfits.equipped = {hat/glasses/neck/back} — Lauf 1 fragte
## die falschen Pfade (cosmetics.owned / Slot „hut") ab.
func beanie_gekauft() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var owned: Variant = gs.get_value("cosmetics.outfits.owned", [])
	return owned is Array and (owned as Array).has("beanie")


func beanie_angelegt() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var equipped: Variant = gs.get_value("cosmetics.outfits.equipped", {})
	return equipped is Dictionary and str((equipped as Dictionary).get("hat", "")) == "beanie"


func muenzen_um_100_gefallen() -> bool:
	var jetzt := muenzen()
	print("[PT4] Münzen: %d (vorher %d)" % [jetzt, muenzen_merker])
	return muenzen_merker >= 100 and jetzt == muenzen_merker - 100


## Zu-teuer-Gegenprobe: Krone (1200) darf weder im Besitz landen noch
## Münzen kosten (Kauf-Feedback ist Kopfschütteln + ui_error, kein Toast).
func krone_nicht_gekauft() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var owned: Variant = gs.get_value("cosmetics.outfits.owned", [])
	var nicht_gekauft: bool = not (owned is Array and (owned as Array).has("crown"))
	var muenzen_gleich := muenzen() == muenzen_merker - 100
	print("[PT4] Krone nicht gekauft=%s, Münzen unverändert=%s" % [nicht_gekauft, muenzen_gleich])
	return nicht_gekauft and muenzen_gleich


## User-Befund 5 (1.8.): „Gestalten-Liste schneidet ‚Briefkasten' ab".
## P54-Fix nachgemessen: Der Button-Text passt bei gesetzter Schriftgröße
## in die Zeilenbreite (minus Style-Ränder) und Ellipsis ist aus.
func kategorie_label_vollstaendig() -> bool:
	var knopf := harness.root.find_child("Kat_briefkasten", true, false) as Button
	if knopf == null or not knopf.is_visible_in_tree():
		print("[PT4] Kat_briefkasten nicht sichtbar")
		return false
	var breite := HudLabelFit.text_breite(
		knopf.get_theme_font("font"), knopf.text, knopf.get_theme_font_size("font_size")
	)
	var verfuegbar := knopf.size.x
	var stil := knopf.get_theme_stylebox("normal")
	if stil != null:
		verfuegbar -= stil.get_content_margin(SIDE_LEFT) + stil.get_content_margin(SIDE_RIGHT)
	var kein_trim := knopf.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING
	var passt := breite <= verfuegbar + 0.5
	print(
		(
			"[PT4] Kat_briefkasten '%s': Text %.0f px / Platz %.0f px, Trim aus=%s -> %s"
			% [knopf.text, breite, verfuegbar, str(kein_trim), "ok" if passt else "ABGESCHNITTEN"]
		)
	)
	return passt and kein_trim

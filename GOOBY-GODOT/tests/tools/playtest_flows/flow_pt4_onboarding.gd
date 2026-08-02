extends "res://tests/tools/playtest_flows/flow_basis.gd"
## PT-4 Flow (a) „Onboarding komplett": frischer Spielstand → Boot-Cover →
## ALLE vier Onboarding-Karten wie ein Spieler (Name, Spitzname, Editor mit
## echtem Slider-Zug, Los geht's!) → Ankunft im Wohnzimmer → die Overlay-
## Kette nach dem Onboarding (Tagesbonus → Guide-Tour → Coachmark) Schritt
## für Schritt MIT Sicht-Prüfungen — das war der Pionier-Befund G7-P58
## („unsichtbarer Tagesbonus-Schleier schluckt Taps"): hier wird der
## Fix-Stand verifiziert (ist der Schleier sichtbar? kommt die Kette in
## Spieler-Reihenfolge? ist danach wirklich alles wieder tippbar?).
## Dazu: Karten-Zentrierung (Pionier: „Karten links der Mitte") und die
## HUD-Kachel-Labels (User-Screenshot 1.8.: „IGohbi/Garder/Gestalt").
## Aufruf: tools/ci/run_playtest.sh flow_pt4_onboarding

## Karten-Zentrierung: mehr als so viel Canvas-Anteil daneben = Befund.
const ZENTRIER_TOLERANZ := 0.06

## Münzstand vor dem Tagesbonus (merke → gestiegen-Prüfung).
var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	return [
		{
			"name": "boot_bis_onboarding",
			"aktion": "warte_bis",
			"klasse": "OnboardingFlow",
			"timeout_s": 240.0,
		},
		{"name": "welcome_karte_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "welcome_karte_zentriert",
			"aktion": "tue",
			"funktion": karte_zentriert.bind("StepWelcome"),
			"erwartung": "Welcome-Karte sitzt mittig im Canvas (Pionier-Befund)",
			"pflicht": false,
		},
		{"name": "name_eingeben", "aktion": "eingabe", "node": "NameEdit", "text": "Pionier"},
		{
			"name": "welcome_weiter",
			"aktion": "tipp_name",
			"node": "WelcomeNext",
			"erwarte": {"name": "NicknameEdit"},
		},
		{
			"name": "spitzname_eingeben",
			"aktion": "eingabe",
			"node": "NicknameEdit",
			"text": "Goobster",
		},
		{
			"name": "spitzname_weiter",
			"aktion": "tipp_name",
			"node": "NicknameNext",
			"erwarte": {"name": "EditorNext"},
		},
		{"name": "editor_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "editor_slider_ziehen",
			"aktion": "wisch",
			"von_funktion": slider_griff_pos,
			"nach_funktion": slider_ziel_pos,
			"dauer_s": 0.6,
		},
		{
			"name": "editor_karte_zentriert",
			"aktion": "tue",
			"funktion": karte_zentriert.bind("StepEditor"),
			"erwartung": "Editor-Karte sitzt mittig im Canvas (Pionier-Befund)",
			"pflicht": false,
		},
		{
			"name": "editor_weiter",
			"aktion": "tipp_name",
			"node": "EditorNext",
			"erwarte": {"name": "DoneButton"},
		},
		{"name": "done_karte_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "onboarding_fertig",
			"aktion": "tipp_name",
			"node": "DoneButton",
			"erwarte": {"route": "home/living"},
			"timeout_s": 150.0,
		},
		{"name": "wohnzimmer_ankommen", "aktion": "warte", "sekunden": 3.0},
		# ── Overlay-Kette (Pionier-Befund „Overlay-Stau"): Tagesbonus zuerst.
		{
			"name": "tagesbonus_erscheint",
			"aktion": "warte_bis",
			"text": "Abholen!",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{
			"name": "tagesbonus_schleier_sichtbar",
			"aktion": "tue",
			"funktion": bonus_schleier_sichtbar,
			"erwartung": "Tagesbonus-Popup hat einen SICHTBAREN Schleier (Alpha > 0.05)",
			"pflicht": false,
		},
		{"name": "muenzen_merken", "aktion": "tue", "funktion": merke_muenzen},
		{
			"name": "tagesbonus_abholen",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "tagesbonus_gebucht",
			"aktion": "warte_bis",
			"bedingung": muenzen_gestiegen,
			"timeout_s": 15.0,
			"erwartung": "Tagesbonus bucht wirklich Münzen (+20 an Tag 1)",
			"pflicht": false,
		},
		# ── Guide-Tour: liegt als Nächstes oben — wie ein Freispieler: X.
		{
			"name": "guide_tour_erscheint",
			"aktion": "warte_bis",
			"bedingung": guide_sichtbar,
			"timeout_s": 15.0,
			"pflicht": false,
		},
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
			"timeout_s": 8.0,
			"pflicht": false,
		},
		{"name": "hud_ansehen", "aktion": "warte", "sekunden": 2.0},
		# ── Stau-Gegenprobe: NACH der Kette muss das HUD wieder tippbar sein.
		{
			"name": "hud_frei_telefon_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnIgohbie",
			"erwarte": {"klasse": "PhoneShell"},
			"timeout_s": 45.0,
		},
		{"name": "telefon_offen_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "telefon_wieder_zu",
			"aktion": "tipp_name",
			"node": "HomeBalken",
			"erwarte": {"weg_klasse": "PhoneShell"},
			"timeout_s": 30.0,
		},
		{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
	]


## Onboarding-Karte (Node-Name) horizontal zentriert im Canvas?
func karte_zentriert(node_name: String) -> bool:
	var karte := harness.root.find_child(node_name, true, false) as Control
	if karte == null or not karte.is_visible_in_tree():
		return false
	var canvas := harness.root.get_visible_rect().size
	var mitte := karte.get_global_rect().get_center().x
	var abweichung: float = absf(mitte - canvas.x / 2.0) / canvas.x
	print(
		(
			"[PT4] Karte %s: Mitte %.0f / Canvas %.0f (Abweichung %.1f%%)"
			% [node_name, mitte, canvas.x, abweichung * 100.0]
		)
	)
	return abweichung <= ZENTRIER_TOLERANZ


## Erste Editor-Slider-Position (Griff ≈ Wertposition im Slider-Rect).
func slider_griff_pos() -> Vector2:
	var slider := harness.root.find_child("SliderEyesApart", true, false) as Control
	if slider == null:
		return harness.root.get_visible_rect().size * 0.5
	var rect := slider.get_global_rect()
	return Vector2(rect.get_center().x, rect.get_center().y)


func slider_ziel_pos() -> Vector2:
	var slider := harness.root.find_child("SliderEyesApart", true, false) as Control
	if slider == null:
		return harness.root.get_visible_rect().size * 0.5
	var rect := slider.get_global_rect()
	return Vector2(rect.position.x + rect.size.x * 0.9, rect.get_center().y)


## Tagesbonus-Popup: Veil vorhanden UND sichtbar (Alpha > 0.05)?
## Der Pionier-Befund war ein UNSICHTBARER Vollbild-Schleier über der Tour.
func bonus_schleier_sichtbar() -> bool:
	var popup := harness.root.find_child("DailyBonusPopup", true, false) as Control
	if popup == null or not popup.is_visible_in_tree():
		print("[PT4] Kein Tagesbonus-Popup sichtbar (heute evtl. schon abgeholt?)")
		return false
	var veil := popup.find_child("Veil", true, false) as ColorRect
	if veil == null:
		print("[PT4] Popup ohne Veil-Node")
		return false
	var alpha := veil.color.a * veil.modulate.a * veil.self_modulate.a
	print("[PT4] Tagesbonus-Veil Alpha effektiv: %.2f" % alpha)
	return veil.is_visible_in_tree() and alpha > 0.05


func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", -1))
	return _muenzen_vorher >= 0


func muenzen_gestiegen() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0:
		return false
	return int(gs.get_value("economy.coins", 0)) > _muenzen_vorher


## OnboardingGuide sichtbar (Tour-Karte „Schritt 1/9")?
func guide_sichtbar() -> bool:
	return harness.root.find_child("GuideBeenden", true, false) != null

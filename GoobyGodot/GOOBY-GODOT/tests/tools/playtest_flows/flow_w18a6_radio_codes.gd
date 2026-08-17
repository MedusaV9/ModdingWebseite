extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18/3 Playtest Agent 6 — Flow (c) + (f): RADIO am Wohnzimmer-Gerät
## (Like-Offscreen-Fix G7/P53 prüfen: Like-Knopf bleibt im Canvas), Codes-
## Screen (GOLDIGOLD einlösen), Einstellungen-Sweep — Haptik-Stärke,
## Updates-Tab (nur UI, kein echter Download), News-Panel und der
## versteckte DEV-Modus (3× Tipp auf „Deutsch“ + Halte-Bestätigung).
##
## V4 (W18/4-Fix B6): der Möbel-Tap ist an der Wurzel gefixt (TapArea
## feuert auf Release + dedupliziert das Maus/Touch-Doppel von
## emulate_touch_from_mouse — das Sheet schloss sich sonst sofort wieder
## über den frisch gespawnten Backdrop). Der physische 3D-Tap aufs Radio
## ist deshalb PFLICHT-Wache, der Direkt-Fallback (`_on_tapped`) ist raus.
## V3 (W18/4-Fix): B4 ist an der Wurzel gefixt (home_entry räumt das
## Settings-Overlay bei travel_started ab) — der Codes-über-Settings-Pfad
## am Ende ist jetzt PFLICHT-Wache statt Repro: Settings müssen nach dem
## Routenwechsel WEG sein (weg_klasse + Baum-Check), der Codes-Screen wird
## per physischem Zurück-Tap bedient (der vorher von den Settings
## geschluckt wurde). Der Workaround „Settings-Zurück blind treffen“ ist raus.
## V2 (nach Lauf 1): Codes werden zuerst DIREKT über die Route getestet
## (Funktionstest).
## Aufruf: tools/ci/run_playtest.sh flow_w18a6_radio_codes

## Münzstand vor dem Code (merke_muenzen → code_wirkt).
var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_aufraeumen())
	liste.append_array(_schritte_radio())
	liste.append_array(_schritte_codes_direkt())
	liste.append_array(_schritte_einstellungen())
	liste.append_array(_schritte_codes_aus_settings())
	return liste


func _schritte_aufraeumen() -> Array[Dictionary]:
	return [
		# Befund B1/B2: verspäteter Tagesbonus + verspätete Tour-Karte
		# abräumen, sonst schlucken sie die folgenden Taps (Test-Staging).
		{
			"name": "spaeter_tagesbonus",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 45.0,
			"pflicht": false,
		},
		{
			"name": "tour_spaet_beenden",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{
			"name": "wasnun_weg",
			"aktion": "tipp_falls_da",
			"node": "WasNunSchliessen",
			"timeout_s": 10.0,
			"pflicht": false,
		},
	]


func _schritte_radio() -> Array[Dictionary]:
	return [
		{
			"name": "radio_lage",
			"aktion": "tue",
			"funktion": radio_lage,
			"erwartung": "Radio-Möbel + TapArea im Baum, Projektion geloggt",
			"pflicht": false,
		},
		# W18/4 Kamera-Staging: das Wohnzimmer-Rig folgt Gooby, das Radio kann
		# darum am Canvas-Rand unter den HUD-Chips liegen (Lauf g5_radio_v4:
		# Projektion (48, 838) = exakt der „Wo ist mein Gooby?“-Chip — der Tap
		# traf den Chip statt des Möbels). Wie ein Spieler: Boden nahe dem
		# Radio greifen und zur Mitte ziehen (freier Kamera-Pan; MANUAL_HOLD_S
		# hält das Bild danach 2,5 s still), zweimal für weite Wege, dann
		# sofort physisch tippen. Der Griffpunkt ist nie ein Tap (s. Helper).
		{
			"name": "radio_in_sicht_ziehen",
			"aktion": "wisch",
			"von_funktion": radio_pan_griff,
			"nach_funktion": _canvas_mitte,
			"dauer_s": 0.5,
		},
		{
			"name": "radio_nachziehen",
			"aktion": "wisch",
			"von_funktion": radio_pan_griff,
			"nach_funktion": _canvas_mitte,
			"dauer_s": 0.4,
		},
		# W18/4 B6-Wache: der physische Tap ist PFLICHT — und das Sheet muss
		# offen BLEIBEN (vorher schloss der zweite emulierte Press es über
		# den frisch gespawnten Backdrop sofort wieder). Kein Fallback mehr.
		{
			"name": "radio_antippen",
			"aktion": "tipp_3d",
			"finder": finde_radio,
			"offset": Vector3(0.0, 0.15, 0.0),
			"erwarte": {"klasse": "RadioSheet"},
			"timeout_s": 25.0,
		},
		{"name": "radio_bleibt_moment", "aktion": "warte", "sekunden": 1.5},
		{"name": "radio_offen", "aktion": "warte_bis", "klasse": "RadioSheet", "timeout_s": 10.0},
		{"name": "radio_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "radio_besitz",
			"aktion": "tue",
			"funktion": pruefe_radio_besitz,
			"erwartung": "Standard-Radio im Wohnzimmer = Vollradio",
			"pflicht": false,
		},
		{
			"name": "like_im_canvas",
			"aktion": "tue",
			"funktion": pruefe_like_im_canvas,
			"erwartung": "Like-Knopf komplett im Canvas (G7/P53-Fix)",
			"pflicht": false,
		},
		{"name": "radio_an", "aktion": "tipp_name", "node": "AnAus", "timeout_s": 20.0},
		{"name": "musik_laeuft", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "naechster_titel",
			"aktion": "tipp_name",
			"node": "Naechster",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "titel_wechselt", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "like_tippen",
			"aktion": "tipp_name",
			"node": "Like",
			"erwarte": {"bedingung": like_verbucht},
			"timeout_s": 15.0,
		},
		{"name": "like_ansehen", "aktion": "warte", "sekunden": 1.0},
		# Lauf 2: „Schliessen“ liegt unterhalb des Sheet-Folds (Tap ging ins
		# Leere) — erst ins Bild scrollen (UX-Nit im Report).
		{
			"name": "zu_schliessen_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("Schliessen"),
			"erwartung": "Schliessen-Knopf im Bild",
			"pflicht": false,
		},
		{"name": "schliessen_settelt", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "radio_schliessen",
			"aktion": "tipp_name",
			"node": "Schliessen",
			"erwarte": {"weg_klasse": "RadioSheet"},
			"timeout_s": 20.0,
		},
	]


## Funktionstest Codes-Screen OHNE Settings darüber: Route direkt anfahren.
## (Der reguläre Weg über die Einstellungen ist die B4-Repro am Ende.)
func _schritte_codes_direkt() -> Array[Dictionary]:
	return [
		{
			"name": "codes_route_direkt",
			"aktion": "tue",
			"funktion": codes_direkt_oeffnen,
			"erwartung": "SceneRouter.goto(codes) abgesetzt",
		},
		{"name": "codes_da", "aktion": "warte_bis", "klasse": "CodesScreen", "timeout_s": 30.0},
		{"name": "codes_settelt", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "muenzen_merken",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "code_eingeben",
			"aktion": "eingabe",
			"node": "CodeEingabe",
			"text": "GOLDIGOLD",
		},
		{
			"name": "code_einloesen",
			"aktion": "tipp_name",
			"node": "Einloesen",
			"erwarte": {"bedingung": code_wirkt},
			"timeout_s": 20.0,
		},
		{"name": "einloese_feier", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "codes_zurueck",
			"aktion": "tipp_name",
			"node": "Zurueck",
			"erwarte": {"weg_klasse": "CodesScreen"},
			"timeout_s": 25.0,
			"pflicht": false,
		},
		{
			"name": "codes_zurueck_fallback",
			"aktion": "tue",
			"funktion": codes_notfalls_schliessen,
			"erwartung": "CodesScreen zu (regulär oder per Signal-Fallback)",
			"pflicht": false,
		},
		{
			"name": "wieder_daheim",
			"aktion": "warte_bis",
			"route": "home/living",
			"timeout_s": 60.0,
		},
		{"name": "heim_settelt", "aktion": "warte", "sekunden": 2.0},
	]


func _schritte_einstellungen() -> Array[Dictionary]:
	return [
		{
			"name": "einstellungen_oeffnen",
			"aktion": "tipp_name",
			"node": "SettingsButton",
			"erwarte": {"klasse": "SettingsScreen"},
			"timeout_s": 45.0,
		},
		# Haptik-Stärke (Steuerung): Picker zeigen + auf „Stark“ stellen.
		{
			"name": "zu_haptik_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("RowControlsHaptics"),
			"erwartung": "Haptik-Zeile im Bild",
		},
		{"name": "haptik_im_bild", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "haptik_picker_auf",
			"aktion": "tipp_pos",
			"pos_funktion": haptik_picker_pos,
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "haptik_popup_ansehen", "aktion": "warte", "sekunden": 1.5},
		{"name": "haptik_popup_zu", "aktion": "taste", "keycode": KEY_ESCAPE},
		{
			"name": "haptik_auf_stark",
			"aktion": "tue",
			"funktion": haptik_auf_stark,
			"erwartung": "controls.haptics == stark",
		},
		# Updates-Tab: nur UI — Prüfung anstoßen, Toast abwarten.
		{
			"name": "zu_updates_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("UpdateCheckButton"),
			"erwartung": "Updates-Sektion im Bild",
		},
		{"name": "updates_im_bild", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "updates_pruefen",
			"aktion": "tipp_name",
			"node": "UpdateCheckButton",
			"timeout_s": 20.0,
		},
		{"name": "updates_toast", "aktion": "warte", "sekunden": 4.0},
		# News-Panel (Info-Gruppe).
		{
			"name": "zu_news_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("NewsButton"),
			"erwartung": "News-Knopf im Bild",
		},
		{"name": "news_im_bild", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "news_oeffnen",
			"aktion": "tipp_name",
			"node": "NewsButton",
			"erwarte": {"klasse": "News50Panel"},
			"timeout_s": 30.0,
		},
		{"name": "news_lesen", "aktion": "warte", "sekunden": 2.5},
		# Lauf 2: Wisch ab Sheet-MITTE scrollt nur den Inhalt — das Sheet
		# blieb offen und schluckte ALLE weiteren Taps (Dev-Trigger, B4).
		# Deshalb am GRIFF ziehen und notfalls programmatisch schließen.
		{
			"name": "news_schliessen",
			"aktion": "wisch",
			"von_rel": Vector2(0.5, 0.24),
			"nach_rel": Vector2(0.5, 0.98),
			"dauer_s": 0.5,
			"erwarte": {"weg_klasse": "News50Panel"},
			"timeout_s": 20.0,
			"pflicht": false,
		},
		{
			"name": "news_zu_fallback",
			"aktion": "tue",
			"funktion": news_notfalls_schliessen,
			"erwartung": "News-Sheet zu (Geste oder close()-Fallback)",
		},
		{
			"name": "news_wirklich_weg",
			"aktion": "warte_bis",
			"weg_klasse": "News50Panel",
			"timeout_s": 10.0,
		},
		# Versteckter DEV-Modus: 3× Tipp auf das aktive „Deutsch“, dann den
		# Bestätigungs-Knopf 2 s HALTEN (DevTrigger.HOLD_MS).
		{
			"name": "zu_sprache_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("RowLanguage"),
			"erwartung": "Sprach-Zeile im Bild",
		},
		{"name": "sprache_im_bild", "aktion": "warte", "sekunden": 1.0},
		# Lauf 2: drei einzelne Harness-Taps brauchen je ~1,1 s und reißen
		# das 1,5-s-Fenster von DevTrigger.WINDOW_MS — die Serie verfällt.
		# Deshalb EIN Schritt, der die drei Tipps im Fenster auslöst.
		{
			"name": "dev_dreifachtipp",
			"aktion": "tue",
			"funktion": dev_dreifachtipp,
			"erwartung": "3 Tipps auf „Deutsch“ innerhalb 1,5 s",
		},
		{
			"name": "dev_dialog_da",
			"aktion": "warte_bis",
			"bedingung": dev_dialog_da,
			"timeout_s": 15.0,
		},
		# HOLD_MS ist 2000 — unter llvmpipe kommt der synthetische Druck erst
		# beim nächsten (u. U. sehr späten) Frame an, 2,6 s Wanduhr reichten
		# dann nicht (Lauf 1 + 4 flakten genau hier). 4 s geben echten Puffer.
		{
			"name": "dev_halten",
			"aktion": "halte",
			"pos_funktion": dev_halteknopf_pos,
			"dauer_s": 4.0,
		},
		{
			"name": "dev_badge_da",
			"aktion": "warte_bis",
			"bedingung": dev_badge_da,
			"timeout_s": 15.0,
		},
		{
			"name": "dev_menu_oeffnen",
			"aktion": "tipp_name",
			"node": "DevBadgeButton",
			"erwarte": {"klasse": "DevMenu"},
			"timeout_s": 20.0,
		},
		{"name": "dev_menu_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "dev_menu_schliessen",
			"aktion": "tipp_name",
			"node": "CloseButton",
			"erwarte": {"weg_klasse": "DevMenu"},
			"timeout_s": 20.0,
		},
	]


## B4-Wache (W18/4-Fix, PFLICHT): „Aktionscodes einlösen“ AUS den offenen
## Einstellungen — der Routenwechsel baut das Settings-Overlay generisch ab
## (home_entry hört auf travel_started), der Codes-Screen liegt frei und
## der physische Zurück-Tap (vorher von den Settings geschluckt) trifft.
func _schritte_codes_aus_settings() -> Array[Dictionary]:
	return [
		# Fehler-Isolation: flakt die Dev-Halte-Bestätigung davor, bleibt ihr
		# Warn-Dialog offen und schluckt JEDEN Tap — die B4-Wache würde dann
		# fälschlich rot. Einen hängenden Dialog deshalb abbrechen (ohne Fund
		# ist der Schritt ein No-op).
		{
			"name": "dev_dialog_notschliessen",
			"aktion": "tipp_falls_da",
			"node": "CancelButton",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "b4_zu_codes_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("CodesButton"),
			"erwartung": "Codes-Knopf im Bild",
		},
		{"name": "b4_scroll_settelt", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "b4_codes_aus_settings",
			"aktion": "tipp_name",
			"node": "CodesButton",
			"erwarte": {"klasse": "CodesScreen"},
			"timeout_s": 30.0,
		},
		# Kern der Wache: die Settings sind nach dem Routenwechsel WEG —
		# nicht bloß unsichtbar, sondern aus dem Baum abgebaut.
		{
			"name": "b4_settings_weg",
			"aktion": "warte_bis",
			"weg_klasse": "SettingsScreen",
			"timeout_s": 15.0,
		},
		{"name": "b4_codes_settelt", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "b4_codes_frei",
			"aktion": "tue",
			"funktion": pruefe_codes_frei,
			"erwartung": "Settings abgebaut, Codes-Screen frei",
		},
		# Bedienbarkeit beweisen: der physische Zurück-Tap trifft den
		# Codes-Screen (vor dem Fix schluckten ihn die Settings darüber).
		{
			"name": "b4_codes_zurueck",
			"aktion": "tipp_name",
			"node": "Zurueck",
			"erwarte": {"weg_klasse": "CodesScreen"},
			"timeout_s": 25.0,
		},
		{
			"name": "b4_heim",
			"aktion": "warte_bis",
			"route": "home/living",
			"timeout_s": 60.0,
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------------------------------------- Werkzeuge


func _control(node_name: String) -> Control:
	return harness.root.find_child(node_name, true, false) as Control


func finde_radio() -> Node3D:
	return finde_moebel("radio")


## W18/4 Kamera-Staging: Griffpunkt für den Boden-Pan, der das Radio zur
## Bildmitte zieht. Die Radio-Projektion wird in die HUD-freie Zone geklemmt
## (links Statuspillen, unten „Wo ist mein Gooby?“-Chip, rechts App-Spalte);
## liegt der Griff schon nahe der Mitte, wird er nach außen verlängert, damit
## der Wisch IMMER ein echter Pan bleibt und nie zum versehentlichen Tap
## degeneriert (Release ≥ 160 px vom Druckpunkt > TapArea-Toleranz).
func radio_pan_griff() -> Vector2:
	var canvas: Vector2 = harness.root.get_visible_rect().size
	var mitte := canvas / 2.0
	var punkt := mitte + Vector2(200.0, 0.0)
	var radio := finde_moebel("radio")
	if radio != null:
		var kamera := radio.get_viewport().get_camera_3d()
		if kamera != null and not kamera.is_position_behind(radio.global_position):
			punkt = kamera.unproject_position(radio.global_position)
	var rand := Vector2(canvas.x * 0.18, canvas.y * 0.25)
	punkt = punkt.clamp(rand, canvas - rand)
	if punkt.distance_to(mitte) < 160.0:
		var richtung := Vector2.RIGHT
		if punkt != mitte:
			richtung = (punkt - mitte).normalized()
		punkt = mitte + richtung * 160.0
	return punkt


func _canvas_mitte() -> Vector2:
	return harness.root.get_visible_rect().size / 2.0


## Diagnose vor dem Tap: Wo liegt das Radio, gibt es RadioGeraet/TapArea,
## wohin projiziert der Tap? (Befund-Futter, falls der 3D-Tap fehlschlägt.)
func radio_lage() -> bool:
	var radio := finde_moebel("radio")
	if radio == null:
		print("[A6] radio_lage: radio-Möbel fehlt")
		return false
	var geraete := harness.root.find_children("*", "RadioGeraet", true, false)
	var tap_area: Node = null
	if not geraete.is_empty():
		tap_area = geraete[0].find_child("TapArea", true, false)
	var kamera := radio.get_viewport().get_camera_3d()
	var schirm := Vector2(-1, -1)
	var hinter := false
	if kamera != null:
		var punkt: Vector3 = radio.global_position + Vector3(0.0, 0.15, 0.0)
		schirm = kamera.unproject_position(punkt)
		hinter = kamera.is_position_behind(punkt)
	print(
		(
			"[A6] radio_lage: pos=%s geraete=%d tap_area=%s schirm=%s hinter=%s"
			% [radio.global_position, geraete.size(), tap_area != null, schirm, hinter]
		)
	)
	return not geraete.is_empty() and tap_area != null


func pruefe_radio_besitz() -> bool:
	var gs := game_state()
	if gs == null or not gs.has_method("state"):
		return false
	# Vollradio = radio.owned ODER Radio-Möbel im Haus (Default-Wohnzimmer).
	var owned: bool = RadioLogic.besitzt_radio(gs.state())
	print("[A6] besitzt_radio=%s" % owned)
	return owned


## G7/P53-Fix: Like-Knopf (und die ganze Transportzeile) im Canvas.
func pruefe_like_im_canvas() -> bool:
	var like := _control("Like")
	if like == null or not like.is_visible_in_tree():
		print("[A6] Like-Knopf fehlt")
		return false
	var sicht := harness.root.get_visible_rect()
	var rect := like.get_global_rect()
	var drin := sicht.grow(2.0).encloses(rect)
	print("[A6] Like rect=%s canvas=%s drin=%s" % [str(rect), str(sicht), drin])
	return drin


func like_verbucht() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	# radio.likes ist eine Map track_id -> bool (RadioLogic.likes_von).
	var likes: Variant = gs.get_value("radio.likes", {})
	if not (likes is Dictionary):
		return false
	for track_id: Variant in likes as Dictionary:
		if (likes as Dictionary)[track_id] is bool and bool((likes as Dictionary)[track_id]):
			return true
	return false


## Codes-Route direkt anfahren (Funktionstest ohne Settings-Deckel).
func codes_direkt_oeffnen() -> bool:
	CodesScreen.register_routes()
	var router := harness.root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		print("[A6] codes_direkt: SceneRouter fehlt")
		return false
	router.goto(CodesScreen.ROUTE)
	return true


## Fallback: hängt der Codes-Screen noch im Baum, den Zurück-Knopf per
## Signal drücken (falls der physische Tap geschluckt wurde).
func codes_notfalls_schliessen() -> bool:
	var codes := _finde_klasse_instanz("CodesScreen")
	if codes == null:
		return true
	print("[A6] codes_zurueck_fallback: Codes noch offen — Zurueck per Signal")
	var zurueck := codes.find_child("Zurueck", true, false) as BaseButton
	if zurueck == null:
		return false
	zurueck.pressed.emit()
	return true


## B4-Wache (W18/4-Fix): Settings sind ABGEBAUT (keine Instanz mehr im
## Baum, nichts schluckt Taps), der Codes-Screen steht.
func pruefe_codes_frei() -> bool:
	var settings := _finde_klasse_instanz("SettingsScreen")
	var codes := _finde_klasse_instanz("CodesScreen")
	print("[A6] B4-Wache: settings_im_baum=%s codes_im_baum=%s" % [settings != null, codes != null])
	return settings == null and codes != null


func _finde_klasse_instanz(klasse: String) -> Node:
	return _suche_klasse(harness.root, klasse)


func _suche_klasse(node: Node, klasse: String) -> Node:
	var skript := node.get_script() as Script
	if skript != null and str(skript.get_global_name()) == klasse:
		return node
	for kind in node.get_children():
		var gefunden := _suche_klasse(kind, klasse)
		if gefunden != null:
			return gefunden
	return null


func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	return true


## GOLDIGOLD wirkt: gvz.goldi-Flag ODER Münzzuwachs ODER Redeemed-Eintrag.
func code_wirkt() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	if bool(gs.get_value("gvz.goldi", false)):
		return true
	var redeemed: Variant = gs.get_value("codes.redeemed", {})
	if redeemed is Dictionary and (redeemed as Dictionary).has("goldiGold"):
		return true
	return _muenzen_vorher >= 0 and int(gs.get_value("economy.coins", 0)) > _muenzen_vorher


## Ziel-Control in seinem ScrollContainer ins Bild holen.
func scrolle_zu(node_name: String) -> bool:
	var ziel := _control(node_name)
	if ziel == null:
		print("[A6] scrolle_zu: %s fehlt" % node_name)
		return false
	var scroll: ScrollContainer = null
	var n: Node = ziel.get_parent()
	while n != null:
		if n is ScrollContainer:
			scroll = n
			break
		n = n.get_parent()
	if scroll == null:
		print("[A6] scrolle_zu: kein ScrollContainer über %s" % node_name)
		return false
	var delta := ziel.get_global_rect().position.y - scroll.get_global_rect().position.y
	scroll.scroll_vertical += int(delta - scroll.get_global_rect().size.y * 0.35)
	return true


## Mitte des Haptik-Pickers (OptionButton „Value“ in RowControlsHaptics).
func haptik_picker_pos() -> Vector2:
	var zeile := _control("RowControlsHaptics")
	if zeile == null:
		return harness.root.get_visible_rect().size * 0.5
	var picker := zeile.find_child("Value", true, false) as Control
	if picker == null:
		return zeile.get_global_rect().get_center()
	return picker.get_global_rect().get_center()


## Haptik-Stärke programmatisch auf „stark“ (Popup-Menüs sind für die
## Harness nicht tippbar) — der echte Handler + Persistenz laufen mit.
func haptik_auf_stark() -> bool:
	var zeile := _control("RowControlsHaptics")
	if zeile == null:
		return false
	var picker := zeile.find_child("Value", true, false) as OptionButton
	if picker == null:
		return false
	picker.select(3)
	picker.item_selected.emit(3)
	var app := harness.root.get_node_or_null("/root/AppSettings")
	if app == null or not app.has_method("get_setting"):
		return false
	var wert := str(app.get_setting("controls.haptics"))
	print("[A6] controls.haptics=%s" % wert)
	return wert == "stark"


## News-Sheet notfalls programmatisch schließen (falls die Griff-Geste
## nicht gegriffen hat) — sonst schluckt der Backdrop alle weiteren Taps.
func news_notfalls_schliessen() -> bool:
	var panel := _finde_klasse_instanz("News50Panel")
	if panel == null:
		return true
	print("[A6] News-Sheet noch offen — close()-Fallback")
	if not panel.has_method("close"):
		return false
	panel.call("close")
	return true


## Drei Tipps auf das aktive „Deutsch“ innerhalb des DevTrigger-Fensters
## (1,5 s) — der echte Button-Handler läuft jedes Mal mit.
func dev_dreifachtipp() -> bool:
	var knopf := _control("LangDE") as BaseButton
	if knopf == null or not knopf.is_visible_in_tree():
		print("[A6] dev_dreifachtipp: LangDE fehlt")
		return false
	for i in 3:
		knopf.pressed.emit()
	return true


func dev_dialog_da() -> bool:
	var knopf := _control("HoldButton")
	return knopf != null and knopf.is_visible_in_tree()


func dev_halteknopf_pos() -> Vector2:
	var knopf := _control("HoldButton")
	if knopf == null:
		return harness.root.get_visible_rect().size * 0.5
	return knopf.get_global_rect().get_center()


func dev_badge_da() -> bool:
	var badge := _control("DevBadgeButton")
	return badge != null and badge.is_visible_in_tree()

extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18/3 Playtest Agent 6 — Flow (b) „IGohbie-Telefon komplett“: alle Apps
## öffnen/schließen (Taxi, Guber, Gooberando, GoobyPal, Instant), Freunde-
## App (eigenen Code teilen/kopieren, eingehende Anfrage ANNEHMEN — ein
## Buddy-Agent am lokalen GOOBY-Server schickt sie), Links-Wisch zurück
## aufs Grid, Wisch-nach-unten schließt das Handy, Fotomodus inkl. SELFIE
## (Kamera-Item wird als Test-Staging ins Inventar gelegt — der POW-Kauf
## ist nicht Testziel dieses Flows).
## Voraussetzung: GOOBY-SERVER läuft auf 127.0.0.1:8765 und der Buddy-
## Agent (buddy_agent.mjs) pollt /tmp/gooby-w18/playtest/player_code*.txt.
## Aufruf: tools/ci/run_playtest.sh flow_w18a6_telefon

## Austausch-Ordner mit dem Buddy-Agenten (außerhalb des Repos).
const BUDDY_DIR := "/tmp/gooby-w18/playtest"

## Fotostand vor dem Knipsen (foto_gezaehlt → foto_dazu).
var _fotos_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_apps())
	liste.append_array(_schritte_freunde())
	liste.append_array(_schritte_gesten())
	liste.append_array(_schritte_fotomodus())
	return liste


func _schritte_apps() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		# Befund B1 (Lauf 1+2): der Tagesbonus kommt auf frischen Saves erst
		# NACH dem Coachmark (verspätet) und schluckt sonst den nächsten Tap
		# als Backdrop-„Später“; die Tour-Karte kommt ebenfalls verspätet und
		# legt sich übers Handy (B2). Beides hier abräumen (Test-Staging).
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
		{
			"name": "kamera_freischalten",
			"aktion": "tue",
			"funktion": kamera_freischalten,
			"erwartung": "Kamera-Item liegt im Inventar (Test-Staging)",
		},
		{
			"name": "handy_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnIgohbie",
			"erwarte": {"klasse": "PhoneShell"},
			"timeout_s": 60.0,
		},
		{"name": "grid_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "grid_vollstaendig",
			"aktion": "tue",
			"funktion": pruefe_grid,
			"erwartung": "7 App-Kacheln, Kamera entsperrt",
			"pflicht": false,
		},
	]
	for app_id: String in ["taxi", "guber", "gooberando", "goobypal", "instant"]:
		(
			liste
			. append(
				{
					"name": "app_%s_oeffnen" % app_id,
					"aktion": "tipp_name",
					"node": "Kachel%s" % app_id.capitalize(),
					"erwarte": {"bedingung": app_aktiv.bind(app_id)},
					"timeout_s": 30.0,
				}
			)
		)
		liste.append({"name": "app_%s_ansehen" % app_id, "aktion": "warte", "sekunden": 1.5})
		(
			liste
			. append(
				{
					"name": "app_%s_zurueck" % app_id,
					"aktion": "tipp_name",
					"node": "HomeBalken",
					"erwarte": {"bedingung": app_aktiv.bind("")},
					"timeout_s": 20.0,
				}
			)
		)
	return liste


func _schritte_freunde() -> Array[Dictionary]:
	return [
		{
			"name": "freunde_oeffnen",
			"aktion": "tipp_name",
			"node": "KachelFreunde",
			"erwarte": {"bedingung": app_aktiv.bind("freunde")},
			"timeout_s": 30.0,
		},
		{
			"name": "eigener_code_da",
			"aktion": "warte_bis",
			"bedingung": eigener_code_da,
			"timeout_s": 45.0,
		},
		{
			"name": "code_teilen",
			"aktion": "tue",
			"funktion": code_exportieren,
			"erwartung": "Freundes-Code liegt für den Buddy bereit",
		},
		{
			"name": "code_kopieren",
			"aktion": "tipp_name",
			"node": "KopierenButton",
			"timeout_s": 20.0,
			"pflicht": false,
		},
		{
			"name": "anfrage_kommt",
			"aktion": "warte_bis",
			"bedingung": anfrage_da,
			"timeout_s": 60.0,
		},
		{"name": "anfrage_ansehen", "aktion": "warte", "sekunden": 2.0},
		# B3: die „Was nun?“-Karte schwebt ÜBER dem Handy — wegtippen, sonst
		# schluckt sie den Annehmen-Tap. Danach zur Anfragen-Box scrollen
		# (sie liegt unter „Freund hinzufügen“ außerhalb des Sichtfensters).
		{
			"name": "wasnun_weg_2",
			"aktion": "tipp_falls_da",
			"node": "WasNunSchliessen",
			"timeout_s": 6.0,
			"pflicht": false,
		},
		{
			"name": "zu_anfragen_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("AnfragenBox"),
			"erwartung": "Anfragen-Box im Sichtfenster",
			"pflicht": false,
		},
		{"name": "scroll_settelt", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "anfrage_annehmen",
			"aktion": "tipp_text",
			"text": "Annehmen",
			"erwarte": {"bedingung": freund_da},
			"timeout_s": 30.0,
		},
		{"name": "freundesliste_ansehen", "aktion": "warte", "sekunden": 2.0},
	]


func _schritte_gesten() -> Array[Dictionary]:
	return [
		# Nach der Freunde-App erst zurück aufs Grid (Kacheln sind sonst
		# verdeckt), dann Gooberando für den Links-Wisch öffnen (G7/P52).
		{
			"name": "geste_heim_aufs_grid",
			"aktion": "tipp_falls_da",
			"node": "HomeBalken",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "gooberando_fuer_geste",
			"aktion": "tipp_name",
			"node": "KachelGooberando",
			"erwarte": {"bedingung": app_aktiv.bind("gooberando")},
			"timeout_s": 30.0,
		},
		{
			"name": "linkswisch_zurueck",
			"aktion": "wisch",
			"von_funktion": geraet_links,
			"nach_funktion": geraet_links_ziel,
			"dauer_s": 0.5,
			"erwarte": {"bedingung": app_aktiv.bind("")},
			"timeout_s": 15.0,
		},
		# Wisch nach unten (auf dem Gerät) schließt das Handy vom Grid aus.
		{
			"name": "wisch_zu",
			"aktion": "wisch",
			"von_funktion": geraet_links,
			"nach_funktion": geraet_runter_ziel,
			"dauer_s": 0.5,
			"erwarte": {"weg_klasse": "PhoneShell"},
			"timeout_s": 15.0,
		},
	]


func _schritte_fotomodus() -> Array[Dictionary]:
	return [
		# B3-Staging: die „Was nun?“-Karte taucht periodisch wieder auf und
		# schwebt über Handy/Fotomodus — vor der Foto-Session wegtippen.
		{
			"name": "wasnun_weg_3",
			"aktion": "tipp_falls_da",
			"node": "WasNunSchliessen",
			"timeout_s": 6.0,
			"pflicht": false,
		},
		{
			"name": "handy_wieder_auf",
			"aktion": "tipp_name",
			"node": "BtnIgohbie",
			"erwarte": {"klasse": "PhoneShell"},
			"timeout_s": 60.0,
		},
		{
			"name": "kamera_app_oeffnen",
			"aktion": "tipp_name",
			"node": "KachelKamera",
			"erwarte": {"bedingung": app_aktiv.bind("kamera")},
			"timeout_s": 30.0,
		},
		{
			"name": "fotomodus_starten",
			"aktion": "tipp_name",
			"node": "FotomodusStarten",
			"erwarte": {"klasse": "FotoModus"},
			"timeout_s": 45.0,
		},
		{
			"name": "fotostand_merken",
			"aktion": "tue",
			"funktion": foto_gezaehlt,
			"erwartung": "Fotostand notiert",
		},
		{
			"name": "foto_knipsen",
			"aktion": "tipp_name",
			"node": "Ausloeser",
			"erwarte": {"bedingung": foto_dazu.bind(1)},
			"timeout_s": 20.0,
		},
		{
			"name": "selfie_an",
			"aktion": "tipp_name",
			"node": "SelfieButton",
			"timeout_s": 20.0,
		},
		{"name": "selfie_einrichten", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "selfie_knipsen",
			"aktion": "tipp_name",
			"node": "Ausloeser",
			"erwarte": {"bedingung": foto_dazu.bind(2)},
			"timeout_s": 20.0,
		},
		{"name": "selfie_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "fotomodus_fertig",
			"aktion": "tipp_name",
			"node": "FertigButton",
			"erwarte": {"weg_klasse": "FotoModus"},
			"timeout_s": 20.0,
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------------------------------------- Werkzeuge


func _control(node_name: String) -> Control:
	return harness.root.find_child(node_name, true, false) as Control


func _phone() -> Node:
	return harness.root.find_child("PhoneShell", true, false)


func _net() -> Node:
	return harness.root.get_node_or_null("/root/Net")


## Kamera-Item ins Inventar legen (Gate PowAngebote.hat_kamera).
func kamera_freischalten() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("inventory") is Dictionary):
				state["inventory"] = {}
			var inventar: Dictionary = state["inventory"]
			if not (inventar.get("items") is Dictionary):
				inventar["items"] = {}
			inventar["items"]["kamera"] = 1
	)
	return int(gs.get_value("inventory.items.kamera", 0)) > 0


## Alle 7 Kacheln da und die Kamera-Kachel OHNE Schloss-Badge?
func pruefe_grid() -> bool:
	var fehlend: Array[String] = []
	for app_id: String in [
		"taxi", "guber", "gooberando", "kamera", "freunde", "goobypal", "instant"
	]:
		var kachel := _control("Kachel%s" % app_id.capitalize())
		if kachel == null or not kachel.is_visible_in_tree():
			fehlend.append(app_id)
	var kamera := _control("KachelKamera")
	var schloss := kamera.find_child("SchlossBadge", true, false) if kamera != null else null
	print("[A6] Grid fehlend=%s kamera_schloss=%s" % [str(fehlend), schloss != null])
	return fehlend.is_empty() and schloss == null


func app_aktiv(app_id: String) -> bool:
	var telefon := _phone()
	return telefon != null and str(telefon.get("aktive_app")) == app_id


func eigener_code_da() -> bool:
	var netz := _net()
	return netz != null and str(netz.get("friend_code")).begins_with("GOOBY-")


## Eigenen Code für den Buddy-Agenten hinterlegen (Datei-Briefkasten).
func code_exportieren() -> bool:
	var netz := _net()
	if netz == null:
		return false
	var code := str(netz.get("friend_code"))
	if not code.begins_with("GOOBY-"):
		return false
	var datei := FileAccess.open("%s/player_code_phone.txt" % BUDDY_DIR, FileAccess.WRITE)
	if datei == null:
		return false
	datei.store_string(code)
	datei.flush()
	print("[A6] Eigener Code exportiert: %s" % code)
	return true


func anfrage_da() -> bool:
	var netz := _net()
	if netz == null:
		return false
	var freunde_service: Variant = netz.get("friends")
	if freunde_service == null:
		return false
	var anfragen: Variant = freunde_service.get("requests")
	return anfragen is Array and not (anfragen as Array).is_empty()


func freund_da() -> bool:
	var netz := _net()
	if netz == null:
		return false
	var freunde_service: Variant = netz.get("friends")
	if freunde_service == null:
		return false
	var freunde: Variant = freunde_service.get("friends")
	return freunde is Array and not (freunde as Array).is_empty()


## Startpunkt der Gesten: linker Innenrand des Geräts (auf dem AcCard-
## Panel selbst, unter keinem Kind-Control) auf halber Höhe.
func geraet_links() -> Vector2:
	var geraet := _control("Geraet")
	if geraet == null:
		return harness.root.get_visible_rect().size * 0.5
	var rect := geraet.get_global_rect()
	return Vector2(rect.position.x + 9.0, rect.get_center().y)


func geraet_links_ziel() -> Vector2:
	return geraet_links() + Vector2(500.0, 0.0)


func geraet_runter_ziel() -> Vector2:
	return geraet_links() + Vector2(0.0, 420.0)


func foto_gezaehlt() -> bool:
	_fotos_vorher = _foto_anzahl()
	return _fotos_vorher >= 0


func foto_dazu(anzahl: int) -> bool:
	return _foto_anzahl() >= _fotos_vorher + anzahl


func _foto_anzahl() -> int:
	var ordner := DirAccess.open("user://fotos")
	if ordner == null:
		return 0
	var anzahl := 0
	for datei: String in ordner.get_files():
		if datei.ends_with(".png"):
			anzahl += 1
	return anzahl


## Ziel-Control in seinem ScrollContainer ins Sichtfenster holen.
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

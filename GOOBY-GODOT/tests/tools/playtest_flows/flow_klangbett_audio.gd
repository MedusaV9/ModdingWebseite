extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18/J5 „Jeder Ort ein Klangbett“ (I-33) — Beweis-Flow für das Klangbett-
## System (scripts/audio/klangbett.gd) im ECHTEN Spiel: Onboarding wie ein
## Spieler, dann zeigt ein Audio-Pegel-Dump ([KLANGBETT-PEGEL]-Zeilen in
## lauf.log, Quelle Klangbett.debug_dump) die drei Kernmomente:
##   an    — Wohnzimmer: Kamin+Uhr-Bett läuft (Gain auf Ziel, Duck frei),
##   duck  — Gooby brabbelt (GoobyVoice.sagt) und ein Jingle
##           (Music.play_stinger) drücken das Bett weich auf DUCK_FAKTOR
##           und lassen es gemächlich zurückkommen,
##   aus/wechsel — Reise in die Stadt: Kamin fährt aus, Stadt-Bett fährt an;
##           Sfx-Regler 0 = Bus-Mute (Stumm-Modus), zurückgedreht wieder an.
## Audio läuft headless über den Dummy-Treiber: hörbar ist nichts, aber die
## Player-/Bus-Zustände sind echt — genau die stehen im Dump.
## Aufruf: tools/ci/run_playtest.sh flow_klangbett_audio


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_klangbett())
	return liste


func _schritte_klangbett() -> Array[Dictionary]:
	return [
		# Morgen-Ritual (W18/J1-Overlay-Sequenz) GANZ zu Ende spielen: die
		# Overlays kommen ZEITVERSETZT (Gooby-Vorlauf → Tagesbonus-Blatt →
		# Coachmark → Guide-Karte) — die kurzen falls_da-Fenster der Basis-
		# Onboarding-Schritte verpassen sie gern; hier mit Geduld nachtippen,
		# sonst liegt später eine modale Karte über dem HUD (Reise-Knopf).
		{
			"name": "tagesbonus_spaeter_abholen",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 75.0,
			"pflicht": false,
		},
		{
			"name": "coachmark_spaeter_wegtippen",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{
			"name": "guide_tour_wegtippen",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 45.0,
			"pflicht": false,
		},
		# Begrüßungs-Gebrabbel/Jingles ausklingen lassen: erst wenn der Duck
		# wieder frei ist, ist der Ruhezustand für die Messungen da.
		{
			"name": "bett_einfahren_lassen",
			"aktion": "warte_bis",
			"bedingung": duck_wieder_frei,
			"timeout_s": 90.0,
		},
		{
			"name": "pegel_wohnzimmer_bett_an",
			"aktion": "tue",
			"funktion": pruefe_wohnzimmer_bett,
			"erwartung": "Kamin+Uhr-Bett läuft im Wohnzimmer (Duck frei)",
		},
		# Duck-Quelle 1: Gooby brabbelt (echter Produktions-Hook in
		# GoobyVoice._babble) — das Bett sackt binnen DUCK_ZU_S auf 0,25.
		{
			"name": "gooby_brabbelt",
			"aktion": "tue",
			"funktion": gooby_spricht,
			"erwartung": "GoobyVoice gefunden und sagt() gestartet",
		},
		{"name": "duck_absacken_lassen", "aktion": "warte", "sekunden": 0.4},
		{
			"name": "pegel_gebrabbel_duck",
			"aktion": "tue",
			"funktion": pruefe_duck_unten.bind("gebrabbel_duck_unten"),
			"erwartung": "Bett unter Gebrabbel weich geduckt (< 0,5)",
		},
		# Gooby führt im Heim auch SELBSTGESPRÄCHE (GoobyReactions-Idle alle
		# 18–35 s) — die ducken korrekt mit. Für eine saubere Release-Messung
		# alle Stimmen deterministisch verstummen (sagt("") bricht ab, die
		# Produktions-Semantik „neuer Aufruf ersetzt den alten“).
		{
			"name": "gooby_verstummt",
			"aktion": "tue",
			"funktion": alle_stimmen_verstummen,
			"erwartung": "Alle GoobyVoice-Stimmen abgebrochen",
		},
		{
			"name": "gebrabbel_erholt_sich",
			"aktion": "warte_bis",
			"bedingung": duck_wieder_frei,
			"timeout_s": 60.0,
		},
		{
			"name": "pegel_gebrabbel_zurueck",
			"aktion": "tue",
			"funktion": pruefe_duck_frei.bind("gebrabbel_duck_zurueck"),
			"erwartung": "Bett nach dem Satz wieder frei",
		},
		# Duck-Quelle 2: Jingle (echter Produktions-Hook in
		# MusicDirector.play_stinger) — gleiche Kurve, Halt = Länge + Nachhall.
		{
			"name": "jingle_spielt",
			"aktion": "tue",
			"funktion": jingle_starten,
			"erwartung": "Music.play_stinger gestartet",
		},
		{"name": "jingle_absacken_lassen", "aktion": "warte", "sekunden": 0.4},
		{
			"name": "pegel_jingle_duck",
			"aktion": "tue",
			"funktion": pruefe_duck_unten.bind("jingle_duck_unten"),
			"erwartung": "Bett unterm Jingle weich geduckt (< 0,5)",
		},
		# Timeout großzügig: dazwischen darf Gooby ruhig nochmal plappern —
		# entscheidend ist, dass der Duck DANACH wieder voll freikommt.
		{
			"name": "jingle_erholt_sich",
			"aktion": "warte_bis",
			"bedingung": duck_wieder_frei,
			"timeout_s": 60.0,
		},
		{
			"name": "pegel_jingle_zurueck",
			"aktion": "tue",
			"funktion": pruefe_duck_frei.bind("jingle_duck_zurueck"),
			"erwartung": "Bett nach dem Jingle wieder frei",
		},
		# Die Guide-Tour-Karte („Schritt 1/9“) taucht zeitversetzt NACH der
		# Willkommens-Sequenz wieder auf und läge sonst modal über dem HUD —
		# vor der Reise sicherheitshalber nochmal wegtippen (wie ein Spieler).
		{
			"name": "guide_tour_nochmal_beenden",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 6.0,
			"pflicht": false,
		},
		# Ortswechsel: Router-Hook fährt Kamin aus und das Stadt-Bett an.
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		# Auf den fertigen Fade WARTEN statt Sekunden zu raten: unter
		# llvmpipe-Volllast (Stadt-Szene) laufen die Frames zäh und der
		# 2,5-s-Bett-Fade braucht real spürbar länger.
		{
			"name": "stadt_bett_einfahren",
			"aktion": "warte_bis",
			"bedingung": stadt_bett_oben,
			"timeout_s": 45.0,
		},
		{
			"name": "pegel_stadt_bett_gewechselt",
			"aktion": "tue",
			"funktion": pruefe_stadt_bett,
			"erwartung": "Kamin aus, Stadt-Bett an",
		},
		# Stumm-Modus: Sfx-Regler 0 → Bus-Mute (Betten hängen am Sfx-Bus),
		# zurückgedreht ist der Bus wieder hörbar.
		{
			"name": "pegel_stumm_modus",
			"aktion": "tue",
			"funktion": pruefe_stumm_modus,
			"erwartung": "Sfx-Regler 0 mutet den Bus, zurückdrehen entmutet",
		},
	]


# ── Pegel-Dump + Prüf-Bausteine ──────────────────────────────────────────────


func _bett() -> Klangbett:
	return harness.root.get_node_or_null("/root/Klangbett") as Klangbett


## Zustands-Foto des Klangbetts als [KLANGBETT-PEGEL]-Zeile in lauf.log.
func _dump(label: String) -> Dictionary:
	var bett := _bett()
	if bett == null:
		print("[KLANGBETT-PEGEL] %s KEIN /root/Klangbett" % label)
		return {}
	var dump := bett.debug_dump()
	print("[KLANGBETT-PEGEL] %s %s" % [label, JSON.stringify(dump)])
	return dump


func duck_wieder_frei() -> bool:
	var bett := _bett()
	return bett != null and bett.duck_faktor() >= 0.999


## Stadt-Bett fertig eingefahren: Stadt-Ebene auf Ziel-Gain, Kamin still.
func stadt_bett_oben() -> bool:
	var bett := _bett()
	if bett == null or bett.ziel_ort() != "city":
		return false
	var ebenen: Dictionary = bett.debug_dump().get("ebenen", {})
	if not (ebenen.has("stadt") and ebenen.has("kamin")):
		return false
	var stadt: Dictionary = ebenen["stadt"]
	var kamin: Dictionary = ebenen["kamin"]
	return float(stadt["ist"]) >= 0.8 and not bool(kamin["spielt"])


## Alle GoobyVoice-Stimmen abbrechen (sagt("") ersetzt das laufende
## Gebrabbel durch nichts) — deterministischer Ruhe-Start für die Messung.
func alle_stimmen_verstummen() -> bool:
	var gefunden := false
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is GoobyVoice:
			gefunden = true
			(aktuell as GoobyVoice).sagt("")
		for kind in aktuell.get_children():
			stapel.append(kind)
	return gefunden


func pruefe_wohnzimmer_bett() -> bool:
	var dump := _dump("wohnzimmer_bett_an")
	if dump.is_empty() or str(dump.get("ziel_ort", "")) != "home/living":
		return false
	var ebenen: Dictionary = dump.get("ebenen", {})
	if not (ebenen.has("kamin") and ebenen.has("uhr")):
		return false
	var kamin: Dictionary = ebenen["kamin"]
	var uhr: Dictionary = ebenen["uhr"]
	return (
		bool(kamin["spielt"])
		and float(kamin["ist"]) >= 0.8
		and bool(uhr["spielt"])
		and float(dump.get("duck", 0.0)) >= 0.999
	)


func pruefe_duck_unten(label: String) -> bool:
	var dump := _dump(label)
	return not dump.is_empty() and float(dump.get("duck", 1.0)) <= 0.5


func pruefe_duck_frei(label: String) -> bool:
	var dump := _dump(label)
	return not dump.is_empty() and float(dump.get("duck", 0.0)) >= 0.999


func gooby_spricht() -> bool:
	var stimme := _finde_gooby_voice(harness.root)
	if stimme == null:
		return false
	stimme.sagt("Oooh, hoerst du das leise Klangbett? Es duckt sich jetzt gaaanz weich weg!")
	return true


func jingle_starten() -> bool:
	var musik := harness.root.get_node_or_null("/root/Music")
	if musik == null or not musik.has_method("play_stinger"):
		return false
	musik.play_stinger("stinger-levelup")
	return true


func pruefe_stadt_bett() -> bool:
	var dump := _dump("stadt_bett_gewechselt")
	if dump.is_empty() or str(dump.get("ziel_ort", "")) != "city":
		return false
	var ebenen: Dictionary = dump.get("ebenen", {})
	if not (ebenen.has("stadt") and ebenen.has("kamin")):
		return false
	var stadt: Dictionary = ebenen["stadt"]
	var kamin: Dictionary = ebenen["kamin"]
	return bool(stadt["spielt"]) and float(stadt["ist"]) >= 0.8 and not bool(kamin["spielt"])


func pruefe_stumm_modus() -> bool:
	var audio := harness.root.get_node_or_null("/root/Audio")
	var einstellungen := harness.root.get_node_or_null("/root/AppSettings")
	if audio == null or einstellungen == null:
		return false
	var vorher := float(einstellungen.get_setting("audio.sfx", 1.0))
	audio.apply_volume("Sfx", 0.0)
	var stumm := _dump("stumm_sfx_bus")
	audio.apply_volume("Sfx", maxf(vorher, 0.05))
	var zurueck := _dump("stumm_wieder_hoerbar")
	return bool(stumm.get("sfx_bus_mute", false)) and not bool(zurueck.get("sfx_bus_mute", true))


func _finde_gooby_voice(wurzel: Node) -> GoobyVoice:
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is GoobyVoice:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null

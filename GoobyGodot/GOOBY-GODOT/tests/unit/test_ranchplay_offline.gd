extends TestCase
## RANCH-2 — Tagesrhythmus + Offline-Verfall (RanchOffline): Nacht-Fenster,
## Aufstellungs-Hinweis, Phasenwechsel-Mathe und simulate_offline (Weide-Cap
## 480 min bei 0.3×, Stall-Nächte voll, Bindungs-Verfall mit Karenz,
## Warn-Events, Determinismus). Zeit ist überall gepinnt (offsetMin 0).

const Offline := preload("res://scripts/ranch/gameplay/ranch_offline.gd")
const Care := preload("res://scripts/ranch/gameplay/horse_care.gd")
const Slices := preload("res://scripts/ranch/data/ranch_play_slices.gd")

## 12:00 UTC an Tag 3 — mitten am Tag, weit weg von Phasengrenzen.
const MITTAG_MS := (3 * 24 + 12) * 3600 * 1000


func _tiere_mit(pferd: Dictionary) -> Dictionary:
	var tiere := Slices.default_tiere()
	tiere["pferde"]["p1"] = pferd
	return tiere


func _pferd(werte: Dictionary, bindung := 50.0, pflege_at := 0) -> Dictionary:
	var pferd := Slices.neues_pferd("Testpferd", "braun")
	pferd["werte"] = werte
	pferd["bindung"] = bindung
	pferd["letztePflegeAt"] = pflege_at
	return pferd


func test_nacht_fenster_und_wohin() -> void:
	assert_true(Offline.ist_nacht(21.0), "21:00 = Stallzeit")
	assert_true(Offline.ist_nacht(23.5))
	assert_true(Offline.ist_nacht(0.0))
	assert_true(Offline.ist_nacht(6.99))
	assert_false(Offline.ist_nacht(7.0), "07:00 = Weide")
	assert_false(Offline.ist_nacht(12.0))
	assert_false(Offline.ist_nacht(20.99))
	assert_true(Offline.ist_nacht(24.0 + 3.0), "Stunden > 24 werden gefaltet")
	assert_eq(Offline.wohin(23.0), "stall")
	assert_eq(Offline.wohin(10.0), "weide")


func test_stunde_lokal_und_phasenwechsel() -> void:
	assert_almost(Offline.stunde_lokal(MITTAG_MS), 12.0)
	assert_almost(Offline.stunde_lokal(MITTAG_MS, 120), 14.0, 1e-6, "Offset verschiebt")
	assert_eq(Offline.ms_bis_phasenwechsel(MITTAG_MS), 9 * 3600000, "12:00 → 21:00")
	var um_22 := MITTAG_MS + 10 * 3600000
	assert_eq(Offline.ms_bis_phasenwechsel(um_22), 9 * 3600000, "22:00 → 07:00")


func test_erster_lauf_setzt_nur_den_stempel() -> void:
	var tiere := _tiere_mit(_pferd({"hunger": 80.0, "durst": 80.0, "sauberkeit": 80.0}))
	var res := Offline.simulate_offline(tiere, MITTAG_MS)
	assert_eq(int(res["tiere"]["lastTickAt"]), MITTAG_MS)
	assert_almost(float(res["tiere"]["pferde"]["p1"]["werte"]["hunger"]), 80.0)
	assert_eq((res["events"] as Array).size(), 0)
	assert_eq(int(tiere["lastTickAt"]), 0, "Eingabe bleibt unberührt (pure)")


func test_tag_segment_verfaellt_mit_offline_rate() -> void:
	var tiere := _tiere_mit(_pferd({"hunger": 80.0, "durst": 80.0, "sauberkeit": 80.0}))
	tiere["lastTickAt"] = MITTAG_MS
	var res := Offline.simulate_offline(tiere, MITTAG_MS + 60 * 60000)
	var werte: Dictionary = res["tiere"]["pferde"]["p1"]["werte"]
	assert_almost(float(werte["hunger"]), 80.0 - 0.25 * 60.0 * 0.3, 1e-4, "0.3× Weide-Rate")
	assert_almost(float(werte["durst"]), 80.0 - 0.4 * 60.0 * 0.3, 1e-4)


func test_weide_cap_stoppt_nach_480_minuten() -> void:
	var tiere := _tiere_mit(_pferd({"hunger": 90.0, "durst": 90.0, "sauberkeit": 90.0}))
	# 07:00 bis 21:00 = 840 Tages-Minuten — nur 480 davon zählen.
	var start := 3 * 86400000 + 7 * 3600000
	tiere["lastTickAt"] = start
	var res := Offline.simulate_offline(tiere, start + 840 * 60000)
	var werte: Dictionary = res["tiere"]["pferde"]["p1"]["werte"]
	assert_almost(float(werte["hunger"]), 90.0 - 0.25 * 480.0 * 0.3, 1e-4, "Cap greift")


func test_nacht_segment_laeuft_voll_und_verschmutzt_den_stall() -> void:
	var tiere := _tiere_mit(_pferd({"hunger": 90.0, "durst": 90.0, "sauberkeit": 90.0}))
	# 22:00 bis 02:00 = 4 reine Stall-Stunden.
	var start := 3 * 86400000 + 22 * 3600000
	tiere["lastTickAt"] = start
	var res := Offline.simulate_offline(tiere, start + 4 * 3600000)
	var werte: Dictionary = res["tiere"]["pferde"]["p1"]["werte"]
	assert_almost(float(werte["hunger"]), 90.0 - 0.08 * 240.0, 1e-4, "Schlaf-Rate voll")
	assert_almost(
		float(res["tiere"]["stall"]["sauberkeit"]), 100.0 - 0.05 * 240.0, 1e-4, "Stall-Tick"
	)


func test_bindung_verfaellt_erst_nach_karenz() -> void:
	var frisch := _tiere_mit(
		_pferd({"hunger": 90.0, "durst": 90.0, "sauberkeit": 90.0}, 60.0, MITTAG_MS)
	)
	frisch["lastTickAt"] = MITTAG_MS
	var kurz := Offline.simulate_offline(frisch, MITTAG_MS + 24 * 3600000)
	assert_almost(float(kurz["tiere"]["pferde"]["p1"]["bindung"]), 60.0, 1e-6, "24 h < 48 h Karenz")
	var lange := Offline.simulate_offline(frisch, MITTAG_MS + 72 * 3600000)
	assert_almost(
		float(lange["tiere"]["pferde"]["p1"]["bindung"]),
		60.0 - 1.0,
		1e-4,
		"72 h = 24 Straf-Stunden = 1 Punkt"
	)


func test_events_melden_neu_abgerutschte_werte() -> void:
	var tiere := _tiere_mit(_pferd({"hunger": 26.0, "durst": 90.0, "sauberkeit": 20.0}))
	tiere["lastTickAt"] = MITTAG_MS
	var res := Offline.simulate_offline(tiere, MITTAG_MS + 3 * 3600000)
	var events: Array = res["events"]
	assert_true(events.has("hungrig:p1"), "frisch unter 25 gerutscht → Event")
	assert_false(events.has("stinkig:p1"), "schon niedrige Werte bleiben still")
	assert_false(events.has("durstig:p1"))


func test_stall_dreckig_event() -> void:
	var tiere := _tiere_mit(_pferd({"hunger": 90.0, "durst": 90.0, "sauberkeit": 90.0}))
	tiere["stall"]["sauberkeit"] = 41.0
	var start := 3 * 86400000 + 21 * 3600000
	tiere["lastTickAt"] = start
	var res := Offline.simulate_offline(tiere, start + 60 * 60000)
	assert_true((res["events"] as Array).has("stallDreckig"), "41 → unter 40 gerutscht")


func test_elapsed_cap_und_determinismus() -> void:
	var tiere := _tiere_mit(_pferd({"hunger": 100.0, "durst": 100.0, "sauberkeit": 100.0}))
	tiere["lastTickAt"] = MITTAG_MS
	var nach_7t := Offline.simulate_offline(tiere, MITTAG_MS + 7 * 86400000)
	var nach_30t := Offline.simulate_offline(tiere, MITTAG_MS + 30 * 86400000)
	assert_almost(
		float(nach_30t["tiere"]["pferde"]["p1"]["werte"]["hunger"]),
		float(nach_7t["tiere"]["pferde"]["p1"]["werte"]["hunger"]),
		1e-6,
		"älter als 7 Tage rechnet nicht weiter (identisches 7-Tage-Fenster ab 12:00)"
	)
	var a := Offline.simulate_offline(tiere, MITTAG_MS + 49 * 3600000)
	var b := Offline.simulate_offline(tiere, MITTAG_MS + 49 * 3600000)
	assert_eq(str(a), str(b), "gleiche Eingabe → identisches Ergebnis")


func test_rueckwaerts_laufende_uhr_ist_harmlos() -> void:
	var tiere := _tiere_mit(_pferd({"hunger": 80.0, "durst": 80.0, "sauberkeit": 80.0}))
	tiere["lastTickAt"] = MITTAG_MS
	var res := Offline.simulate_offline(tiere, MITTAG_MS - 3600000)
	assert_almost(float(res["tiere"]["pferde"]["p1"]["werte"]["hunger"]), 80.0)
	assert_eq(int(res["tiere"]["lastTickAt"]), MITTAG_MS - 3600000, "Stempel folgt der Uhr")

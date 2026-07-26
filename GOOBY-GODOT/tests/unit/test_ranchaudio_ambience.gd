extends TestCase
## RW-8: Ambience-Mix der Ranch — Ziel-Gains je Zone/Wetter/Tageszeit (PURE),
## Lautstärke nach Entfernung, und der Node fährt Wechsel mit weichen Fades
## statt hart umzuschalten.

const SONNE := {"typ": "sonne", "intensitaet": 0.5, "wind": 0.3}
const REGEN := {"typ": "regen", "intensitaet": 0.7, "wind": 0.5}
const GEWITTER := {"typ": "gewitter", "intensitaet": 0.9, "wind": 0.8}


func test_sonniger_tag_voegel_statt_grillen() -> void:
	var mix := RanchAudio.ambience_ziel("hof", SONNE, 12.0)
	assert_true(float(mix["voegel"]) > 0.0, "Tagsüber singen Vögel.")
	assert_eq(float(mix["grillen"]), 0.0, "Keine Grillen am Mittag.")
	assert_eq(float(mix["regen"]), 0.0, "Kein Regen bei Sonne.")
	assert_eq(float(mix["gewitter"]), 0.0)
	assert_true(float(mix["wind"]) > 0.0, "Etwas Wind liegt immer in der Luft.")


func test_nachts_grillen_statt_voegel() -> void:
	var mix := RanchAudio.ambience_ziel("hof", SONNE, 22.0)
	assert_true(float(mix["grillen"]) > 0.0, "Nachts zirpen Grillen.")
	assert_eq(float(mix["voegel"]), 0.0, "Vögel schlafen nachts.")


func test_wetterwechsel_aendert_den_mix() -> void:
	var sonne := RanchAudio.ambience_ziel("hof", SONNE, 12.0)
	var regen := RanchAudio.ambience_ziel("hof", REGEN, 12.0)
	var gewitter := RanchAudio.ambience_ziel("hof", GEWITTER, 12.0)
	assert_true(float(regen["regen"]) > 0.0, "Regen-Ebene an bei Regen.")
	assert_eq(float(regen["voegel"]), 0.0, "Vögel verstummen im Regen.")
	assert_true(float(gewitter["gewitter"]) > 0.0, "Donner-Ebene nur bei Gewitter.")
	assert_eq(float(sonne["gewitter"]), 0.0)
	assert_true(float(gewitter["wind"]) > float(sonne["wind"]), "Sturmwind lauter als Brise.")
	var regennacht := RanchAudio.ambience_ziel("hof", REGEN, 23.0)
	assert_eq(float(regennacht["grillen"]), 0.0, "Regen verstummt auch die Grillen.")


func test_zonenwechsel_aendert_den_mix() -> void:
	var hof := RanchAudio.ambience_ziel("hof", SONNE, 12.0)
	var bach := RanchAudio.ambience_ziel("bachlauf", SONNE, 12.0)
	var see := RanchAudio.ambience_ziel("see", SONNE, 12.0)
	var wald := RanchAudio.ambience_ziel("waeldchen", SONNE, 12.0)
	var kamm := RanchAudio.ambience_ziel("huegelkamm", SONNE, 12.0)
	assert_eq(float(hof["bach"]), 0.0, "Kein Bach auf dem Hof.")
	assert_true(float(bach["bach"]) > float(see["bach"]), "Am Bach am lautesten.")
	assert_true(float(see["bach"]) > 0.0, "Am See noch hörbar.")
	assert_true(float(wald["voegel"]) > float(hof["voegel"]), "Wald voller Vögel.")
	assert_true(float(kamm["wind"]) > float(hof["wind"]), "Auf dem Kamm pfeift der Wind.")


func test_lautstaerke_nach_entfernung() -> void:
	assert_almost(RanchAudio.entfernung_gain(0.0, 60.0), 1.0, 1e-4, "Direkt dran = voll.")
	assert_almost(RanchAudio.entfernung_gain(30.0, 60.0), 0.5, 1e-4, "Halbe Strecke = halb.")
	assert_almost(RanchAudio.entfernung_gain(90.0, 60.0), 0.0, 1e-4, "Außer Hörweite = still.")
	var nah := RanchAudio.ambience_ziel("hof", SONNE, 12.0, 10.0)
	var fern := RanchAudio.ambience_ziel("hof", SONNE, 12.0, 50.0)
	var weg := RanchAudio.ambience_ziel("hof", SONNE, 12.0, 200.0)
	assert_true(float(nah["bach"]) > float(fern["bach"]), "Näher am Wasser = lauter.")
	assert_true(float(fern["bach"]) > 0.0)
	assert_eq(float(weg["bach"]), 0.0, "Weit weg = still.")


func test_alle_gains_zwischen_0_und_1() -> void:
	for zone: String in ["hof", "bachlauf", "see", "waeldchen", "huegelkamm", "weidetal"]:
		for wetter: Dictionary in [SONNE, REGEN, GEWITTER, {"typ": "nebel", "wind": 1.0}]:
			for stunde: float in [3.0, 12.0, 21.0]:
				var mix := RanchAudio.ambience_ziel(zone, wetter, stunde)
				for ebene: String in mix:
					var gain := float(mix[ebene])
					assert_true(
						gain >= 0.0 and gain <= 1.0,
						"Gain 0..1: %s/%s/%s" % [zone, wetter["typ"], ebene]
					)


func test_node_faehrt_wechsel_mit_weichen_fades() -> void:
	var audio := RanchAudio.new()
	audio.stunde_override = 12.0
	tree.root.add_child(audio)
	await wait_frames(1)
	audio.ambience_anwenden("hof", SONNE, 12.0)
	await wait_frames(2)
	var wind: AudioStreamPlayer = audio._ebenen_player.get("wind")
	assert_true(wind != null and wind.playing, "Wind-Loop läuft.")
	assert_true(wind.volume_db < -20.0, "Fade startet leise (weicher Übergang, kein Hart-Schnitt).")
	var voegel: AudioStreamPlayer = audio._ebenen_player.get("voegel")
	assert_true(voegel != null and voegel.playing, "Vogel-Loop läuft am Tag.")
	assert_false(audio._ebenen_player.has("gewitter"), "Keine Donner-Ebene bei Sonne.")
	audio.ambience_anwenden("hof", GEWITTER, 12.0)
	await wait_frames(2)
	var gewitter: AudioStreamPlayer = audio._ebenen_player.get("gewitter")
	assert_true(gewitter != null and gewitter.playing, "Wetterwechsel startet Donner-Ebene.")
	assert_eq(float(audio._ebenen_ziel["voegel"]), 0.0, "Vögel werden ausgeblendet.")
	var lauter: bool = await wait_until(func() -> bool: return gewitter.volume_db > -30.0, 4000)
	assert_true(lauter, "Donner blendet hörbar ein.")
	audio.ambience_stop()
	assert_eq(float(audio._ebenen_ziel["wind"]), 0.0, "Stop fährt alle Ebenen auf 0.")
	tree.root.remove_child(audio)
	audio.free()


func test_publikum_nach_entfernung() -> void:
	var audio := RanchAudio.new()
	tree.root.add_child(audio)
	await wait_frames(1)
	audio.publikum_loop(true, 0.0)
	await wait_frames(1)
	var menge: AudioStreamPlayer = audio._ebenen_player.get("menge")
	assert_true(menge != null and menge.playing, "Publikums-Gemurmel läuft.")
	audio.publikum_loop(true, 100.0)
	assert_eq(float(audio._ebenen_ziel["menge"]), 0.0, "Außer Hörweite = still.")
	audio.publikum_loop(false)
	tree.root.remove_child(audio)
	audio.free()

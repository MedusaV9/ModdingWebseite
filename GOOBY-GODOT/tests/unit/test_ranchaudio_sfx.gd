extends TestCase
## RW-8: Ranch-SFX-Verdrahtung — alle 23 DLC-Sounds sind in der SfxMap
## (deutsche Ids, Dateien existieren), Untergrund→Hufschlag-Zuordnung ist
## vollständig und fällt defensiv auf Gras zurück, Reaktions- und Pflege-
## Zuordnungen liefern nur bekannte Ids.

const SFX_ORDNER := "res://assets/ranch/audio/sfx"


func test_alle_23_ranch_ids_gemappt_und_dateien_da() -> void:
	assert_eq(SfxMap.RANCH_REQUIRED_IDS.size(), 23, "23 Pflicht-Ids (alle DLC-Dateien).")
	for id: String in SfxMap.RANCH_REQUIRED_IDS:
		assert_true(SfxMap.SOUNDS.has(id), "Ranch-Id fehlt in der Map: %s" % id)
		var pfad := SfxMap.path(id)
		assert_true(pfad.begins_with(SFX_ORDNER), "Ranch-Id zeigt in den DLC-Ordner: %s" % id)
		assert_true(ResourceLoader.exists(pfad), "Sound-Datei fehlt: %s (%s)" % [id, pfad])


## Jede OGG-Datei unter assets/ranch/audio/sfx ist über GENAU eine Id
## erreichbar — nichts liegt tot im Projekt.
func test_jede_dlc_datei_hat_eine_id() -> void:
	var gemappt: Dictionary = {}
	for id: String in SfxMap.RANCH_REQUIRED_IDS:
		gemappt[SfxMap.path(id).get_file()] = id
	var dir := DirAccess.open(SFX_ORDNER)
	assert_true(dir != null, "DLC-SFX-Ordner existiert.")
	if dir == null:
		return
	for datei in dir.get_files():
		if datei.ends_with(".ogg"):
			assert_true(gemappt.has(datei), "Datei ohne SfxMap-Id: %s" % datei)


func test_untergrund_hufschlag_zuordnung() -> void:
	assert_eq(RanchAudio.huf_id_fuer("gras"), "ranch_huf_gras")
	assert_eq(RanchAudio.huf_id_fuer("wiese"), "ranch_huf_gras")
	assert_eq(RanchAudio.huf_id_fuer("sand"), "ranch_huf_sand")
	assert_eq(RanchAudio.huf_id_fuer("holz"), "ranch_huf_holz")
	assert_eq(RanchAudio.huf_id_fuer("stein"), "ranch_huf_stein")
	assert_eq(RanchAudio.huf_id_fuer("matsch"), "ranch_huf_gras", "Matsch klingt weich.")
	assert_eq(
		RanchAudio.huf_id_fuer("lava"), "ranch_huf_gras", "Unbekannter Boden → Gras-Fallback."
	)


## Die Untergrund-Ids von RW-2 (ride_feel.UNTERGRUND) sind alle abgedeckt —
## die Anbindung bleibt defensiv, aber vollständig.
func test_ride_feel_untergruende_abgedeckt() -> void:
	for untergrund: String in RanchRideFeel.UNTERGRUND.keys():
		var id := RanchAudio.huf_id_fuer(untergrund)
		assert_true(SfxMap.SOUNDS.has(id), "Untergrund %s → gültige Id %s" % [untergrund, id])


func test_huf_loops_je_gangart() -> void:
	assert_eq(RanchAudio.huf_loop_id_fuer("trab"), "ranch_huf_trab")
	assert_eq(RanchAudio.huf_loop_id_fuer("galopp"), "ranch_huf_galopp")
	assert_eq(RanchAudio.huf_loop_id_fuer("schritt"), "", "Schritt nimmt Einzelschläge.")
	assert_eq(RanchAudio.huf_loop_id_fuer("stand"), "")


func test_reaktions_zuordnung() -> void:
	for art: String in ["begruessung", "freude", "scheu", "bindung", "erschoepfung"]:
		var id := RanchAudio.reaktion_id(art)
		assert_true(SfxMap.SOUNDS.has(id), "Reaktion %s → gültige Id %s" % [art, id])
	assert_true(
		RanchAudio.reaktion_id("begruessung").begins_with("ranch_wiehern"),
		"Begrüßung wiehert (sozial, laut)."
	)
	assert_true(
		RanchAudio.reaktion_id("erschoepfung").begins_with("ranch_schnauben"),
		"Erschöpfung schnaubt (körperlich, leise)."
	)
	assert_eq(RanchAudio.reaktion_id("tanzen"), "", "Unbekannte Reaktion bleibt still.")


func test_pflege_zuordnung() -> void:
	for aktion: String in ["buersten", "striegeln", "heu", "futter", "sattel", "aufsteigen"]:
		var id := RanchAudio.pflege_id(aktion)
		assert_true(SfxMap.SOUNDS.has(id), "Pflege %s → gültige Id %s" % [aktion, id])
	assert_eq(RanchAudio.pflege_id("gibtsnicht"), "", "Unbekannte Aktion bleibt still.")


func test_lautstaerken_im_map_kontrakt() -> void:
	for id: String in SfxMap.RANCH_REQUIRED_IDS:
		var db := float(SfxMap.entry(id).get("volume_db", 0.0))
		assert_true(db > -24.0 and db <= 0.0, "volume_db im Kontrakt: %s = %f" % [id, db])

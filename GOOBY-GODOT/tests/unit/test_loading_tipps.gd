extends TestCase
## RW-8: Die Spieltipps der grossen Ladebildschirme — mindestens 25 deutsche
## Tipps mit echtem Nutzwert, EN paritätisch, und die Shuffle-Bag-Rotation
## wiederholt keinen Tipp, bevor alle einmal dran waren (nie derselbe Tipp
## zweimal hintereinander, auch nicht über die Rundengrenze).


func test_mindestens_25_deutsche_tipps() -> void:
	I18nService.reset_cache()
	var de: Array = I18nService.table("de").get(LoadingScreenRules.TIPS_KEY, [])
	assert_true(de.size() >= 25, "Mindestens 25 Tipps (sind %d)." % de.size())
	for tip: Variant in de:
		assert_true(str(tip).length() > 20, "Tipp ist ein echter Satz: %s" % str(tip))


func test_tipps_en_paritaet() -> void:
	I18nService.reset_cache()
	var de: Array = I18nService.table("de").get(LoadingScreenRules.TIPS_KEY, [])
	var en: Array = I18nService.table("en").get(LoadingScreenRules.TIPS_KEY, [])
	assert_eq(en.size(), de.size(), "DE/EN gleich viele Tipps.")
	for tip: Variant in en:
		assert_true(str(tip).length() > 20, "EN-Tipp ist ein echter Satz: %s" % str(tip))


func test_rotation_ohne_wiederholung_innerhalb_der_runde() -> void:
	var anzahl := 28
	var zustand: Dictionary = {}
	for _runde in 6:
		var gesehen: Dictionary = {}
		for _i in anzahl:
			var index := LoadingScreenRules.naechster_tipp_index(anzahl, zustand)
			assert_true(index >= 0 and index < anzahl, "Index im Bereich.")
			assert_false(gesehen.has(index), "Kein Tipp doppelt in einer Runde (%d)." % index)
			gesehen[index] = true
		assert_eq(gesehen.size(), anzahl, "Jeder Tipp genau einmal pro Runde.")


func test_rotation_nie_zweimal_derselbe_hintereinander() -> void:
	var anzahl := 7
	var zustand: Dictionary = {}
	var vorher := -1
	for _i in anzahl * 40:
		var index := LoadingScreenRules.naechster_tipp_index(anzahl, zustand)
		assert_ne(index, vorher, "Nie derselbe Tipp zweimal hintereinander.")
		vorher = index


func test_rotation_randfaelle() -> void:
	var zustand: Dictionary = {}
	assert_eq(LoadingScreenRules.naechster_tipp_index(0, zustand), -1, "Keine Tipps → -1.")
	var einer: Dictionary = {}
	assert_eq(LoadingScreenRules.naechster_tipp_index(1, einer), 0, "Ein Tipp → immer 0.")
	assert_eq(LoadingScreenRules.naechster_tipp_index(1, einer), 0, "Ein Tipp wiederholt 0.")

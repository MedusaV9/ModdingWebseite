extends TestCase
## GOOBY-WELT/STADT — Orts-Architektur-Pläne (EVAL-2026-08 B §2: „Stadtorte
## werden durch übergroße Labels statt Architektur erklärt"): jeder Ort hat
## einen nicht-leeren Plan, jeder Laden trägt Portal + 3D-Logo +
## Schaufenster, alle GLB-Requisiten existieren wirklich und die
## Neonfarben sind gültige Hex-Werte.

const FORMEN: Array[String] = ["box", "zyl", "kugel", "kapsel", "torus", "glb"]


func test_alle_orte_haben_plan() -> void:
	var ids := CityOrtArchitektur.orte_mit_plan()
	assert_true(ids.size() >= 12, "mindestens 12 geplante Orte")
	for id in ids:
		assert_false(CityOrtArchitektur.plan(id).is_empty(), "Plan %s gefüllt" % id)
	assert_true(CityOrtArchitektur.plan("gibtsnicht").is_empty(), "unbekannte Id ⇒ leerer Plan")


func test_laeden_erklaeren_sich_ueber_architektur() -> void:
	for id: String in CityOrtArchitektur.NEON_FARBEN:
		var rollen: Dictionary = {}
		for element: Dictionary in CityOrtArchitektur.plan(id):
			rollen[str(element.get("rolle", ""))] = true
		for rolle: String in ["portal", "logo", "schaufenster"]:
			assert_true(rollen.has(rolle), "%s hat ein %s-Element" % [id, rolle])


func test_neon_farben_sind_gueltig() -> void:
	for id: String in CityOrtArchitektur.NEON_FARBEN:
		var hex := CityOrtArchitektur.neon_farbe(id)
		assert_true(Color.html_is_valid(hex), "Neonfarbe %s (%s) ist gültig" % [hex, id])
	assert_eq(CityOrtArchitektur.neon_farbe("wochenmarkt"), "", "Markt hat keine Neonleiste")
	assert_eq(CityOrtArchitektur.neon_farbe("gibtsnicht"), "", "unbekannte Id ⇒ keine Farbe")


func test_formen_bekannt_und_glbs_existieren() -> void:
	for id in CityOrtArchitektur.orte_mit_plan():
		for element: Dictionary in CityOrtArchitektur.plan(id):
			var form := str(element.get("form", "box"))
			assert_true(form in FORMEN, "%s: bekannte Form statt %s" % [id, form])
			if form == "glb":
				var pfad := CityBau.glb_pfad(str(element["glb"]))
				assert_true(ResourceLoader.exists(pfad), "%s: Asset %s existiert" % [id, pfad])

class_name GoobyeLadenLeben
## J3 „Läden lebendig 2“ — Schaufenster-Bummler für den Goo-und-Bye-Laden,
## ausgelagert (laden_scene.gd steht an der gdlint-1000-Zeilen-Kante):
## 2 OrtLeben-Besucher schlendern an der Ladenfront entlang, solange offen
## ist — deterministisch über den Markttag-Seed, stumm (die Laden-Audio-
## Identität gehört der Kassen-Choreo). Die Wegpunkte bleiben VOR den
## Choreo-Ankern (Regal/Kasse frei), zusätzlich zu Alwin & Co.

## Bummel-Route an der Ladenfront (vor dem Regal, hinter der Straße).
## W18/4-B9 „gekippter Abgangs-Hoppler“: der alte Endpunkt (4.6, 2.3) lag
## im äußersten Kamerarand DIREKT im Tür-Korridor des Kunden-Abgangs
## (KASSE_STOP → TUER_POS) — dort liest der Weitwinkel-Keystone den
## Hoppler als „liegend“ (Ohren horizontal, Hut schwebt) und er kreuzte
## den zahlenden Kunden. Die Route endet jetzt VOR dem Tür-Korridor.
const PUNKTE: Array[Vector3] = [
	Vector3(-3.6, 0.0, 1.8),
	Vector3(-0.8, 0.0, 2.2),
	Vector3(2.6, 0.0, 1.7),
	Vector3(3.2, 0.0, 2.0),
]


## Bummler einhängen (Ladenöffnung); existiert schon einer, bleibt er.
static func starte(szene: Node3D, blick: Vector3, ui: Control, seed_wert: int) -> OrtLeben:
	var bestehend := szene.get_node_or_null("OrtLeben")
	if bestehend is OrtLeben:
		return bestehend
	var leben := OrtLeben.new()
	leben.name = "OrtLeben"
	leben.konfig = {
		"besucher": 2,
		"ort_id": "goobye_laden",
		"punkte": Array(PUNKTE),
		"sprueche": "goobye",
		"blick": blick,
	}
	leben.ui_layer = ui
	leben.seed_override = seed_wert
	leben.stumm = true
	szene.add_child(leben)
	return leben


## Bummler ausklinken (Kassensturz/Feierabend); gibt immer null zurück.
static func stoppe(leben: OrtLeben) -> OrtLeben:
	if leben != null and is_instance_valid(leben):
		leben.queue_free()
	return null

class_name HudButtonOrder
extends RefCounted
## W14/UISCREENS-B — PURE Reihenfolge-Logik für die HUD-Aktions-Buttons
## (H-Doc §1.3 „Daumen-Bogen"/„Cockpit", User: „Anordnung war nie gut").
##
## Prinzip aus der H-Doc: die HAUPT-Aktionen (📱 IGohbie · 🏠 Bauen ·
## ✈ Reise · 🎮 Arcade · 👤 Profil) gehören in die natürliche Ruhelage
## des rechten Daumens; alles Spätere (Album/Garderobe/Möbel/Gestalten/
## Quests) eine Ebene weiter weg. Konkret:
## - HOCHKANT (5+5-Dock, HFlow füllt Zeile 1 = OBEN zuerst):
##   Zweitrangiges oben, Hauptaktionen in der UNTEREN (daumennahen) Zeile.
## - QUERFORMAT (Grid, row-major): bei 2 Spalten wird verschränkt, damit
##   die Hauptaktionen die RECHTE (Kanten-/Daumen-)Spalte bilden; bei
##   1 Spalte Hauptaktionen zuerst (oben, H-Doc-L1-Lesereihenfolge).

## H-Doc-Reihenfolge der Hauptaktionen (Bogen von links nach oben).
const PRIMARY: Array[StringName] = [&"igohbie", &"bau", &"reise", &"arcade", &"profil"]
## Später dazugekommene Aktionen (W6/REST-2) — zweite Reihe.
const SECONDARY: Array[StringName] = [&"album", &"wardrobe", &"ikea", &"gestalten", &"quests"]


## Hochkant-Dock: obere Zeile zweitrangig, untere Zeile = Daumen-Zeile.
static func portrait_order() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(SECONDARY)
	out.append_array(PRIMARY)
	return out


## Cockpit-Spalte(n): `columns` kommt aus der gemessenen Spaltenzahl.
## Row-major-Grid → bei 2 Spalten [sek0, pri0, sek1, pri1, …] legen,
## damit PRIMARY die rechte Außenspalte bildet.
static func landscape_order(columns: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if columns == 2 and PRIMARY.size() == SECONDARY.size():
		for i in PRIMARY.size():
			out.append(SECONDARY[i])
			out.append(PRIMARY[i])
		return out
	out.append_array(PRIMARY)
	out.append_array(SECONDARY)
	return out


## Spalte(n)-Zuordnung für Tests: liefert die ids der Grid-Spalte `col`.
static func column_of(order: Array[StringName], columns: int, col: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in order.size():
		if i % columns == col:
			out.append(order[i])
	return out

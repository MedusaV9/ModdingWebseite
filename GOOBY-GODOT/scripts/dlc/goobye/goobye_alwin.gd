class_name GoobyeAlwin
extends RefCounted
## Alwin-Ausbau des „Goo und Bye“ (G6/GOOBYE-B, Doc §6.3/§7.3) — PURE +
## static: Onkel Alwin kommt täglich um 9 und kauft GENAU 1 Möhre (am
## Sonderwunsch-Tag: ZWEI, s. GoobyeMarkttag.alwin_menge). Hier bekommt er
## Persönlichkeit: 8 Kenner-Sprüche (deterministisch aus dem Tages-Seed,
## dieselbe Wahrheit für UI und Tests) und die ALWIN-STREAK — jeder
## Markttag, an dem er seine Möhre BEKOMMT, zählt; steht er vor leerem
## Regal, beginnt er von vorn (keine Strafe, nur ein Kennerblick). Jeder
## 3. Streak-Tag steckt er Gooby heimlich ein kleines Trinkgeld zu
## („Für den Laden. Nicht für Süßkram.“) — ATOMAR im selben update-Block.

const Economy := preload("res://scripts/logic/economy.gd")

## Anzahl der Spruch-Keys dlc_goobye.alwin.spruch_1..N (Strings-Datei).
const SPRUECHE := 8

## Streak-Belohnung: jeder n-te Tag in Folge bringt das Trinkgeld.
const BELOHNUNG_JEDE := 3
const BELOHNUNG_MUENZEN := 12
const REASON := "gooundbye_alwin"


## Kenner-Spruch des Tages (deterministisch aus dem Tages-Seed).
static func spruch_key(seed_wert: int) -> String:
	return "dlc_goobye.alwin.spruch_%d" % (posmod(seed_wert, SPRUECHE) + 1)


## Alwins Auftritts-Zeile (String-Key): am Sonderwunsch-Tag der
## „ZWEI Möhren?!“-Gag, sonst der Kenner-Spruch des Tages.
static func auftritt_key(seed_wert: int) -> String:
	if GoobyeMarkttag.alwin_menge(seed_wert) >= 2:
		return "dlc_goobye.alwin.sonderwunsch"
	return spruch_key(seed_wert)


## Trinkgeld für einen Streak-Stand (0 = heute keins).
static func belohnung_fuer(streak: int) -> int:
	if streak > 0 and streak % BELOHNUNG_JEDE == 0:
		return BELOHNUNG_MUENZEN
	return 0


## Aktueller Alwin-Stand {streak, best, bedientGesamt} (geheilte Kopie).
static func stand_von(gs: Object) -> Dictionary:
	var stand := {"streak": 0, "best": 0, "bedientGesamt": 0}
	if gs == null:
		return stand
	var raw: Variant = gs.get_value("dlc.goobye.alwin", {})
	if raw is Dictionary:
		for feld: String in stand:
			stand[feld] = maxi(0, int((raw as Dictionary).get(feld, 0)))
	return stand


## Alwins Kassen-Moment verbuchen — EIN update-Block, Trinkgeld inklusive:
## bedient=true → Streak+1 (+Best/+Gesamt, ggf. Münzen auf die Kasse),
## bedient=false → Streak fällt sanft auf 0 (Best bleibt stehen).
## Ergebnis: {streak, best, bedient_gesamt, belohnung}.
static func verbuchen(gs: Object, bedient: bool) -> Dictionary:
	# Dictionary als Rückkanal (die Lambda fängt Referenzen).
	var ergebnis := {"streak": 0, "best": 0, "bedient_gesamt": 0, "belohnung": 0}
	if gs == null:
		return ergebnis
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := GoobyeState.ensure_goobye(state)
			var alwin: Dictionary = goobye["alwin"]
			if bedient:
				alwin["streak"] = int(alwin.get("streak", 0)) + 1
				alwin["best"] = maxi(int(alwin.get("best", 0)), int(alwin["streak"]))
				alwin["bedientGesamt"] = int(alwin.get("bedientGesamt", 0)) + 1
				var belohnung := belohnung_fuer(int(alwin["streak"]))
				if belohnung > 0:
					Economy.award(state["economy"], belohnung, REASON)
				ergebnis["belohnung"] = belohnung
			else:
				alwin["streak"] = 0
			ergebnis["streak"] = int(alwin["streak"])
			ergebnis["best"] = int(alwin.get("best", 0))
			ergebnis["bedient_gesamt"] = int(alwin.get("bedientGesamt", 0))
	)
	gs.notify_slice_changed(GoobyeState.SLICE_ID)
	return ergebnis

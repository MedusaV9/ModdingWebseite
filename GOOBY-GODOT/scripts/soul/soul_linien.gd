class_name SoulLinien
extends RefCounted
## W14/VOICE: 120 neue Text-Lines in Kategorien + Auswahl-Logik. PURE
## Statics — Zufall kommt als roll (0..1) herein, das Anti-Wiederholungs-
## Gedächtnis (letzte GEDAECHTNIS_MAX Lines je Kategorie) als Dictionary
## {kategorie: Array[String]} und wandert als NEUE Map wieder hinaus
## (persistiert im Soul-Slice unter "linien", s. SoulState).
##
## Die Keys leben in strings/{de,en}/soul_lines.json (DE führend,
## paritätisch). Kategorien mit fester Key-Systematik: <prefix><n> mit
## n = 1..anzahl. Die Fütter-Kommentare nutzen die mit W14/FRIDGE
## vereinbarte Schnittstelle fuettern.kommentar.<kategorie>.<n>.

## Anti-Wiederholung: so viele zuletzt gezeigte Keys je Kategorie sperren.
const GEDAECHTNIS_MAX := 5

## Kategorie → {prefix, anzahl}. Gesamtsumme = 120 Lines (Test-Gate).
const KATEGORIEN := {
	# Tageszeit-Grüße (12) — NEUE Varianten zusätzlich zu soul.gruss.*.
	"gruss.morgen": {"prefix": "soul.linie.gruss.morgen.", "anzahl": 3},
	"gruss.mittag": {"prefix": "soul.linie.gruss.mittag.", "anzahl": 2},
	"gruss.nachmittag": {"prefix": "soul.linie.gruss.nachmittag.", "anzahl": 2},
	"gruss.abend": {"prefix": "soul.linie.gruss.abend.", "anzahl": 3},
	"gruss.nacht": {"prefix": "soul.linie.gruss.nacht.", "anzahl": 2},
	# Wetter-Kommentare (10) — auch für Typen, die bisher stumm waren
	# (sonne/wolken/niesel/nebel); begleitet vom Mini-Wetter-FX
	# (GoobyGespraech.wetter_fx).
	"wetter.sonne": {"prefix": "soul.linie.wetter.sonne.", "anzahl": 2},
	"wetter.wolken": {"prefix": "soul.linie.wetter.wolken.", "anzahl": 1},
	"wetter.niesel": {"prefix": "soul.linie.wetter.niesel.", "anzahl": 1},
	"wetter.regen": {"prefix": "soul.linie.wetter.regen.", "anzahl": 1},
	"wetter.gewitter": {"prefix": "soul.linie.wetter.gewitter.", "anzahl": 1},
	"wetter.nebel": {"prefix": "soul.linie.wetter.nebel.", "anzahl": 2},
	"wetter.schnee": {"prefix": "soul.linie.wetter.schnee.", "anzahl": 2},
	# Reaktionen auf W13-Features (40) — Aufrufer: die Feature-Besitzer
	# über SeeleRunner.kommentar(kategorie) (s. Handoff-Requests).
	"w13.ball": {"prefix": "soul.linie.w13.ball.", "anzahl": 6},
	"w13.nougat": {"prefix": "soul.linie.w13.nougat.", "anzahl": 6},
	"w13.gobty": {"prefix": "soul.linie.w13.gobty.", "anzahl": 6},
	"w13.girlande": {"prefix": "soul.linie.w13.girlande.", "anzahl": 4},
	"w13.galaxie": {"prefix": "soul.linie.w13.galaxie.", "anzahl": 4},
	"w13.raumstation": {"prefix": "soul.linie.w13.raumstation.", "anzahl": 6},
	"w13.ranch": {"prefix": "soul.linie.w13.ranch.", "anzahl": 8},
	# Fütter-Kategorie-Sprüche (16) — Schnittstelle für W14/FRIDGE.
	"fuettern.obst": {"prefix": "fuettern.kommentar.obst.", "anzahl": 4},
	"fuettern.gemuese": {"prefix": "fuettern.kommentar.gemuese.", "anzahl": 4},
	"fuettern.suess": {"prefix": "fuettern.kommentar.suess.", "anzahl": 4},
	"fuettern.deftig": {"prefix": "fuettern.kommentar.deftig.", "anzahl": 4},
	# Minispiel-Ergebnis-Reaktionen (12).
	"minispiel.rekord": {"prefix": "soul.linie.minispiel.rekord.", "anzahl": 4},
	"minispiel.knapp": {"prefix": "soul.linie.minispiel.knapp.", "anzahl": 4},
	"minispiel.verloren": {"prefix": "soul.linie.minispiel.verloren.", "anzahl": 4},
	# Selbstgespräche beim Idle-Wandern (15).
	"selbstgespraech": {"prefix": "soul.linie.selbstgespraech.", "anzahl": 15},
	# Sticker-/Erfolgs-Feier-Varianten (10).
	"feier.sticker": {"prefix": "soul.linie.feier.sticker.", "anzahl": 5},
	"feier.erfolg": {"prefix": "soul.linie.feier.erfolg.", "anzahl": 5},
	# „Lange nicht gesehen“-Staffelung (5) — Auswahl über wiedersehen_key.
	"wiedersehen": {"prefix": "soul.linie.wiedersehen.", "anzahl": 5},
}

## Wiedersehen-Staffel: ab dieser Lücke (Stunden) gilt Stufe n (1..5).
const WIEDERSEHEN_STUFEN_H: Array[float] = [6.0, 24.0, 48.0, 168.0, 720.0]

## Anteil des Plauder-Takts, der bei besonderem Wetter dem Wetter gehört.
const PLAUDER_WETTER_ANTEIL := 0.35


## Alle Keys einer Kategorie (leer bei unbekannter Kategorie).
static func keys_of(kategorie: String) -> Array[String]:
	var def: Variant = KATEGORIEN.get(kategorie)
	if not (def is Dictionary):
		return []
	var out: Array[String] = []
	for n in int((def as Dictionary)["anzahl"]):
		out.append("%s%d" % [str((def as Dictionary)["prefix"]), n + 1])
	return out


## Line wählen: deterministisch über roll (0..1), die letzten
## GEDAECHTNIS_MAX gezeigten Keys der Kategorie sind gesperrt. Ist der Pool
## kleiner als die Sperrliste, wird unter den am längsten nicht gezeigten
## gewählt (nie ""). "" nur bei unbekannter Kategorie.
static func waehle(kategorie: String, gedaechtnis: Dictionary, roll: float) -> String:
	var pool := keys_of(kategorie)
	if pool.is_empty():
		return ""
	var zuletzt := _zuletzt(gedaechtnis, kategorie)
	var frei: Array[String] = []
	for key in pool:
		if not zuletzt.has(key):
			frei.append(key)
	if frei.is_empty():
		# Kleiner Pool: der älteste Eintrag des Gedächtnisses wird wieder
		# frei — so bleibt die Reihenfolge maximal gespreizt.
		for key: Variant in zuletzt:
			if pool.has(str(key)):
				return str(key)
		return pool[0]
	return frei[int(clampf(roll, 0.0, 0.999999) * frei.size())]


## Gezeigten Key ins Gedächtnis buchen — gibt eine NEUE Map zurück
## (die alte bleibt unangetastet; pure Logik, testbar).
static func merke(gedaechtnis: Dictionary, kategorie: String, key: String) -> Dictionary:
	var out := gedaechtnis.duplicate(true)
	var zuletzt: Array = _zuletzt(out, kategorie).duplicate()
	zuletzt.erase(key)
	zuletzt.append(key)
	while zuletzt.size() > GEDAECHTNIS_MAX:
		zuletzt.pop_front()
	out[kategorie] = zuletzt
	return out


## Wiedersehen-Staffel (5 Stufen): Besuchslücke → Key ("" unter Stufe 1 —
## normale Tages-Grüße übernehmen dann).
static func wiedersehen_key(gap_ms: int) -> String:
	var hours := float(gap_ms) / 3_600_000.0
	var stufe := 0
	for schwelle in WIEDERSEHEN_STUFEN_H:
		if hours >= schwelle:
			stufe += 1
	if stufe <= 0:
		return ""
	return "soul.linie.wiedersehen.%d" % stufe


## Plauder-Kategorie fürs Idle-Wandern: bei besonderem Wetter kommentiert
## Gooby manchmal das Wetter (sichtbarer Mini-FX), sonst Selbstgespräch.
## Deterministisch über roll; "wolken" gilt als unspektakulär.
static func plauder_kategorie(wetter_typ: String, roll: float) -> String:
	var wetter := "wetter." + wetter_typ
	if wetter_typ != "wolken" and KATEGORIEN.has(wetter) and roll < PLAUDER_WETTER_ANTEIL:
		return wetter
	return "selbstgespraech"


## Gesamtzahl aller Kategorie-Lines (Test-Gate: 120).
static func gesamt_anzahl() -> int:
	var total := 0
	for def: Dictionary in KATEGORIEN.values():
		total += int(def["anzahl"])
	return total


static func _zuletzt(gedaechtnis: Dictionary, kategorie: String) -> Array:
	var raw: Variant = gedaechtnis.get(kategorie)
	return raw if raw is Array else []

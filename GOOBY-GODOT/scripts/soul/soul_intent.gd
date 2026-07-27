class_name SoulIntent
extends RefCounted
## Eigenleben mit ABSICHT (SEELE-2): Gooby tut Dinge, WEIL er etwas will —
## Hunger → zum Kühlschrank (oder zur Küchentür) und dich anschauen;
## Langeweile → Spielzeug holen; müde → Richtung Bett; klamm → Richtung Bad;
## Regen → ans Fenster. Sichtbare Absicht schlägt Zufallsanimation: der
## Runner fragt ZUERST hier an und würfelt nur ohne Bedürfnis ein Idle.
##
## PURE Statics: Stats/Kontext/Cooldowns/Zeit werden hereingereicht.
## Die Texte/Emotionen kommen als "absicht"-Defs aus dem Content-Pack;
## dieser Picker liefert nur {id, ziel_art, ziel, drang}.

## Bedürfnis-Schwellen (§C1-Skala 0..100). Bewusst ÜBER den "low"-Warnungen
## (25), damit die Absicht VOR dem Alarm sichtbar wird — Vorahnung statt
## Sirene.
const SCHWELLE_HUNGER := 35.0
const SCHWELLE_SPASS := 30.0
const SCHWELLE_ENERGIE := 25.0
const SCHWELLE_HYGIENE := 30.0
## Regen-Fensterplatz: schwaches "Bedürfnis", kommt nur ohne echte Not dran.
const REGEN_DRANG := 4.0
## Je Absicht frühestens alle 4 Minuten wieder (In-Memory-Cooldown des
## Aufrufers, wie bei den Idle-Akten — gehört nicht in den Save).
const COOLDOWN_MS := 240_000

## Ziel-Aufloesung je Absicht, in Prioritätsreihenfolge: erstes Ziel, das im
## Raum existiert, gewinnt ("item:<prefix>" | "tuer:<raum>" | "fenster").
const ZIELE := {
	"absicht_hunger": ["item:kitchenFridge", "tuer:kitchen"],
	"absicht_langeweile": ["item:bear", "item:television"],
	"absicht_muede": ["item:bed", "tuer:bedroom"],
	"absicht_dreckig": ["item:bathtub", "tuer:bathroom"],
	"absicht_regen": ["fenster"],
}


## Alle aktuell drängenden Absichten, dringendste zuerst (deterministisch).
## ctx: {"regen": bool, "schlaeft": bool, "vorhanden": {ziel_string: bool}}
## — "vorhanden" sagt je Ziel-Eintrag, ob er in DIESEM Raum auflösbar ist.
static func kandidaten(stats: Dictionary, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if bool(ctx.get("schlaeft", false)):
		return out
	_biete(out, ctx, "absicht_hunger", SCHWELLE_HUNGER - _stat(stats, "hunger"))
	_biete(out, ctx, "absicht_muede", SCHWELLE_ENERGIE - _stat(stats, "energy"))
	_biete(out, ctx, "absicht_dreckig", SCHWELLE_HYGIENE - _stat(stats, "hygiene"))
	_biete(out, ctx, "absicht_langeweile", SCHWELLE_SPASS - _stat(stats, "fun"))
	if bool(ctx.get("regen", false)):
		_biete(out, ctx, "absicht_regen", REGEN_DRANG)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["drang"] > b["drang"])
	return out


## Die EINE Absicht für jetzt ({} = kein Bedürfnis / alles im Cooldown).
static func waehle(
	stats: Dictionary, ctx: Dictionary, cooldowns: Dictionary, now_ms: int
) -> Dictionary:
	for kandidat in kandidaten(stats, ctx):
		if now_ms >= int(cooldowns.get(str(kandidat["id"]), 0)):
			return kandidat
	return {}


static func _biete(out: Array[Dictionary], ctx: Dictionary, id: String, drang: float) -> void:
	if drang <= 0.0:
		return
	var ziel := _ziel_fuer(id, ctx)
	if ziel.is_empty():
		return
	(
		out
		. append(
			{
				"id": id,
				"drang": drang,
				"ziel_art": str(ziel["art"]),
				"ziel": str(ziel["wert"]),
			}
		)
	)


## Erstes im Raum auflösbares Ziel der Absicht ({} = keins da → keine
## Absicht; ein Wollen ohne sichtbares Wohin wirkt kaputt, nicht beseelt).
static func _ziel_fuer(id: String, ctx: Dictionary) -> Dictionary:
	var vorhanden: Dictionary = ctx.get("vorhanden", {})
	for eintrag: String in ZIELE.get(id, []):
		if eintrag == "fenster" or bool(vorhanden.get(eintrag, false)):
			var teile := eintrag.split(":")
			return {"art": teile[0], "wert": teile[1] if teile.size() > 1 else ""}
	return {}


static func _stat(stats: Dictionary, key: String) -> float:
	var value: Variant = stats.get(key)
	if value is int or value is float:
		return float(value)
	return 100.0

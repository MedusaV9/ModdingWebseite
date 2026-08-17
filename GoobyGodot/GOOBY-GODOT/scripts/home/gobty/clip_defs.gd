class_name GobtyClipDefs
extends RefCounted
## GOB.TY-Programmheft (W13C/GOBTY, Doc H §6.2 + User-Wunsch „witzige
## Videos zwischen Goobys"): die 5 Puppet-Clips als PURE, datengetriebene
## Sequenzen — KEINE neuen GLB-Clips, alles läuft über vorhandene Rig-Clips,
## Emotionen und Tween-Gags (fx), die der GobtyTvStage inszeniert.
##
## Clip-Schema:
##   {id, titel_key, dauer_s, schritte: [Schritt...]}
## Schritt-Schema (Schritte sind nach `t` aufsteigend sortiert, t in s):
##   t             — Startzeit im Clip
##   sprecher      — 0/1 = handelnder Mini-Gooby, -1 = keiner
##   emotion       — Rig-Emotion des Sprechers ("" = unverändert)
##   clip          — Rig-Clip des Sprechers ("" = unverändert)
##   banner_key    — Bauchbinden-Text (I18n-Key; "" = Banner bleibt)
##   banner        — "schlagzeile" = rotierende News-Schlagzeile (Player
##                   liefert den Key), sonst ""
##   slot          — Schlagzeilen-Slot innerhalb des News-Clips (0..2)
##   sound         — SfxMap-Id für AudioDirector ("" = still)
##   fx            — Bühnen-Gag: "puff" | "umfallen" | "aufstehen" |
##                   "testbild" | "symbol" ("" = keiner)
##   wetter        — nur Wetter-Clip: {stunde, typ} aus dem ECHTEN
##                   SoulWetter-Tagesplan von MORGEN
##   zuschauer     — Emotion, mit der der zuschauende Raum-Gooby reagiert
##                   ("" = keine Reaktion)
##
## Alles hier ist pur und deterministisch: `alle(morgen)` baut das Programm
## für ein hereingereichtes Morgen-Datum — Tests injizieren ein festes Datum.

## Sendeplatz-Reihenfolge (Zapping-Rotation).
const CLIP_IDS: Array[String] = ["news", "kochen", "sport", "wetter", "nacht"]
## Anzahl Quatsch-Schlagzeilen im News-Pool (gobty.news.schlagzeile1..N).
const SCHLAGZEILEN_ANZAHL := 10
## Schlagzeilen-Slots pro News-Durchlauf.
const SCHLAGZEILEN_SLOTS := 3
## Wetter-Clip: zu diesen Stunden wird der Morgen-Plan abgetastet.
const WETTER_STUNDEN: Array[float] = [8.0, 12.0, 16.0, 20.0]


## Das komplette Programm. `morgen` ist das Datum von MORGEN ("YYYY-MM-DD")
## — der Wetter-Clip liest darüber den echten SoulWetter-Tagesplan (Gag:
## Wolke Wuschel sagt das Wetter an, das morgen wirklich im Spiel läuft).
static func alle(morgen: String) -> Array[Dictionary]:
	return [_news(), _kochen(), _sport(), _wetter(morgen), _nacht()]


## Schlagzeilen-Key für Durchlauf `rotation` + Slot — rotiert deterministisch
## durch alle SCHLAGZEILEN_ANZAHL Texte (jeder Durchlauf zeigt 3 neue).
static func schlagzeilen_key(rotation: int, slot: int) -> String:
	var index := posmod(rotation * SCHLAGZEILEN_SLOTS + slot, SCHLAGZEILEN_ANZAHL)
	return "gobty.news.schlagzeile%d" % (index + 1)


## Morgen-Datum zu einem "YYYY-MM-DD"-Datum (pur; 12:00 UTC gegen
## Randfälle, Monats-/Jahreswechsel inklusive).
static func datum_morgen(heute: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string("%sT12:00:00" % heute)
	var morgen := Time.get_datetime_dict_from_unix_time(int(unix) + 86_400)
	return "%04d-%02d-%02d" % [int(morgen["year"]), int(morgen["month"]), int(morgen["day"])]


## Datum ("YYYY-MM-DD") aus einer injizierten Uhrzeit (epoch-ms).
static func datum_von_ms(now_ms: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(now_ms / 1000.0))
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## Wetter-Symbole des Morgen-Plans: [{stunde, typ}] — der ECHTE Plan
## (SoulWetter ist deterministisch pro Tag, inkl. Winter-Schnee).
static func wetter_symbole(morgen: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stunde: float in WETTER_STUNDEN:
		var zustand := SoulWetter.zustand(morgen, stunde)
		out.append({"stunde": stunde, "typ": str(zustand.get("typ", "sonne"))})
	return out


# ── Die 5 Clips ───────────────────────────────────────────────────────────────


## (1) „GOOBY NEWS": Sprecher-Gooby hinterm Pult brabbelt wichtig,
## Eilmeldungs-Banner rotiert durch die Quatsch-Schlagzeilen.
static func _news() -> Dictionary:
	return {
		"id": "news",
		"titel_key": "gobty.clip.news",
		"dauer_s": 13.0,
		"schritte":
		[
			_s(0.0, {"emotion": "neutral", "clip": "idle", "banner_key": "gobty.news.intro"}),
			_s(2.0, {"emotion": "angry", "banner": "schlagzeile", "slot": 0, "sound": "ui_chip"}),
			_s(5.5, {"emotion": "neutral", "clip": "wave", "banner": "schlagzeile", "slot": 1}),
			_s(
				9.0,
				{
					"emotion": "scared",
					"banner": "schlagzeile",
					"slot": 2,
					"sound": "ui_chip",
					"zuschauer": "happy",
				}
			),
		],
	}


## (2) „Kochen mit Küchen-Gooby": rührt im Topf, es Puff-t, Gesicht rußig.
static func _kochen() -> Dictionary:
	return {
		"id": "kochen",
		"titel_key": "gobty.clip.kochen",
		"dauer_s": 12.0,
		"schritte":
		[
			_s(0.0, {"emotion": "happy", "clip": "build_hammer", "banner_key": "gobty.kochen.b1"}),
			_s(4.0, {"emotion": "ecstatic", "sound": "mg_good"}),
			_s(
				6.5,
				{
					"emotion": "dizzy",
					"clip": "idle",
					"banner_key": "gobty.kochen.b2",
					"sound": "gvz_boom",
					"fx": "puff",
					"zuschauer": "ecstatic",
				}
			),
			_s(9.5, {"emotion": "happy", "clip": "wave", "banner_key": "gobty.kochen.b3"}),
		],
	}


## (3) „GOOBY SPORT": zwei Goobys hüpfen um einen Ball, einer fällt um.
static func _sport() -> Dictionary:
	return {
		"id": "sport",
		"titel_key": "gobty.clip.sport",
		"dauer_s": 12.0,
		"schritte":
		[
			_s(0.0, {"emotion": "ecstatic", "clip": "hop", "banner_key": "gobty.sport.b1"}),
			_s(2.5, {"sprecher": 1, "emotion": "happy", "clip": "hop", "sound": "mg_go"}),
			_s(5.0, {"emotion": "ecstatic", "clip": "hop", "banner_key": "gobty.sport.b2"}),
			_s(
				7.5,
				{
					"sprecher": 1,
					"emotion": "dizzy",
					"banner_key": "gobty.sport.b3",
					"sound": "mg_spill",
					"fx": "umfallen",
					"zuschauer": "ecstatic",
				}
			),
			_s(10.0, {"clip": "celebrate", "sound": "mg_win", "fx": "aufstehen"}),
		],
	}


## (4) „Wetter mit Wolke Wuschel": Gooby zeigt auf Symbole — der ECHTE
## SoulWetter-Tagesplan von morgen als Gag.
static func _wetter(morgen: String) -> Dictionary:
	var schritte: Array[Dictionary] = [
		_s(0.0, {"emotion": "happy", "clip": "wave", "banner_key": "gobty.wetter.intro"}),
	]
	var t := 2.5
	for eintrag: Dictionary in wetter_symbole(morgen):
		(
			schritte
			. append(
				_s(
					t,
					{
						"emotion": "happy",
						"clip": "wave",
						"sound": "ui_tick",
						"fx": "symbol",
						"wetter": eintrag,
					}
				)
			)
		)
		t += 2.5
	schritte.append(_s(t, {"emotion": "ecstatic", "clip": "celebrate", "zuschauer": "happy"}))
	return {
		"id": "wetter",
		"titel_key": "gobty.clip.wetter",
		"dauer_s": t + 2.0,
		"schritte": schritte,
	}


## (5) „Gute-Nacht-Sender": Gooby gähnt, Testbild mit schlafendem Gooby.
static func _nacht() -> Dictionary:
	return {
		"id": "nacht",
		"titel_key": "gobty.clip.nacht",
		"dauer_s": 14.0,
		"schritte":
		[
			_s(0.0, {"emotion": "sleepy", "clip": "idle", "banner_key": "gobty.nacht.b1"}),
			_s(4.0, {"emotion": "sleepy", "clip": "sit", "banner_key": "gobty.nacht.b2"}),
			_s(
				8.0,
				{
					"emotion": "sleepy",
					"clip": "sleep",
					"banner_key": "gobty.nacht.b3",
					"sound": "ui_close",
					"fx": "testbild",
					"zuschauer": "sleepy",
				}
			),
		],
	}


## Schritt mit Defaults füllen — Defs bleiben kurz, der Player/die Bühne
## können sich auf vollständige Schlüssel verlassen.
static func _s(t: float, felder: Dictionary) -> Dictionary:
	var schritt := {
		"t": t,
		"sprecher": 0,
		"emotion": "",
		"clip": "",
		"banner_key": "",
		"banner": "",
		"slot": 0,
		"sound": "",
		"fx": "",
		"wetter": {},
		"zuschauer": "",
	}
	schritt.merge(felder, true)
	return schritt

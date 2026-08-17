class_name RanchHorseTaming
extends RefCounted
## Wildpferde zaehmen (RW-2, IDEAS-1 A5) — PURE Zustandsmaschine.
## BotW-Fantasie ohne Frust: Anschleichen (geduckt, langsam) + sanftes
## Beruhigen im Schnaub-Rhythmus. KEIN Abwerfen — jeder Fehlversuch heisst
## nur "es trabt davon, kommt wieder" (Cooldown). Die Welt (RW-1) spawnt
## die Herde; dieses Modul rechnet NUR die Begegnung.
##
## Ablauf: phase "anschleichen" → (nah genug) "beruhigen" → "gezaehmt".
## Bei zu viel Aufmerksamkeit oder Ruhe 0 → "davongetrabt" (+ Cooldown).

## --------------------------------------------------------- Anschleichen
## Aufmerksamkeit 0..100; bei 100 trabt das Pferd davon.
const AUFMERKSAM_MAX := 100.0
## Grundanstieg pro Sekunde in Sichtweite (skaliert mit Naehe).
const AUFMERKSAM_ANSTIEG_PRO_S := 22.0
## Geduckt schleicht man fast unsichtbar; still stehen beruhigt.
const DUCK_MULT := 0.35
const STILL_MULT := 0.25
const AUFMERKSAM_ABBAU_PRO_S := 8.0
## Ausserhalb dieses Radius sieht das Wildpferd nichts (m).
const SICHT_RADIUS_M := 10.0
## Nah genug fuers Beruhigen (m).
const BERUEHR_ABSTAND_M := 1.5

## ----------------------------------------------------------- Beruhigen
## Das Pferd schnaubt im Takt; Tipp im Fenster beruhigt es.
const TAKT_S := 1.4
const TREFFER_FENSTER_S := 0.3
const RUHE_START := 30.0
const RUHE_ZIEL := 100.0
const RUHE_TREFFER := 14.0
const RUHE_DANEBEN := -8.0

## Davongetrabte Pferde kommen nach dem Cooldown wieder (s).
const COOLDOWN_S := 20.0

## Wildpferd-Rassen-Pool + Sonder-Fellmuster-Chancen (G6: besondere
## Muster sind der Zaehm-Lohn).
const WILD_RASSEN: Array[String] = [
	"puschelhufer", "zottelgnuff", "moosmaehne", "flitzewind", "westernwuschel"
]
const WILD_SCHECKE_CHANCE := 0.6
const WILD_GLITZER_TRAEGER_CHANCE := 0.25


## Frische Begegnung (deterministisch aus Seed): Start im Anschleichen.
static func neue_begegnung(seed_wert: int) -> Dictionary:
	return {
		"seed": seed_wert,
		"phase": "anschleichen",
		"aufmerksamkeit": 0.0,
		"ruhe": RUHE_START,
		"seit_schnauben_s": 0.0,
		"cooldown_s": 0.0,
	}


## Ein Anschleich-Schritt. Pure — neuer Zustand; `event` ist "" |
## "bereit" (nah genug → Beruhigen) | "davongetrabt".
static func step_anschleichen(
	zustand: Dictionary, dt: float, abstand_m: float, bewegt_sich: bool, geduckt: bool
) -> Dictionary:
	var z := zustand.duplicate(true)
	if str(z.get("phase")) != "anschleichen":
		z["event"] = ""
		return z
	var a := _num(z.get("aufmerksamkeit"), 0.0)
	if abstand_m <= SICHT_RADIUS_M:
		var naehe := clampf((SICHT_RADIUS_M - abstand_m) / SICHT_RADIUS_M, 0.0, 1.0)
		var mult := (DUCK_MULT if geduckt else 1.0) * (1.0 if bewegt_sich else STILL_MULT)
		a += AUFMERKSAM_ANSTIEG_PRO_S * naehe * mult * dt
	else:
		a -= AUFMERKSAM_ABBAU_PRO_S * dt
	if not bewegt_sich and geduckt:
		a -= AUFMERKSAM_ABBAU_PRO_S * 0.5 * dt
	z["aufmerksamkeit"] = clampf(a, 0.0, AUFMERKSAM_MAX)
	z["event"] = ""
	if z["aufmerksamkeit"] >= AUFMERKSAM_MAX:
		return _davongetrabt(z)
	if abstand_m <= BERUEHR_ABSTAND_M:
		z["phase"] = "beruhigen"
		z["seit_schnauben_s"] = 0.0
		z["event"] = "bereit"
	return z


## Beruhigen-Zeitschritt: treibt den Schnaub-Takt (Anzeige + Fenster).
## `event` ist "" | "schnauben" (neuer Takt-Moment, HUD pulsiert).
static func step_beruhigen(zustand: Dictionary, dt: float) -> Dictionary:
	var z := zustand.duplicate(true)
	z["event"] = ""
	if str(z.get("phase")) != "beruhigen":
		return z
	var t := _num(z.get("seit_schnauben_s"), 0.0) + maxf(0.0, dt)
	if t >= TAKT_S:
		t = fmod(t, TAKT_S)
		z["event"] = "schnauben"
	z["seit_schnauben_s"] = t
	return z


## Ein Beruhigungs-Tipp: im Fenster (±0,3 s um den Schnaub-Moment) steigt
## die Ruhe, daneben sinkt sie sanft. `event`: "treffer" | "daneben" |
## "gezaehmt" | "davongetrabt".
static func beruhigen_tap(zustand: Dictionary) -> Dictionary:
	var z := zustand.duplicate(true)
	z["event"] = ""
	if str(z.get("phase")) != "beruhigen":
		return z
	var t := _num(z.get("seit_schnauben_s"), 0.0)
	var abstand := minf(t, TAKT_S - t)
	var ruhe := _num(z.get("ruhe"), RUHE_START)
	if abstand <= TREFFER_FENSTER_S:
		ruhe += RUHE_TREFFER
		z["event"] = "treffer"
	else:
		ruhe += RUHE_DANEBEN
		z["event"] = "daneben"
	z["ruhe"] = clampf(ruhe, 0.0, RUHE_ZIEL)
	if z["ruhe"] >= RUHE_ZIEL:
		z["phase"] = "gezaehmt"
		z["event"] = "gezaehmt"
	elif z["ruhe"] <= 0.0:
		return _davongetrabt(z)
	return z


## Cooldown-Schritt fuer davongetrabte Pferde; nach Ablauf beginnt die
## Begegnung von vorn ("es kommt wieder").
static func step_cooldown(zustand: Dictionary, dt: float) -> Dictionary:
	var z := zustand.duplicate(true)
	z["event"] = ""
	if str(z.get("phase")) != "davongetrabt":
		return z
	var rest := _num(z.get("cooldown_s"), 0.0) - maxf(0.0, dt)
	if rest <= 0.0:
		var frisch := neue_begegnung(int(_num(z.get("seed"), 0.0)))
		frisch["event"] = "wieder_da"
		return frisch
	z["cooldown_s"] = rest
	return z


## Gezaehmtes Wildpferd DETERMINISTISCH aus dem Begegnungs-Seed:
## Wild-Rasse aus dem Pool, dazu besondere Fellmuster (Schecken-Chance
## 60 %, Glitzer-TRAEGER 25 % — der NPC-Hinweis "da steckt was drin!").
static func wildpferd_dict(seed_wert: int, balance: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("wild|%d" % seed_wert)
	var rasse: String = WILD_RASSEN[rng.randi_range(0, WILD_RASSEN.size() - 1)]
	var individuum := RanchRassen.neues_individuum(rasse, seed_wert, balance)
	var gene: Dictionary = individuum.get("gene", {})
	if rng.randf() < WILD_SCHECKE_CHANCE:
		gene["s"] = ["Sch", "s0"]
	if rng.randf() < WILD_GLITZER_TRAEGER_CHANCE:
		gene["glitzer"] = ["gx", "g0"]
	individuum["gene"] = gene
	individuum["farbe"] = RanchRassen.fellfarbe_aus_genen(gene)
	individuum["wild"] = true
	return individuum


static func _davongetrabt(z: Dictionary) -> Dictionary:
	z["phase"] = "davongetrabt"
	z["cooldown_s"] = COOLDOWN_S
	z["event"] = "davongetrabt"
	return z


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback

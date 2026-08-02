class_name StimmungsSheet
extends RefCounted
## Inhalt des „So geht's {gooby}“-Blatts (G8/IDEA-SEELE, Idee 2): die träge
## SEELE-2-Laune in WORTEN — Band-Satz, das WARUM aus den ECHTEN Treibern
## (dieselben Inputs wie Stats.mood: Hunger/Energie/Hygiene/Spaß, dazu
## Krankheit und Früh-Weck-Brummeln), Goobys offener Wunsch, die zuletzt
## erzählte Erinnerung und 1–2 sanfte Handlungs-Hinweise.
##
## BEWUSST keine Zahlen, keine Balken: die Stats-Kapseln im HUD bleiben die
## Meter — die Laune bleibt Gefühl (Web-Treue, s. Ideen-Doc). Reiner Builder
## nach HudStatusSheet-Muster: inhalt() ist PUR (State + Zeit rein, Daten
## raus — headless testbar mit injizierten Zuständen), build_content() baut
## nur noch Nodes aus den Daten.

const Stats := preload("res://scripts/logic/stats.gd")
const Sleep := preload("res://scripts/logic/sleep.gd")
const Health := preload("res://scripts/logic/health.gd")

## Höchstens so viele Warum-Zeilen (mehr wird Zustandsbericht statt Wärme).
const MAX_GRUENDE := 2
## Höchstens so viele Handlungs-Hinweise.
const MAX_TIPPS := 2
## Treiber-Prüfreihenfolge = Dringlichkeit (krank vor hungrig vor müde …).
## Jeder Eintrag: Stat-Key (oder "" für Nicht-Stat-Treiber), Grund-/Tipp-Key.
const TREIBER: Array[Dictionary] = [
	{"stat": "hunger", "grund": "hunger", "tipp": "hunger"},
	{"stat": "energy", "grund": "muede", "tipp": "muede"},
	{"stat": "fun", "grund": "langeweile", "tipp": "langeweile"},
	{"stat": "hygiene", "grund": "hygiene", "tipp": "hygiene"},
]

# ── PUR: Daten-Snapshot aus dem State ────────────────────────────────────────


## Sheet-Daten aus dem GameState-Snapshot (deterministisch): Band-Satz,
## Warum-Zeilen, Wunsch-Zeile, Erinnerungs-Zeile, Tipps. `state` ist der
## VOLLE Save-Baum (gs.state()) — Tests reichen gebaute Zustände herein.
static func inhalt(state: Dictionary, now_ms: int) -> Dictionary:
	var soul: Variant = state.get("soul", {})
	var slice: Dictionary = soul if soul is Dictionary else {}
	var stimmung := SoulMood.normalize(slice.get("stimmung"))
	var wert := float(stimmung["wert"])
	var band := SoulMood.band(wert)
	var args := {"gooby": _nickname(state)}
	var gruende: Array[String] = []
	var tipps: Array[String] = []
	_sammle_treiber(state, now_ms, gruende, tipps)
	return {
		"band": band,
		"wert": wert,
		"args": args,
		"laune_key": "seele_tag.laune." + band,
		"gruende": gruende,
		"tipps": tipps,
		"wunsch_key": _wunsch_key(state, slice),
		"erinnerung": _letzte_erinnerung(state, slice),
	}


## Warum-Zeilen + Tipps aus den ECHTEN Treibern, in Dringlichkeits-Folge:
## Krankheit → niedrigste Stats (Stats.is_low, kritisch verschärft den
## Hunger-Ton) → Früh-Weck-Brummeln. Ohne Befund: „alles gut“-Zeile.
static func _sammle_treiber(
	state: Dictionary, now_ms: int, gruende: Array[String], tipps: Array[String]
) -> void:
	var gooby: Dictionary = state.get("gooby", {}) if state.get("gooby") is Dictionary else {}
	var stats: Dictionary = gooby.get("stats", {}) if gooby.get("stats") is Dictionary else {}
	var krank_grad := Health.grade(gooby.get("health"))
	if krank_grad >= 2:
		gruende.append("seele_tag.grund.krank")
		tipps.append("seele_tag.tipp.krank")
	elif krank_grad == 1:
		gruende.append("seele_tag.grund.flau")
		tipps.append("seele_tag.tipp.krank")
	# Stats in fester Dringlichkeits-Folge; unter den niedrigen gewinnt der
	# NIEDRIGSTE zuerst (der dominante Treiber wird zuerst benannt).
	var niedrige: Array[Dictionary] = []
	for eintrag in TREIBER:
		var v := float(Stats.clamp_stat(stats.get(str(eintrag["stat"]))))
		if Stats.is_low(v):
			var reihe := eintrag.duplicate()
			reihe["wert"] = v
			niedrige.append(reihe)
	niedrige.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["wert"] < b["wert"])
	for reihe in niedrige:
		if gruende.size() >= MAX_GRUENDE:
			break
		var grund := str(reihe["grund"])
		if grund == "hunger" and Stats.is_critical(float(reihe["wert"])):
			grund = "hunger_stark"
		gruende.append("seele_tag.grund." + grund)
		tipps.append("seele_tag.tipp." + str(reihe["tipp"]))
	if gruende.size() < MAX_GRUENDE and Sleep.grumpy_debuff(gooby, now_ms) > 0.0:
		gruende.append("seele_tag.grund.frueh_geweckt")
	if gruende.is_empty():
		gruende.append("seele_tag.grund.alles_gut")
	if tipps.is_empty():
		tipps.append("seele_tag.tipp.weiter_so")
	while tipps.size() > MAX_TIPPS:
		tipps.pop_back()


## Goobys aktueller Wunsch als Sheet-Zeile ("" = keiner offen). Nur der
## AKTIV gefasste Wunsch (soul.wunsch) zählt — und nur solange er laut
## echten Daten offen ist (SoulMemories.wunsch_offen).
static func _wunsch_key(state: Dictionary, slice: Dictionary) -> String:
	var wunsch: Variant = slice.get("wunsch", {})
	if not (wunsch is Dictionary):
		return ""
	var wunsch_id := str((wunsch as Dictionary).get("id", ""))
	if wunsch_id.is_empty() or not SoulMemories.wunsch_offen(state, wunsch_id):
		return ""
	return "seele_tag.wunsch." + wunsch_id


## Die zuletzt GEZEIGTE Erinnerung ({text_key, args} oder {}): jüngster
## memoryShownAt-Stempel, dessen Kandidat noch aus echten Daten baubar ist.
static func _letzte_erinnerung(state: Dictionary, slice: Dictionary) -> Dictionary:
	var shown: Variant = slice.get("memoryShownAt", {})
	if not (shown is Dictionary) or (shown as Dictionary).is_empty():
		return {}
	var beste_id := ""
	var bester_ms := 0
	var ids: Array = (shown as Dictionary).keys()
	ids.sort()
	for memory_id: Variant in ids:
		var at: Variant = shown[memory_id]
		if (at is int or at is float) and int(at) > bester_ms:
			bester_ms = int(at)
			beste_id = str(memory_id)
	if beste_id.is_empty():
		return {}
	for candidate in SoulMemories.candidates(state):
		if str(candidate["id"]) == beste_id:
			return candidate
	return {}


static func _nickname(state: Dictionary) -> String:
	var meta: Variant = state.get("meta", {})
	if meta is Dictionary:
		var nick := str((meta as Dictionary).get("goobyNickname", ""))
		if not nick.is_empty():
			return nick
	return "Gooby"


# ── Node-Baum (nur Darstellung — keine Logik) ────────────────────────────────


## Sheet-Inhalt aus inhalt()-Daten bauen. `avail_width` = nutzbare
## Innenbreite in Canvas-px (0 = egal) — FIX1-Regel wie HudStatusSheet.
static func build_content(daten: Dictionary, ui_scale := 1.0, avail_width := 0.0) -> Control:
	var spalte := VBoxContainer.new()
	spalte.name = "StimmungsInhalt"
	spalte.add_theme_constant_override("separation", int(10 * ui_scale))
	var breite := 460.0 * ui_scale
	if avail_width > 0.0:
		breite = minf(breite, avail_width)
	spalte.custom_minimum_size = Vector2(breite, 0)
	var args: Dictionary = daten.get("args", {})
	# Band-Satz — die Laune in EINEM warmen Satz, prominent.
	var kopf := _zeile(I18nService.t(str(daten["laune_key"]), args), ui_scale, "TitleLabel")
	kopf.name = "LauneSatz"
	spalte.add_child(kopf)
	# Warum-Zeilen (die echten Treiber).
	for i in (daten["gruende"] as Array[String]).size():
		var grund := _zeile(I18nService.t(daten["gruende"][i], args), ui_scale, "SoftLabel")
		grund.name = "Grund%d" % (i + 1)
		spalte.add_child(grund)
	# Wunsch + Erinnerung — Goobys Innenleben, beiläufig erwähnt.
	var wunsch_key := str(daten.get("wunsch_key", ""))
	if not wunsch_key.is_empty():
		var wunsch := _zeile(I18nService.t(wunsch_key, args), ui_scale, "SoftLabel")
		wunsch.name = "Wunsch"
		spalte.add_child(wunsch)
	var erinnerung: Dictionary = daten.get("erinnerung", {})
	if not erinnerung.is_empty():
		var text := I18nService.t(str(erinnerung["text_key"]), erinnerung.get("args", {}))
		var zeile := _zeile("„%s“" % text, ui_scale, "CaptionLabel")
		zeile.name = "Erinnerung"
		spalte.add_child(zeile)
	# Sanfte Hinweise in einer warmen Mulde (AcWell) — Vorschlag, kein Befehl.
	spalte.add_child(_tipp_box(daten, args, ui_scale))
	return spalte


static func _tipp_box(daten: Dictionary, args: Dictionary, ui_scale: float) -> Control:
	var box := PanelContainer.new()
	box.name = "TippBox"
	box.theme_type_variation = "AcWell"
	var innen := VBoxContainer.new()
	innen.name = "TippSpalte"
	innen.add_theme_constant_override("separation", int(4 * ui_scale))
	box.add_child(innen)
	for i in (daten["tipps"] as Array[String]).size():
		var tipp := _zeile(I18nService.t(daten["tipps"][i], args), ui_scale, "SoftLabel")
		tipp.name = "Tipp%d" % (i + 1)
		innen.add_child(tipp)
	return box


static func _zeile(text: String, ui_scale: float, variation: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ui_scale > 1.0:
		var basis := AcTokens.FONT_SIZE_BODY
		if variation == "TitleLabel":
			basis = AcTokens.FONT_SIZE_TITLE
		elif variation == "CaptionLabel":
			basis = AcTokens.FONT_SIZE_CAPTION
		label.add_theme_font_size_override("font_size", int(basis * ui_scale))
	return label

extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## Flow „J6 Münzflug": Belohnungen reisen sichtbar (W18/J6, I-31).
## 1. Boot/Onboarding wie ein Spieler (Tagesbonus/Coachmark/Guide wegtippen).
## 2. KAPSEL-PFAD: eine echte Münz-Gutschrift im Wohnzimmer (Economy.award in
##    GameState.update — derselbe Pfad wie Verkäufe/Events) startet den
##    Münzflug zur HUD-Kapsel; Zeitlupe (Engine.time_scale) streckt den Flug,
##    damit die Schritt-Screenshots die fliegenden Münzen + den Kapsel-Puls
##    einfangen.
## 3. TOAST-PFAD: eine Tagesquest wird erfüllbar gemacht (Baseline-Trick im
##    quests-Slice), das Blatt geöffnet und „Abholen" getippt — das HUD ist
##    geduckt, also sammelt der Zähler-Toast; der Flug startet am getappten
##    Knopf (melde_quelle über den Service-Hook).
## 4. MINISPIEL-SCHUTZ: eine Möhrenfang-Runde bis „Runde vorbei!" — die
##    Results-Buchung (MinigameAward) darf KEINEN Flug/Toast auslösen
##    (W18 B7: der Results-Screen zählt selbst hoch).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_j6_muenzflug

const Economy := preload("res://scripts/logic/economy.gd")

## Zeitlupe für die Flug-Frames (Tweens laufen über Engine.time_scale).
const ZEITLUPE := 0.3

var _muenzen_vor_claim := -1
## Wird von quest_erfuellbar_machen auf den echten Knopf-Namen gesetzt
## (Dictionary-Referenz — die Harness liest "node" erst bei Ausführung).
var _abhol_schritt := {
	"name": "quest_abholen",
	"aktion": "tipp_name",
	"node": "",
	"timeout_s": 30.0,
}


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_morgen_aufraeumen())
	liste.append_array(_kapsel_schritte())
	liste.append_array(_quest_claim_schritte())
	liste.append_array(_minispiel_schritte())
	return liste


## Die J1-Willkommens-Sequenz (Gooby-Gruß → Tagesbonus → Coachmark → Guide-
## Karte) braucht unter llvmpipe länger als die Basis-tipp_falls_da-Schritte
## warten — hier wird JEDES Overlay geduldig abgewartet und weggetippt,
## damit Kapsel-/Claim-Pfad auf einem ruhigen Wohnzimmer aufsetzen.
func _morgen_aufraeumen() -> Array[Dictionary]:
	return [
		{
			"name": "tagesbonus_abwarten",
			"aktion": "warte_bis",
			"klasse": "DailyBonusPopup",
			"timeout_s": 90.0,
			"pflicht": false,
		},
		{
			"name": "tagesbonus_wegtippen",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{
			"name": "coachmark_spaet_wegtippen",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{
			"name": "guide_karte_abwarten",
			"aktion": "warte_bis",
			"text": "Schritt 1/",
			"timeout_s": 60.0,
			"pflicht": false,
		},
		{
			"name": "guide_spaet_beenden",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 15.0,
			"pflicht": false,
		},
	]


## --- 2. Kapsel-Pfad: Gutschrift im Wohnzimmer, HUD sichtbar ------------------


func _kapsel_schritte() -> Array[Dictionary]:
	return [
		{"name": "wohnzimmer_ruhe", "aktion": "warte", "sekunden": 2.0},
		{"name": "zeitlupe_an", "aktion": "tue", "funktion": zeitlupe_an},
		{
			"name": "muenzen_gutschreiben",
			"aktion": "tue",
			"funktion": muenzen_gutschreiben,
			"erwartung": "Economy.award bucht +25 über GameState.update",
		},
		{
			"name": "muenzflug_gestartet",
			"aktion": "warte_bis",
			"bedingung": flug_aktiv,
			"timeout_s": 15.0,
		},
		{"name": "muenzflug_frame_1", "aktion": "warte", "sekunden": 0.08},
		{"name": "muenzflug_frame_2", "aktion": "warte", "sekunden": 0.08},
		{"name": "muenzflug_frame_3", "aktion": "warte", "sekunden": 0.08},
		{
			"name": "muenzflug_angekommen",
			"aktion": "warte_bis",
			"bedingung": flug_fertig,
			"timeout_s": 30.0,
		},
		{
			"name": "kapsel_pulst",
			"aktion": "tue",
			"funktion": kapsel_pulst,
			"erwartung": "Münz-Kapsel trägt den Squish-Puls (kapsel_puls lief)",
		},
		{"name": "zeitlupe_aus", "aktion": "tue", "funktion": zeitlupe_aus},
	]


## --- 3. Toast-Pfad: Quest claimen, HUD geduckt -------------------------------


func _quest_claim_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "quest_erfuellbar_machen",
			"aktion": "tue",
			"funktion": quest_erfuellbar_machen,
			"erwartung": "eine Tagesquest ist claimbar (Baseline-Trick)",
		},
		{
			"name": "quests_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnQuests",
			"erwarte": {"klasse": "DailyQuestPanel"},
			"timeout_s": 45.0,
		},
		{"name": "brett_ansehen", "aktion": "warte", "sekunden": 1.0},
		{"name": "zeitlupe_an_claim", "aktion": "tue", "funktion": zeitlupe_an},
		_abhol_schritt,
		{
			"name": "claim_flug_gestartet",
			"aktion": "warte_bis",
			"bedingung": flug_aktiv,
			"timeout_s": 20.0,
		},
		{"name": "claim_flug_frame_1", "aktion": "warte", "sekunden": 0.08},
		{"name": "claim_flug_frame_2", "aktion": "warte", "sekunden": 0.08},
		{
			"name": "toast_sammelt",
			"aktion": "warte_bis",
			"bedingung": toast_da,
			"timeout_s": 20.0,
		},
		{
			"name": "claim_flug_fertig",
			"aktion": "warte_bis",
			"bedingung": flug_fertig,
			"timeout_s": 30.0,
		},
		{"name": "zeitlupe_aus_claim", "aktion": "tue", "funktion": zeitlupe_aus},
		{
			"name": "claim_gebucht",
			"aktion": "tue",
			"funktion": claim_gebucht,
			"erwartung": "Quest-Belohnung ist auf dem Konto",
		},
		{
			"name": "quests_schliessen",
			"aktion": "taste",
			"keycode": KEY_ESCAPE,
			"erwarte": {"weg_klasse": "DailyQuestPanel"},
			"timeout_s": 20.0,
		},
	]


## --- 4. Minispiel-Schutz: Results zählt selbst, der Flug schweigt ------------


func _minispiel_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(arcade_bis_pregame("carrotCatch", 0))
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{
					"name": "korb_fangen",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.5, 0.75)),
					"dauer_s": 1.5,
				},
				{"name": "runde_laufen_lassen", "aktion": "warte", "sekunden": 2.0},
				runde_zu_ende(240.0),
				{"name": "results_ansehen", "aktion": "warte", "sekunden": 4.0},
				{
					"name": "flug_schweigt_bei_results",
					"aktion": "tue",
					"funktion": flug_schweigt,
					"erwartung": "kein Flug/Toast über dem Results-Count-Up (W18 B7)",
				},
			]
		)
	)
	return liste


## --- Bausteine ---------------------------------------------------------------


func _flug() -> RewardFlug:
	var flug := harness.get_first_node_in_group(&"reward_flug")
	return flug if flug is RewardFlug else null


func _hud() -> Hud:
	var hud := harness.get_first_node_in_group(&"hud")
	return hud if hud is Hud else null


func zeitlupe_an() -> bool:
	Engine.time_scale = ZEITLUPE
	return true


func zeitlupe_aus() -> bool:
	Engine.time_scale = 1.0
	return true


## Echte Gutschrift über den EINEN Wallet-Pfad (wie Verkäufe/Events):
## Quelle nahe Gooby melden, dann Economy.award in GameState.update.
func muenzen_gutschreiben() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var canvas := harness.root.get_visible_rect().size
	RewardFlug.melde_quelle(Vector2(canvas.x * 0.5, canvas.y * 0.62))
	var tag_dict := Time.get_datetime_dict_from_system()
	var tag := "%04d-%02d-%02d" % [tag_dict["year"], tag_dict["month"], tag_dict["day"]]
	gs.update(func(s: Dictionary) -> void: Economy.award(s["economy"], 25, "quest", tag))
	return true


func flug_aktiv() -> bool:
	var flug := _flug()
	return flug != null and flug.aktive_sprites() > 0


func flug_fertig() -> bool:
	var flug := _flug()
	return flug != null and flug.aktive_sprites() == 0


func toast_da() -> bool:
	var flug := _flug()
	return flug != null and flug.toast_offen()


func kapsel_pulst() -> bool:
	var hud := _hud()
	if hud == null:
		return false
	return (hud._coin_chip as Control).has_meta(&"_rf_puls")


## Results-Schutz: während der Zähl-Animation weder Flug noch Toast.
func flug_schweigt() -> bool:
	var flug := _flug()
	return flug != null and flug.aktive_sprites() == 0 and not flug.toast_offen()


## Erste Quest mit „Baseline-n"-Messung claimbar machen: base.n um das Ziel
## senken → progress_of liefert das Ziel (Live-Zähler bleiben unberührt).
## Setzt zugleich den Knopf-Namen des Abholen-Schritts (ClaimIdPascal).
func quest_erfuellbar_machen() -> bool:
	var dienst := DailyQuestService.find_service()
	var gs := game_state()
	if dienst == null or gs == null:
		return false
	dienst.ensure_roll()
	_muenzen_vor_claim = int(gs.get_value("economy.coins", -1))
	var machbar := [
		"counter", "spiele_gesamt", "spiel_runden", "muenzen_verdient", "muenzen_ausgegeben"
	]
	var by_id := DailyQuestEngine.pool_by_id(dienst.pool())
	var ok := {"id": ""}
	gs.update(
		func(state: Dictionary) -> void:
			var slice: Dictionary = state.get("quests") if state.get("quests") is Dictionary else {}
			var active: Array = slice.get("active") if slice.get("active") is Array else []
			for entry: Variant in active:
				if not (entry is Dictionary) or bool((entry as Dictionary).get("claimed", false)):
					continue
				var def: Dictionary = by_id.get(str((entry as Dictionary).get("id", "")), {})
				var messung: Dictionary = (
					def.get("messung") if def.get("messung") is Dictionary else {}
				)
				if not machbar.has(str(messung.get("typ", ""))):
					continue
				var base: Dictionary = (
					(entry as Dictionary).get("base")
					if (entry as Dictionary).get("base") is Dictionary
					else {}
				)
				base["n"] = int(base.get("n", 0)) - DailyQuestEngine.target_of(def)
				(entry as Dictionary)["base"] = base
				ok["id"] = str(def.get("id", ""))
				return
	)
	if str(ok["id"]).is_empty():
		return false
	gs.notify_slice_changed("quests")
	_abhol_schritt["node"] = "Claim" + str(ok["id"]).to_pascal_case()
	return true


func claim_gebucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vor_claim < 0:
		return false
	return int(gs.get_value("economy.coins", -1)) > _muenzen_vor_claim

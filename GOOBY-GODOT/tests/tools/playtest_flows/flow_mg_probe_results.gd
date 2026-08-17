extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## DIAGNOSE-Flow „Results-Vermessung“ (Regressionswächter für den Befund
## „zweite Results-Karte klebt am unteren Bildschirmrand, Knöpfe
## unerreichbar“): startet starHopper, beendet Runde 1 kontrolliert über
## ctx.report_end (derselbe sanktionierte Weg wie im FB3-UI-Audit), misst
## die Rechtecke von _results/_center/_panel, tippt „Nochmal“, beendet
## Runde 2 genauso und misst erneut — die Zahlen landen im lauf.log
## ([PROBE]-/[WATCH]-Zeilen). Nach dem Fix müssen beide Messungen
## identisch zentrieren und „Nach Hause“ erreichbar sein.
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_mg_probe_results


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame("starHopper", 2))
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{"name": "kurz_fliegen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "runde1_beenden",
					"aktion": "tue",
					"funktion": runde_beenden.bind(3),
					"erwartung": "report_end({score: 3}) über den Spiel-Kontext",
				},
				{
					"name": "results1_da",
					"aktion": "warte_bis",
					"text": "Runde vorbei!",
					"timeout_s": 30.0,
				},
				{"name": "results1_ruhe", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "results1_messen",
					"aktion": "tue",
					"funktion": results_messen.bind("RESULTS1"),
					"erwartung": "Rechtecke geloggt",
				},
				{
					"name": "beobachter_starten",
					"aktion": "tue",
					"funktion": beobachter_starten,
					"erwartung": "Frame-Beobachter am Results-Center hängt",
				},
				{
					"name": "nochmal_tippen",
					"aktion": "tipp_text",
					"text": "Nochmal",
					"erwarte": {"weg_text": "Runde vorbei!"},
					"timeout_s": 30.0,
				},
				{
					"name": "quick_go_abwarten",
					"aktion": "warte_bis",
					"bedingung": countdown_fertig,
					"timeout_s": 30.0,
				},
				{"name": "runde2_kurz", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "runde2_beenden",
					"aktion": "tue",
					"funktion": runde_beenden.bind(4),
					"erwartung": "report_end({score: 4}) über den Spiel-Kontext",
				},
				{
					"name": "results2_da",
					"aktion": "warte_bis",
					"text": "Runde vorbei!",
					"timeout_s": 30.0,
				},
				{"name": "results2_ruhe", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "results2_messen",
					"aktion": "tue",
					"funktion": results_messen.bind("RESULTS2"),
					"erwartung": "Rechtecke geloggt",
				},
				{
					"name": "results_nach_hause",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 60.0,
					"pflicht": false,
				},
			]
		)
	)
	return liste


## Frame-Beobachter: loggt JEDE Änderung von _center.size/_rows-Kinderzahl/
## _panel-Min zwischen Results 1 und Results 2 (Frame-genaue Diagnose,
## welcher Moment die Karte verschiebt). Hängt am Host, stirbt mit ihm.
func beobachter_starten() -> bool:
	var host := host_node()
	if host == null:
		return false
	var results: Variant = host.get("_results")
	if not (results is Control):
		return false
	var beobachter := Beobachter.new()
	beobachter.results = results as Control
	host.add_child(beobachter)
	return true


## Runde über den Spiel-Kontext beenden (FB3-Audit-Muster) — true bei Erfolg.
func runde_beenden(score: int) -> bool:
	var spiel := spiel_node()
	if spiel == null or spiel.get("ctx") == null:
		return false
	spiel.ctx.report_end({"score": score})
	return true


## Rechtecke des Results-Screens ins Log drucken (Diagnose).
func results_messen(tag: String) -> bool:
	var host := host_node()
	if host == null:
		return false
	var results: Variant = host.get("_results")
	if not (results is Control):
		return false
	var wurzel := results as Control
	print(
		(
			"[PROBE] %s results rect=%s visible=%s anchors_t/b=%.2f/%.2f offs_t/b=%.1f/%.1f"
			% [
				tag,
				str(wurzel.get_global_rect()),
				str(wurzel.visible),
				wurzel.anchor_top,
				wurzel.anchor_bottom,
				wurzel.offset_top,
				wurzel.offset_bottom,
			]
		)
	)
	var center: Variant = wurzel.get("_center")
	if center is Control:
		var mitte := center as Control
		print(
			(
				"[PROBE] %s center rect=%s min=%s scale=%s anch_t/b=%.2f/%.2f offs_t/b=%.1f/%.1f"
				% [
					tag,
					str(mitte.get_global_rect()),
					str(mitte.get_combined_minimum_size()),
					str(mitte.scale),
					mitte.anchor_top,
					mitte.anchor_bottom,
					mitte.offset_top,
					mitte.offset_bottom,
				]
			)
		)
		for kind in mitte.get_children():
			if kind is Control:
				var k := kind as Control
				print(
					(
						"[PROBE] %s center-kind %s rect=%s min=%s"
						% [
							tag,
							k.name,
							str(k.get_global_rect()),
							str(k.get_combined_minimum_size())
						]
					)
				)
	var zeilen: Variant = wurzel.get("_rows")
	if zeilen is Control:
		print(
			(
				"[PROBE] %s rows kinder=%d min=%s"
				% [
					tag,
					(zeilen as Control).get_child_count(),
					str((zeilen as Control).get_combined_minimum_size()),
				]
			)
		)
	var panel: Variant = wurzel.get("_panel")
	if panel is Control:
		var karte := panel as Control
		print(
			(
				"[PROBE] %s panel rect=%s min=%s scale=%s"
				% [
					tag,
					str(karte.get_global_rect()),
					str(karte.get_combined_minimum_size()),
					str(karte.scale),
				]
			)
		)
	return true


## Frame-genauer Zustands-Logger (nur bei ÄNDERUNG drucken — Log bleibt klein).
class Beobachter:
	extends Node

	var results: Control
	var _letzte := ""

	func _process(_delta: float) -> void:
		if results == null or not is_instance_valid(results):
			return
		var center: Variant = results.get("_center")
		var rows: Variant = results.get("_rows")
		var panel: Variant = results.get("_panel")
		if not (center is Control and rows is Control and panel is Control):
			return
		var zeile := (
			"center_size=%s center_min=%s rows_kinder=%d panel_min=%s sichtbar=%s"
			% [
				str((center as Control).size),
				str((center as Control).get_combined_minimum_size()),
				(rows as Control).get_child_count(),
				str((panel as Control).get_combined_minimum_size()),
				str(results.visible),
			]
		)
		if zeile != _letzte:
			_letzte = zeile
			print("[WATCH] f=%d %s" % [Engine.get_process_frames(), zeile])

class_name MumieSzene
extends RefCounted
## Klopapier-Mumie (W13B, M1-Rest, Doc F §4.2) — ausgelagerte Runner-Szene
## (CI-Split wegen gdlint max-file-lines, Muster wie event_props.gd; der
## Match-Arm in event_runner.gd delegiert hierher): Gooby hat sich als
## Klopapier-Mumie verkleidet und findet nicht mehr raus. Fünf Papier-
## Wicklungen (weiße Ring-Bänder) umschlingen ihn; Tap-Muster wie Kleber-
## Stuhl/Mehl-Unfall: jeder Tap wickelt EINE Lage ab — Papier-Streifen-FX
## (weißer Puff + davonfliegendes Band) und Gooby dreht sich einmal um die
## eigene Achse. Nach der letzten Wicklung: Hop + Fun-Buff aus der Def.
## PURE Statics AUF dem Runner-Zustand (_remaining/_props/_say/_resolve):
## der Runner bleibt Besitzer von Props und Lebensdauer wie bei den
## Inline-Szenen, nur der Code wohnt hier.

const PAPER_COLOR := Color(0.99, 0.98, 0.95)


## Szene aufbauen: Ring-Bänder in Lagen um den Körper + unsichtbare Tap-Zone.
static func setup(runner: EventRunner, wickel_taps: int) -> void:
	var gooby := runner._gooby()
	if gooby == null or not ("rig" in gooby) or gooby.rig == null:
		runner._running = false
		return
	gooby.set_wander_enabled(false)
	runner._set_gooby_emotion("dizzy")
	runner._remaining = maxi(1, wickel_taps)
	for i in runner._remaining:
		var band := MeshInstance3D.new()
		var ring := BoxMesh.new()
		ring.size = Vector3(0.62 - 0.03 * float(i), 0.09, 0.62 - 0.03 * float(i))
		band.mesh = ring
		band.material_override = EventProps.flat_mat(PAPER_COLOR)
		band.position = gooby.position + Vector3(0.0, 0.14 + 0.13 * float(i), 0.0)
		band.rotation.y = 0.35 * float(i)
		band.name = "MumienBand%d" % i
		runner.add_child(band)
		runner._props.append(band)
	runner._say("events.mumie.bubble")
	var zone := runner._make_prop(
		Color(1, 1, 1, 0.02), Vector3(0.9, 1.2, 0.9), MumieSzene.tap.bind(runner), false
	)
	zone.position = gooby.position + Vector3(0.0, 0.55, 0.0)
	runner.add_child(zone)
	runner._props.append(zone)


## Ein Tap = eine Lage ab: oberstes Band fliegt davon (Streifen-FX + Puff),
## Gooby dreht sich; die letzte Lage löst das Event auf (Hop + Buff).
static func tap(runner: EventRunner) -> void:
	runner._remaining -= 1
	runner._sfx("gvz_pop")
	var gooby := runner._gooby()
	var band := runner.get_node_or_null("MumienBand%d" % runner._remaining)
	if band is MeshInstance3D:
		runner._props.erase(band)
		var weg := runner.create_tween()
		var richtung := Vector3(1.2 if runner._remaining % 2 == 0 else -1.2, 0.6, 0.4)
		weg.tween_property(band, "position", (band as Node3D).position + richtung, 0.35)
		weg.parallel().tween_property(band, "rotation:z", PI * 1.5, 0.35)
		weg.tween_callback((band as Node3D).queue_free)
	runner._puff_at(runner._gooby_pos() + Vector3(0.0, 0.7, 0.0), PAPER_COLOR)
	# Jede Wicklung dreht Gooby einmal um die eigene Achse.
	if gooby != null and "rig" in gooby and gooby.rig != null:
		var rig: Node3D = gooby.rig
		var dreh := runner.create_tween()
		dreh.tween_property(rig, "rotation:y", rig.rotation.y + TAU, 0.4)
	if runner._remaining > 0:
		runner._say("events.mumie.wickel")
		return
	runner._sfx("ui_confirm")
	runner._say("events.mumie.danke")
	if gooby != null:
		gooby.play_clip("hop")
	runner._set_gooby_emotion("happy")
	runner._resolve()

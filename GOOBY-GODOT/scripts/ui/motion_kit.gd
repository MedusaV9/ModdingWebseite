class_name MotionKit
extends RefCounted
## W21/ACNH — DIE verbindliche Motion-Grammatik des Redesigns
## (UI-DESIGN-ACNH §6). Baut bewusst NEBEN UiMotion (Web-Parität-Altbestand):
## neue/umgebaute Flächen nutzen NUR noch dieses Kit; UiMotion bleibt für
## Bestands-Call-Sites, bis das jeweilige Umsetzungs-Paket migriert.
##
## API (alle statisch; ALLE Reduced-Motion-gated: bei UiTheme.reduced_motion
## springen sie sofort in den Endzustand und geben null zurück):
##   MotionKit.pop_in(ctl)                # Auftritt: 240 ms Back-Out, 1.04
##   MotionKit.squish(ctl)                # Druck-Antwort: 0.94, 120 ms+Feder
##   MotionKit.blatt_slide_in(ctl)        # Blatt-Einflug: 280 ms Quint-Out
##   MotionKit.blatt_slide_out(ctl)       # Blatt-Abgang (await tween.finished)
##   MotionKit.stagger_ein(ctls)          # Listen: 40 ms Versatz, pop_in je Kind
##   MotionKit.count_up(label, von, bis)  # Zähler: 600 ms Quad-Out
##   MotionKit.stempel(ctl)               # Stempel-Landung: 1.6→1, −8°→0°
##   MotionKit.papier_puff(host)          # Papier-Staub (6 Flöckchen, RNG injizierbar)
##   MotionKit.puls(ctl)                  # sanfter 1.03-Puls bei Wert-Änderung
##
## Zeiten/Kurven sind VERBINDLICH (Konstanten unten) — kein Screen erfindet
## eigene Dauern. Effekt-Sparsamkeit: papier_puff/stempel nur an ECHTEN
## Belohnungs-/Abschluss-Momenten (Konfetti-Regel, UI-DESIGN-ACNH §6.3).

## Auftritt (Pop-In): Dauer + Overshoot der Feder.
const POP_S := 0.24
const POP_OVERSHOOT := 1.04
## Druck-Antwort (Squish): Zieldruck + Dauer der Druckphase.
const SQUISH_SCALE := 0.94
const SQUISH_S := 0.12
## Blatt-Einflug/-Abgang: Dauer + Einfahr-Offset in Design-px (×f skalieren).
const BLATT_S := 0.28
const BLATT_OFFSET := 24.0
## Listen-Staffelung: Versatz zwischen zwei Elementen.
const STAGGER_S := 0.04
## Zähler (Count-Up).
const COUNT_S := 0.6
## Stempel-Landung (Album „gefunden!“, Codes „eingelöst“).
const STEMPEL_S := 0.32
const STEMPEL_START_SCALE := 1.6
const STEMPEL_START_DEG := -8.0
## Papier-Puff: Flöckchen-Zahl, Dauer, Flöckchen-Kante in Design-px.
const PUFF_TEILE := 6
const PUFF_S := 0.45
const PUFF_KANTE := 7.0
## Wert-Puls (Stat ändert sich spürbar).
const PULS_SCALE := 1.03
const PULS_S := 0.18


## Reduced-Motion-Zustand (statisch-sicher, ohne Autoload false).
static func reduced(node: Node) -> bool:
	return ThemeService.is_reduced_motion(node)


## Auftritt: Scale 0.9 → 1.04 → 1.0 (Back-Out-Feder) + schneller Fade.
static func pop_in(ctl: Control, dur := POP_S) -> Tween:
	if not ctl.is_inside_tree():
		return null
	if reduced(ctl):
		ctl.scale = Vector2.ONE
		ctl.modulate.a = 1.0
		return null
	ctl.pivot_offset = ctl.size / 2.0
	ctl.scale = Vector2.ONE * 0.9
	ctl.modulate.a = 0.0
	var tween := ctl.create_tween()
	tween.set_parallel()
	tween.tween_property(ctl, "modulate:a", 1.0, dur * 0.5).set_trans(Tween.TRANS_LINEAR)
	(
		tween
		. tween_property(ctl, "scale", Vector2.ONE * POP_OVERSHOOT, dur * 0.6)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. chain()
		. tween_property(ctl, "scale", Vector2.ONE, dur * 0.4)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	return tween


## Druck-Antwort für Nicht-Buttons (Karten, Kapseln): kurzer 0.94-Druck,
## federnd zurück (SquishButton bleibt der Weg für echte Buttons).
static func squish(ctl: Control) -> Tween:
	if not ctl.is_inside_tree() or reduced(ctl):
		ctl.scale = Vector2.ONE
		return null
	ctl.pivot_offset = ctl.size / 2.0
	var tween := _fresh_tween(ctl, &"_mk_squish")
	(
		tween
		. tween_property(ctl, "scale", Vector2.ONE * SQUISH_SCALE, SQUISH_S)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(ctl, "scale", Vector2.ONE, SQUISH_S * 1.5)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	return tween


## Blatt-Einflug (Sheets/Karten): von +offset (Design-px — Aufrufer skaliert
## mit f) federleicht in die Ruhelage, Quint-Out + Fade.
static func blatt_slide_in(ctl: Control, offset := BLATT_OFFSET) -> Tween:
	if not ctl.is_inside_tree():
		return null
	if reduced(ctl):
		ctl.modulate.a = 1.0
		return null
	var rest_y := ctl.position.y
	ctl.position.y = rest_y + offset
	ctl.modulate.a = 0.0
	var tween := ctl.create_tween()
	tween.set_parallel()
	tween.tween_property(ctl, "position:y", rest_y, BLATT_S).set_trans(Tween.TRANS_QUINT).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(ctl, "modulate:a", 1.0, BLATT_S * 0.5).set_trans(Tween.TRANS_LINEAR)
	return tween


## Blatt-Abgang: zur Kante gleiten + ausblenden. Der Aufrufer awaitet
## `tween.finished` und versteckt/entfernt das Blatt selbst (Position wird
## NICHT zurückgesetzt). Reduced Motion: sofort unsichtbar, null zurück.
static func blatt_slide_out(ctl: Control, offset := BLATT_OFFSET) -> Tween:
	if not ctl.is_inside_tree() or reduced(ctl):
		ctl.modulate.a = 0.0
		return null
	var tween := ctl.create_tween()
	tween.set_parallel()
	(
		tween
		. tween_property(ctl, "position:y", ctl.position.y + offset, BLATT_S)
		. set_trans(Tween.TRANS_QUINT)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(ctl, "modulate:a", 0.0, BLATT_S * 0.7).set_trans(Tween.TRANS_LINEAR)
	return tween


## Gestaffeltes Einblenden für Listen/Gruppen: EIN Sequenz-Tween, jedes
## Element federt nach `step` Sekunden Versatz auf (pop_in). Reduced Motion:
## alles sofort sichtbar, keine Bewegung.
static func stagger_ein(ctls: Array, step := STAGGER_S) -> void:
	if ctls.is_empty():
		return
	var first := ctls[0] as Control
	if first == null or not first.is_inside_tree() or reduced(first):
		for ctl: Control in ctls:
			ctl.modulate.a = 1.0
		return
	for ctl: Control in ctls:
		ctl.modulate.a = 0.0
	var tween := first.create_tween()
	for ctl: Control in ctls:
		tween.tween_callback(_stagger_pop.bind(ctl))
		tween.tween_interval(step)


## Zähler zählt hoch statt zu springen (Ergebnis-Zeilen, Münzen).
## `formatter` bekommt den gerundeten int und liefert den Label-Text.
static func count_up(label: Label, von: int, bis: int, formatter := Callable()) -> Tween:
	var fmt := formatter if formatter.is_valid() else func(v: int) -> String: return str(v)
	if not label.is_inside_tree() or reduced(label) or von == bis:
		label.text = fmt.call(bis)
		return null
	var tween := label.create_tween()
	(
		tween
		. tween_method(
			func(v: float) -> void: label.text = fmt.call(int(roundf(v))),
			float(von),
			float(bis),
			COUNT_S
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	return tween


## Stempel-Landung: groß und leicht verdreht rein, federnd auf 1.0/0°
## (Album „gefunden!“, Codes „eingelöst“, Quest-Häkchen).
static func stempel(ctl: Control) -> Tween:
	if not ctl.is_inside_tree() or reduced(ctl):
		ctl.scale = Vector2.ONE
		ctl.rotation = 0.0
		ctl.modulate.a = 1.0
		return null
	ctl.pivot_offset = ctl.size / 2.0
	ctl.scale = Vector2.ONE * STEMPEL_START_SCALE
	ctl.rotation = deg_to_rad(STEMPEL_START_DEG)
	ctl.modulate.a = 0.0
	var tween := ctl.create_tween()
	tween.set_parallel()
	tween.tween_property(ctl, "modulate:a", 1.0, STEMPEL_S * 0.3).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(ctl, "scale", Vector2.ONE, STEMPEL_S).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(ctl, "rotation", 0.0, STEMPEL_S).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	return tween


## Papier-Staub-Puff: kleine Papier-Flöckchen (Paper/Paper-Shade) stieben
## radial auseinander und verblassen — der leise ACNH-„Platzier“-Moment.
## RNG injizierbar (Tests); ohne RNG streut ein frischer Generator.
static func papier_puff(
	host: Control, anzahl := PUFF_TEILE, rng: RandomNumberGenerator = null
) -> void:
	if not host.is_inside_tree() or reduced(host):
		return
	var streu := rng
	if streu == null:
		streu = RandomNumberGenerator.new()
		streu.randomize()
	var center := host.size / 2.0
	var radius := maxf(center.length() * 0.8, 20.0)
	var toene: Array[Color] = [AcTokens.PAPER, AcTokens.PAPER_SHADE, AcTokens.WHITE]
	for i in anzahl:
		var flocke := ColorRect.new()
		flocke.color = toene[i % toene.size()]
		flocke.custom_minimum_size = Vector2.ONE * PUFF_KANTE
		flocke.size = Vector2.ONE * PUFF_KANTE
		flocke.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flocke.z_index = 10
		host.add_child(flocke)
		flocke.pivot_offset = Vector2.ONE * (PUFF_KANTE / 2.0)
		flocke.position = center - flocke.pivot_offset
		flocke.rotation = streu.randf_range(-PI, PI)
		var winkel := TAU * (float(i) + streu.randf() * 0.5) / float(anzahl)
		var ziel := center + Vector2.from_angle(winkel) * radius - flocke.pivot_offset
		flocke.scale = Vector2.ONE * 0.4
		var tween := flocke.create_tween()
		tween.set_parallel()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(flocke, "position", ziel, PUFF_S)
		tween.tween_property(flocke, "scale", Vector2.ONE, PUFF_S * 0.4)
		(
			tween
			. tween_property(
				flocke, "rotation", flocke.rotation + streu.randf_range(-1.2, 1.2), PUFF_S
			)
			. set_trans(Tween.TRANS_LINEAR)
		)
		tween.chain().tween_property(flocke, "modulate:a", 0.0, PUFF_S * 0.45)
		tween.chain().tween_callback(flocke.queue_free)


## Sanfter Wert-Puls: 1.0 → 1.03 → 1.0 (Sine) — für Kapseln/Chips, deren
## Wert sich spürbar geändert hat. Anti-Stapeln über _fresh_tween.
static func puls(ctl: Control) -> Tween:
	if not ctl.is_inside_tree() or reduced(ctl):
		ctl.scale = Vector2.ONE
		return null
	ctl.pivot_offset = ctl.size / 2.0
	var tween := _fresh_tween(ctl, &"_mk_puls")
	(
		tween
		. tween_property(ctl, "scale", Vector2.ONE * PULS_SCALE, PULS_S * 0.5)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(ctl, "scale", Vector2.ONE, PULS_S).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
	return tween


## Vorherigen Impuls-Tween desselben Helfers auf ctl killen (Anti-Stapeln —
## Muster aus UiMotion: Serien erzeugten sonst parallele Tweens → Zittern).
static func _fresh_tween(ctl: Control, key: StringName) -> Tween:
	if ctl.has_meta(key):
		var alt: Variant = ctl.get_meta(key)
		if alt is Tween and (alt as Tween).is_valid():
			(alt as Tween).kill()
		ctl.scale = Vector2.ONE
	var tween := ctl.create_tween()
	ctl.set_meta(key, tween)
	return tween


static func _stagger_pop(ctl: Control) -> void:
	if is_instance_valid(ctl) and ctl.is_inside_tree():
		ctl.modulate.a = 1.0
		pop_in(ctl)

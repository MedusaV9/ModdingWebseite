class_name OrtTierarzt
extends OrtScene
## Tierarztpraxis Dr. Dr. Möhrchen (REST-3, Rang 7): betretbarer Ort mit
## Wartezimmer (links: Bänkchen-Kisten, Lesetisch) und Sprechzimmer (rechts:
## Behandlungs-Counter, Wattebausch-Glas, Möhrenvorrat). Der Patient — UNSER
## Gooby — sitzt mit echtem Save-Aussehen (Gewicht + Symptome) auf dem
## Bänkchen. Dr. Dr. Möhrchen ist die Ranch-Figur in Stadt-Praxis (Ton aus
## rnpc moehrchen.json uebernommen).
##
## Ablauf im Dialogbaum (tierarzt.json): Empfang → Untersuchung (kleine
## Sequenz: Möhren-Stethoskop, Temperatur, Ohrenwackel-Test — Toasts +
## Patient niest) → Diagnose → Behandlung (120 Muenzen, Health.pay_vet) ODER
## Rezept (setzt das city-Flag `rezept_tropfen` — der vorhandene
## GOOBYTHEKE-Flow loest es ein) ODER Ruhe → Nachsorge. Check-up 30 Muenzen.
## Die vet_*-Marker-Flags aus dem Baum sind reine Signale an diesen Ort und
## landen NIE im Save (nur rezept_tropfen persistiert, wie beim GOOUHBUS).
## Zu wenig Muenzen ist nie eine Strafe: freundlicher Toast, Dialog geht
## weiter, Gooby wird trotzdem liebgehabt.

const Sleep := preload("res://scripts/logic/sleep.gd")
const Health := preload("res://scripts/logic/health.gd")
const Weight := preload("res://scripts/logic/weight.gd")

const INNEN := "res://assets/city/innen"
const CC0_MOEBEL := "res://assets/models/cc0/kenney_furniture_extra"
const CC0_TIERE := "res://assets/models/cc0/quaternius_animals"
const UNTERSUCHUNG_SCHRITT_S := 1.4

## Roher Footprint (Breite, Tiefe) der Ecke-Ursprung-Wartebank (GLB-AABB).
const GRUND_BANK := Vector2(0.4, 0.2)
## Wartezimmer-Bank in beruhigendem Praxis-Mint.
const TINT_BANK := Color("#BBDFD3")

var _patient: GoobyRig


func _baue_innenraum() -> void:
	# Wartezimmer (links): zwei Bänkchen-Kisten + Lesetisch mit Aushang.
	_prop("%s/table_round_A.gltf" % INNEN, Vector3(-3.2, 0.0, -1.2), 0.0, 0.5)
	_prop("%s/crate.gltf" % INNEN, Vector3(-4.3, 0.0, -2.5), 10.0, 1.4)
	_prop("%s/crate.gltf" % INNEN, Vector3(-2.4, 0.0, -2.7), 350.0, 1.4)
	_prop("%s/menu.gltf" % INNEN, Vector3(-5.0, 0.0, -3.5), 20.0, 1.6)
	# Sprechzimmer (rechts): Counter, Wattebausch-Glas, Möhrenvorrat.
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(3.4, 0.0, -3.2), 0.0, 0.9)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(3.2, 0.9, -3.0), 0.0, 1.2)
	_prop("%s/crate_carrots.gltf" % INNEN, Vector3(4.6, 0.0, -2.2), 30.0, 1.6)
	# J3/CC0: echte Wartebank an der linken Wand + ein wartender
	# Shiba-Patient (Quaternius-Tier, pastellisiert, Idle-Loop) — das
	# Wartezimmer wirkt endlich wie eines.
	var bank := _cc0(
		"%s/bench_cushion.glb" % CC0_MOEBEL, Vector3(-5.6, 0.0, -1.4), -90.0, 2.0, GRUND_BANK
	)
	OrtRequisiten.tinte(bank, TINT_BANK, 0.4)
	var hund := _prop("%s/shiba_inu.glb" % CC0_TIERE, Vector3(-1.5, 0.0, -2.3), 145.0, 0.18)
	OrtRequisiten.pastellisiere(hund)
	OrtRequisiten.spiele_idle(hund)
	_baue_patient()


## J3: Ambient-Leben — 2 wartende Besucher tigern durchs Wartezimmer
## (keine Kasse: Praxis, kein Laden — bezahlt wird im Dialog).
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 2,
		"punkte":
		[
			Vector3(-4.6, 0.0, -0.4),
			Vector3(-2.8, 0.0, 0.8),
			Vector3(-1.2, 0.0, 0.2),
			Vector3(-3.8, 0.0, 1.6),
		],
		"sprueche": "tierarzt",
		"blick": Vector3(-3.2, 0.0, -4.0),
		"gemurmel": false,
		"tuer_glocke": true,
		"kasse": false,
	}


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/tierarzt.json"


func _npc_konfig() -> Dictionary:
	# Möhrchen-Orange wie die Ranch-Figur; steht im Sprechzimmer.
	return {"tint": Color("#E8A24A"), "emotion": "happy", "pos": Vector3(1.6, 0.0, -2.2)}


## Unser Gooby als Patient: sitzt im Wartezimmer, traegt sein ECHTES
## Save-Aussehen (Gewichts-Silhouette + Krankheits-Symptome, REST-3-Optik).
func _baue_patient() -> void:
	_patient = GoobyRig.new()
	_patient.name = "Patient"
	_patient.position = Vector3(-1.2, 0.0, -1.5)
	_patient.rotation.y = 0.6
	add_child(_patient)
	_patient_look_auffrischen()
	_patient.play_clip.call_deferred("sit")


func _patient_look_auffrischen() -> void:
	if _patient == null:
		return
	var slice := _gooby_slice()
	_patient.set_weight(Weight.clamp_weight(slice.get("weight", Weight.DEFAULT)))
	var grade := Health.grade(slice.get("health"))
	_patient.set_care(grade, Sleep.tiredness01(slice.get("stats")))
	_patient.set_emotion("sad" if grade >= 1 else "happy")


## Dialog mit LIVE-Zustandsflags starten: gesund/krank/schwer_krank kommen
## aus dem health-Slice, die persistenten city-Flags (rezept_tropfen) bleiben
## wie in der Basisklasse dabei.
func _starte_dialog() -> void:
	var pfad := _dialog_pfad()
	if pfad.is_empty():
		return
	var baum := OrtDialogRunner.baum_laden(pfad)
	dialog.starte(baum, _dialog_flags())


func _dialog_flags() -> Dictionary:
	var flags: Dictionary = {}
	var gs := game_state()
	if gs != null:
		var raw: Variant = gs.get_value("city.flags", {})
		if raw is Dictionary:
			flags = raw.duplicate(true)
	var grade := Health.grade(_gooby_slice().get("health"))
	flags["gesund"] = grade == 0
	flags["krank"] = grade == 1
	flags["schwer_krank"] = grade >= 2
	return flags


## vet_*-Marker abfangen (Untersuchung/Behandlung/Check-up/Rezept-Toast) —
## alles andere (auch flag:rezept_tropfen) macht die Basisklasse.
func _on_dialog_effekt(daten: Dictionary) -> void:
	if str(daten.get("typ", "")) == "flag":
		match str(daten.get("name", "")):
			"vet_untersuchung":
				_untersuchung_sequenz()
				return
			"vet_cure":
				_bezahle("cure")
				return
			"vet_checkup":
				_bezahle("checkup")
				return
			"vet_rezept":
				AudioDirector.try_play(self, "ui_confirm")
				zeige_toast(I18nService.t("vet.rezept_ok"))
				return
	super._on_dialog_effekt(daten)


## Kleine Untersuchungs-Sequenz parallel zum Dialogtext: drei Befund-Toasts
## im Takt, der Patient niest (falls krank), der Doktor schaut erst streng,
## dann zufrieden.
func _untersuchung_sequenz() -> void:
	zeige_toast(I18nService.t("vet.untersuchung.horchen"))
	if rig != null:
		rig.set_emotion("neutral")
	if _patient != null and Health.grade(_gooby_slice().get("health")) >= 1:
		_patient.sneeze()
		AudioDirector.try_play(self, "pet_squish", 1.55)
	if not is_inside_tree():
		return
	await get_tree().create_timer(UNTERSUCHUNG_SCHRITT_S).timeout
	zeige_toast(I18nService.t("vet.untersuchung.temperatur"))
	if not is_inside_tree():
		return
	await get_tree().create_timer(UNTERSUCHUNG_SCHRITT_S).timeout
	zeige_toast(I18nService.t("vet.untersuchung.ohren"))
	if rig != null:
		rig.set_emotion("happy")


## Behandlung (cure, 120 c: Vollheilung + Stat-Bonus) oder Check-up (30 c:
## Druck-Zaehler-Reset) bezahlen — Web-payVet via Health.pay_vet. Zu wenig
## Muenzen oder schon gesund: nur ein freundlicher Toast, nie eine Strafe.
func _bezahle(kind: String) -> void:
	var gs := game_state()
	if gs == null:
		return
	var res := {"r": {}}
	var now := _now_ms()
	gs.update(func(state: Dictionary) -> void: res["r"] = Health.pay_vet(state, kind, now))
	var r: Dictionary = res["r"]
	if bool(r.get("ok", false)):
		AudioDirector.try_play(self, "ui_coins")
		var key := "vet.behandlung_ok" if kind == "cure" else "vet.checkup_ok"
		zeige_toast(I18nService.t(key))
		_patient_look_auffrischen()
	elif str(r.get("reason", "")) == "coins":
		zeige_toast(I18nService.t("vet.zu_wenig"))
	elif str(r.get("reason", "")) == "healthy":
		zeige_toast(I18nService.t("vet.behandlung_gesund"))


func _gooby_slice() -> Dictionary:
	var gs := game_state()
	if gs == null or not gs.has_method("state"):
		return {}
	var raw: Variant = (gs.state() as Dictionary).get("gooby")
	return raw if raw is Dictionary else {}


func _now_ms() -> int:
	var gs := game_state()
	if gs != null and gs.get("clock") != null:
		return gs.clock.now_ms()
	return int(Time.get_unix_time_from_system() * 1000.0)

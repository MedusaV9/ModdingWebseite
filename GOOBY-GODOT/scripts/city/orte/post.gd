class_name OrtPost
extends OrtScene
## Post (Doc E §2.3, Doc C §3.7): Schalter-Halle mit Frau Zettel hinter der
## Scheibe, Paketberg im Hintergrund. FERTIG-1: statt des gestrichenen
## Multiplayer-Versand-Hooks gibt es hier das echte TAGESPAKET (PostLogic).
## W13B: daneben steht jetzt der echte BRIEF-Schalter (Post/Mail-Multiplayer,
## MailSheet) — Briefe + Fotos + Item-Geschenke an Freunde, offline-first
## über die NetMail-Outbox. Das Tagespaket (PostSheet/PostLogic) bleibt
## unverändert.
## G3/P07: Ungelesen-Zähler als StatusCapsule-Badge in der Kopfzeile
## (statt Knopftext-Anhang), Schalter-Knopf auf SquishButton + Touch-Floor.
## G8-P1 „Jeder Ort lebt“ (PT2-B4): kleine Paket-Schlange vor dem Schalter
## (Paket-Requisiten), Frau Zettel stempelt im Kassen-Takt, dazu die
## Momente Stempel-KLACK und Paket-Abholung.

const INNEN := "res://assets/city/innen"
const MOEBEL := "res://assets/furniture"

var _ungelesen_badge: PanelContainer


func _baue_innenraum() -> void:
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(-0.4, 0.0, -1.3), 90.0, 0.95)
	_prop("%s/kitchencounter_sink.gltf" % INNEN, Vector3(1.6, 0.0, -1.3), 90.0, 0.95)
	_prop("%s/bookcaseClosedWide.glb" % MOEBEL, Vector3(-4.4, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/bookcaseClosedWide.glb" % MOEBEL, Vector3(4.4, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/deko/box_A.gltf" % MOEBEL, Vector3(3.2, 0.0, -0.4), 14.0, 1.5)
	_prop("%s/deko/box_B.gltf" % MOEBEL, Vector3(3.6, 0.0, 0.9), -9.0, 1.5)
	_prop("%s/deko/box_A.gltf" % MOEBEL, Vector3(-3.5, 0.0, 0.7), 27.0, 1.5)
	_prop("%s/coatRackStanding.glb" % MOEBEL, Vector3(-5.6, 0.0, -0.6), 0.0, 1.1)
	_prop("%s/pottedPlant.glb" % MOEBEL, Vector3(5.6, 0.0, -0.4), 0.0, 1.1)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/post.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#FFD166"), "emotion": "happy", "pos": Vector3(-0.4, 0.0, -2.4)}


## G8-P1: Schalterhallen-Leben — die Paket-Schlange rückt vor dem Schalter
## vor (Trage-Requisit „paket“), dazu Abhol-Stopps am Paketberg. Frau
## Zettel tippt/stempelt im Kassen-Takt (KassenNpc). Momente: Stempel-
## KLACK (door_knock hochgestimmt = trockener Gummistempel) und die
## Paket-Abholung mit Freuden-Hopser.
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 3,
		# Schlangen-Punkte bleiben bei z ≤ 1,2 — tiefer würde die Schlange
		# als Vordergrund-Riese vor der Ort-Kamera (z 4,2) hängen.
		"punkte":
		[
			Vector3(-0.5, 0.0, 0.05),
			Vector3(-0.35, 0.0, 0.65),
			Vector3(0.0, 0.0, 1.2),
			Vector3(2.7, 0.0, 0.1),
			Vector3(-2.5, 0.0, 0.7),
		],
		"requisit": "paket",
		"sprueche": "post",
		"blick": Vector3(-0.4, 0.0, -2.4),
		"gemurmel": true,
		"tuer_glocke": true,
		"kasse": true,
		"momente":
		[
			{
				"alle_s": 17.0,
				"versatz_s": 5.0,
				"sound": "door_knock",
				"pitch": 1.45,
				"clip": "idle_lookaround",
				"sprueche": "post_stempel",
			},
			{
				"alle_s": 26.0,
				"versatz_s": 14.0,
				"sound": "gvz_collect",
				"pitch": 0.9,
				"clip": "celebrate",
				"sprueche": "post_paket",
			},
		],
	}


## Post hat ein eigenes Schalter-UI: Tagespaket + Postkarten-Archiv (PostSheet,
## unverändert) und daneben der neue Brief-Schalter (W13B).
func oeffne_laden() -> void:
	var inhalt := VBoxContainer.new()
	inhalt.add_theme_constant_override("separation", 12)
	var paket := PostSheet.new()
	paket.gs = game_state()
	paket.schalter_gewaehlt.connect(_on_schalter)
	inhalt.add_child(paket)
	inhalt.add_child(_baue_briefe_schalter())
	zeige_sheet(I18nService.t("city.post.sheet_titel"), inhalt)


func _on_schalter(_schalter: String) -> void:
	if rig != null:
		rig.play_clip("wave")


## Brief-Schalter-Karte: Kopfzeile mit StatusCapsule-Ungelesen-Badge,
## Knopf zum Briefkasten plus Offline-/Outbox-Hinweis. Ohne /root/Net
## (z. B. Tests) bleibt der Knopf stehen und meldet ehrlich Offline.
func _baue_briefe_schalter() -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.name = "BriefeSchalter"
	var karte := CitySheetBausteine.karte(wrapper)
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 8)
	karte.add_child(kopf)
	var titel := Label.new()
	titel.text = I18nService.t("mail.schalter.titel")
	titel.theme_type_variation = "HeadlineLabel"
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(titel)
	_ungelesen_badge = baue_ungelesen_badge(_briefe_ungelesen())
	kopf.add_child(_ungelesen_badge)
	CitySheetBausteine.label(karte, I18nService.t("mail.schalter.text"), "CaptionLabel")
	var status := _briefe_status_text()
	if not status.is_empty():
		CitySheetBausteine.label(karte, status, "CaptionLabel")
	# Öffnet das MailSheet-Overlay — das klingt selbst (ui_open), der Knopf
	# bleibt deshalb stumm (§3-Grammatik: kein Doppel-Klang).
	var knopf := SquishButton.new()
	knopf.name = "BriefeOeffnen"
	knopf.theme_type_variation = "AccentButton"
	knopf.text = I18nService.t("mail.schalter.offen")
	knopf.pressed.connect(_on_briefe_oeffnen)
	if is_inside_tree():
		ScreenShell.touch_target(knopf, ScreenShell.metrics(get_viewport()))
	karte.add_child(knopf)
	return wrapper


## G3/P07: Ungelesen-Badge als StatusCapsule — pur baubar, direkt testbar.
static func baue_ungelesen_badge(n: int) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "UngelesenBadge"
	badge.theme_type_variation = &"StatusCapsule"
	var label := Label.new()
	label.name = "Zahl"
	label.theme_type_variation = &"CaptionLabel"
	badge.add_child(label)
	setze_ungelesen_badge(badge, n)
	return badge


## Badge-Stand nachziehen (0 = unsichtbar statt „0 neu“).
static func setze_ungelesen_badge(badge: PanelContainer, n: int) -> void:
	badge.visible = n > 0
	var label := badge.get_node_or_null("Zahl") as Label
	if label != null:
		label.text = I18nService.t("mail.schalter.neu", {"n": n})


func _briefe_ungelesen() -> int:
	var net := get_node_or_null("/root/Net")
	if net == null:
		return 0
	var service := NetMail.attach(net)
	return service.unread if service != null else 0


## Offline-Chip + Outbox-Hinweis („wird zugestellt, sobald du online bist“).
func _briefe_status_text() -> String:
	var net := get_node_or_null("/root/Net")
	if net == null:
		return I18nService.t("mail.schalter.offline")
	var service := NetMail.attach(net)
	var teile := PackedStringArray()
	if not (net.has_method("is_online") and net.is_online()):
		teile.append(I18nService.t("mail.schalter.offline"))
	if service != null and service.outbox_count() > 0:
		teile.append(I18nService.t("mail.schalter.outbox", {"n": service.outbox_count()}))
	return " · ".join(teile)


func _on_briefe_oeffnen() -> void:
	if rig != null:
		rig.play_clip("wave")
	var sheet := MailSheet.new()
	sheet.setup(get_node_or_null("/root/Net"), game_state())
	sheet.toast_requested.connect(zeige_toast)
	sheet.unread_changed.connect(_on_unread_changed)
	_ui.add_child(sheet)


## Das Badge lebt hinter dem offenen Briefkasten weiter — Stand mitziehen,
## damit es nach dem Schließen nicht veraltet dasteht (G3/P07).
func _on_unread_changed(unread: int) -> void:
	if _ungelesen_badge != null and is_instance_valid(_ungelesen_badge):
		OrtPost.setze_ungelesen_badge(_ungelesen_badge, unread)

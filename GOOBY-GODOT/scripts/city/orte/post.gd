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
## J3 „Läden lebendig 2“: Ambient-Kundschaft + Schalter-Verhalten für Frau
## Zettel, dazu ein CC0-Paketberg und der Schalter-Bildschirm.

const INNEN := "res://assets/city/innen"
const MOEBEL := "res://assets/furniture"
const CC0_MOEBEL := "res://assets/models/cc0/kenney_furniture_extra"

## Rohe Footprints (Breite, Tiefe) der Ecke-Ursprung-Möbel laut GLB-AABB.
const GRUND_KARTON := Vector2(0.212, 0.212)
const GRUND_KARTON_OFFEN := Vector2(0.372, 0.212)
const GRUND_SCREEN := Vector2(0.393, 0.104)

## Schalter-Tech in kühlem Grau-Blau (Muster GooUndBye-Kasse).
const TINT_TECH := Color("#9FB4C7")

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
	# J3/CC0: Paketberg hinter dem Schalter (Karton-Stapel, Warenausgang)
	# + Schalter-Bildschirm auf der Counter-Platte (~0,9 m, s. gouhbus-Glas).
	_cc0(
		"%s/cardboard_box_closed.glb" % CC0_MOEBEL,
		Vector3(-2.2, 0.0, -3.4),
		10.0,
		1.9,
		GRUND_KARTON
	)
	_cc0(
		"%s/cardboard_box_closed.glb" % CC0_MOEBEL,
		Vector3(-2.15, 0.534, -3.35),
		38.0,
		1.9,
		GRUND_KARTON
	)
	_cc0(
		"%s/cardboard_box_open.glb" % CC0_MOEBEL,
		Vector3(-1.4, 0.0, -3.2),
		-14.0,
		1.9,
		GRUND_KARTON_OFFEN
	)
	var screen := _cc0(
		"%s/computer_screen.glb" % CC0_MOEBEL, Vector3(-0.35, 0.9, -1.0), 180.0, 1.25, GRUND_SCREEN
	)
	OrtRequisiten.tinte(screen, TINT_TECH, 0.4)


## J3: Ambient-Leben — 2 Kundschaften mit Paketen unterwegs, Frau Zettel
## tippt am Schalter (Kassen-Verhalten).
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 2,
		"punkte":
		[
			Vector3(-3.0, 0.0, -0.4),
			Vector3(-1.0, 0.0, 1.2),
			Vector3(2.2, 0.0, -0.3),
			Vector3(1.0, 0.0, 1.8),
		],
		"sprueche": "post",
		"blick": Vector3(0.0, 0.0, -4.0),
		"gemurmel": false,
		"tuer_glocke": true,
		"kasse": true,
	}


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/post.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#FFD166"), "emotion": "happy", "pos": Vector3(-0.4, 0.0, -2.4)}


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


## W18/B7: das MailSheet mountet über `zeige_overlay()` ÜBER dem offenen
## Schalter-Sheet (vorher hing es in `_ui` und damit HINTER dem Sheet —
## alle Taps landeten im Schalter, der Brief-Loop war unbenutzbar).
func _on_briefe_oeffnen() -> void:
	if rig != null:
		rig.play_clip("wave")
	var sheet := MailSheet.new()
	sheet.setup(get_node_or_null("/root/Net"), game_state())
	sheet.toast_requested.connect(zeige_toast)
	sheet.unread_changed.connect(_on_unread_changed)
	zeige_overlay(sheet)


## Das Badge lebt hinter dem offenen Briefkasten weiter — Stand mitziehen,
## damit es nach dem Schließen nicht veraltet dasteht (G3/P07).
func _on_unread_changed(unread: int) -> void:
	if _ungelesen_badge != null and is_instance_valid(_ungelesen_badge):
		OrtPost.setze_ungelesen_badge(_ungelesen_badge, unread)

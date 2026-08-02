class_name DlcLoadingKarten
extends RefCounted
## G6/DLC-LOAD — Daten-Zuordnung Ort → DLC-Ladekarte (PURE, ueberall aufrufbar).
##
## Jeder DLC bekommt beim Betreten UND auf dem Rueckweg seine eigene
## Ladebildschirm-Identitaet — aber im ETABLIERTEN Karten-Look (W16/VEIL:
## Cover-Zone, huepfender Sticker, Teal-Balken, Tipps). Es gibt bewusst
## KEINEN Fork des Veil-Systems: diese Klasse liefert nur DATEN (Cover,
## Motiv-Sticker, Farbstimmung des Fallback-Verlaufs, I18n-Keys), das
## LoadingVeil tauscht damit Motiv/Texte und sonst nichts. Der
## Blueten-Wipe, der Karten-Pop-in und alle FROZEN-Vertraege bleiben.
##
## Regeln:
## - Betreten schlaegt Rueckweg: Ziel-DLC gewinnt vor Herkunfts-DLC.
## - Unbekannte Ziele/Herkuenfte → "" → die Standard-Karte (home/trip/game)
##   bleibt unangetastet (Fallback per Test abgesichert).
## - Der Minigame-Travel-Hint und der grosse Ranch-Vollbildschirm
##   (LoadingScreenRules.ist_lange_reise) behalten Vorrang — die Weiche
##   dafuer sitzt wie bisher in loading_veil.gd.
##
## Cover: die bestehenden DLC-Hub-Coverarts (assets/dlc/, W14/DLCHUB) —
## Stil-Konsistenz vor Neuartigkeit, und die Ladekarte traegt dieselbe
## Identitaet wie die Hub-Karte. Motiv-Sticker: eigene runde Motive im
## Stil der Bestands-Sticker (assets/acui/motif_*.png). Fehlt ein Bild,
## greift wie im Web der onerror-Fallback (Verlauf bzw. Winke-Gooby).

## DLC-Id → Karten-Profil. `praefixe`/`ziele` matchen SceneRouter-Targets
## (Praefix-Logik wie LoadingVeil.TRIP_PRAEFIXE). `farben` ist die
## Farbstimmung des Cover-Fallback-Verlaufs (3 Stops wie im Web, 155°).
const PROFILE := {
	"ranch":
	{
		"praefixe": ["ranch/"],
		"ziele": [],
		"cover": "res://assets/dlc/ranch.png",
		"motiv": "res://assets/acui/motif_ranch_heu.png",
		"farben": ["#FFF7E6", "#FFE2AC", "#E0AC6A"],
	},
	"goobye":
	{
		"praefixe": ["dlc/goobye"],
		"ziele": [],
		"cover": "res://assets/dlc/goo_und_bye.png",
		"motiv": "res://assets/acui/motif_goobye_korb.png",
		"farben": ["#F1FBF6", "#CFEEE2", "#8FD6C0"],
	},
	"mcgooby":
	{
		"praefixe": ["mcgooby", "dlc/mcgooby"],
		"ziele": [],
		"cover": "res://assets/dlc/mcgooby.png",
		"motiv": "res://assets/acui/motif_mcgooby_burger.png",
		"farben": ["#FFF8E5", "#FFE9A9", "#F6C34E"],
	},
}


## DLC-Id eines Router-Ziels ("" = kein DLC-Ort). Praefixe matchen exakt
## oder als Wortanfang — der DLC-Hub selbst (Ziel `dlc`) ist KEIN DLC-Ort.
static func dlc_fuer_ziel(target: StringName) -> String:
	var ziel := String(target)
	if ziel.is_empty():
		return ""
	for id: String in PROFILE:
		var profil: Dictionary = PROFILE[id]
		var ziele: Array = profil.get("ziele", [])
		if ziele.has(ziel):
			return id
		for praefix: String in profil.get("praefixe", []):
			if ziel == praefix or ziel.begins_with(praefix):
				return id
	return ""


## DIE Zuordnung: welche DLC-Karte zeigt die Reise `herkunft` → `ziel`?
## Betreten (Ziel ist DLC) schlaegt Rueckweg (Herkunft ist DLC); "" = keine.
static func karten_id_fuer(ziel: StringName, herkunft: StringName = StringName()) -> String:
	var betreten := dlc_fuer_ziel(ziel)
	if not betreten.is_empty():
		return betreten
	return dlc_fuer_ziel(herkunft)


## true = die Reise BETRITT den DLC (steuert Titel-/Bereit-Zeile).
static func ist_betreten(ziel: StringName) -> bool:
	return not dlc_fuer_ziel(ziel).is_empty()


## Cover-Pfad einer DLC-Id ("" = unbekannt → Standard-Cover).
static func cover_pfad(id: String) -> String:
	return str(_profil(id).get("cover", ""))


## Motiv-Sticker-Pfad einer DLC-Id ("" = unbekannt → Winke-Gooby).
static func motiv_pfad(id: String) -> String:
	return str(_profil(id).get("motiv", ""))


## Farbstimmung des Cover-Fallback-Verlaufs ([] = Standard-Web-Verlauf).
static func fallback_farben(id: String) -> Array[Color]:
	var farben: Array[Color] = []
	for hex: Variant in _profil(id).get("farben", []):
		farben.append(Color(str(hex)))
	return farben


## I18n-Key des Tipp-Pools (strings/*/veil.json, je 6+ Sprueche).
static func tips_key(id: String) -> String:
	return "veil.dlc.%s.tips" % id


## I18n-Key der Titel-Zeile (Betreten bzw. Rueckweg).
static func titel_key(id: String, betreten: bool) -> String:
	return "veil.dlc.%s.%s" % [id, "titel" if betreten else "titel_zurueck"]


## I18n-Key der weissen Ready-Zeile in der Cover-Zone.
static func bereit_key(id: String, betreten: bool) -> String:
	return "veil.dlc.%s.%s" % [id, "bereit" if betreten else "bereit_zurueck"]


static func _profil(id: String) -> Dictionary:
	var profil: Variant = PROFILE.get(id, {})
	return profil if profil is Dictionary else {}

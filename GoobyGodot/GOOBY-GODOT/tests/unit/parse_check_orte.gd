extends SceneTree
## Temporärer Lade-Check (ORTE) — kein Test, wird nach dem Lauf gelöscht.

const PFADE: Array[String] = [
	"res://scripts/city/orte/pow.gd",
	"res://scripts/city/orte/post.gd",
	"res://scripts/city/orte/autohaus.gd",
	"res://scripts/city/orte/baumarkt.gd",
	"res://scripts/city/orte/wochenmarkt.gd",
	"res://scripts/city/orte/ort_katalog.gd",
	"res://scripts/city/orte/pow_angebote.gd",
	"res://scripts/city/orte/auto_katalog.gd",
	"res://scripts/city/orte/baumarkt_katalog.gd",
	"res://scripts/city/orte/markt_preise.gd",
	"res://scripts/city/ui/sheet_bausteine.gd",
	"res://scripts/city/ui/pow_sheet.gd",
	"res://scripts/city/ui/post_sheet.gd",
	"res://scripts/city/ui/autohaus_sheet.gd",
	"res://scripts/city/ui/baumarkt_sheet.gd",
	"res://scripts/city/ui/markt_sheet.gd",
	"res://scripts/city/phone/phone_apps.gd",
	"res://scripts/city/phone/fahrdienst.gd",
	"res://scripts/city/phone/fahrdienst_app.gd",
	"res://scripts/city/phone/foto_modus.gd",
	"res://scripts/city/phone/kamera_app.gd",
	"res://scripts/city/phone/social_apps.gd",
	"res://scripts/city/phone/phone_shell.gd",
	"res://scenes/city/orte/pow.tscn",
	"res://scenes/city/orte/post.tscn",
	"res://scenes/city/orte/autohaus.tscn",
	"res://scenes/city/orte/baumarkt.tscn",
	"res://scenes/city/orte/wochenmarkt.tscn",
]


func _init() -> void:
	var fehler := 0
	for pfad in PFADE:
		var res: Resource = load(pfad)
		if res == null:
			print("LADEFEHLER: %s" % pfad)
			fehler += 1
	print("geprueft: %d, fehler: %d" % [PFADE.size(), fehler])
	quit(1 if fehler > 0 else 0)

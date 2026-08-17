class_name CosmeticBuilders
extends RefCounted
## Ein Item-Def → ein fertiger Mesh-Baum (CONTENT-A).
##
## Die Katalog-Definition nennt nur eine Builder-Id (`build`) plus Farben und
## Parameter — der Rest ist Geometrie aus `CosmeticParts`. Dadurch kann der
## Auto-Updater neue Cosmetics als reine JSON-Daten nachliefern, solange sie
## eine BEKANNTE Builder-Id benutzen: kein App-Update, kein Asset-Download.
##
## Unbekannte Builder-Ids bekommen einen neutralen Platzhalter-Würfel statt
## eines Absturzes; `bekannt()` sagt Tests, was ohne Platzhalter geht.
##
## Fell ist KEIN Mesh — es färbt die Palette-Textur des Rigs um und läuft
## deshalb über `CosmeticAttach.apply_fell()`, nicht hierüber.

## Alle Builder-Ids, die gebaut werden können (Kategorie → Ids).
const REGISTER := {
	"hut":
	[
		"kegel",
		"kappe",
		"zylinder",
		"krone",
		"chefhut",
		"kranz",
		"dreispitz",
		"helm",
		"kuerbis",
		"torte",
		"ananas",
	],
	"brille": ["brille", "goggles", "monokel", "augenklappe", "scherzbrille", "visier"],
	"hals": ["schal", "fliege", "tuch", "halsband", "umhang", "krawatte", "kragen", "kopfhoerer"],
	"ruecken":
	[
		"rucksack",
		"ballon",
		"propeller",
		"panzer",
		"fluegel",
		"brett",
		"jetpack",
		"schirm",
		"rueckenschleife",
		"schwert",
		"gitarre",
	],
	"fell": ["fell"],
}


## Baut das Item aus seiner normalisierten Katalog-Def. Gibt `null` zurück,
## wenn das Item gar kein Mesh hat (Fell).
static func build(def: Dictionary) -> Node3D:
	if def.is_empty():
		return null
	var kategorie := str(def.get("kategorie", ""))
	if kategorie == CosmeticsCatalog.FELL:
		return null
	var build_id := str(def.get("build", ""))
	var node: Node3D = null
	match kategorie:
		"hut":
			node = HutBuilders.build(build_id, def)
		"brille":
			node = BrilleBuilders.build(build_id, def)
		"hals":
			node = HalsBuilders.build(build_id, def)
		"ruecken":
			node = RueckenBuilders.build(build_id, def)
	if node == null:
		node = _platzhalter(def)
	node.name = str(def.get("id", "cosmetic"))
	return node


## Item-Id direkt bauen (Bequemlichkeit für Vorschauen).
static func build_id(id: String) -> Node3D:
	return build(CosmeticsCatalog.by_id(id))


## Kennt der Dispatcher diese Builder-Id in dieser Kategorie?
static func bekannt(kategorie: String, build_id_name: String) -> bool:
	var ids: Variant = REGISTER.get(kategorie, [])
	return ids is Array and (ids as Array).has(build_id_name)


## Alle Katalog-Items, deren Builder-Id niemand kennt (Test-Wächter: ein Pack
## darf keine Fantasie-Builder mitbringen, die als graue Würfel enden).
static func unbekannte_builds() -> Array:
	var out: Array = []
	for def: Dictionary in CosmeticsCatalog.all():
		if not bekannt(str(def["kategorie"]), str(def["build"])):
			out.append("%s (%s/%s)" % [def["id"], def["kategorie"], def["build"]])
	return out


## Neutraler Würfel in der ersten Item-Farbe — sichtbar falsch, aber harmlos.
static func _platzhalter(def: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Platzhalter"
	CosmeticParts.box(
		wurzel, Vector3(0.16, 0.16, 0.16), CosmeticParts.farbe_von(def, 0, Color("#C9C4BC"))
	)
	return wurzel

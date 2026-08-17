extends RefCounted
## W1d-Testhelfer: numerisch tolerantes Deep-Equal fuer State-Vergleiche.
##
## WARUM: Godots Dictionary/Array-`==` ist TYP-strikt (int 3 != float 3.0),
## JSON.parse liefert aber ALLE Zahlen als float — und JS (die Quelle der
## Fixtures/Goldwerte) kennt ohnehin nur double. Fuer die Vergleiche
## "Web-Fixture vs GDScript-Ergebnis" und "State vs Datei-Roundtrip" gilt
## deshalb die JS-Zahlensemantik: gleich ist, was denselben WERT hat.
## (Kein test_-Prefix: der W1a-Runner soll diese Datei nicht entdecken.)

## Relative Toleranz fuer float-Leaves (Web rechnet double, GDScript auch;
## Abweichungen entstehen nur durch Operationsreihenfolge, Groessenordnung ULP).
const EPS := 1e-9


static func deep_equal(a: Variant, b: Variant) -> bool:
	return first_diff(a, b).is_empty()


## "" == gleich; sonst Pfad + Werte der ersten Abweichung (fuer Assert-Text).
static func first_diff(a: Variant, b: Variant, path := "$") -> String:
	if a is Dictionary and b is Dictionary:
		for k: Variant in a.keys():
			if not b.has(k):
				return "%s.%s fehlt rechts" % [path, str(k)]
			var sub := first_diff(a[k], b[k], "%s.%s" % [path, str(k)])
			if not sub.is_empty():
				return sub
		for k: Variant in b.keys():
			if not a.has(k):
				return "%s.%s fehlt links" % [path, str(k)]
		return ""
	if a is Array and b is Array:
		if a.size() != b.size():
			return "%s: Array-Groesse %d != %d" % [path, a.size(), b.size()]
		for i in a.size():
			var sub := first_diff(a[i], b[i], "%s[%d]" % [path, i])
			if not sub.is_empty():
				return sub
		return ""
	if _is_num(a) and _is_num(b):
		var x := float(a)
		var y := float(b)
		if x == y or absf(x - y) <= EPS * maxf(1.0, maxf(absf(x), absf(y))):
			return ""
		return "%s: %.17g != %.17g" % [path, x, y]
	if typeof(a) != typeof(b):
		return "%s: Typ %s != %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a != b:
		return "%s: %s != %s" % [path, str(a), str(b)]
	return ""


static func _is_num(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

class_name CatenaryLogic
extends RefCounted
## Catenary-Mathe der Girlanden (W13B, Doc H §6.3) — PUR und headless
## testbar: kein Node, kein Zufall, keine Zeit. Eine zwischen zwei Punkten
## gespannte Kette hängt als Kettenlinie (cosh) durch; die Form wird so
## normiert, dass beide Endpunkte EXAKT getroffen werden und der Durchhang
## direkt in Metern steuerbar ist.

## Formfaktor der Kettenlinie (größer = bauchigerer Durchhang).
const FORM := 2.4
## Durchhang-Parameter: Basis + Anteil der Spannweite, gedeckelt — die
## Decke hängt auf 2,45 m (GridData.DECKEN_HOEHE), mehr als ~0,9 m
## Durchhang sähe nach Wäscheleine aus.
const DURCHHANG_BASIS := 0.1
const DURCHHANG_ANTEIL := 0.12
const DURCHHANG_MAX := 0.9


## Durchhang (m) aus der Spannweite (m): wächst monoton mit der Distanz.
static func durchhang(distanz: float) -> float:
	return minf(DURCHHANG_BASIS + DURCHHANG_ANTEIL * maxf(distanz, 0.0), DURCHHANG_MAX)


## Normierte Hängeform: 0.0 an beiden Enden (t = 0/1), 1.0 am Tiefpunkt
## (t = 0.5) — symmetrisch, weil cosh eine gerade Funktion ist.
static func haengeform(t: float) -> float:
	var tc := clampf(t, 0.0, 1.0)
	var rand := cosh(FORM * 0.5)
	return (rand - cosh(FORM * (tc - 0.5))) / (rand - 1.0)


## Punkte der Girlande von `a` nach `b` (BEIDE Endpunkte inklusive).
## `segmente` = Anzahl Teilstücke (≥ 1) → segmente + 1 Punkte. `sag` < 0
## heißt: Durchhang automatisch aus der Distanz ableiten.
static func punkte(a: Vector3, b: Vector3, segmente: int, sag := -1.0) -> Array[Vector3]:
	var n := maxi(1, segmente)
	var s := sag if sag >= 0.0 else durchhang(a.distance_to(b))
	var out: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		p.y -= s * haengeform(t)
		out.append(p)
	return out

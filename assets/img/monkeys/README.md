# Affen-Puppen — Gelenk-/Klassen-Doku für Client-Agents

Die 8 Charaktere aus `docs/ART-SOUND-VIDEO-PLAN.md` §2.1 plus 6
Erweiterungs-Charaktere als 2D-Vektor-Pappfiguren (Plan §2.2,
„Kasperletheater deluxe"). Alle Dateien teilen dasselbe Grundskelett
und dieselben Klassen/IDs; Silhouetten-Merkmale sind pro Charakter
ausgetauschte Teile.

## Dateien

| Datei | Charakter | Silhouetten-Merkmal | Extra-Gelenke |
|---|---|---|---|
| `don-bananas.svg` | Don Bananas (der Pate) | Breite Sakko-Schultern + Fedora + Bananen-Zigarre | — |
| `gitti-giro.svg` | Gitti Giro (die Buchhalterin) | Turmhohe Bienenkorb-Frisur + Abakus | `#frisur` |
| `kiki-krawall.svg` | Kiki Krawall (Chaos-Äffchen) | Kleinste Figur, Antennen-Wuschelfrisur, Arme oben | `#frisur` |
| `baron-von-bananenstein.svg` | Baron Bodo von Bananenstein | Zylinder + Stehkragen-Umhang + Monokel + Bananen-Weinglas | — |
| `oma-zinseszins.svg` | Oma Zinseszins | Gebückte Haltung + Kopftuch + Riesen-Handtasche + Strickzeug | — |
| `pumper-paule.svg` | Pumper-Paule (Gym-Gorilla) | Massives V-Profil, winziger Kopf, Tanktop, Shaker | — |
| `schnarch-schorsch.svg` | Schnarch-Schorsch | Hängende Schultern, schwere Lider, Zipfelmütze | `#bommel` |
| `glitzer-gina.svg` | Glitzer-Gina (die Diva) | Federkrone + Boa + Dauer-Pose-Arm überm Kopf | `#krone` |
| `dj-trommelfell.svg` | DJ Trommelfell (der Beat-Affe) | Fette Over-Ear-Kopfhörer + hochgehaltene Vinyl-Platte | — |
| `astro-astrid.svg` | Astro-Astrid (die Raumfahrerin) | Glas-Helm-Kuppel + Antenne + klobige Mond-Stiefel | `#antenne` |
| `kommissar-kokosnuss.svg` | Kommissar Kokosnuss (der Detektiv) | Deerstalker-Doppelschirm + Riesen-Lupe + Trenchcoat-Kragen | — |
| `iro-ines.svg` | Iro-Ines (die Punkerin) | Zacken-Iro + Nietenkragen + Springerstiefel | `#iro` |
| `abraka-dieter.svg` | Abraka-Dieter (der Zauberer) | Schiefer Spitzhut + Rauschebart + Glockenrobe + Zauberstab | `#bart` |
| `kahuna-kalle.svg` | Kahuna-Kalle (der Surfer) | Surfbrett — vom SCHWANZ gehalten! — + Zottel-Mähne + Shaka | `#frisur` |

## Einbau (WICHTIG)

**Inline einbetten** (fetch → `innerHTML`/Template), NICHT als `<img>`,
sonst funktionieren weder Palette-Swap noch Gesichts-/Gelenk-Steuerung.
Alle Style-Regeln in den Dateien sind auf `svg[data-affe="<name>"]`
gescoped — mehrere Affen im selben Dokument stören sich nicht.
Die Gelenk-IDs (`#kopf`, `#arm-l` …) wiederholen sich pro Datei; im
Client deshalb IMMER relativ zum jeweiligen `<svg>`-Element selektieren
(`svgEl.querySelector('#arm-l')`), nie global `document.getElementById`.

## Gelenk-Gruppen (in jeder Datei)

Zeichen-Reihenfolge hinten→vorn: `#schwanz` → `#bein-l/r` → `#koerper`
→ `#arm-l/r` → `#kopf` (Gesichter + Accessoire im Kopf).

| ID | Pivot (transform-origin) | Animations-Idee |
|---|---|---|
| `#kopf` | Halsansatz | Nicken, Kopfschütteln, Neigen |
| `#arm-l`, `#arm-r` | **Schulter** | Winken, Jubel-Wurf, Buzzern |
| `#bein-l`, `#bein-r` | Hüfte | Hüpfen, Trampeln |
| `#schwanz` | Schwanzwurzel | Wedeln (Idle), Zucken |
| `#frisur` / `#bommel` / `#krone` | Ansatz | Nachschwingen (Overshoot) |

`transform-box: view-box` und die Pivots sind in den Dateien
vordefiniert — im Client reicht `#arm-l { transform: rotate(-40deg) }`
bzw. per JS `el.style.transform`. Nur `transform`/`opacity` animieren
(Plan §1.3 Gesetz 6).

### Pivots der 6 Erweiterungs-Affen (transform-origin, x y in viewBox-px)

| Datei | `#kopf` | `#arm-l` | `#arm-r` | `#bein-l` | `#bein-r` | `#schwanz` | Extra |
|---|---|---|---|---|---|---|---|
| `dj-trommelfell.svg` | 120 142 | 88 158 | 152 158 | 102 240 | 138 240 | 146 240 | — |
| `astro-astrid.svg` | 120 148 | 86 164 | 154 164 | 102 240 | 138 240 | 146 240 | `#antenne` 120 46 |
| `kommissar-kokosnuss.svg` | 120 144 | 88 160 | 152 160 | 102 240 | 138 240 | 146 240 | — |
| `iro-ines.svg` | 120 146 | 90 162 | 150 162 | 102 242 | 138 242 | 146 242 | `#iro` 120 64 |
| `abraka-dieter.svg` | 120 140 | 90 156 | 150 156 | 102 244 | 138 244 | 146 244 | `#bart` 120 114 |
| `kahuna-kalle.svg` | 120 144 | 88 160 | 152 160 | 102 240 | 138 240 | 144 240 | `#frisur` 120 70 |

Gag-Hinweis Kahuna-Kalle: das Surfbrett (`#prop-surfbrett`) hängt IM
`#schwanz` — Schwanz-Wedeln wackelt automatisch mit dem Brett.

## Gesichts-Varianten

Vier Gruppen pro Datei: `#gesicht-neutral` (Default sichtbar),
`#gesicht-jubel`, `#gesicht-frust`, `#gesicht-denk`.
Umschalten über ein Attribut am `<svg>`-Element:

```js
svgEl.dataset.gesicht = "jubel";   // neutral | jubel | frust | denk
delete svgEl.dataset.gesicht;      // zurück zu neutral
```

## Palette-Swap (Customization)

Fellfarben hängen an CSS-Custom-Properties — ein Asset-Satz für alle
Farb-Unlocks (Plan §2.2 Punkt 4):

```css
.podium--spieler-3 .mm-affe { --fell: #29D9D5; --fell-hell: #B8F2F0; }
```

| Variable | Wirkung | Default |
|---|---|---|
| `--fell` | Hauptfell (Körper, Kopf, Gliedmaßen, Schwanz) | pro Charakter (siehe Datei) |
| `--fell-hell` | Schnauze, Bauch, Ohr-Innenseiten | pro Charakter |
| `--prop` | Signature-Prop (Barons Umhang, Ginas Boa) | pro Charakter |

Kleidung/Props behalten bewusst feste Palette-Farben (Silhouette und
Wiedererkennung sind heilig, Farben sind Customization — Plan §2.1).

### Fell-MUSTER (Pattern-Fill, Kosmetik-Welle 3 — ADDITIV)

Neben Farb-Swaps gibt es echte Muster-Skins (Tiger-Streifen, Bananen-Punkte,
Sterne, Camo, Gold-Glitzer). Ansatz: KEINE Puppen-Änderung nötig — der
Renderer (`client/shared/meta-avatar.ts`) injiziert pro Puppen-Instanz ein
`<defs><pattern id="mm-muster-N">…</pattern></defs>` (Kachel aus
`assets/img/cosmetics/fell-*.svg`) plus ein `<style>` ans SVG-Ende, das die
bestehenden Fell-Klassen überschreibt:

```css
svg[data-affe][data-mm-muster="mm-muster-N"] .fell   { fill:   url(#mm-muster-N) }
svg[data-affe][data-mm-muster="mm-muster-N"] .fell-s { stroke: url(#mm-muster-N) }
```

Wichtig dabei:

- `.fell-s` mit abdecken — Arme/Beine/Schwanz sind DICKE STRICHE, keine
  Flächen; ohne den stroke-Override blieben die Gliedmaßen musterlos.
- Die Pattern-Id MUSS pro SVG-Instanz eindeutig sein (mehrere Affen im selben
  Dokument — gleiche Falle wie bei den Gelenk-IDs oben).
- Die Kachel-Basis ist `var(--fell, …)` ⇒ Palette-Swaps (`--fell`) und
  Fell-/Spezies-Swaps scheinen durchs Muster (Muster + Farbe kombinierbar).
- Das zusätzliche `[data-affe]` im Selektor ist PFLICHT: Es hebt die
  Spezifität über die Fell-Regeln der Puppen-Datei (`svg[data-affe="…"]
  .fell`). Auf den Dokument-Reihenfolge-Tiebreak (injizierter `<style>` steht
  später) ist bei dynamisch eingefügten SVG-Styles in Chrome KEIN Verlass —
  empirisch gewann sonst die Puppen-Regel. Keine `!important`-Krücken.

### Kopf-Anker (Overlays sitzen pro Puppe verschieden!)

Die 14 Puppen teilen das Skelett, aber NICHT Kopf-Position und -Größe:
Kiki (120/166, r 36, tief), Oma (112/140, vorgebeugt), Paule (120/74, r 30,
winzig), Schorsch (rotierter Kopf) … Kopf-/Gesichts-Overlays werden deshalb
im STANDARD-Kopfraum von Don Bananas gezeichnet (Kopf-Mitte 120/94, r 44,
Augen ≈ 104/136 auf y 82) und vom Renderer per `KOPF_ANKER`-Tabelle
(translate + scale) auf die jeweilige Puppe gemappt. NEUE PUPPE ⇒ Eintrag in
`KOPF_ANKER` (client/shared/meta-avatar.ts) ergänzen — der vitest
„jede Puppe hat einen Kopf-Anker“ erinnert daran.

Kopf-Overlays (gekaufte Hüte/Kronen …) docken im `#accessoire` an; solange
eines ausgerüstet ist, blendet die Klasse `mm-hut-an` am `<svg>` den
Standard-Hut der Puppe aus (`#accessoire > :not(.mm-meta-extra)`).
Datei-Konventionen der Overlays/Kacheln: `assets/img/cosmetics/README.md`.

## Slots

- `#accessoire`: Hut-/Kopf-Slot (bei Don/Baron/Oma/Paule/Schorsch sowie
  Kokosnuss/Dieter belegt, bei Gitti/Kiki/Gina/DJ/Astrid/Ines/Kalle leer
  bzw. durch Frisur/Krone/Kopfhörer/Helm/Iro/Mähne besetzt).
- `#prop-*`: benannte Einzel-Props (z. B. `#prop-zigarre`,
  `#prop-abakus`, `#prop-handtasche`, `#prop-vinyl`, `#prop-helm`,
  `#prop-lupe`, `#prop-zauberstab`, `#prop-surfbrett`) — für
  Signature-Animationen einzeln greifbar.

## Maße

Alle Figuren: `viewBox="0 0 240 320"`, Fußsohle ≈ y 300–310, Outlines
`#1A1208` (nie reines Schwarz), Breiten 4–6 relativ zur viewBox.
Handy-Mini-Avatar: dieselbe Datei, einfach klein skaliert (~48–64 px).

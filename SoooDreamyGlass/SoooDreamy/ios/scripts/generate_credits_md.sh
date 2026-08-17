#!/usr/bin/env bash
# generate_credits_md.sh — regeneriert docs/CREDITS.md aus
# ios/SoooDreamy/Resources/Sounds/sound_credits.json (Single Source of Truth,
# Dossier 47e). Handgepflegte Zweitwahrheiten driften — deshalb wird die
# Audio-Sektion hier gerendert, nie von Hand editiert.
#
#   bash ios/scripts/generate_credits_md.sh
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "FEHLER: jq wird gebraucht." >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
MANIFEST="$ROOT/ios/SoooDreamy/Resources/Sounds/sound_credits.json"
OUT="$ROOT/docs/CREDITS.md"

TABLE=$(jq -r '
    .sounds[]
    | select(.source != null)
    | "| `\(.cue)` | \(.source.title) | \(.source.author) | \(.source.license) | [Quelle](\(.source.url)) | \(.source.edits // "—") |"
' "$MANIFEST")

SYNTH_LIST=$(jq -r '[.sounds[] | select(.mode == "synth") | "`\(.cue)`"] | join(", ")' "$MANIFEST")
FILE_COUNT=$(jq -r '[.sounds[] | select(.source != null)] | length' "$MANIFEST")

cat > "$OUT" << EOF
# Credits & Lizenzen

<!-- Audio-Sektion generiert aus sound_credits.json —
     bash ios/scripts/generate_credits_md.sh — nicht von Hand editieren. -->

## Audio

SoooDreamy klingt hybrid: Die prozedurale Synthese
(\`ios/SoooDreamy/Core/SoundEngine.swift\`) bleibt das Herz und der ewige
Fallback jedes Cues — zusätzlich tragen ausgewählte Cues gebündelte
CC0-Aufnahmen (\`Resources/Sounds/cue_<id>.caf\`, ${FILE_COUNT} Dateien), die den
Klängen echtes Material geben (Papier, Wachs, Glas, Wasser, Würfel). Fehlt
eine Datei oder lässt sie sich nicht dekodieren, greift still die Synthese —
kein Cue hängt je von einer Datei ab.

Alle Quellen, Lizenzen und Laufzeit-Gains stehen in
\`ios/SoooDreamy/Resources/Sounds/sound_credits.json\` (Schema samt
SHA-256-Beleg der Rohdatei). Ein LogicTest erzwingt: Lizenz auf der
Allowlist (CC0-1.0, CC-BY-3.0/4.0, Pixabay), CC-BY nur mit vollständiger
Attribution, ≤120 KB pro Cue, ≤1.5 MB gesamt, keine Waisen-Dateien.
Das Credits-Panel in den Einstellungen wird aus derselben JSON generiert.

### Gebündelte Aufnahmen

| Cue | Aufnahme | Autor:in | Lizenz | Quelle | Bearbeitung |
| --- | --- | --- | --- | --- | --- |
${TABLE}

Verarbeitung: \`ios/scripts/prepare_sounds.sh\` (ffmpeg) — Stille-Trim,
5/10-ms-Fades, mono 44.1 kHz, Peak-Normalisierung auf −6 dBTP, Container
CAF/PCM16 (bewusst kein AAC: Encoder-Priming würde die Transienten
anschneiden). Feintuning läuft über das \`gain\`-Feld im Manifest zur
Laufzeit, nie über Re-Encoding. Die Original-Downloads liegen gitignored in
\`tools/sound_sources/\`.

### Original-Synthese

Reine Synthese bleiben: ${SYNTH_LIST} — plus die 7 \`notif_*.wav\`
(UNNotificationSound, eigenes Inventar) und alle Hybrid-Synth-Schichten.

### Synthese-Techniken

| Technik | Zweck |
| --- | --- |
| Stereo-Voices mit Cent-Verstimmung (±3–8 Cent L/R) | Wärme & Breite statt sterilem Mono-Sinus |
| Echte Attack/Decay-Hüllkurven | keine Klicks, weiche Einsätze |
| Inharmonische Bell-Partials (1 / 2.0 / 2.99 / 4.16 / 5.43) | glaubwürdige Glas-Glocken statt Piepser |
| Pitch-Glides | Herzschlag-Thumps, Bubble-Pops |
| Animiert gefiltertes Rauschen (auf-/zugehender Low-Pass, dekorrelierte Kanäle) | Luft, Papier, Umarmungs-Whoosh |
| Feedback-Delay über den ganzen Buffer | verträumte Echo-Fahnen |
| Soft-Knee-Sättigung (tanh) statt Hard-Clip | analoger Charakter, keine Verzerrungsartefakte |

Standard-Lautstärken sind bewusst sanft (Momente 0.65, Chat 0.5, Spiele 0.6,
Interface 0.35) und pro Kategorie in den Einstellungen regelbar. Die Engine
läuft als \`.ambient\` mit \`.mixWithOthers\`; läuft eigene Musik, verschwinden
Interface-Cues ganz und alles andere duckt ~10 dB.

## App-Icon

Prozedural gerendert im CI durch \`ios/scripts/GenerateIcon.swift\`
(CoreGraphics) — keine Bild-Assets von Drittanbietern.

## Schriften & Symbole

- System-Font (SF Pro Rounded) und SF Symbols — Bestandteil von iOS,
  Nutzung gemäß Apple-Systemrichtlinien.

## Inhalte

Alle Fragen, Quiz-Items, Date-Ideen, Wordle-Wortlisten und
Wahrheit-oder-Pflicht-Karten in \`ios/SoooDreamy/Content/\` sind eigens für
dieses Projekt geschrieben.
EOF

echo "docs/CREDITS.md neu generiert (${FILE_COUNT} Aufnahmen)."

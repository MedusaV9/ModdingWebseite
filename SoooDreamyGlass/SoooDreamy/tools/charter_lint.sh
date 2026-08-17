#!/usr/bin/env bash
# charter_lint.sh — die Anti-Slop-Ratchet der SoooDreamy-Qualitätscharta.
#
# Misst die Slop-Muster aus DESIGN.md (Gebote 1/2/4/6/7/10/11/12 + Symptom 12)
# und vergleicht sie mit den eingecheckten Baselines in charter_baseline.json.
# Regel: Jeder Zähler darf sinken oder gleich bleiben, NIE steigen — steigt
# einer, bricht das Skript (und damit CI) mit Muster und verletztem Gebot.
#
#   bash SoooDreamy/tools/charter_lint.sh            # prüfen (CI-Modus)
#   bash SoooDreamy/tools/charter_lint.sh --update   # Baselines neu schreiben
#                                                    # (nur nach echtem Aufräumen,
#                                                    #  im selben Commit)
#
# Braucht ripgrep (rg) und jq — läuft auf Linux wie macOS.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
BASELINE_FILE="tools/charter_baseline.json"
UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

command -v rg >/dev/null 2>&1 || { echo "FEHLER: ripgrep (rg) wird gebraucht."; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FEHLER: jq wird gebraucht."; exit 2; }

# App-Code-Scope: die App selbst, Shared-Bridge und Widgets. LogicTests und
# Skripte zählen nicht — die Charta regelt, was das Paar sieht und fühlt.
APP=(ios/SoooDreamy ios/Shared ios/Widgets)

count() { # count <pattern> <path...>
    local pattern="$1"; shift
    # `|| true`: rg meldet "nichts gefunden" per Exit-Code 1 — für eine
    # Metrik ist 0 aber ein legitimer (idealer) Messwert, kein Fehler.
    { rg --no-config -c --glob '*.swift' -e "$pattern" "$@" 2>/dev/null || true; } \
        | awk -F: '{s+=$NF} END {print s+0}'
}

# Metrik-Katalog: name | Gebot | Beschreibung. Die Zählung selbst steht in
# measure() — Muster und Scope gehören zusammen an einer Stelle gepflegt.
METRICS=(
    "emoji_as_text|Gebot 1|Emoji als Icon in Text(\"…\") — Icons sind SF Symbols"
    "emoji_in_de_copy|Gebot 2|Deko-Emoji in deutschen L10n-Strings"
    "epic_celebrations|Gebot 4|celebrate(.epic)-Aufrufstellen — epic ist verdient, nicht Default"
    "try_await_api|Gebot 6|try? await ohne sichtbaren Fallback — stumm verschluckte Fehler (Task.sleep zählt nicht)"
    "bare_progressview|Gebot 7|nackte ProgressView() statt GlassSkeleton"
    "bang_strings_de|Gebot 10|Ausrufezeichen-Strings in CoreStrings (DE)"
    "spring_literals|Gebot 11|Freihand-spring(response:) außerhalb von Theme.Motion"
    "easing_literals|Gebot 11|Freihand-easeIn/easeOut/linear(duration:) statt Theme.Motion"
    "bare_white_opacity|Gebot 11|white.opacity(0.x)-Freihandwerte in Features + Widgets"
    "raw_corner_radius|Gebot 11|rohe cornerRadius:-Zahlen in Features statt Radius-Tokens"
    "hardcoded_pink_purple_features|Gebot 11|Theme.pink/purple/rose-Rohfarben in Features statt coupleTint"
    "ultrathin_material_features|Gebot 11|ultraThinMaterial-Glas-Nachbauten in Features (GlassLevel.chrome benutzen)"
    "surface_glass_features|Gebot 11|GlassLevel.surface/tinted + glassCard( in Features — Content wird Papier (paperCard), Richtung 0"
    "bright_paper_features|Gebot 11|helle .paperCard(.brief*/.karton/.polaroid)-Karten in Features — helles Papier NUR fürs Papier-Artefakt (MIGRATION_DUNKEL §10), Chrome spricht Nacht (nightCard)"
    "raw_rotation_features|Gebot 11|freihändige .rotationEffect( in Features — Rotation nur über das seeded PaperTilt-Token"
    "smallcaps_features|Gebot 11|.smallCaps() außerhalb UI/ — Typo.anschrift ist der einzige Kapitälchen-Einsatz"
    "fixed_font_sizes|Gebot 12|Font.scaled(<Zahl>) — ignoriert Dynamic Type"
    "system_size_fonts|Gebot 12|.system(size:)-Fixgrößen in Features + Widgets"
    "version_graffiti|Symptom 12|Versions-/Agenten-Graffiti in Kommentaren"
)

# Deckel (kein Ratchet, ein Festwert): TornEdgeShape-Verwendungen in
# Features + Shared + Widgets — Risse sind Ausnahme, nicht Rhythmus
# (Papier & Licht; gepinnt als PaperRules.tornEdgeAppCap). Die Definition
# in UI/ zählt nicht: gemessen wird, wo gerissen WIRD.
TORN_EDGE_CAP=6

measure() { # measure <name>
    case "$1" in
        emoji_as_text)
            # Zwei Alternativen: Emoji direkt im Literal UND Emoji hinter
            # einer String-Interpolation ("\(x) … 💞") — die Interpolation
            # darf das Muster nicht unsichtbar machen (Emoji-Evasion).
            count 'Text\("[^"]*[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]|Text\("[^"]*\\\(.*[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]' "${APP[@]}" ;;
        emoji_in_de_copy)
            count 'de: "[^"]*[\x{1F300}-\x{1FAFF}\x{2764}]|de: "[^"]*\\\(.*[\x{1F300}-\x{1FAFF}\x{2764}]' "${APP[@]}" ;;
        epic_celebrations)
            count 'celebrate\(\.epic' "${APP[@]}" ;;
        try_await_api)
            # try? await Task.sleep ist eine Choreografie-Pause, kein
            # verschluckter Fehler — gemessen wird nur der Rest (echte
            # API-/IO-Aufrufe, deren Scheitern unsichtbar bliebe).
            local all sleeps
            all="$(count 'try\? await' "${APP[@]}")"
            sleeps="$(count 'try\? await Task\.sleep' "${APP[@]}")"
            echo $((all - sleeps)) ;;
        bare_progressview)
            count 'ProgressView\(\)' "${APP[@]}" ;;
        bang_strings_de)
            count 'de: "[^"]*!' ios/SoooDreamy/Core/CoreStrings.swift ;;
        spring_literals)
            # Theme.swift ist das Token-Zuhause — dort DÜRFEN die vier
            # benannten Federn als Rohwerte stehen, nirgendwo sonst
            # (auch nicht in den Widgets).
            { rg --no-config -c --glob '*.swift' --glob '!**/UI/Theme.swift' \
                -e '\.spring\(response: 0\.' \
                ios/SoooDreamy ios/Widgets 2>/dev/null || true; } \
                | awk -F: '{s+=$NF} END {print s+0}' ;;
        easing_literals)
            # Ergänzt spring_literals: easeIn/easeOut/easeInOut(duration:)
            # und withAnimation(.linear…) sind dieselbe Freihand-Motion,
            # nur mit anderer Kurve.
            { rg --no-config -c --glob '*.swift' --glob '!**/UI/Theme.swift' \
                -e '\.ease(In|Out|InOut)\(duration:' \
                -e 'withAnimation\(\.linear' \
                ios/SoooDreamy ios/Widgets 2>/dev/null || true; } \
                | awk -F: '{s+=$NF} END {print s+0}' ;;
        bare_white_opacity)
            count 'white\.opacity\(0\.' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst ios/Widgets ;;
        raw_corner_radius)
            # Radius.card/control/pane & Radius.concentric sind die Tokens —
            # gemessen werden nur nackte Zahlen direkt am Parameter.
            count 'cornerRadius:\s*[0-9]' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst ;;
        hardcoded_pink_purple_features)
            # Die Paar-Farben sind DIE Signatur (coupleTint) — Stock-Pink/
            # Purple/Rose in Features ist der alte Template-Look.
            count 'Theme\.(pink|purple|rose)' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst ;;
        ultrathin_material_features)
            # Auf 0 gepinnt seit der GlassLevel.chrome-Migration — Features
            # bauen nie wieder eigenes Pseudo-Glas.
            count 'ultraThinMaterial' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst ;;
        surface_glass_features)
            # Der Papier-Fortschrittszähler der Bau-Wellen: Content-Glas
            # (glassCard + die deprecated Stufen surface/tinted) wird
            # Karte für Karte zu paperCard — Startwert = Ist-Stand beim
            # Migrationsstart, Ziel 0. Echtes System-Glas bleibt dem
            # Chrome vorbehalten (GlassLevel.chrome zählt nicht).
            count 'glassCard\(|GlassLevel\.(surface|tinted)' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst ;;
        bright_paper_features)
            # Der Weiß-Audit-Zähler (MIGRATION_DUNKEL §10): jede helle
            # .paperCard(-Karte in Features, die KEIN nachtkarton ist —
            # also .brief (Default), .briefbogen, .karton, .polaroid.
            # Helles Papier ist exklusiv das Papier-DING (Briefbogen,
            # Zettel, Polaroid, Spielbrett, Gutschein); Navigation/
            # Promos/Settings sprechen Nacht. Zähler darf nur sinken.
            local all_paper night_paper
            all_paper="$(count '\.paperCard\(' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst)"
            night_paper="$(count '\.paperCard\(\.nachtkarton' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst)"
            echo $((all_paper - night_paper)) ;;
        raw_rotation_features)
            # Rotation existiert nur über das seeded PaperTilt-Token der
            # UI-Schicht (−6°…+6°, stabile Item-ID) — freihändige
            # rotationEffect-Winkel in Features sind Freihand-Motion.
            count '\.rotationEffect\(' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst ;;
        smallcaps_features)
            # Typo.anschrift (UI-Schicht) ist der EINZIGE legale
            # Kapitälchen-Einsatz der App — außerhalb UI/ auf 0 gepinnt.
            { rg --no-config -c --glob '*.swift' --glob '!**/UI/*' \
                -e '\.smallCaps\(\)' \
                "${APP[@]}" 2>/dev/null || true; } \
                | awk -F: '{s+=$NF} END {print s+0}' ;;
        fixed_font_sizes)
            count '\.scaled\([0-9]' "${APP[@]}" ;;
        system_size_fonts)
            count '\.system\(size:' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst ios/Widgets ;;
        version_graffiti)
            count '// v[0-9]+\.[0-9]|\(Agent [A-Z]\)|\(v[0-9]+\.[0-9]' "${APP[@]}" ;;
        *) echo "unbekannte Metrik: $1" >&2; exit 2 ;;
    esac
}

if [[ $UPDATE -eq 1 ]]; then
    json="{"
    first=1
    for entry in "${METRICS[@]}"; do
        name="${entry%%|*}"
        value="$(measure "$name")"
        [[ $first -eq 0 ]] && json+=","
        json+=$'\n'"    \"$name\": $value"
        first=0
    done
    json+=$'\n'"}"
    printf '{\n  "_rule": "Zähler dürfen nur sinken. Siehe DESIGN.md — bash tools/charter_lint.sh",\n  "metrics": %s\n}\n' \
        "$(echo "$json" | sed 's/^/  /' | sed '1s/^  //')" > "$BASELINE_FILE"
    echo "Baselines neu geschrieben nach $BASELINE_FILE:"
    jq . "$BASELINE_FILE"
    exit 0
fi

[[ -f "$BASELINE_FILE" ]] || { echo "FEHLER: $BASELINE_FILE fehlt — einmal mit --update erzeugen."; exit 2; }

fail=0
improved=0
printf '%-28s %9s %9s   %s\n' "Metrik" "Baseline" "Ist" "Status"
printf '%.0s─' {1..72}; printf '\n'
for entry in "${METRICS[@]}"; do
    name="${entry%%|*}"
    rest="${entry#*|}"
    gebot="${rest%%|*}"
    desc="${rest#*|}"
    baseline="$(jq -r --arg n "$name" '.metrics[$n] // empty' "$BASELINE_FILE")"
    if [[ -z "$baseline" ]]; then
        echo "FEHLER: Metrik '$name' fehlt in $BASELINE_FILE"; fail=1; continue
    fi
    actual="$(measure "$name")"
    if (( actual > baseline )); then
        printf '%-28s %9s %9s   VERSTOSS (%s)\n' "$name" "$baseline" "$actual" "$gebot"
        echo "         → $desc"
        fail=1
    elif (( actual < baseline )); then
        printf '%-28s %9s %9s   gesunken — Baseline mit --update nachziehen\n' \
            "$name" "$baseline" "$actual"
        improved=1
    else
        printf '%-28s %9s %9s   ok\n' "$name" "$baseline" "$actual"
    fi
done

# torn_edge_uses ist ein DECKEL, kein sinkender Zähler: bis zu
# $TORN_EDGE_CAP Risse sind legal (Ausnahme, nicht Rhythmus), erst der
# siebte bricht — deshalb läuft er neben der Ratchet-Schleife.
torn_actual="$(count 'TornEdgeShape' ios/SoooDreamy/Stationen ios/SoooDreamy/Kino ios/SoooDreamy/Zeremonien ios/SoooDreamy/Zustelldienst ios/Shared ios/Widgets)"
if (( torn_actual > TORN_EDGE_CAP )); then
    printf '%-28s %9s %9s   VERSTOSS (Gebot 11)\n' "torn_edge_uses" "≤$TORN_EDGE_CAP" "$torn_actual"
    echo "         → TornEdgeShape-Verwendungen app-weit über dem Deckel — Risse sind Ausnahme, nicht Rhythmus"
    fail=1
else
    printf '%-28s %9s %9s   ok (Deckel)\n' "torn_edge_uses" "≤$TORN_EDGE_CAP" "$torn_actual"
fi

if (( fail )); then
    echo
    echo "Die Anti-Slop-Ratchet hat angeschlagen: mindestens ein Slop-Zähler ist"
    echo "GESTIEGEN. Muster und Gebot stehen oben — DESIGN.md erklärt, wie es"
    echo "richtig geht (Tokens, SF Symbols, Skeletons, sichtbare Fehler)."
    exit 1
fi
if (( improved )); then
    echo
    echo "Zähler gesunken — schön. Bitte 'bash tools/charter_lint.sh --update'"
    echo "laufen lassen und die neue Baseline mitcommitten, damit der"
    echo "Fortschritt eingerastet bleibt."
fi
echo
echo "Charta-Ratchet grün."

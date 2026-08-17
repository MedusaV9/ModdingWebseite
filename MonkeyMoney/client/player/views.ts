// Player-Templates (iPhone hochkant): alle Engine-Phasen mit Handy-Polish —
// Mini-Affe im Kopf, Münz-Einwurf beim Lock-in, charmante Warte-Screens,
// „Psst…"-Umschlag für Flüster-Tipps, Joker-Leiste mit echten Icons.
// Touch-Targets ≥ 44pt, Safe-Areas via mobil.css.
import { html, type TemplateResult } from "lit-html";
import { keyed } from "lit-html/directives/keyed.js";
import { kategorieLabel, schwierigkeitLabel } from "../../shared/kategorien";
import { formatMM } from "../../shared/money";
import type { PlayerView } from "../../shared/views";
import { avatarFarbe } from "../shared/fx/avatar";
import { teamBadge, teamErgebnisHandy, teamWahlBlock, teamZwischenstand } from "../shared/teams-ui";
import { spielerChip, timerBalken, zwischenstand } from "../shared/ui";
import type { PlayerAppState } from "./main";
import { fotoFinishHandy, highlightsHandy, tiebreakerHandy } from "./v2";

/** Sendet eine der neuen C→S-Nachrichten (idemKey ergänzt main.ts). */
export type SendeAktion = (event: string, payload?: Record<string, unknown>) => void;

interface MgPlayerView {
  endsAt: number;
  timerMs: number;
  /** „x von y haben geantwortet" — nicht jedes Format liefert die Felder. */
  answeredCount?: number;
  spielerZahl?: number;
  aufloesung: {
    correctIndex: number;
    perPlayer: {
      playerId: string;
      choice: number | null;
      correct: boolean;
      delta: number;
      /** Formatspezifischer Ergebnis-Stempel (z. B. Affenbank „NICHT GEBANKT")
       * — ohne ihn greift das generische Richtig/Falsch/Zu-langsam-Mapping. */
      status?: string;
      hinweis?: string;
    }[];
  } | null;
}

const JOKER_ICONS: Record<string, string> = {};
for (const [id, datei] of [
  ["bananen-split", "j1-bananen-split"],
  ["ueberziehungskredit", "j2-ueberziehungskredit"],
  ["goldene-banane", "j3-goldene-banane"],
  ["schmiergeld", "j4-schmiergeld"],
  ["rueckgaberecht", "j5-rueckgaberecht"],
  ["bananentresor", "j6-bananentresor"],
  ["portfolio-umschichtung", "j7-portfolio-umschichtung"],
] as const) {
  JOKER_ICONS[id] = new URL(`../../assets/img/ui/joker/${datei}.svg`, import.meta.url).href;
}

export function renderSpielPhase(
  view: PlayerView,
  mgHost: TemplateResult,
  serverNow: number,
  sende: SendeAktion,
  state: PlayerAppState,
  zeichne: () => void,
  soundControl: TemplateResult | "" = "",
): TemplateResult {
  // Kopfzeile in ALLEN Phasen identisch aufgebaut (kein Springen): feste Höhe
  // via mobil.css, Name mit Ellipsis, Konto tick-animiert (data-konto-ziel —
  // Textinhalt gehört handy-fx.fuelleKonto, darum KEIN lit-Text-Binding).
  const kopf = html`<div
    class="spieler-kopf"
    style="--spielerfarbe:${avatarFarbe(view.you.avatar)}"
  >
    <div class="mini-affe mm-affe" data-avatar=${view.you.avatar}></div>
    <strong class="kopf-name">${view.you.name}</strong>
    ${streakBadge(view.you.streak)}
    ${view.you.rueckenwind ? html`<span title="Rückenwind">💨×${view.you.rueckenwind}</span>` : ""}
    ${view.you.schild ? html`<span title="Bananentresor">🛡</span>` : ""}
    ${view.you.clown ? html`<span title="Clown bis Rundenende">🤡</span>` : ""}
    ${teamBadge(view.teams)}
    <span class="konto mm-money-zahl" data-konto-ziel=${view.you.balance}></span>
    ${soundControl}
  </div>`;

  // Phasen-Bühne: Wrapper für die Übergangs-Choreo (View Transitions bzw.
  // Einflug-Fallback in main.ts) — Kopf + Overlays bleiben außen vor.
  return html`${kopf}${momentBanner(view, serverNow)}
    <div class="phase-buehne" data-phase=${view.phase}>
      ${phaseInhalt(view, mgHost, serverNow, sende, state, zeichne)}
    </div>
    ${muenzOverlay(state, serverNow)} ${moodKarte(view, sende)} ${votingKarte(view, sende)}
    ${view.phase !== "ende" ? feedbackKarte(view, sende, state, zeichne) : ""}`;
}

/** Streak-Badge ab ×2 mit Flammen-Steigerung — keyed ⇒ Pop-Animation bei
 * jeder Änderung, data-stufe steuert die Eskalation (2 / 3–4 / 5+). */
function streakBadge(streak: number): TemplateResult | "" {
  if (streak < 2) return "";
  const stufe = streak >= 5 ? 5 : streak >= 3 ? 3 : 2;
  return keyed(
    streak,
    html`<span class="streak-badge" data-stufe=${stufe} title="Streak ×${streak}">
      🔥<span class="streak-mal">×${streak}</span>
    </span>`,
  ) as TemplateResult;
}

/** Münz-Einwurf-Overlay: Antwort eingerastet = Münze fällt in den Schlitz. */
function muenzOverlay(state: PlayerAppState, serverNow: number): TemplateResult {
  if (state.muenzBis <= serverNow) return html``;
  return html`<div class="muenz-overlay">
    <div class="muenze">🍌</div>
    <div class="schlitz"></div>
    <div class="eingerastet">EINGERASTET!</div>
  </div>`;
}

/** Warte-Screen: eigener Mini-Affe + Zwischenstands-Story („Du bist 200 hinter …"). */
function warteScreen(view: PlayerView, titel: string, text: string): TemplateResult {
  return html`<div class="warte-screen">
    <div
      class="eigene-puppe mm-affe mm-affe-idle"
      data-avatar=${view.you.avatar}
      data-gesicht="denk"
    ></div>
    <h2 style="margin:0">${titel}</h2>
    ${text ? html`<div class="warte-story">${text}</div>` : ""}
  </div>`;
}

/** Tröstliche Falsch-Momente: kurz, warm, nie strafend — deterministisch über
 * die Fragen-Nummer rotiert (Rng-Regel: kein Zufall in Render-Logik). */
const TROST_TEXTE = [
  "Kopf hoch — die nächste Banane gehört dir! 🍌",
  "Halb so wild. Neue Frage, neues Glück!",
  "Auch Affen fallen mal vom Baum. Weiter geht's! 🐒",
  "Abgehakt — gleich holst du dir was zurück!",
];

function trostText(frageNr: number): string {
  return TROST_TEXTE[Math.abs(frageNr) % TROST_TEXTE.length];
}

/** „Du führst!" / „Du bist 200 MM hinter Kiki" — kleine Stand-Story. */
function standStory(view: PlayerView): string {
  const idx = view.standings.findIndex((s) => s.id === view.you.id);
  if (idx < 0 || view.standings.length < 2) return "";
  if (idx === 0) {
    const vorsprung = view.standings[0].balance - view.standings[1].balance;
    return vorsprung > 0
      ? `Du führst mit ${formatMM(vorsprung)} Vorsprung! 👑`
      : "Du führst — aber nur hauchdünn! 👑";
  }
  const vordermann = view.standings[idx - 1];
  const abstand = vordermann.balance - view.standings[idx].balance;
  return `Du bist ${formatMM(abstand)} hinter ${vordermann.name} — hol's dir zurück!`;
}

function phaseInhalt(
  view: PlayerView,
  mgHost: TemplateResult,
  serverNow: number,
  sende: SendeAktion,
  state: PlayerAppState,
  zeichne: () => void,
): TemplateResult {
  switch (view.phase) {
    case "lobby":
      return html`<div class="warte-screen">
        <div
          class="eigene-puppe mm-affe mm-affe-idle"
          data-avatar=${view.you.avatar}
          data-gesicht="jubel"
        ></div>
        <h2 style="margin:0">Du bist drin! 🎉</h2>
        <div class="spieler-liste">${view.players.map((p) => spielerChip(p))}</div>
        ${view.teams !== null && view.teams.wahlOffen ? teamWahlBlock(view.teams, sende) : ""}
        <p class="muted">Warten auf den Show-Master …</p>
      </div>`;

    case "intro":
      return warteScreen(view, "🎬 Gleich geht's los!", "Augen auf den großen Bildschirm!");

    case "kategorie-wahl":
      return kategorieWahl(view, sende);

    case "erklaerkarte":
      return erklaerkarte(view, sende);

    case "frage": {
      const mg = view.minigame?.view as MgPlayerView | undefined;
      return html`<div style="padding:4px 10px 0">
          ${mg?.endsAt ? timerBalken(mg.endsAt, mg.timerMs, serverNow, true) : ""}
        </div>
        ${kategorieZeile(view)} ${tippBanner(view)} ${mgHost} ${antwortFortschritt(mg)}
        ${jokerLeiste(view, sende)}`;
    }

    case "aufloesung": {
      const mg = view.minigame?.view as MgPlayerView | undefined;
      const meins = mg?.aufloesung?.perPlayer.find((p) => p.playerId === view.you.id);
      // Formatspezifischer Status (z. B. Affenbank) gewinnt — das generische
      // choice===null-Mapping („ZU LANGSAM") gilt nur für Frage-Formate.
      return html`<div class="zentriert">
        ${
          meins?.correct
            ? html`<div class="ergebnis-stempel richtig" style="color:var(--gruen)">
                  ${meins.status ?? "✅ RICHTIG!"}
                </div>
                <p class="ergebnis-geld">
                  <span
                    class="mm-money-zahl"
                    data-zaehl-ziel=${meins.delta}
                    data-zaehl-key="q${view.frageNr}"
                  ></span>
                </p>
                ${
                  view.you.streak >= 2
                    ? html`<p
                        class="streak-moment"
                        data-stufe=${view.you.streak >= 5 ? 5 : view.you.streak >= 3 ? 3 : 2}
                      >
                        🔥 Streak ×${view.you.streak}!
                      </p>`
                    : ""
                }`
            : html`<div class="ergebnis-stempel falsch" style="color:var(--rot)">
                  ${meins?.status ?? (meins?.choice === null ? "⏰ ZU LANGSAM!" : "❌ FALSCH!")}
                </div>
                <p class="trost">${meins?.hinweis ?? trostText(view.frageNr)}</p>`
        }
        <p class="muted" style="font-size:0.95rem">${standStory(view)}</p>
      </div>`;
    }

    case "zwischenstand":
      // Team-Modus: Team-Ranking (Topf) MIT Individual-Aufschlüsselung (§1.4).
      return html`<div class="zentriert">
        <h2>💰 Zwischenstand</h2>
        ${standStory(view) ? html`<div class="warte-story">${standStory(view)}</div>` : ""}
        ${toepfe(view)}
        ${
          view.teams !== null && !view.teams.wahlOffen
            ? teamZwischenstand(view.teams, view.you.id)
            : zwischenstand(view.standings, view.you.id)
        }
        ${jokerLeiste(view, sende)}
      </div>`;

    case "rad":
      return radPhase(view, sende);

    // v2 Sudden-Death: Kokosnuss-Shake (Tap-Frenzy bzw. Zuschauer-Duell).
    case "tiebreaker":
      return tiebreakerHandy(view, serverNow, sende, zeichne);

    // v2 Replay-Highlights: eigene Beteiligung hervorgehoben („DU warst das!").
    case "highlights":
      return highlightsHandy(view, serverNow);

    case "siegerehrung":
      return siegerehrung(view);

    case "ende": {
      const platz = view.standings.findIndex((s) => s.id === view.you.id) + 1;
      const teamPlatz = view.teams?.teams.find((t) => t.id === view.teams?.deinTeam)?.platz;
      return html`<div class="zentriert">
        <h1>
          ${
            teamPlatz !== undefined
              ? teamPlatz === 1
                ? "🏆 Euer Team gewinnt!"
                : `Team-Platz ${teamPlatz}`
              : platz === 1
                ? "🏆 Du gewinnst!"
                : `Platz ${platz}`
          }
        </h1>
        ${teamErgebnisHandy(view.teams)} ${zwischenstand(view.standings, view.you.id)}
        ${fotoFinishHandy(view, serverNow, zeichne)} ${feedbackKarte(view, sende, state, zeichne)}
      </div>`;
    }
  }
}

/** Dezenter Fortschritts-Hinweis unter der Frage: „2 von 4 haben geantwortet"
 * — nur wenn das Format die Felder liefert (prüft answeredCount/spielerZahl). */
function antwortFortschritt(mg: MgPlayerView | undefined): TemplateResult | "" {
  if (
    mg?.aufloesung ||
    typeof mg?.answeredCount !== "number" ||
    typeof mg.spielerZahl !== "number" ||
    mg.spielerZahl < 2
  ) {
    return "";
  }
  return html`<p class="antwort-fortschritt" data-testid="antwort-fortschritt">
    ${
      mg.answeredCount === 0
        ? "🐵 Alle grübeln noch …"
        : `🐵 ${mg.answeredCount} von ${mg.spielerZahl} haben geantwortet`
    }
  </p>`;
}

/** Kategorien-Voting: Optionen als XXL-Buttons, Live-Stimmen, Comeback-Regel. */
function kategorieWahl(view: PlayerView, sende: SendeAktion): TemplateResult {
  const kw = view.kategorieWahl;
  if (!kw) return warteScreen(view, "📚 Kategorie wird gewählt …", "");
  const darfWaehlen = !kw.nurLetzterWaehlt || kw.waehlerName === view.you.name;
  if (!darfWaehlen) {
    return warteScreen(
      view,
      "📚 Comeback-Regel!",
      `${kw.waehlerName} liegt hinten und wählt die Kategorie allein.`,
    );
  }
  const stimmenGesamt = kw.stimmen.reduce((a, b) => a + b, 0);
  return html`<div class="zentriert" style="gap:10px">
    <h2>📚 Welche Kategorie?</h2>
    ${kw.nurLetzterWaehlt ? html`<p class="muted">Comeback-Regel: DU wählst allein!</p>` : ""}
    ${
      !kw.nurLetzterWaehlt && stimmenGesamt > 0 && view.players.length >= 2
        ? html`<p class="antwort-fortschritt">
            🗳 ${stimmenGesamt} von ${view.players.length} haben abgestimmt
          </p>`
        : ""
    }
    ${kw.optionen.map(
      (o, i) =>
        html`<button
          class=${kw.deineStimme === i ? "primaer" : ""}
          style="width:min(340px,86vw);font-size:1.1rem"
          @click=${() => sende("kategorie.vote", { kategorie: o })}
        >
          ${kategorieLabel(o)}
          ${kw.stimmen[i] > 0 ? html`<span class="muted">(${kw.stimmen[i]})</span>` : ""}
        </button>`,
    )}
  </div>`;
}

/** Format-Ankündigungs-Karte: Bereit-Meldung + Streik-Stimme (Minispiel-Skip). */
function erklaerkarte(view: PlayerView, sende: SendeAktion): TemplateResult {
  const ek = view.erklaerkarte;
  if (!ek) return warteScreen(view, "🃏 Gleich geht's weiter …", "");
  const bereit = ek.bereit.includes(view.you.id);
  const streik = ek.streik.includes(view.you.id);
  return html`<div class="zentriert" style="gap:10px">
    <h2>${ek.minigameName}</h2>
    ${ek.wFinal ? html`<p style="color:var(--gold);font-size:1.3rem">Finale: jede Frage ${formatMM(ek.wFinal)}!</p>` : ""}
    <p>${ek.text}</p>
    <p class="muted">
      ${ek.kategorie ? `Kategorie: ${kategorieLabel(ek.kategorie)} · ` : ""}${ek.schwierigkeiten
        .map(schwierigkeitLabel)
        .join(" / ")}
    </p>
    <button
      class="primaer"
      style="width:min(340px,86vw)"
      ?disabled=${bereit}
      @click=${() => sende("phase.ready", { was: "bereit" })}
    >
      ${bereit ? "✅ Bereit!" : "Bereit!"}
    </button>
    <button
      style="width:min(340px,86vw)"
      ?disabled=${streik}
      @click=${() => sende("phase.ready", { was: "streik" })}
    >
      ${streik ? "✊ Streik läuft …" : "✊ Anderes Spiel! (Streik)"}
    </button>
    ${
      ek.bereit.length > 0 && view.players.length >= 2
        ? html`<p class="antwort-fortschritt">
            ✅ ${ek.bereit.length} von ${view.players.length} sind bereit
          </p>`
        : ""
    }
    ${jokerLeiste(view, sende)}
  </div>`;
}

/** Rad-Phase: Interaktionen (Börsen-Roulette/Umarmt/Kompliment) oder Warte-Screen. */
function radPhase(view: PlayerView, sende: SendeAktion): TemplateResult {
  const rad = view.rad;
  if (!rad) return warteScreen(view, "🎡 Glücksrad!", "");
  if (rad.interaktion) {
    const ia = rad.interaktion;
    const wahlKnopf = (wahl: string, label: string): TemplateResult =>
      html`<button
        class=${ia.deineWahl === wahl ? "primaer" : ""}
        style="width:min(340px,86vw);font-size:1.2rem"
        ?disabled=${ia.deineWahl !== null && ia.deineWahl !== undefined}
        @click=${() => sende("rad.aktion", { wahl })}
      >
        ${label}
      </button>`;
    if (ia.typ === "long-short") {
      return html`<div class="zentriert" style="gap:10px">
        <h2>🎰 Börsen-Roulette</h2>
        <p class="muted">
          Setzt du auf richtig (LONG) oder falsch (SHORT) bei deiner nächsten Antwort?
        </p>
        ${wahlKnopf("long", "📈 LONG")} ${wahlKnopf("short", "📉 SHORT")}
      </div>`;
    }
    if (ia.typ === "umarmt") {
      // Der Buzzer-XXL-Moment: buzzer.svg-Look, Press-Feedback via mobil.css.
      return html`<div class="zentriert" style="gap:14px">
        <h2>🤗 Umarmungs-Bonus!</h2>
        <p class="muted">Wer JETZT drückt (und wirklich jemanden umarmt), kriegt Bonus-MM!</p>
        <button
          class="buzzer-xxl"
          style="--spielerfarbe:${avatarFarbe(view.you.avatar)}"
          ?disabled=${ia.deineWahl !== null && ia.deineWahl !== undefined}
          @click=${() => sende("rad.aktion", { wahl: "umarmt" })}
        >
          🤗 UMARMT!
        </button>
      </div>`;
    }
    const von = view.players.find((p) => p.id === ia.paar?.von)?.name ?? "?";
    const zu = view.players.find((p) => p.id === ia.paar?.zu)?.name ?? "?";
    return html`<div class="zentriert" style="gap:10px">
      <h2>💬 Kompliment-Konto</h2>
      <p><strong>${von}</strong> macht <strong>${zu}</strong> ein Kompliment. War's gut?</p>
      ${wahlKnopf("ja", "👍 Ja!")} ${wahlKnopf("nein", "👎 Nö.")}
    </div>`;
  }
  if (rad.ergebnis) {
    return html`<div class="zentriert" style="gap:8px">
      <h1>${rad.ergebnis.klasse === "gold" ? "✨" : "🎡"} ${rad.ergebnis.name}</h1>
      <p>${rad.ergebnis.wirkung}</p>
    </div>`;
  }
  return warteScreen(view, "🎡 Das Rad dreht …", "Augen auf den Bildschirm!");
}

function siegerehrung(view: PlayerView): TemplateResult {
  const sg = view.siegerehrung;
  if (!sg) return warteScreen(view, "🏆 Siegerehrung!", "");
  const meins = sg.platzierungen.find((p) => p.playerId === view.you.id);
  const medaille = (platz: number): string =>
    platz === 1 ? "🥇" : platz === 2 ? "🥈" : platz === 3 ? "🥉" : `${platz}.`;
  // Team-Modus: das eigene Team-Ergebnis (Platz + Topf) steht über allem —
  // Jubel gilt dem TEAM-Sieg, die Einzel-Liste bleibt darunter sichtbar.
  const meinTeamPlatz = view.teams?.teams.find((t) => t.id === view.teams?.deinTeam)?.platz;
  return html`<div class="zentriert" style="gap:8px">
    <div
      class="eigene-puppe mm-affe mm-affe-idle"
      style="width:min(110px,30vw);aspect-ratio:240/320"
      data-avatar=${view.you.avatar}
      data-gesicht=${
        meinTeamPlatz !== undefined
          ? meinTeamPlatz === 1
            ? "jubel"
            : "frust"
          : meins && meins.platz <= 2
            ? "jubel"
            : "frust"
      }
    ></div>
    ${teamErgebnisHandy(view.teams)}
    <h1 style="margin:0">${meins ? medaille(meins.platz) : "🏆"} Platz ${meins?.platz ?? "?"}</h1>
    ${sg.platzierungen.map(
      (p) =>
        html`<div
          class="zwischenstand-zeile"
          style=${p.playerId === view.you.id ? "outline:3px solid var(--gold)" : ""}
        >
          <strong>${medaille(p.platz)}</strong> ${p.name}
          <span class="betrag">${formatMM(p.balance)}</span>
          <span class="muted" title="AT = All-Time-Bananen: dein Dauer-Konto">+${p.at} AT</span>
        </div>`,
    )}
    ${sg.awards.map(
      (a) =>
        html`<p style="margin:2px 0">🏅 <strong>${a.titel}</strong>: ${a.name} (${a.wert})</p>`,
    )}
  </div>`;
}

/** Joker-Leiste: echte Icons (assets/img/ui/joker) + Besitz/Kaufpreis. */
function jokerLeiste(view: PlayerView, sende: SendeAktion): TemplateResult {
  if (view.jokers.length === 0) return html``;
  const knopf = (
    j: PlayerView["jokers"][number],
    label: string,
    payload: Record<string, unknown>,
  ): TemplateResult =>
    html`<button
      class="joker-knopf"
      ?disabled=${!j.nutzbar}
      title=${j.beschreibung}
      @click=${() => sende("joker.use", payload)}
    >
      ${
        JOKER_ICONS[j.id]
          ? html`<img src=${JOKER_ICONS[j.id]} alt="" />`
          : html`<span style="font-size:1.6rem">${j.emoji}</span>`
      }
      <span>${label}</span>
      ${
        j.ladungen > 0
          ? html`<span class="ladung">×${j.ladungen}</span>`
          : j.preis !== null
            ? html`<span class="muted">${formatMM(j.preis)}</span>`
            : ""
      }
    </button>`;
  return html`<div class="joker-leiste">
    ${view.jokers.map((j) => {
      if (j.id === "schmiergeld") {
        return html`${knopf(j, `${j.name} 1`, { jokerId: j.id, stufe: 1 })}
        ${knopf(j, `${j.name} 2`, { jokerId: j.id, stufe: 2 })}`;
      }
      return knopf(j, j.name, { jokerId: j.id });
    })}
  </div>`;
}

/** Kategorie-Badge (Kontext-Anker, Eval 5): Mini-Zeile „Gaming · Minecraft"
 * über der Frage — in ALLEN Frage-Formaten (Daten zentral aus dem View). */
function kategorieZeile(view: PlayerView): TemplateResult {
  if (!view.frageKategorie) return html``;
  return html`<p
    class="muted"
    data-testid="frage-kategorie"
    style="text-align:center;margin:2px 0 0;font-size:0.78rem;letter-spacing:0.04em"
  >
    📚 ${view.frageKategorie}
  </p>`;
}

/** Flüster-Tipp als „Psst…"-Umschlag + Schmiergeld-Hinweis + Tipp-Kanone. */
function tippBanner(view: PlayerView): TemplateResult {
  if (!view.fluesterTipp && !view.hinweis && view.tipps.length === 0) return html``;
  return html`${
    view.tipps.length > 0
      ? html`<div class="psst-umschlag" style="rotate:-1deg">
          <span class="psst" style="color:var(--gold)">💡 Tipp-Kanone:</span>
          ${view.tipps.map(
            (t, i) => html`<em style="display:block;margin-top:4px">${i + 1}. ${t}</em>`,
          )}
        </div>`
      : ""
  }
  ${
    view.fluesterTipp
      ? html`<div class="psst-umschlag">
          <span class="psst">🤫 Psst …</span>
          <em style="display:block;margin-top:4px">${view.fluesterTipp}</em>
        </div>`
      : ""
  }
  ${
    view.hinweis
      ? html`<div class="psst-umschlag" style="rotate:1deg">
          <span class="psst" style="color:var(--mm-leaf)">💡 Dein Schmiergeld wirkt:</span>
          <em style="display:block;margin-top:4px">${view.hinweis}</em>
        </div>`
      : ""
  }`;
}

/** Jackpot-Glas + Fragen-Pott (nur wenn gefüllt). */
function toepfe(view: PlayerView): TemplateResult {
  if (view.jackpotGlas === 0 && view.pott === 0) return html``;
  return html`<p class="muted">
    ${view.jackpotGlas > 0 ? html`🍯 Jackpot-Glas: ${formatMM(view.jackpotGlas)} ` : ""}
    ${view.pott > 0 ? html`💰 Pott: ${formatMM(view.pott)}` : ""}
  </p>`;
}

/** Letzter Bildschirm-Moment als Banner (max. ~6 s sichtbar, nie in Cutscenes). */
function momentBanner(view: PlayerView, serverNow: number): TemplateResult {
  if (view.phase === "siegerehrung" || view.phase === "ende") return html``;
  const m = view.momente[view.momente.length - 1];
  if (!m || serverNow - m.ts > 6000) return html``;
  return html`<div class="moment-banner" style="font-size:0.95rem;padding:6px">${m.text}</div>`;
}

/** Blitz-Stimmung (GM-Werkzeug 14): 5 Emojis, 1 Tap — Antwort läuft über vote.cast. */
const MOOD_EMOJIS = ["😴", "🥱", "🙂", "😄", "🤩"];
function moodKarte(view: PlayerView, sende: SendeAktion): TemplateResult {
  const m = view.mood;
  if (!m) return html``;
  return html`<div class="zentriert" style="gap:8px;padding:10px">
    <h3 style="margin:0">⚡ Blitz-Stimmung: Wie fühlt sich's an?</h3>
    <div style="display:flex;gap:8px;justify-content:center">
      ${MOOD_EMOJIS.map(
        (emoji, i) =>
          html`<button
            class=${m.deineWahl === i ? "primaer" : ""}
            style="font-size:2rem;min-width:56px"
            ?disabled=${m.deineWahl !== null}
            @click=${() => sende("vote.cast", { option: i })}
          >
            ${emoji}
          </button>`,
      )}
    </div>
  </div>`;
}

/** GM-Voting-Overlay (Publikums-Entscheid) — in jeder Phase möglich. */
function votingKarte(view: PlayerView, sende: SendeAktion): TemplateResult {
  const v = view.voting;
  if (!v) return votingErgebnisKarte(view);
  return html`<div class="zentriert" style="gap:8px;padding:10px">
    <h3 style="margin:0">🗳 ${v.frage}</h3>
    ${v.optionen.map(
      (o, i) =>
        html`<button
          class=${v.deineStimme === i ? "primaer" : ""}
          style="width:min(340px,86vw)"
          @click=${() => sende("vote.cast", { option: i })}
        >
          ${o} ${v.stimmen[i] > 0 ? html`<span class="muted">(${v.stimmen[i]})</span>` : ""}
        </button>`,
    )}
  </div>`;
}

/** Voting-Ergebnis (~7 s nach Schluss): Balken + Sieger-Option auch am Handy. */
function votingErgebnisKarte(view: PlayerView): TemplateResult {
  const e = view.votingErgebnis;
  if (!e) return html``;
  const max = Math.max(1, ...e.stimmen);
  return html`<div class="zentriert" style="gap:6px;padding:10px" data-testid="voting-ergebnis">
    <h3 style="margin:0">🗳 ${e.frage} — Ergebnis</h3>
    ${e.optionen.map((o, i) => {
      const gewinner = i === e.gewinnerIndex;
      const breite = 12 + Math.round(((e.stimmen[i] ?? 0) / max) * 60);
      return html`<div style="display:flex;align-items:center;gap:8px;width:min(340px,86vw)">
        <span
          style="flex:0 0 40%;text-align:right;${gewinner ? "color:var(--gold);font-weight:700" : ""}"
        >
          ${gewinner ? "🏆 " : ""}${o}
        </span>
        <div
          style="height:14px;width:${breite}%;border-radius:7px;background:${
            gewinner ? "var(--gold)" : "var(--gruen)"
          };opacity:${gewinner ? 1 : 0.55}"
        ></div>
        <strong>${e.stimmen[i] ?? 0}</strong>
      </div>`;
    })}
  </div>`;
}

/** Freitext-Feedback (GM-Werkzeug 14 / Abspann). */
function feedbackKarte(
  view: PlayerView,
  sende: SendeAktion,
  state: PlayerAppState,
  zeichne: () => void,
): TemplateResult {
  if (!view.feedbackAngefragt) return html``;
  if (state.feedbackGesendet) {
    return html`<p class="muted" style="text-align:center">💌 Danke für dein Feedback!</p>`;
  }
  return html`<div class="zentriert" style="gap:8px;padding:10px">
    <h3 style="margin:0">💬 Wie fandest du's?</h3>
    <textarea
      id="feedback-input"
      maxlength="280"
      rows="3"
      style="width:min(340px,86vw);font-size:1rem"
      placeholder="Dein Feedback (ehrlich!)"
    ></textarea>
    <button
      class="primaer"
      style="width:min(340px,86vw)"
      @click=${() => {
        const el = document.getElementById("feedback-input") as HTMLTextAreaElement | null;
        const text = el?.value.trim() ?? "";
        if (text.length === 0) return;
        sende("feedback.text", { text });
        state.feedbackGesendet = true;
        zeichne();
      }}
    >
      Abschicken
    </button>
  </div>`;
}

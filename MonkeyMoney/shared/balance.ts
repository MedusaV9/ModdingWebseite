// Economy-Tabelle (MASTERPLAN Welle 1) — EIN Blick auf alle Geld-Konstanten.
// Kunden-Befund: „Rewards inkonsistent (500 vs. 100), Preise wirken beliebig."
// Diese Tabelle aggregiert die verbindlichen Werte aus shared/money.ts,
// shared/economy.ts und den Minigame-Metas an EINEM Ort — und
// shared/balance.test.ts wacht über die Invarianten (Raster, Progression,
// Formel-Ganzzahligkeit, Wett-Einheitlichkeit). Die Metas bleiben die Quelle
// (kein Doppel-Pflegen): hier wird nur importiert und strukturiert.
import { AB_KETTE } from "./minigames/affenbank.meta";
import { GA_WETTE_MM } from "./minigames/goldener-affe.meta";
import { BT_ERFOLG_MM } from "./minigames/buchstaben-telegramm.meta";
import { BX_WETTE_MM } from "./minigames/bananen-boxkampf.meta";
import { EGA_BEIDE_MM, EGA_SOLO_MM, EGA_TEAM_MM } from "./minigames/einer-gegen-alle.meta";
import { KQ_KONTER_MM, KQ_RICHTIG_MM } from "./minigames/konter-quiz.meta";
import {
  LD_GETEILT_MM,
  LD_SIEG_BANK_MM,
  LD_SIEG_TRANSFER_MM,
  LD_WETTE_MM,
} from "./minigames/lianensteg-duell.meta";
import { PD_TREPPE } from "./minigames/pixel-dschungel.meta";
import { RL_LEITER } from "./minigames/risiko-leiter.meta";
import { SACK_TICK_MM } from "./minigames/kokosnuss-uhr.meta";
import { SB_EXPLOSION_MM, SB_WEITERGABE_MM } from "./minigames/stinkbanane.meta";
import { SS_STRAFE_MM } from "./minigames/song-snippet.meta";
import { TD_KLAU_MM } from "./minigames/taschendieb.meta";
import { TS_TOPF_MM } from "./minigames/bananen-tortenschlacht.meta";
import { WS_WERT } from "./minigames/wer-singts.meta";
import {
  APPLAUS_ALMOSEN,
  BANANENSTEUER,
  DISPO_LIMIT,
  JACKPOT_FRAGE_WERT,
  JACKPOT_GLAS_START,
  MITLEIDS_BANANE,
  REKLAMATION_GEBUEHR,
} from "./economy";
import { FRAGE_TIMER_MS, FRAGE_WERTE } from "./money";

/** Die eine Economy-Tabelle: Frage-Werte, Format-Payouts, Wetten, Strafen,
 * Glas und soziale Sicherungen — konsolidiert für Doku, GM-Cockpit und Tests. */
export const BALANCE = {
  /** Grundgerüst §3.1: W = Frage-Grundwert; Speed-Bonus max. +50 % von W. */
  fragen: {
    werte: FRAGE_WERTE,
    timerMs: FRAGE_TIMER_MS,
  },
  /** Format-Payouts — wo möglich als W-Vielfache designt (Bluff W/2,
   * Börse-Einsatz W/2, Market-Chip W/10, Blitz-DJ-Start 2×W). */
  formate: {
    affenbankKette: AB_KETTE,
    einerGegenAlle: { solo: EGA_SOLO_MM, beide: EGA_BEIDE_MM, team: EGA_TEAM_MM },
    konterQuiz: { richtig: KQ_RICHTIG_MM, konter: KQ_KONTER_MM },
    telegrammErfolgJePartner: BT_ERFOLG_MM,
    tortenschlachtTopf: TS_TOPF_MM,
    kokosnussSackTick: SACK_TICK_MM,
    stinkbanane: { weitergabe: SB_WEITERGABE_MM, explosion: SB_EXPLOSION_MM },
    taschendiebKlau: TD_KLAU_MM,
    pixelDschungelTreppe: PD_TREPPE,
    risikoLeiter: RL_LEITER,
    werSingts: WS_WERT,
    lianensteg: {
      siegBank: LD_SIEG_BANK_MM,
      siegTransfer: LD_SIEG_TRANSFER_MM,
      geteilt: LD_GETEILT_MM,
    },
  },
  /** Zuschauer-Wetten: EIN einheitlicher Einsatz überall (Eval-Konsistenz). */
  wetten: { lianensteg: LD_WETTE_MM, boxkampf: BX_WETTE_MM, goldenerAffe: GA_WETTE_MM },
  /** Strafen wandern ins Jackpot-Glas (nie „verschwindet" Geld einfach). */
  strafen: {
    blitzDjFalschBuzz: SS_STRAFE_MM,
    reklamationAbgewiesen: REKLAMATION_GEBUEHR,
    bananensteuer: BANANENSTEUER,
  },
  glas: { start: JACKPOT_GLAS_START, jackpotFrageBasis: JACKPOT_FRAGE_WERT },
  /** Soziale Sicherungen (§3.2/§3.4): niemand fällt aus der Show. */
  sicherungen: {
    dispoLimit: DISPO_LIMIT,
    mitleidsBanane: MITLEIDS_BANANE,
    applausAlmosen: APPLAUS_ALMOSEN,
  },
} as const;

/** Alle MM-Beträge der Tabelle flach — Grundlage der Raster-Invarianten. */
export function alleBetraege(): number[] {
  const b = BALANCE;
  return [
    ...Object.values(b.fragen.werte),
    ...b.formate.affenbankKette,
    b.formate.einerGegenAlle.solo,
    b.formate.einerGegenAlle.beide,
    b.formate.einerGegenAlle.team,
    b.formate.konterQuiz.richtig,
    b.formate.konterQuiz.konter,
    b.formate.telegrammErfolgJePartner,
    b.formate.tortenschlachtTopf,
    b.formate.kokosnussSackTick,
    b.formate.stinkbanane.weitergabe,
    b.formate.stinkbanane.explosion,
    ...Object.values(b.formate.taschendiebKlau),
    ...Object.values(b.formate.pixelDschungelTreppe).map((t) => t.start),
    ...b.formate.risikoLeiter,
    ...Object.values(b.formate.werSingts),
    b.formate.lianensteg.siegBank,
    b.formate.lianensteg.siegTransfer,
    b.formate.lianensteg.geteilt,
    ...Object.values(b.wetten),
    ...Object.values(b.strafen),
    b.glas.start,
    b.glas.jackpotFrageBasis,
    Math.abs(b.sicherungen.dispoLimit),
    b.sicherungen.mitleidsBanane,
    b.sicherungen.applausAlmosen,
  ];
}

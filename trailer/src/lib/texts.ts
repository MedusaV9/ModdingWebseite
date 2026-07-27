/**
 * Text-Overlays V2 (T1–T9; T10/T11 = Endcard, liegen in components/EclipseRing.tsx).
 * Wortlaute aus v2_storyboard.md §3, Zeitfenster auf das angepasste Bar-Grid gezogen.
 * Stil/Animation unveraendert aus V1 (components/TextCard.tsx).
 */

import type {TextCardSpec} from './shots';

export interface TextEntry extends TextCardSpec {
  id: string;
}

export const TEXTS: TextEntry[] = [
  // V01 (0–225)
  {id: 't1', text: 'Sieben Tage.', inStart: 60, inEnd: 80, outStart: 180, outEnd: 200},
  // V02 (225–563) — laeuft ueber den Breakdown
  {
    id: 't2',
    text: 'Der Tod ist erst der Anfang.',
    inStart: 280,
    inEnd: 305,
    outStart: 495,
    outEnd: 520,
    size: 104,
  },
  // V03 (563–675) — DROP
  {
    id: 't3',
    text: 'Der Himmel bricht.',
    inStart: 568,
    inEnd: 575,
    outStart: 645,
    outEnd: 660,
    pop: true,
    glitchy: true,
  },
  // V04 (675–788)
  {
    id: 't4',
    text: 'Zahl mit Herzen.',
    inStart: 690,
    inEnd: 706,
    outStart: 758,
    outEnd: 775,
    gold: true,
  },
  // V05 (788–900)
  {
    id: 't5',
    text: '30 Zauber. Dein Pfad.',
    inStart: 800,
    inEnd: 816,
    outStart: 870,
    outEnd: 888,
  },
  // V06 (900–1125)
  {id: 't6', text: 'Tag 7.', inStart: 905, inEnd: 912, outStart: 960, outEnd: 975, pop: true},
  // V07 (1125–1238)
  {
    id: 't7',
    text: 'Kein Ort ist sicher.',
    inStart: 1135,
    inEnd: 1150,
    outStart: 1208,
    outEnd: 1225,
  },
  // V08 (1238–1350) bleibt bewusst textfrei
  // V09 (1350–1575) — Musik-Peak
  {
    id: 't8',
    text: 'Der Fährmann wartet.',
    inStart: 1360,
    inEnd: 1380,
    outStart: 1530,
    outEnd: 1550,
  },
  // V10 (1575–1688)
  {
    id: 't9',
    text: 'Eine Woche. Keine zweite Chance.',
    inStart: 1580,
    inEnd: 1596,
    outStart: 1652,
    outEnd: 1670,
    y: 0.78,
    size: 96,
    stagger: 1,
  },
];

export const textById = (id: string) => TEXTS.find((t) => t.id === id);

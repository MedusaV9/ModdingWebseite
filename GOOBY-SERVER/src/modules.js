// Dokumentierter Modul-Loader (Plan §3.1): server.js iteriert diese Liste und ruft
// register(ctx) auf jedem Modul auf. Spätere Wellen (z. B. M2: mail.js) ergänzen hier
// GENAU EINE Zeile — sonst keine server.js-Änderung nötig.
//
// Reihenfolge ist relevant: rooms zuerst (stellt ctx.rooms für joinGuards/kindHooks),
// friends vor presence/pal/visits/boardgames (liefert areFriends/friendCodesOf).

import * as rooms from './rooms.js';
import * as friends from './friends.js';
import * as presence from './presence.js';
import * as goobypal from './goobypal.js';
import * as analytics from './analytics.js';
import * as codes from './codes.js';
import * as events from './events.js';
import * as visits from './visits.js';
import * as boardgames from './boardgames.js';
import * as ranchmp from './ranchmp.js';
import * as mail from './mail.js';

export const MODULES = [
  rooms,
  friends,
  presence,
  goobypal,
  analytics,
  codes,
  events,
  visits,
  boardgames,
  ranchmp,
  mail,
];

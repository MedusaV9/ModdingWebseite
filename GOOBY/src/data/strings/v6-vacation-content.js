// V6/D2 — vacation-depth content strings (PLAN6 Wave D §D2) — OWNED BY
// AGENT D2. The pooled postcard texts (3 variants per destination ×9 —
// systems/postcards.js picks deterministically per trip day; key pattern
// `vacation.postcard.<destId>.<variant>` extends the v5-vacation
// `vacation.postcard.<destId>` shape; V6/FIX2 dropped the literal '*stamp*'
// suffix — the rack renderer in ui/airportScreen.js draws a real postmark
// glyph instead), the postcard-rack section labels,
// and the two new notification copy pairs (NOTIFY.IDS.vacReturn 9 /
// vacLastCall 10 — systems/notifyRules.js). Emoji appear ONLY in the
// notify.* keys (OS notification bodies are the ruled D4 audit exemption);
// everything the game renders itself is emoji-free. Always EN + DE; spread
// into data/strings.js AFTER the v6-juice module. No other agent may edit
// this module.

/** @type {Record<string, string>} */
export const EN = {
  // ── postcard rack (airport/album section labels) ──
  'vacation.rack.title': 'Postcards from Gooby',
  'vacation.rack.day': 'Day {day}',
  'vacation.rack.empty': 'No postcards yet — book a trip!',

  // ── pooled postcard lines (vacation.postcard.<destId>.<variant>) ──
  'vacation.postcard.beach.1': 'The waves keep chasing my toes!!',
  'vacation.postcard.beach.2': 'I built a sand Gooby. He is rounder than me!',
  'vacation.postcard.beach.3': 'A crab waved at me and I waved back all day.',
  'vacation.postcard.meadowTrip.1': 'I rolled down THREE whole hills today!',
  'vacation.postcard.meadowTrip.2': 'The bees hum my favorite song, I think.',
  'vacation.postcard.meadowTrip.3': 'I made a flower crown. It keeps sliding off.',
  'vacation.postcard.bigCity.1': 'So many snack stands, so little tummy!!',
  'vacation.postcard.bigCity.2': 'The lights stay on ALL night. I checked.',
  'vacation.postcard.bigCity.3': 'I rode an escalator six times. Both ways.',
  'vacation.postcard.space.1': 'Carrots float up here!! I chase them!',
  'vacation.postcard.space.2': 'I did a somersault that never stopped.',
  'vacation.postcard.space.3': 'Earth looks like a tiny blueberry from here.',
  'vacation.postcard.harbor.1': 'A gull shared my pretzel. Half each!',
  'vacation.postcard.harbor.2': 'The boats bob like sleepy ducks. So calm.',
  'vacation.postcard.harbor.3': 'I learned a sailor knot! It is just a tangle.',
  'vacation.postcard.spookGarden.1': 'The ghosts giggle when I sneeze!',
  'vacation.postcard.spookGarden.2': 'A pumpkin glowed just for me tonight.',
  'vacation.postcard.spookGarden.3': 'We played hide and seek. Ghosts are SO good.',
  'vacation.postcard.bakery.1': 'I napped on a warm bread loaf…',
  'vacation.postcard.bakery.2': 'Sugar dust snowed on my ears today!',
  'vacation.postcard.bakery.3': 'The baker let me poke the dough. It poked back.',
  'vacation.postcard.nightSky.1': 'I counted 100 stars, then lost count!!',
  'vacation.postcard.nightSky.2': 'The balloon drifts so slow up here. Cozy.',
  'vacation.postcard.nightSky.3': 'A shooting star! I wished for carrots.',
  'vacation.postcard.toyRoom.1': 'The toy robot is my best friend now!',
  'vacation.postcard.toyRoom.2': 'We built a block tower taller than me!!',
  'vacation.postcard.toyRoom.3': 'The teddy snores louder than I do. Barely.',

  // ── notifications (ids 9/10 — OS bodies, the ruled emoji exemption) ──
  'notify.vacReturn.title': 'Gooby is landing! ✈️',
  'notify.vacReturn.body': 'Gooby is back from vacation — pick him up at the airport! ✈️',
  'notify.vacLastCall.title': 'Last call for Gooby! 🧳',
  'notify.vacLastCall.body': 'Gooby is still waiting at the airport — pick him up within 3 hours or he needs a taxi!',
};

/** @type {Record<string, string>} */
export const DE = {
  // ── Postkarten-Regal (Flughafen/Album-Abschnitt) ──
  'vacation.rack.title': 'Postkarten von Gooby',
  'vacation.rack.day': 'Tag {day}',
  'vacation.rack.empty': 'Noch keine Postkarten — buch eine Reise!',

  // ── Postkarten-Textpools (vacation.postcard.<destId>.<variant>) ──
  'vacation.postcard.beach.1': 'Die Wellen jagen immer meine Zehen!!',
  'vacation.postcard.beach.2': 'Ich habe einen Sand-Gooby gebaut. Er ist runder als ich!',
  'vacation.postcard.beach.3': 'Ein Krebs hat mir gewunken und ich den ganzen Tag zurück.',
  'vacation.postcard.meadowTrip.1': 'Ich bin heute DREI ganze Hügel runtergerollt!',
  'vacation.postcard.meadowTrip.2': 'Die Bienen summen mein Lieblingslied, glaube ich.',
  'vacation.postcard.meadowTrip.3': 'Ich habe eine Blumenkrone gebastelt. Sie rutscht dauernd runter.',
  'vacation.postcard.bigCity.1': 'So viele Snackbuden, so wenig Bauch!!',
  'vacation.postcard.bigCity.2': 'Die Lichter bleiben die GANZE Nacht an. Ich hab nachgeschaut.',
  'vacation.postcard.bigCity.3': 'Ich bin sechsmal Rolltreppe gefahren. In beide Richtungen.',
  'vacation.postcard.space.1': 'Hier oben schweben die Karotten!! Ich jage sie!',
  'vacation.postcard.space.2': 'Ich habe einen Purzelbaum gemacht, der nie aufgehört hat.',
  'vacation.postcard.space.3': 'Die Erde sieht von hier aus wie eine winzige Blaubeere.',
  'vacation.postcard.harbor.1': 'Eine Möwe hat meine Brezel geteilt. Halbe-halbe!',
  'vacation.postcard.harbor.2': 'Die Boote schaukeln wie müde Enten. So friedlich.',
  'vacation.postcard.harbor.3': 'Ich habe einen Seemannsknoten gelernt! Es ist nur ein Knäuel.',
  'vacation.postcard.spookGarden.1': 'Die Geister kichern, wenn ich niese!',
  'vacation.postcard.spookGarden.2': 'Ein Kürbis hat heute Nacht nur für mich geleuchtet.',
  'vacation.postcard.spookGarden.3': 'Wir haben Verstecken gespielt. Geister sind SO gut darin.',
  'vacation.postcard.bakery.1': 'Ich habe auf einem warmen Brot geschlafen…',
  'vacation.postcard.bakery.2': 'Heute hat es Zuckerstaub auf meine Ohren geschneit!',
  'vacation.postcard.bakery.3': 'Der Bäcker ließ mich den Teig anstupsen. Er hat zurückgestupst.',
  'vacation.postcard.nightSky.1': 'Ich habe 100 Sterne gezählt und mich dann verzählt!!',
  'vacation.postcard.nightSky.2': 'Der Ballon treibt hier oben so langsam. Gemütlich.',
  'vacation.postcard.nightSky.3': 'Eine Sternschnuppe! Ich habe mir Karotten gewünscht.',
  'vacation.postcard.toyRoom.1': 'Der Spielzeugroboter ist jetzt mein bester Freund!',
  'vacation.postcard.toyRoom.2': 'Wir haben einen Klotzturm gebaut, größer als ich!!',
  'vacation.postcard.toyRoom.3': 'Der Teddy schnarcht lauter als ich. Knapp.',

  // ── Benachrichtigungen (ids 9/10 — OS-Bodys, die D4-Emoji-Ausnahme) ──
  'notify.vacReturn.title': 'Gooby landet! ✈️',
  'notify.vacReturn.body': 'Gooby ist zurück aus dem Urlaub — hol ihn am Flughafen ab! ✈️',
  'notify.vacLastCall.title': 'Letzter Aufruf für Gooby! 🧳',
  'notify.vacLastCall.body': 'Gooby wartet noch am Flughafen — hol ihn innerhalb von 3 Stunden ab, sonst braucht er ein Taxi!',
};

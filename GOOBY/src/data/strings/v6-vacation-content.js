// V6/D2 — vacation-depth content strings (PLAN6 Wave D §D2) — OWNED BY
// AGENT D2. The pooled postcard texts (3 variants per destination ×9 —
// systems/postcards.js picks deterministically per trip day; key pattern
// `vacation.postcard.<destId>.<variant>` extends the v5-vacation
// `vacation.postcard.<destId>` shape), the postcard-rack section labels,
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
  'vacation.postcard.beach.1': 'The waves keep chasing my toes!! *stamp*',
  'vacation.postcard.beach.2': 'I built a sand Gooby. He is rounder than me! *stamp*',
  'vacation.postcard.beach.3': 'A crab waved at me and I waved back all day. *stamp*',
  'vacation.postcard.meadowTrip.1': 'I rolled down THREE whole hills today! *stamp*',
  'vacation.postcard.meadowTrip.2': 'The bees hum my favorite song, I think. *stamp*',
  'vacation.postcard.meadowTrip.3': 'I made a flower crown. It keeps sliding off. *stamp*',
  'vacation.postcard.bigCity.1': 'So many snack stands, so little tummy!! *stamp*',
  'vacation.postcard.bigCity.2': 'The lights stay on ALL night. I checked. *stamp*',
  'vacation.postcard.bigCity.3': 'I rode an escalator six times. Both ways. *stamp*',
  'vacation.postcard.space.1': 'Carrots float up here!! I chase them! *stamp*',
  'vacation.postcard.space.2': 'I did a somersault that never stopped. *stamp*',
  'vacation.postcard.space.3': 'Earth looks like a tiny blueberry from here. *stamp*',
  'vacation.postcard.harbor.1': 'A gull shared my pretzel. Half each! *stamp*',
  'vacation.postcard.harbor.2': 'The boats bob like sleepy ducks. So calm. *stamp*',
  'vacation.postcard.harbor.3': 'I learned a sailor knot! It is just a tangle. *stamp*',
  'vacation.postcard.spookGarden.1': 'The ghosts giggle when I sneeze! *stamp*',
  'vacation.postcard.spookGarden.2': 'A pumpkin glowed just for me tonight. *stamp*',
  'vacation.postcard.spookGarden.3': 'We played hide and seek. Ghosts are SO good. *stamp*',
  'vacation.postcard.bakery.1': 'I napped on a warm bread loaf… *stamp*',
  'vacation.postcard.bakery.2': 'Sugar dust snowed on my ears today! *stamp*',
  'vacation.postcard.bakery.3': 'The baker let me poke the dough. It poked back. *stamp*',
  'vacation.postcard.nightSky.1': 'I counted 100 stars, then lost count!! *stamp*',
  'vacation.postcard.nightSky.2': 'The balloon drifts so slow up here. Cozy. *stamp*',
  'vacation.postcard.nightSky.3': 'A shooting star! I wished for carrots. *stamp*',
  'vacation.postcard.toyRoom.1': 'The toy robot is my best friend now! *stamp*',
  'vacation.postcard.toyRoom.2': 'We built a block tower taller than me!! *stamp*',
  'vacation.postcard.toyRoom.3': 'The teddy snores louder than I do. Barely. *stamp*',

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
  'vacation.postcard.beach.1': 'Die Wellen jagen immer meine Zehen!! *Stempel*',
  'vacation.postcard.beach.2': 'Ich habe einen Sand-Gooby gebaut. Er ist runder als ich! *Stempel*',
  'vacation.postcard.beach.3': 'Ein Krebs hat mir gewunken und ich den ganzen Tag zurück. *Stempel*',
  'vacation.postcard.meadowTrip.1': 'Ich bin heute DREI ganze Hügel runtergerollt! *Stempel*',
  'vacation.postcard.meadowTrip.2': 'Die Bienen summen mein Lieblingslied, glaube ich. *Stempel*',
  'vacation.postcard.meadowTrip.3': 'Ich habe eine Blumenkrone gebastelt. Sie rutscht dauernd runter. *Stempel*',
  'vacation.postcard.bigCity.1': 'So viele Snackbuden, so wenig Bauch!! *Stempel*',
  'vacation.postcard.bigCity.2': 'Die Lichter bleiben die GANZE Nacht an. Ich hab nachgeschaut. *Stempel*',
  'vacation.postcard.bigCity.3': 'Ich bin sechsmal Rolltreppe gefahren. In beide Richtungen. *Stempel*',
  'vacation.postcard.space.1': 'Hier oben schweben die Karotten!! Ich jage sie! *Stempel*',
  'vacation.postcard.space.2': 'Ich habe einen Purzelbaum gemacht, der nie aufgehört hat. *Stempel*',
  'vacation.postcard.space.3': 'Die Erde sieht von hier aus wie eine winzige Blaubeere. *Stempel*',
  'vacation.postcard.harbor.1': 'Eine Möwe hat meine Brezel geteilt. Halbe-halbe! *Stempel*',
  'vacation.postcard.harbor.2': 'Die Boote schaukeln wie müde Enten. So friedlich. *Stempel*',
  'vacation.postcard.harbor.3': 'Ich habe einen Seemannsknoten gelernt! Es ist nur ein Knäuel. *Stempel*',
  'vacation.postcard.spookGarden.1': 'Die Geister kichern, wenn ich niese! *Stempel*',
  'vacation.postcard.spookGarden.2': 'Ein Kürbis hat heute Nacht nur für mich geleuchtet. *Stempel*',
  'vacation.postcard.spookGarden.3': 'Wir haben Verstecken gespielt. Geister sind SO gut darin. *Stempel*',
  'vacation.postcard.bakery.1': 'Ich habe auf einem warmen Brot geschlafen… *Stempel*',
  'vacation.postcard.bakery.2': 'Heute hat es Zuckerstaub auf meine Ohren geschneit! *Stempel*',
  'vacation.postcard.bakery.3': 'Der Bäcker ließ mich den Teig anstupsen. Er hat zurückgestupst. *Stempel*',
  'vacation.postcard.nightSky.1': 'Ich habe 100 Sterne gezählt und mich dann verzählt!! *Stempel*',
  'vacation.postcard.nightSky.2': 'Der Ballon treibt hier oben so langsam. Gemütlich. *Stempel*',
  'vacation.postcard.nightSky.3': 'Eine Sternschnuppe! Ich habe mir Karotten gewünscht. *Stempel*',
  'vacation.postcard.toyRoom.1': 'Der Spielzeugroboter ist jetzt mein bester Freund! *Stempel*',
  'vacation.postcard.toyRoom.2': 'Wir haben einen Klotzturm gebaut, größer als ich!! *Stempel*',
  'vacation.postcard.toyRoom.3': 'Der Teddy schnarcht lauter als ich. Knapp. *Stempel*',

  // ── Benachrichtigungen (ids 9/10 — OS-Bodys, die D4-Emoji-Ausnahme) ──
  'notify.vacReturn.title': 'Gooby landet! ✈️',
  'notify.vacReturn.body': 'Gooby ist zurück aus dem Urlaub — hol ihn am Flughafen ab! ✈️',
  'notify.vacLastCall.title': 'Letzter Aufruf für Gooby! 🧳',
  'notify.vacLastCall.body': 'Gooby wartet noch am Flughafen — hol ihn innerhalb von 3 Stunden ab, sonst braucht er ein Taxi!',
};

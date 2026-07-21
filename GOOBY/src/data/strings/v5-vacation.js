// V5/VACATION — vacation/airport strings (PLAN5 idea IDEA-01) — OWNED BY THE
// VACATION AGENT. Airport panel, destination cards, HUD countdown chip,
// postcards, pickup/taxi reunion and the away-gate toasts. Always EN + DE;
// spread into data/strings.js AFTER the earlier v5 modules. No other agent
// may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // airport panel + destination rows
  'vacation.airport.title': 'Airport',
  'vacation.airport.sub': 'Send Gooby on a little vacation!',
  'vacation.dest.priceDays': '{price} coins · {days} days',
  'vacation.dest.beach.name': 'Sunny Beach',
  'vacation.dest.beach.sub': 'Waves, shells and harbor naps',
  'vacation.dest.meadowTrip.name': 'Meadow Trip',
  'vacation.dest.meadowTrip.sub': 'Flower fields and picnic snacks',
  'vacation.dest.bigCity.name': 'Big City',
  'vacation.dest.bigCity.sub': 'Bright lights and snack stands',
  'vacation.dest.space.name': 'Space Camp',
  'vacation.dest.space.sub': 'Zero-gravity carrot floats',
  'city.dest.airport': 'Airport',
  'city.dest.airportSub': 'Book Gooby a vacation',

  // booking flow
  'vacation.booked': 'Gooby is off to {name} — back in {days} days!',
  'vacation.noCoins': 'Not enough coins for this trip…',
  'vacation.blocked': 'Gooby is on vacation right now!',

  // HUD chip
  'vacation.chip.away': 'On vacation · {t}',
  'vacation.chip.return': 'Pick up Gooby! · {t}',
  'vacation.chip.overdue': 'Gooby needs a taxi!',

  // live events
  'vacation.postcard': 'A postcard from Gooby: {text}',
  'vacation.postcard.beach': 'The waves are so splashy! *stamp*',
  'vacation.postcard.meadowTrip': 'I rolled down a whole hill! *stamp*',
  'vacation.postcard.bigCity': 'So many snack stands!! *stamp*',
  'vacation.postcard.space': 'Carrots float up here!! *stamp*',
  'vacation.returnReady': 'Gooby landed! Pick him up at the airport.',
  'vacation.overdueToast': 'Oh no — Gooby is stranded! He needs a taxi.',

  // pickup sheet
  'vacation.pickup.title': 'Gooby is waiting!',
  'vacation.pickup.away': 'Gooby is still on vacation — back in {t}.',
  'vacation.pickup.body': 'Pick him up within {t} or he needs a taxi.',
  'vacation.pickup.overdueBody': 'The pickup window closed. A taxi home costs {fee} coins.',
  'vacation.pickup.btn': 'Pick up',
  'vacation.pickup.taxiBtn': 'Pay taxi ({fee})',
  'vacation.welcomeBack': 'Gooby is home! Souvenir: +{coins} coins',

  // offline welcome-back parts
  'vacation.offline.postcard': 'A postcard arrived',
  'vacation.offline.returnReady': 'Gooby is waiting at the airport!',
  'vacation.offline.overdue': 'Gooby is stranded — taxi needed!',
};

/** @type {Record<string, string>} */
export const DE = {
  // airport panel + destination rows
  'vacation.airport.title': 'Flughafen',
  'vacation.airport.sub': 'Schick Gooby in einen kleinen Urlaub!',
  'vacation.dest.priceDays': '{price} Münzen · {days} Tage',
  'vacation.dest.beach.name': 'Sonnenstrand',
  'vacation.dest.beach.sub': 'Wellen, Muscheln und Hafen-Nickerchen',
  'vacation.dest.meadowTrip.name': 'Wiesen-Ausflug',
  'vacation.dest.meadowTrip.sub': 'Blumenwiesen und Picknick-Snacks',
  'vacation.dest.bigCity.name': 'Großstadt',
  'vacation.dest.bigCity.sub': 'Helle Lichter und Snackbuden',
  'vacation.dest.space.name': 'Weltraum-Camp',
  'vacation.dest.space.sub': 'Schwerelose Karotten-Schwebe',
  'city.dest.airport': 'Flughafen',
  'city.dest.airportSub': 'Buch Gooby einen Urlaub',

  // booking flow
  'vacation.booked': 'Gooby fliegt nach {name} — zurück in {days} Tagen!',
  'vacation.noCoins': 'Nicht genug Münzen für diese Reise…',
  'vacation.blocked': 'Gooby ist gerade im Urlaub!',

  // HUD chip
  'vacation.chip.away': 'Im Urlaub · {t}',
  'vacation.chip.return': 'Gooby abholen! · {t}',
  'vacation.chip.overdue': 'Gooby braucht ein Taxi!',

  // live events
  'vacation.postcard': 'Eine Postkarte von Gooby: {text}',
  'vacation.postcard.beach': 'Die Wellen sind so platschig! *Stempel*',
  'vacation.postcard.meadowTrip': 'Ich bin einen ganzen Hügel runtergerollt! *Stempel*',
  'vacation.postcard.bigCity': 'So viele Snackbuden!! *Stempel*',
  'vacation.postcard.space': 'Hier oben schweben die Karotten!! *Stempel*',
  'vacation.returnReady': 'Gooby ist gelandet! Hol ihn am Flughafen ab.',
  'vacation.overdueToast': 'Oh nein — Gooby ist gestrandet! Er braucht ein Taxi.',

  // pickup sheet
  'vacation.pickup.title': 'Gooby wartet!',
  'vacation.pickup.away': 'Gooby ist noch im Urlaub — zurück in {t}.',
  'vacation.pickup.body': 'Hol ihn innerhalb von {t} ab, sonst braucht er ein Taxi.',
  'vacation.pickup.overdueBody': 'Das Abholfenster ist zu. Ein Taxi nach Hause kostet {fee} Münzen.',
  'vacation.pickup.btn': 'Abholen',
  'vacation.pickup.taxiBtn': 'Taxi zahlen ({fee})',
  'vacation.welcomeBack': 'Gooby ist zu Hause! Souvenir: +{coins} Münzen',

  // offline welcome-back parts
  'vacation.offline.postcard': 'Eine Postkarte ist angekommen',
  'vacation.offline.returnReady': 'Gooby wartet am Flughafen!',
  'vacation.offline.overdue': 'Gooby ist gestrandet — Taxi nötig!',
};

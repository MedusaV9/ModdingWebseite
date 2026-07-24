// V6.1 FINAL WAVE — the single shared string module for the V6.1 wave —
// OWNED BY AGENT G1 (FINAL-WAVE 'STRINGS RULE': G1 owns strings.js +
// this module; G2/G3 hand their keys over via frozen manifests and keep
// local tx() fallbacks until this module lands). Always EN + DE; spread
// into data/strings.js AFTER the v6-fixes module. No other agent may edit
// this module. Contents, in plan order:
//   G1/C2  ach.<id>.name/.desc for the seven V6-content achievements
//   G1/C3  the Reisepass chip label (vacation.pass.progress)
//   G1/B2  the two new passport entry stamps (thm.passport.stamp.park/wheel)
//   G1/A2  nine DISTINCT locked-card teasers (vacation.dest.<id>.teaser) —
//          mystery contract: no destination proper name, glyph, accent,
//          price or days is disclosed, only a one-line scent of the place
//   G1/B4  the three deterministic weather welcome-home lines
//          (vacation.home.clear/cloudy/rain — DE voice verbatim from the
//          binding idea doc B-content.md §4)
//   G2/B7  secret.ducky (manifest /tmp/gooby-v6-handoffs/G2, verbatim; the
//          DE keeps the English "approved" — the in-fiction duck stamp)
//   G3/B5  cutscene.versary.* captions (manifest, verbatim)
//   G3/B3  vacation.postcard.<id>.4/.5 pool growth (manifest, verbatim)
//   G3/B6  gallery.frame.park (proper noun, identical in both languages)
//   G3/B8  park.wheel.apexNight (night apex caption)
//   G3/B1  settings.loveNote ({heart} placeholder stays verbatim — the ♥
//          glyph span is authored in settingsScreen.js)

/** @type {Record<string, string>} */
export const EN = {
  // ── G1/C2: the seven V6-content achievements (data/achievements.js) ──
  'ach.parkDay.name': 'Park Day',
  'ach.parkDay.desc': 'Step through the Funkelpark gates for the first time.',
  'ach.coasterFan.name': 'Coaster Fan',
  'ach.coasterFan.desc': 'Ride the roller coaster 5 times.',
  'ach.wheelRide.name': 'Sky High',
  'ach.wheelRide.desc': 'Take one full turn on the big wheel.',
  'ach.funkelnacht.name': 'Sparkle Night',
  'ach.funkelnacht.desc': 'Visit Funkelpark after dark.',
  'ach.postmaster.name': 'Postmaster',
  'ach.postmaster.desc': 'Keep 10 postcards from Gooby\u2019s travels.',
  'ach.stickerBook84.name': 'Full Album',
  'ach.stickerBook84.desc': 'Unlock all 84 stickers in the book.',
  'ach.weltenbummler.name': 'Globetrotter',
  'ach.weltenbummler.desc': 'Complete a vacation at all 9 destinations.',

  // ── G1/C3: the Reiseziele-Sammelpass chip (ui/airportScreen.js) ──
  'vacation.pass.progress': 'Travel pass {n}/{total}',

  // ── G1/B2: passport entry stamps (ui/profileScreen.js; the park name is
  // a proper noun in both languages, per the binding idea doc) ──
  'thm.passport.stamp.park': 'Funkelpark ×{n}',
  'thm.passport.stamp.wheel': 'Big wheel ×{n}',

  // ── G1/A2: nine distinct locked-card teasers (ui/airportScreen.js) ──
  'vacation.dest.beach.teaser': 'Somewhere, waves are practicing their splashing.',
  'vacation.dest.meadowTrip.teaser': 'A checkered blanket waits to be unfolded.',
  'vacation.dest.bigCity.teaser': 'Streets that hum and windows that wink.',
  'vacation.dest.space.teaser': 'It is very quiet up there. And very floaty.',
  'vacation.dest.harbor.teaser': 'Gooby hears faraway horns going toooot.',
  'vacation.dest.spookGarden.teaser': 'Something giggles softly behind the fog.',
  'vacation.dest.bakery.teaser': 'A warm, buttery smell drifts this way.',
  'vacation.dest.nightSky.teaser': 'Little lights twinkle high, high above.',
  'vacation.dest.toyRoom.teaser': 'Somewhere, tiny blocks go clickety-clack.',

  // ── G1/B4: the weather welcome-home lines (celebrate() seam) ──
  'vacation.home.clear': 'The sun waited for me!!',
  'vacation.home.cloudy': 'Cuddle clouds! Ordered just for us.',
  'vacation.home.rain': 'Rain! Perfect snuggle weather, right?',

  // ── G2/B7: secret ducky toast (manifest, verbatim) ──
  'secret.ducky': 'Squeaky duck approved!!',

  // ── G3/B5: Gooby-versary cutscene captions (manifest, verbatim) ──
  'cutscene.versary.month.title': 'One whole month of Gooby and you!',
  'cutscene.versary.month.dance': 'Gooby does his happiest bounce, just for you.',
  'cutscene.versary.month.thanks': 'Thank you for every single day.',
  'cutscene.versary.year.title': 'A whole YEAR of Gooby and you!',
  'cutscene.versary.year.memories': 'So many naps, snacks and little adventures\u2026',
  'cutscene.versary.year.confetti': 'Gooby jumps so high the confetti joins in!',
  'cutscene.versary.year.thanks': 'Here is to many more days together.',

  // ── G3/B3: postcard pool 3→5, variants .4/.5 (manifest, verbatim) ──
  'vacation.postcard.beach.4': 'I found a shell that whispers the sea!',
  'vacation.postcard.beach.5': 'I buried my feet in the sand. Then I forgot where.',
  'vacation.postcard.meadowTrip.4': 'A butterfly used my ear as a bench!',
  'vacation.postcard.meadowTrip.5': 'The grass tickles. I giggled at a whole field.',
  'vacation.postcard.bigCity.4': 'I found a fountain and made a BIG wish!',
  'vacation.postcard.bigCity.5': 'The pigeons here walk very importantly. Me too now.',
  'vacation.postcard.space.4': 'The moon is very round. We are basically twins!',
  'vacation.postcard.space.5': 'I tried to nap but kept drifting off the bed!',
  'vacation.postcard.harbor.4': 'A little tugboat tooted hello at me!',
  'vacation.postcard.harbor.5': 'The lighthouse blinks slow. I blink back slower.',
  'vacation.postcard.spookGarden.4': 'A friendly bat showed me how to hang upside down!',
  'vacation.postcard.spookGarden.5': 'The fog is soft like a blanket. I tried to fold it.',
  'vacation.postcard.bakery.4': 'I sniffed the croissants until I got dizzy!',
  'vacation.postcard.bakery.5': 'Flour makes a very good pillow. Very dusty too.',
  'vacation.postcard.nightSky.4': 'The clouds below look like sheep. I counted four.',
  'vacation.postcard.nightSky.5': 'I told the moon about you. It smiled, I think.',
  'vacation.postcard.toyRoom.4': 'The marble run goes clickety-click. I watched it forever!',
  'vacation.postcard.toyRoom.5': 'I won at cards against the teddy. He is a good sport.',

  // ── G3/B6 + B8 + B1 (manifest, verbatim) ──
  'gallery.frame.park': 'Funkelpark',
  'park.wheel.apexNight': 'The very top! The whole park twinkles below like spilled stars.',
  'settings.loveNote': 'made with {heart} for you and Gooby',
};

/** @type {Record<string, string>} */
export const DE = {
  // ── G1/C2: the seven V6-content achievements ──
  'ach.parkDay.name': 'Parktag',
  'ach.parkDay.desc': 'Geh zum ersten Mal durch das Funkelpark-Tor.',
  'ach.coasterFan.name': 'Achterbahn-Fan',
  'ach.coasterFan.desc': 'Fahre 5-mal mit der Achterbahn.',
  'ach.wheelRide.name': 'Hoch hinaus',
  'ach.wheelRide.desc': 'Dreh eine ganze Runde im Riesenrad.',
  'ach.funkelnacht.name': 'Funkelnacht',
  'ach.funkelnacht.desc': 'Besuche den Funkelpark bei Nacht.',
  'ach.postmaster.name': 'Postmeister',
  'ach.postmaster.desc': 'Bewahre 10 Postkarten von Goobys Reisen auf.',
  'ach.stickerBook84.name': 'Volles Album',
  'ach.stickerBook84.desc': 'Schalte alle 84 Sticker im Album frei.',
  'ach.weltenbummler.name': 'Weltenbummler',
  'ach.weltenbummler.desc': 'Beende einen Urlaub an allen 9 Reisezielen.',

  // ── G1/C3: der Reiseziele-Sammelpass-Chip ──
  'vacation.pass.progress': 'Reisepass {n}/{total}',

  // ── G1/B2: Reisepass-Stempel ──
  'thm.passport.stamp.park': 'Funkelpark ×{n}',
  'thm.passport.stamp.wheel': 'Riesenrad ×{n}',

  // ── G1/A2: neun verschiedene Teaser für gesperrte Karten ──
  'vacation.dest.beach.teaser': 'Irgendwo üben Wellen schon ihr Platschen.',
  'vacation.dest.meadowTrip.teaser': 'Eine karierte Decke wartet aufs Ausbreiten.',
  'vacation.dest.bigCity.teaser': 'Straßen, die summen, und Fenster, die zwinkern.',
  'vacation.dest.space.teaser': 'Dort oben ist es sehr still. Und sehr schwebig.',
  'vacation.dest.harbor.teaser': 'Gooby hört von Weitem ein Tuuuut.',
  'vacation.dest.spookGarden.teaser': 'Hinter dem Nebel kichert es ganz leise.',
  'vacation.dest.bakery.teaser': 'Ein warmer Butterduft weht herüber.',
  'vacation.dest.nightSky.teaser': 'Kleine Lichter funkeln hoch, hoch oben.',
  'vacation.dest.toyRoom.teaser': 'Irgendwo machen kleine Klötzchen klick-klack.',

  // ── G1/B4: die Wetter-Willkommenszeilen (DE-Stimme verbatim aus dem
  // Ideen-Dokument B-content.md §4) ──
  'vacation.home.clear': 'Die Sonne hat auf mich gewartet!!',
  'vacation.home.cloudy': 'Kuschelwolken! Wie für uns bestellt.',
  'vacation.home.rain': 'Regen! Perfektes Kuschelwetter, oder?',

  // ── G2/B7: Quietsche-Ente (Manifest, verbatim — "approved" bleibt
  // absichtlich englisch, das ist die Enten-Stempel-Stimme) ──
  'secret.ducky': 'Quietsche-Ente approved!!',

  // ── G3/B5: Gooby-versary-Untertitel (Manifest, verbatim) ──
  'cutscene.versary.month.title': 'Ein ganzer Monat Gooby und du!',
  'cutscene.versary.month.dance': 'Gooby macht seinen fröhlichsten Hüpfer, nur für dich.',
  'cutscene.versary.month.thanks': 'Danke für jeden einzelnen Tag.',
  'cutscene.versary.year.title': 'Ein ganzes JAHR Gooby und du!',
  'cutscene.versary.year.memories': 'So viele Nickerchen, Snacks und kleine Abenteuer\u2026',
  'cutscene.versary.year.confetti': 'Gooby springt so hoch, dass das Konfetti mitfeiert!',
  'cutscene.versary.year.thanks': 'Auf viele weitere gemeinsame Tage.',

  // ── G3/B3: Postkarten-Pool 3→5, Varianten .4/.5 (Manifest, verbatim) ──
  'vacation.postcard.beach.4': 'Ich habe eine Muschel gefunden, die das Meer flüstert!',
  'vacation.postcard.beach.5': 'Ich habe meine Füße im Sand vergraben. Dann hab ich vergessen wo.',
  'vacation.postcard.meadowTrip.4': 'Ein Schmetterling hat mein Ohr als Bank benutzt!',
  'vacation.postcard.meadowTrip.5': 'Das Gras kitzelt. Ich habe eine ganze Wiese angekichert.',
  'vacation.postcard.bigCity.4': 'Ich habe einen Brunnen gefunden und mir GROSS was gewünscht!',
  'vacation.postcard.bigCity.5': 'Die Tauben hier laufen sehr wichtig herum. Ich jetzt auch.',
  'vacation.postcard.space.4': 'Der Mond ist sehr rund. Wir sind quasi Zwillinge!',
  'vacation.postcard.space.5': 'Ich wollte schlafen, bin aber immer vom Bett weggeschwebt!',
  'vacation.postcard.harbor.4': 'Ein kleiner Schlepper hat mir Hallo getutet!',
  'vacation.postcard.harbor.5': 'Der Leuchtturm blinkt langsam. Ich blinzle noch langsamer zurück.',
  'vacation.postcard.spookGarden.4': 'Eine nette Fledermaus hat mir gezeigt, wie man kopfüber hängt!',
  'vacation.postcard.spookGarden.5': 'Der Nebel ist weich wie eine Decke. Ich wollte ihn falten.',
  'vacation.postcard.bakery.4': 'Ich habe an den Croissants geschnuppert, bis mir schwindelig war!',
  'vacation.postcard.bakery.5': 'Mehl ist ein sehr gutes Kissen. Aber auch sehr staubig.',
  'vacation.postcard.nightSky.4': 'Die Wolken da unten sehen aus wie Schafe. Ich habe vier gezählt.',
  'vacation.postcard.nightSky.5': 'Ich habe dem Mond von dir erzählt. Er hat gelächelt, glaube ich.',
  'vacation.postcard.toyRoom.4': 'Die Murmelbahn macht klick-klack. Ich habe ewig zugeschaut!',
  'vacation.postcard.toyRoom.5': 'Ich habe beim Kartenspiel gegen den Teddy gewonnen. Er ist ein guter Verlierer.',

  // ── G3/B6 + B8 + B1 (Manifest, verbatim) ──
  'gallery.frame.park': 'Funkelpark',
  'park.wheel.apexNight': 'Ganz oben! Der ganze Park funkelt unten wie verschüttete Sterne.',
  'settings.loveNote': 'mit {heart} gemacht — für dich und Gooby',
};

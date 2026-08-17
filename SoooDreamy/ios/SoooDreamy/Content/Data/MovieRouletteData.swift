import Foundation

/// One swipeable movie-night card. Titles are per-language DISPLAY strings —
/// the deck itself is built from indexes, so mixed-language couples still
/// match on the same card.
struct MovieCard: Hashable {
    let de: String
    let en: String
    let emoji: String
    /// L10n suffix: games.mr.genre.<genre>
    let genre: String

    func title(lang: String) -> String { lang == "de" ? de : en }
}

// Curated movie-night deck — genre mix from cozy to spooky. Deliberately
// generic "night themes" (not licensed titles) plus classics vibes; couples
// add their own favorites as custom cards on top.
enum MovieRouletteData {
    static let cards: [MovieCard] = [
        MovieCard(de: "Verliebt in Paris", en: "In Love in Paris", emoji: "🗼", genre: "romance"),
        MovieCard(de: "Sommer am Meer", en: "Summer by the Sea", emoji: "🌊", genre: "romance"),
        MovieCard(de: "Tanz mit mir", en: "Dance with Me", emoji: "💃", genre: "romance"),
        MovieCard(de: "Briefe an dich", en: "Letters to You", emoji: "💌", genre: "romance"),
        MovieCard(de: "Hochzeit mit Hindernissen", en: "Wedding Chaos", emoji: "💒", genre: "romcom"),
        MovieCard(de: "Der Kuss um Mitternacht", en: "The Midnight Kiss", emoji: "🌙", genre: "romance"),
        MovieCard(de: "Kaffee & Schmetterlinge", en: "Coffee & Butterflies", emoji: "☕️", genre: "romcom"),
        MovieCard(de: "Fake Dating Deluxe", en: "Fake Dating Deluxe", emoji: "🎭", genre: "romcom"),
        MovieCard(de: "Nachbarn zum Verlieben", en: "Lovely Neighbors", emoji: "🏠", genre: "romcom"),
        MovieCard(de: "Chaos-Roadtrip", en: "Chaos Road Trip", emoji: "🚗", genre: "comedy"),
        MovieCard(de: "Die WG-Party", en: "The House Party", emoji: "🎉", genre: "comedy"),
        MovieCard(de: "Agent aus Versehen", en: "Accidental Agent", emoji: "🕶️", genre: "comedy"),
        MovieCard(de: "Der schlechteste Koch", en: "World's Worst Chef", emoji: "🍳", genre: "comedy"),
        MovieCard(de: "Bürokrieg", en: "Office Wars", emoji: "🖇️", genre: "comedy"),
        MovieCard(de: "Oma dreht durch", en: "Grandma Goes Wild", emoji: "👵", genre: "comedy"),
        MovieCard(de: "Mitternachtsjagd", en: "Midnight Chase", emoji: "🏃", genre: "action"),
        MovieCard(de: "Codename: Kolibri", en: "Codename: Hummingbird", emoji: "🐦", genre: "action"),
        MovieCard(de: "Diamantenraub um 8", en: "Heist at Eight", emoji: "💎", genre: "action"),
        MovieCard(de: "Turbo-Legenden", en: "Turbo Legends", emoji: "🏎️", genre: "action"),
        MovieCard(de: "Die letzte Bastion", en: "The Last Bastion", emoji: "🏰", genre: "action"),
        MovieCard(de: "Sturmflug", en: "Storm Flight", emoji: "✈️", genre: "action"),
        MovieCard(de: "Das Flüstern im Wald", en: "Whispers in the Woods", emoji: "🌲", genre: "horror"),
        MovieCard(de: "Zimmer 13", en: "Room 13", emoji: "🚪", genre: "horror"),
        MovieCard(de: "Nachtschicht", en: "Night Shift", emoji: "🌃", genre: "horror"),
        MovieCard(de: "Der Spiegelgast", en: "The Mirror Guest", emoji: "🪞", genre: "horror"),
        MovieCard(de: "Kellergeschichten", en: "Basement Tales", emoji: "🕯️", genre: "horror"),
        MovieCard(de: "Sternenstaub-Odyssee", en: "Stardust Odyssey", emoji: "🚀", genre: "scifi"),
        MovieCard(de: "Planet der Träume", en: "Planet of Dreams", emoji: "🪐", genre: "scifi"),
        MovieCard(de: "Zeitschleife 2049", en: "Time Loop 2049", emoji: "⏳", genre: "scifi"),
        MovieCard(de: "Die KI, die mich liebte", en: "The AI Who Loved Me", emoji: "🤖", genre: "scifi"),
        MovieCard(de: "Parallelwelt-Picknick", en: "Parallel World Picnic", emoji: "🌀", genre: "scifi"),
        MovieCard(de: "Der verschwundene Zug", en: "The Vanished Train", emoji: "🚂", genre: "thriller"),
        MovieCard(de: "Kalte Spuren", en: "Cold Trails", emoji: "❄️", genre: "thriller"),
        MovieCard(de: "Das dritte Alibi", en: "The Third Alibi", emoji: "🕵️", genre: "thriller"),
        MovieCard(de: "Stille Zeugen", en: "Silent Witnesses", emoji: "🤫", genre: "thriller"),
        MovieCard(de: "Die Inselvilla", en: "The Island Villa", emoji: "🏝️", genre: "thriller"),
        MovieCard(de: "Drachenherz-Saga", en: "Dragonheart Saga", emoji: "🐉", genre: "fantasy"),
        MovieCard(de: "Die Nebelkrone", en: "The Mist Crown", emoji: "👑", genre: "fantasy"),
        MovieCard(de: "Hüter des Lichts", en: "Keepers of Light", emoji: "🔮", genre: "fantasy"),
        MovieCard(de: "Elfenwald", en: "Elven Woods", emoji: "🧝", genre: "fantasy"),
        MovieCard(de: "Der Zauberbasar", en: "The Magic Bazaar", emoji: "🎪", genre: "fantasy"),
        MovieCard(de: "Tiefsee-Giganten", en: "Deep Sea Giants", emoji: "🐋", genre: "docu"),
        MovieCard(de: "Unsere Erde bei Nacht", en: "Our Planet at Night", emoji: "🌍", genre: "docu"),
        MovieCard(de: "Straßenküchen Asiens", en: "Street Food Asia", emoji: "🍜", genre: "docu"),
        MovieCard(de: "Vulkane hautnah", en: "Up Close: Volcanoes", emoji: "🌋", genre: "docu"),
        MovieCard(de: "Die Bergsteiger", en: "The Climbers", emoji: "⛰️", genre: "docu"),
        MovieCard(de: "Zeichentrick-Herzen", en: "Animated Hearts", emoji: "🎨", genre: "animation"),
        MovieCard(de: "Das singende Faultier", en: "The Singing Sloth", emoji: "🦥", genre: "animation"),
        MovieCard(de: "Roboter-Freunde", en: "Robot Friends", emoji: "🤖", genre: "animation"),
        MovieCard(de: "Wolkenschloss", en: "Cloud Castle", emoji: "☁️", genre: "animation"),
        MovieCard(de: "Die Mäusebande", en: "The Mouse Gang", emoji: "🐭", genre: "animation"),
        MovieCard(de: "Klassiker-Abend: Schwarzweiß", en: "Classic Night: B&W", emoji: "🎞️", genre: "classic"),
        MovieCard(de: "Der große Stummfilm", en: "The Great Silent", emoji: "🎩", genre: "classic"),
        MovieCard(de: "Casablanca-Vibes", en: "Casablanca Vibes", emoji: "🥃", genre: "classic"),
        MovieCard(de: "Tanz im Regen", en: "Dancing in the Rain", emoji: "☔️", genre: "classic"),
        MovieCard(de: "Krimi-Dinner", en: "Murder Mystery Dinner", emoji: "🍷", genre: "thriller"),
        MovieCard(de: "Weihnachten im Juli", en: "Christmas in July", emoji: "🎄", genre: "romcom"),
        MovieCard(de: "Backduell der Herzen", en: "Bake-Off of Hearts", emoji: "🧁", genre: "comedy"),
        MovieCard(de: "Geister-Airbnb", en: "Haunted Airbnb", emoji: "👻", genre: "horror"),
        MovieCard(de: "Mond-Basis Luna", en: "Moonbase Luna", emoji: "🌕", genre: "scifi"),
    ]
}

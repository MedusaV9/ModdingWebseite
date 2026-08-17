import Foundation

// Montagsmaler word lists (drawable nouns/scenes, couple-flavored mix).
// The deck language comes from the session payload (the creator's language)
// so BOTH clients draw from the identical list — mixed-language couples stay
// in sync. Words are matched case-/whitespace-insensitively.
enum PictionaryWords {
    static func list(lang: String) -> [String] {
        lang == "de" ? de : en
    }

    static let de: [String] = [
        "Herz", "Regenbogen", "Luftballon", "Kaktus", "Leuchtturm", "Schneemann",
        "Pizza", "Croissant", "Spiegelei", "Eiswaffel", "Torte", "Brezel",
        "Kaffeetasse", "Teekanne", "Picknick", "Lagerfeuer", "Zelt", "Wohnmobil",
        "Fahrrad", "Tandem", "Heißluftballon", "Riesenrad", "Karussell", "Achterbahn",
        "Katze", "Hund", "Pinguin", "Faultier", "Oktopus", "Schmetterling",
        "Marienkäfer", "Igel", "Eule", "Flamingo", "Wal", "Seepferdchen",
        "Sonnenblume", "Kirschblüte", "Palme", "Pilz", "Kleeblatt", "Rose",
        "Gitarre", "Klavier", "Kopfhörer", "Mikrofon", "Plattenspieler", "Trommel",
        "Brautkleid", "Ehering", "Liebesbrief", "Kussmund", "Umarmung", "Händchenhalten",
        "Candle-Light-Dinner", "Rosenstrauß", "Pralinen", "Teddybär", "Fotoalbum", "Spieluhr",
        "Strand", "Vulkan", "Wasserfall", "Insel", "Berge", "Vollmond",
        "Sternschnuppe", "Nordlicht", "Gewitter", "Regenschirm", "Schaukel", "Hängematte",
        "Badewanne", "Dusche", "Spiegel", "Zahnbürste", "Föhn", "Lippenstift",
        "Sofa", "Kamin", "Bücherregal", "Wecker", "Lampe", "Schlüssel",
        "Koffer", "Flugzeug", "Segelboot", "U-Boot", "Rakete", "Ufo",
        "Ritterburg", "Krone", "Schatztruhe", "Zauberstab", "Drache", "Einhorn",
        "Meerjungfrau", "Pirat", "Roboter", "Astronaut", "Clown", "Zirkuszelt",
        "Popcorn", "Kino", "Fernbedienung", "Konsole", "Würfel", "Puzzle",
        "Schaukelstuhl", "Strickmütze", "Wollsocken", "Schlittschuhe", "Schlitten", "Iglu",
        "Grill", "Wassermelone", "Cocktail", "Sonnenbrille", "Flip-Flops", "Sandburg",
    ]

    static let en: [String] = [
        "Heart", "Rainbow", "Balloon", "Cactus", "Lighthouse", "Snowman",
        "Pizza", "Croissant", "Fried egg", "Ice cream cone", "Cake", "Pretzel",
        "Coffee cup", "Teapot", "Picnic", "Campfire", "Tent", "Camper van",
        "Bicycle", "Tandem", "Hot air balloon", "Ferris wheel", "Carousel", "Roller coaster",
        "Cat", "Dog", "Penguin", "Sloth", "Octopus", "Butterfly",
        "Ladybug", "Hedgehog", "Owl", "Flamingo", "Whale", "Seahorse",
        "Sunflower", "Cherry blossom", "Palm tree", "Mushroom", "Clover", "Rose",
        "Guitar", "Piano", "Headphones", "Microphone", "Record player", "Drum",
        "Wedding dress", "Wedding ring", "Love letter", "Kiss", "Hug", "Holding hands",
        "Candlelight dinner", "Bouquet", "Chocolates", "Teddy bear", "Photo album", "Music box",
        "Beach", "Volcano", "Waterfall", "Island", "Mountains", "Full moon",
        "Shooting star", "Northern lights", "Thunderstorm", "Umbrella", "Swing", "Hammock",
        "Bathtub", "Shower", "Mirror", "Toothbrush", "Hair dryer", "Lipstick",
        "Sofa", "Fireplace", "Bookshelf", "Alarm clock", "Lamp", "Key",
        "Suitcase", "Airplane", "Sailboat", "Submarine", "Rocket", "UFO",
        "Castle", "Crown", "Treasure chest", "Magic wand", "Dragon", "Unicorn",
        "Mermaid", "Pirate", "Robot", "Astronaut", "Clown", "Circus tent",
        "Popcorn", "Cinema", "Remote control", "Game console", "Dice", "Puzzle",
        "Rocking chair", "Beanie", "Wool socks", "Ice skates", "Sled", "Igloo",
        "Barbecue", "Watermelon", "Cocktail", "Sunglasses", "Flip-flops", "Sandcastle",
    ]
}

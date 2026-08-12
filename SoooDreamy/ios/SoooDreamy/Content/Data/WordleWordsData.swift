import Foundation

// Word pools for the daily Liebes-Wordle 💘.
// Both lists double as the allowed-guess dictionary, so they mix romantic
// words with plenty of common everyday words. Every entry: exactly 5
// letters, UPPERCASE A–Z only (German words are chosen so they need no
// umlauts/ß), no duplicates within a list.
extension ContentPack {
    static let wordleWordsDE: [String] = [
        // Liebe & Gefühle
        "LIEBE", "TRAUM", "BLUME", "STERN", "MONDE", "NACHT", "ROSEN", "GLANZ", "FUNKE", "WONNE",
        "TREUE", "WOLKE", "ENGEL", "PERLE", "BRAUT", "RINGE", "KERZE", "BLICK", "MAGIE", "FEUER",
        "SONNE", "LICHT", "INSEL", "REISE", "FERNE", "HAFEN", "WELLE", "MEERE", "OZEAN", "BRIEF",
        "VERSE", "MUSIK", "KLANG", "WORTE", "SEELE", "GEIST", "SINNE", "WANGE", "LIPPE", "AUGEN",
        "HAARE", "LOCKE", "ANMUT", "GNADE", "JUBEL", "STOLZ", "HUMOR", "WITZE", "SEHNE", "MINNE",
        "FLIRT", "DATES", "DEMUT", "INNIG", "ROMAN",
        // Eigenschaften
        "MUTIG", "STARK", "SANFT", "LEISE", "STILL", "RUHIG", "ERNST", "WEISE", "FLINK", "FLOTT",
        "RASCH", "SAUER", "MILDE", "BLANK", "BLASS", "BLOND", "BRAUN", "EISIG", "DUFTE", "FRECH",
        "SCHEU", "NOBEL", "FIDEL", "VITAL", "AKTIV", "SUPER", "PRIMA", "KRASS",
        // Verben
        "ATMEN", "LEBEN", "LESEN", "MALEN", "BAUEN", "GEHEN", "SEHEN", "ESSEN", "REDEN", "RUFEN",
        "GEBEN", "HEBEN", "EILEN", "BADEN", "NAHEN", "LOBEN", "EHREN", "BETEN", "LOSEN", "RATEN",
        "WEBEN", "FEGEN", "TOBEN", "BOXEN", "TAUEN", "GAREN", "TAGEN", "SAGEN", "ERDEN",
        // Zeit & Alltag
        "ABEND", "WOCHE", "MONAT", "JAHRE", "UHREN", "DATUM", "FESTE", "FEIER", "PARTY", "GABEN",
        "HEUTE", "JETZT", "IMMER", "GERNE", "BEIDE", "ALLES", "ETWAS", "GENUG", "SECHS", "PAUSE",
        // Essen & Trinken
        "APFEL", "BIRNE", "BEERE", "HONIG", "TORTE", "KEKSE", "BROTE", "MILCH", "KAKAO", "TASSE",
        "NUDEL", "SUPPE", "WURST", "QUARK", "SAHNE", "SPECK", "LACHS", "BOHNE", "ERBSE", "LINSE",
        "GURKE", "CHILI", "PILZE", "KRAUT", "KOHLE", "MANGO", "KIWIS", "FEIGE", "OLIVE", "KERNE",
        "SAMEN", "CREME", "SIRUP", "WEINE", "BIERE", "SALAT", "PIZZA", "PASTA", "SUSHI", "HIRSE",
        "HAFER", "MINZE", "CURRY", "PRISE", "AROMA", "LAUCH",
        // Haus & Dinge
        "GABEL", "TISCH", "STUHL", "REGAL", "LAMPE", "BODEN", "DECKE", "KARTE", "SPIEL", "BUCHE",
        "SEITE", "BLATT", "STIFT", "FARBE", "FOTOS", "TAFEL", "HEFTE", "KISTE", "TRUHE", "HAKEN",
        "NADEL", "FADEN", "KNOPF", "SEILE", "KETTE", "KRONE", "JUWEL", "EISEN", "STAHL", "ZINKE",
        "BLECH", "DRAHT", "BETON", "BRETT", "ROHRE", "VASEN", "ZELTE", "LAGER", "SALON", "DIELE",
        "FLURE", "MAUER", "STUFE", "KAMIN", "SEIFE", "PUDER", "LAKEN", "KANNE", "EIMER", "WANNE",
        "BESEN", "HARKE", "ZANGE", "NIETE", "FEDER", "TINTE", "DOSEN", "SIEBE",
        // Kleidung & Stoffe
        "BLUSE", "KLEID", "HOSEN", "JEANS", "JACKE", "SCHAL", "KAPPE", "SOCKE", "SCHUH", "WOLLE",
        "SEIDE", "LEDER", "STOFF", "FASER", "ZWIRN", "FALTE", "KNICK", "FLECK", "DRECK", "PELZE",
        "GARNE", "RISSE",
        // Natur
        "BIRKE", "TANNE", "EICHE", "LINDE", "WIESE", "ACKER", "BERGE", "TEICH", "REGEN", "WINDE",
        "STURM", "BLITZ", "NEBEL", "FROST", "KLIMA", "STEIN", "STAUB", "ASCHE", "RAUCH", "QUALM",
        "DAMPF", "ZWEIG", "MOOSE", "FARNE", "REBEN", "RANKE", "DOLDE", "STAMM", "FLUSS", "ALGEN",
        "WEIDE", "STALL", "PALME", "OASEN", "FJORD", "RIFFE", "DELTA", "STROH",
        // Stadt, Arbeit & Kultur
        "STADT", "PLATZ", "MARKT", "LADEN", "KASSE", "EUROS", "PREIS", "WAREN", "KUNDE", "MARKE",
        "PAKET", "BERUF", "FIRMA", "PLANE", "ZIELE", "IDEEN", "KRAFT", "ANGST", "SORGE", "FRUST",
        "TEMPO", "MACHT", "RECHT", "ORDEN", "REGEL", "KURSE", "PUNKT", "LINIE", "KREIS", "ECKEN",
        "KANTE", "KUGEL", "MITTE", "ENDEN", "START", "SIEGE", "KAMPF", "DUELL", "MATCH", "SPORT",
        "LEHRE", "PROBE", "NOTEN", "GASSE", "OSTEN", "ROUTE", "PFADE", "REICH", "STAAT", "WAGEN",
        "GLEIS", "BUSSE", "AMPEL", "MOTOR", "AUTOS", "HOTEL", "RADIO", "VIDEO", "VILLA", "KINOS",
        "FILME", "SERIE", "MALER", "KUNST", "FRAGE", "TEXTE", "ZEILE", "SILBE", "VOKAL", "TRICK",
        "KNIFF", "PANNE", "CHAOS", "KRISE", "DRAMA", "SZENE", "AKTEN", "ROLLE", "MASKE", "CLOWN",
        "PILOT", "POKAL", "FAHNE", "SEGEL", "ANKER", "BOOTE", "JACHT", "RUDER", "WRACK", "KREBS",
        "METER", "LITER", "GRAMM", "TONNE", "KOMET", "ORBIT", "SONDE", "RADAR", "LASER", "PIXEL",
        "DATEN", "LOGIK", "MATHE", "ATOME", "ZELLE", "VIRUS", "KEIME", "PILLE", "SALBE", "WUNDE",
        "NARBE", "HANDY", "CHIPS", "TIPPS", "LEERE", "GANZE", "ALTAR", "TAUFE", "SEGEN", "GEBET",
        "LANZE", "PFEIL", "BOGEN", "THRON", "PRINZ", "ZWERG", "RIESE", "ELFEN", "NIXEN", "HEXEN",
        "GEIGE", "HARFE", "PAUKE", "ORGEL", "PIANO", "TAKTE", "OPERN", "LAUTE", "SCHAM", "HITZE",
        "EIFER", "LACHE", "WALZE", "HERDE", "BANDE", "SEKTE", "TANGO", "SALSA", "POLKA", "SAUNA",
        "KEGEL", "POKER", "BINGO", "LOTTO", "JOKER", "ATLAS", "VISUM",
        // Tiere
        "KATZE", "HUNDE", "PFERD", "SCHAF", "ZIEGE", "ENTEN", "TAUBE", "ADLER", "FALKE", "EULEN",
        "AMSEL", "MEISE", "SPATZ", "FISCH", "HECHT", "ROBBE", "OTTER", "BIBER", "DACHS", "FUCHS",
        "TIGER", "PANDA", "KOALA", "AFFEN", "ZEBRA", "LAMAS", "RATTE", "HASEN", "ELCHE", "BIENE",
        "WESPE", "RAUPE", "ECHSE", "MOLCH", "LURCH", "OKAPI",
        // Menschen & Körper
        "VATER", "TANTE", "ONKEL", "NEFFE", "LEUTE", "PAARE", "DAMEN", "JUNGE", "BABYS", "STIRN",
        "NASEN", "OHREN", "KEHLE", "BRUST", "BAUCH", "BEINE", "ZEHEN", "NAGEL", "LUNGE", "LEBER",
        "NIERE", "MAGEN", "ADERN", "VENEN", "RIPPE"
    ]

    static let wordleWordsEN: [String] = [
        // Love & feelings
        "HEART", "LOVER", "SWEET", "ANGEL", "BLISS", "CHARM", "DREAM", "FLAME", "SPARK", "ADORE",
        "CUPID", "BRIDE", "GROOM", "AMOUR", "FLIRT", "CRUSH", "TRYST", "ROSES", "DAISY", "TULIP",
        "PEONY", "LILAC", "BLOOM", "PETAL", "PEARL", "JEWEL", "RINGS", "CANDY", "HONEY", "SUGAR",
        "SPICE", "COCOA", "CREAM", "CAKES", "EMBER", "TORCH", "GLEAM", "SHINE", "GLOWS", "BLAZE",
        "MERCY", "GRACE", "FAITH", "TRUST", "PEACE", "UNITY", "PRIDE", "CHEER", "SMILE", "LAUGH",
        "TEARS", "BLUSH", "TEASE", "MUSES", "POEMS",
        // Music & art
        "VERSE", "RHYME", "LYRIC", "SONGS", "DANCE", "TANGO", "SALSA", "WALTZ", "PIANO", "CELLO",
        "FLUTE", "DRUMS", "ORGAN", "OPERA", "CAROL", "CHORD", "BANJO",
        // Everyday things
        "HOUSE", "HOMES", "ROOMS", "TABLE", "CHAIR", "COUCH", "SHELF", "FLOOR", "WALLS", "DOORS",
        "GATES", "FENCE", "PORCH", "ATTIC", "LAMPS", "CLOCK", "WATCH", "PHONE", "PHOTO", "RADIO",
        "MOVIE", "FILMS", "SCENE", "DRAMA", "STAGE", "ACTOR", "MUSIC", "PAINT", "BRUSH", "PAPER",
        "BOOKS", "NOVEL", "DIARY", "STORY", "PAGES", "WORDS", "QUOTE", "NOTES", "CARDS", "GIFTS",
        "PARTY", "FEAST", "TOAST", "BREAD", "FRUIT", "APPLE", "PEACH", "MANGO", "LEMON", "LIMES",
        "GRAPE", "BERRY", "MELON", "OLIVE", "SALAD", "PASTA", "PIZZA", "SUSHI", "CURRY", "BROTH",
        "SOUPS", "SNACK", "TREAT", "DRINK", "JUICE", "CIDER", "WINES", "BEERS", "MOCHA", "LATTE",
        "SPOON", "FORKS", "KNIFE", "PLATE", "GLASS", "BOWLS", "OVENS", "STOVE", "FLOUR", "YEAST",
        "DOUGH", "BAKER", "CHEFS", "COOKS", "SALTY", "MINTY", "ZESTY", "TANGY",
        // Nature
        "NIGHT", "MOONS", "STARS", "COMET", "ORBIT", "SPACE", "EARTH", "WORLD", "OCEAN", "BEACH",
        "SHORE", "WAVES", "TIDES", "CORAL", "SHELL", "CLOUD", "STORM", "RAINY", "WINDY", "SUNNY",
        "FROST", "SNOWY", "MISTY", "FOGGY", "RIVER", "LAKES", "PONDS", "CREEK", "BROOK", "FIELD",
        "GRASS", "GROVE", "WOODS", "TREES", "MAPLE", "BIRCH", "CEDAR", "PINES", "LEAFY", "FERNS",
        "MOSSY", "VINES", "ROOTS", "SEEDS", "PLUMS", "PEARS", "HILLS", "CLIFF", "CAVES", "DUNES",
        "OASIS", "DELTA", "FJORD", "REEFS", "ISLES", "COAST", "NORTH", "SOUTH", "TRAIL", "PATHS",
        "ROADS", "PLAZA", "TOWNS", "URBAN",
        // Animals
        "HORSE", "TIGER", "PANDA", "KOALA", "ZEBRA", "CAMEL", "LLAMA", "SHEEP", "LAMBS", "GOATS",
        "DUCKS", "GEESE", "SWANS", "FINCH", "EAGLE", "HAWKS", "RAVEN", "CRANE", "STORK", "HERON",
        "WHALE", "SHARK", "TROUT", "SNAIL", "CRABS", "PRAWN", "SQUID", "OTTER", "FOXES", "BEARS",
        "LIONS", "MOOSE", "BISON", "SKUNK", "LEMUR", "SLOTH", "GECKO", "COBRA", "VIPER", "FROGS",
        "TOADS", "NEWTS", "WASPS", "MOTHS", "FLIES", "ROBIN", "PUPPY", "KITTY", "BUNNY", "FOALS",
        "COLTS", "DOVES",
        // People & body
        "CHEEK", "BROWS", "MOUTH", "TEETH", "CHEST", "HANDS", "PALMS", "WRIST", "ELBOW", "KNEES",
        "ANKLE", "TORSO", "WAIST", "VOICE", "FACES", "WOMAN", "HUMAN", "CHILD", "UNCLE", "AUNTS",
        "NIECE", "TWINS", "FOLKS", "GUEST", "BUDDY", "MATES",
        // Common staples
        "ABOUT", "ABOVE", "AFTER", "AGAIN", "ALONE", "ALONG", "APART", "AWAKE", "BASIC", "BEGIN",
        "BELOW", "BLEND", "BRAVE", "BRIEF", "BRING", "BROWN", "BUILD", "CARRY", "CATCH", "CLEAN",
        "CLEAR", "CLIMB", "CLOSE", "COLOR", "COUNT", "CRAFT", "DAILY", "DOZEN", "EARLY", "EIGHT",
        "ENJOY", "EQUAL", "EVERY", "EXACT", "EXTRA", "FANCY", "FIFTY", "FIRST", "FOCUS", "FORTY",
        "FRESH", "FRONT", "FUNNY", "GIANT", "GLOBE", "GRAND", "GREAT", "GREEN", "GROUP", "HAPPY",
        "HELLO", "HOTEL", "IDEAL", "IMAGE", "INNER", "JOLLY", "LARGE", "LIGHT", "LUCKY", "LUNCH",
        "MAGIC", "MAJOR", "MERRY", "METAL", "MONEY", "MONTH", "MORAL", "MOUNT", "MOUSE", "NOBLE",
        "OFFER", "OFTEN", "ORDER", "OTHER", "PLACE", "PLANE", "PLANT", "POINT", "POWER", "PRIZE",
        "PROUD", "QUEEN", "QUICK", "QUIET", "RAPID", "REACH", "RIGHT", "ROBOT", "ROUND", "ROYAL",
        "SCALE", "SEVEN", "SHAPE", "SHARP", "SHIRT", "SHOES", "SIGHT", "SIXTY", "SKIRT", "SMALL",
        "SMART", "SOLID", "SOUND", "SPEND", "SPORT", "STAND", "START", "STATE", "STEAM", "STEEL",
        "STICK", "STILL", "STONE", "STORE", "TASTE", "TEACH", "THANK", "THEME", "THING", "THREE",
        "TITLE", "TODAY", "TOKEN", "TOTAL", "TOUCH", "TOWER", "TRAIN", "TREND", "TRUCK", "TRULY",
        "TWICE", "UNDER", "UNION", "VALUE", "VIVID", "WATER", "WHEAT", "WHEEL", "WHILE", "WHITE",
        "WHOLE", "WORTH", "WRITE", "YACHT", "YOUNG", "YOUTH", "LEARN", "STUDY", "SOLVE", "GUESS",
        "SPELL", "GAMES", "PLAYS", "RELAX", "SLEEP", "SHARE", "SPEAK", "THINK", "THROW"
    ]
}

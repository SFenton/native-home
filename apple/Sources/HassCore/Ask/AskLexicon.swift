import Foundation

// MARK: - Lexicon

/// The generic English the resolver needs to read a home question: words that are not part of any device name, and the
/// words that mean a kind, a state or a quantity. Nothing in it is specific to one house.
enum AskLexicon {
    /// Phrases that open a spoken question and carry no content, longest first.
    static let leadIns: [[String]] = [
        ["hey", "siri"], ["okay", "so"], ["ok", "so"], ["i", "was", "wondering"], ["i", "am", "wondering"], ["i", "wonder"],
        ["can", "you", "tell", "me"], ["could", "you", "tell", "me"], ["can", "you", "let", "me", "know"], ["could", "you", "let", "me", "know"],
        ["do", "you", "know"], ["i", "need", "to", "know"], ["i", "want", "to", "know"], ["let", "me", "know"], ["tell", "me"],
        ["quick", "question"], ["just", "checking"], ["can", "you", "check"], ["could", "you", "check"], ["check"],
        ["go", "ahead", "and"], ["hey"], ["hi"], ["hello"], ["okay"], ["ok"], ["so"], ["um"], ["uh"], ["umm"], ["well"],
        ["right"], ["siri"], ["please"], ["actually"], ["alright"], ["and"], ["now"], ["also"], ["yeah"], ["oh"],
    ]

    /// Polite openers that may precede an action verb.
    static let polite: [[String]] = [
        ["i", "need", "you", "to"], ["i", "want", "you", "to"], ["i", "would", "like", "you", "to"], ["i", "d", "like", "you", "to"],
        ["can", "you"], ["could", "you"], ["would", "you"], ["will", "you"], ["you", "should"], ["please"], ["just"], ["kindly"],
        ["go", "ahead", "and"], ["now"],
    ]

    /// First words that make a request an action.
    static let actionVerbs: Set<String> = [
        "turn", "switch", "lock", "unlock", "open", "close", "shut", "set", "dim", "brighten", "start", "stop", "arm", "disarm",
        "toggle", "activate", "deactivate", "enable", "disable", "put", "make", "increase", "decrease", "raise", "lower", "play",
        "pause", "mute", "unmute", "run", "trigger", "cancel", "send", "call", "order", "buy", "remind", "add", "remove", "delete",
        "schedule", "skip", "resume", "restart", "reboot", "reset", "water", "feed", "clean", "sweep", "mop",
    ]

    /// Words that are never part of a name: articles, auxiliaries, interrogatives, prepositions, fillers and the state words
    /// the intent reader consumes. Stored un-stemmed; the resolver stems them the same way it stems the question.
    static let function: Set<String> = Set(
        """
        the a an is are was were be been being am do does did has have had will would can could should shall may might must \
        what whats which who whom whose when whens where wheres how hows why whys that thats this these those there theres here \
        it its of in on off at to for from with by about as into onto over under up down than then and or but nor so if \
        roughly approximately become becomes became put puts pick picked cause caused causes made reason someone somebody nobody idle stopped picking seeing sees detect detects detecting sense senses any anyone anybody anything something everything everyone everybody all both each every some few many much more most least less \
        me my our your us we i you he she they them their him her his hes shes ill ive id were youre theyre \
        please hey hi hello okay ok siri um uh umm quick question wondering tell know check let \
        now currently still yet already moment today tonight tomorrow yesterday ago since long last time again ever just \
        turn turned turning switched switching powered \
        open opened opening closed close shut locked unlocked home away gone left leave leaving out running run playing play paused \
        recording record recorded active detected occupied empty clear enabled disabled armed charging working \
        isnt arent wasnt werent didnt dont doesnt cant wont couldnt wouldnt shouldnt hasnt havent hadnt isn t \
        cold warm hot cool colder warmer hotter cooler coldest warmest hottest coolest humid humidity drier driest humider \
        reading read say says showing show shows value level number count counts degrees degree percent percentage current \
        wise according specifically exactly actually really basically possibly maybe perhaps around anywhere somewhere \
        thing things stuff one ones going go come came comes gets get got getting been tell told said \
        kind sort type like see look looks seem seems feel feels what's \
        wise lately recently late early ones also too very quite pretty
        """.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\\" }).map(String.init)
    )

    /// Words that name a kind of entity (stemmed), and the kind.
    static let kindNouns: [String: AskKind] = [
        "light": .light, "window": .window, "door": .door, "lock": .lock, "alarm": .alarm, "camera": .camera, "vent": .vent,
        "motion": .motion, "occupancy": .occupancy, "presence": .occupancy, "thermostat": .climate, "climate": .climate,
        "tv": .mediaPlayer, "speaker": .mediaPlayer, "player": .mediaPlayer, "music": .mediaPlayer, "fan": .fan, "purifier": .fan,
        "humidifier": .fan, "vacuum": .vacuum, "battery": .battery, "sprinkler": .valve, "valve": .valve, "switch": .switchDevice,
        "plug": .switchDevice, "automation": .automation, "script": .script, "scene": .scene, "weather": .weather,
        "temperature": .temperature, "humidity": .humidity, "aqi": .airQuality, "pm25": .airQuality, "power": .power,
        "doorbell": .camera, "garage": .garage, "movement": .motion, "moving": .motion, "occupied": .occupancy,
    ]

    /// Nouns that carry a value quantity (stemmed) when they appear as a state of the question.
    static let valueWords: [String: AskKind] = [
        "temperature": .temperature, "warm": .temperature, "cold": .temperature, "hot": .temperature, "cool": .temperature,
        "warmer": .temperature, "colder": .temperature, "hotter": .temperature, "cooler": .temperature, "warmest": .temperature,
        "coldest": .temperature, "hottest": .temperature, "coolest": .temperature, "humid": .humidity, "humidity": .humidity,
        "driest": .humidity, "drier": .humidity, "humidest": .humidity, "battery": .battery, "charge": .battery, "pm25": .airQuality,
        "aqi": .airQuality, "quality": .airQuality, "power": .power, "watt": .power, "kw": .power,
    ]

    /// Words that are never an unknown device word: ordinary English that may appear beside a device name.
    static let filler: Set<String> = Set(
        """
        evening morning night afternoon week weekend month year hour minute second day days hours minutes seconds \
        yesterday overnight ever never always sometimes often again before after during while until \
        room house home place space area side part level floor upstairs downstairs outside inside indoors outdoors outdoor indoor \
        name names word words thing stuff way lot bit little big small new old first second third next previous \
        fire fired fires triggered trigger tracking \
        status state states info information update updates report summary details mode thanks thank thankyou tight tightly \
        on off yes no ok okay okay good bad fine okay \
        today tonight own self
        """.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\\" }).map(String.init)
    )

    /// Words that mean the whole house.
    static let houseWords: Set<String> = ["house", "home", "everywhere", "altogether", "overall", "total", "whole", "anywhere", "entire"]

    /// Words for "somebody is in" (occupancy) when no device is named.
    static let personWords: Set<String> = ["anyone", "anybody", "someone", "somebody", "nobody", "noone", "everyone", "everybody"]
}

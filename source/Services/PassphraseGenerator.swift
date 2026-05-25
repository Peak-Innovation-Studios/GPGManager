import Foundation

/// Generates diceware-style passphrases from a curated 256-word English list.
/// 8 words at log2(256) = 8 bits/word → ~64 bits of entropy.
/// Uses `SystemRandomNumberGenerator`, which is cryptographically secure on
/// Apple platforms (backed by `arc4random_buf`).
enum PassphraseGenerator {
    static func suggest(wordCount: Int = 8, separator: String = "-") -> String {
        var rng = SystemRandomNumberGenerator()
        let words = (0..<wordCount).map { _ in pick(using: &rng) }
        return words.joined(separator: separator)
    }

    private static func pick(using rng: inout SystemRandomNumberGenerator) -> String {
        let index = Int.random(in: 0..<wordlist.count, using: &rng)
        return wordlist[index]
    }

    static let wordlist: [String] = [
        // Animals
        "ant", "bat", "bear", "bee", "bird", "bison", "buck", "bunny",
        "camel", "carp", "cat", "clam", "colt", "crab", "crow", "cub",
        "deer", "dog", "dove", "duck", "eagle", "eel", "elk", "emu",
        "ewe", "falcon", "fawn", "ferret", "finch", "fish", "fly", "fox",
        // Nature
        "bay", "beach", "bloom", "bough", "brook", "bush", "cave", "cliff",
        "cloud", "coral", "creek", "delta", "dune", "earth", "fern", "field",
        "fjord", "flame", "fog", "frost", "garden", "geyser", "glade", "glow",
        "grass", "grove", "hill", "ice", "ivy", "jungle", "lake", "leaf",
        // Food
        "apple", "bagel", "bean", "berry", "bread", "broth", "butter", "cake",
        "candy", "carrot", "cheese", "cherry", "chili", "cocoa", "corn", "cream",
        "dough", "egg", "fig", "flour", "fruit", "garlic", "ginger", "grape",
        "herb", "honey", "jam", "kale", "lemon", "lime", "mango", "melon",
        // Objects
        "anchor", "arrow", "axis", "badge", "ball", "banner", "basket", "bell",
        "block", "boat", "book", "bottle", "bowl", "box", "brick", "broom",
        "brush", "candle", "canvas", "card", "chain", "chair", "clock", "coin",
        "compass", "crown", "cup", "desk", "diamond", "dice", "doll", "drum",
        // Adjectives
        "amber", "arctic", "bold", "brave", "bright", "calm", "clear", "cosmic",
        "crisp", "deep", "fancy", "fast", "fierce", "fluid", "fresh", "gentle",
        "happy", "honest", "icy", "ideal", "jolly", "keen", "kind", "lively",
        "lucky", "merry", "noble", "ocean", "polar", "proud", "pure", "quick",
        // Verbs
        "balance", "blossom", "build", "carry", "climb", "create", "dance", "dive",
        "dream", "drift", "echo", "explore", "float", "glide", "guide", "hike",
        "invent", "journey", "leap", "linger", "march", "navigate", "observe", "paint",
        "plant", "polish", "ponder", "render", "rescue", "roam", "rove", "sail",
        // Places
        "abbey", "alley", "arena", "atlas", "bayou", "bistro", "cabin", "campus",
        "canyon", "castle", "chapel", "city", "court", "cove", "depot", "diner",
        "dome", "estate", "harbor", "harvest", "island", "junction", "kingdom", "lagoon",
        "library", "manor", "market", "meadow", "museum", "oasis", "orchard", "palace",
        // Music / arts
        "aria", "ballad", "banjo", "blues", "chord", "concert", "anthem", "flute",
        "harp", "hymn", "jazz", "lyric", "alto", "melody", "opera", "piano",
        "poem", "polka", "quartet", "rhythm", "song", "sonnet", "stage", "tempo",
        "tone", "trio", "tune", "verse", "violin", "waltz", "wave", "weave"
    ]
}

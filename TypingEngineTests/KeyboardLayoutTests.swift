import XCTest
@testable import TypingEngine

final class KeyboardLayoutTests: XCTestCase {
    func testQwertyNeighbors() {
        let n = KeyboardLayout.qwerty.neighbors
        XCTAssertEqual(Set(n["a"] ?? []), ["q", "w", "s", "z"])
        XCTAssertEqual(Set(n["s"] ?? []), ["w", "e", "a", "d", "z", "x"])
        XCTAssertEqual(Set(n["g"] ?? []), ["t", "y", "f", "h", "v", "b"])
        XCTAssertEqual(Set(n["m"] ?? []), ["j", "k", "n"])
        XCTAssertEqual(Set(n["p"] ?? []), ["0", "o", "l"])
        XCTAssertEqual(Set(n["q"] ?? []), ["1", "2", "w", "a"])
    }

    func testJcukenNeighbors() {
        let n = KeyboardLayout.jcuken.neighbors
        XCTAssertEqual(Set(n["ф"] ?? []), ["й", "ц", "ы", "я"])
        XCTAssertEqual(Set(n["ы"] ?? []), ["ц", "у", "ф", "в", "я", "ч"])
        XCTAssertEqual(Set(n["о"] ?? []), ["г", "ш", "р", "л", "т", "ь"])
        XCTAssertEqual(Set(n["ю"] ?? []), ["д", "ж", "б"])
        XCTAssertEqual(Set(n["ъ"] ?? []), ["х", "э"])
    }

    func testEveryLetterHasNeighborsAndRelationIsSymmetric() {
        for layout in KeyboardLayout.all {
            for row in layout.rows {
                for key in row.keys {
                    let neighbors = layout.neighbors[key] ?? []
                    XCTAssertFalse(neighbors.isEmpty, "\(layout.name): у «\(key)» нет соседей")
                    XCTAssertFalse(neighbors.contains(key), "\(layout.name): «\(key)» сосед сам себе")
                    for other in neighbors {
                        XCTAssertTrue(layout.neighbors[other]?.contains(key) == true,
                                      "\(layout.name): «\(key)»→«\(other)» без обратной связи")
                    }
                }
            }
        }
    }

    func testTypoIsNeighborAndPreservesCase() {
        var rng = SeededRandomNumberGenerator(seed: 10)
        for _ in 0..<300 {
            let lower = KeyboardLayout.qwerty.typo(for: "d", using: &rng)!
            XCTAssertTrue(KeyboardLayout.qwerty.neighbors["d"]!.contains(lower))

            let upper = KeyboardLayout.qwerty.typo(for: "D", using: &rng)!
            XCTAssertTrue(upper.isUppercase)
            XCTAssertTrue(KeyboardLayout.qwerty.neighbors["d"]!.contains(Character(upper.lowercased())))

            let cyrillic = KeyboardLayout.jcuken.typo(for: "П", using: &rng)!
            XCTAssertTrue(cyrillic.isUppercase)
            XCTAssertTrue(KeyboardLayout.jcuken.neighbors["п"]!.contains(Character(cyrillic.lowercased())))
        }
    }

    func testNoTypoForCharactersOutsideLayout() {
        var rng = SeededRandomNumberGenerator(seed: 11)
        for character: Character in [" ", "\n", "\t", ",", "!", "😀", "é", "ё", "ß"] {
            XCTAssertNil(KeyboardLayout.qwerty.typo(for: character, using: &rng), "\(character)")
            XCTAssertNil(KeyboardLayout.jcuken.typo(for: character, using: &rng), "\(character)")
        }
    }

    func testLetterLayoutDetection() {
        XCTAssertEqual(KeyboardLayout.letterLayout(for: "k")?.name, "QWERTY")
        XCTAssertEqual(KeyboardLayout.letterLayout(for: "K")?.name, "QWERTY")
        XCTAssertEqual(KeyboardLayout.letterLayout(for: "к")?.name, "ЙЦУКЕН")
        XCTAssertEqual(KeyboardLayout.letterLayout(for: "Щ")?.name, "ЙЦУКЕН")
        XCTAssertNil(KeyboardLayout.letterLayout(for: "5"))
        XCTAssertNil(KeyboardLayout.letterLayout(for: "?"))
    }
}

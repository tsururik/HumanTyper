import Foundation

/// Физическая раскладка клавиатуры и карта соседних клавиш для генерации опечаток.
///
/// Ряды задаются строками со смещением левого края ряда в ширинах клавиши — как на
/// реальной клавиатуре: Q сдвинута на ½ клавиши относительно 1, A — на ¾, Z — на 1¼.
/// Соседи: клавиши того же ряда через одну позицию и клавиши смежных рядов,
/// которые перекрываются по горизонтали (расстояние между центрами < 1 клавиши).
public struct KeyboardLayout: Sendable {
    public struct Row: Sendable {
        public let keys: [Character]
        public let offset: Double

        public init(_ keys: String, offset: Double) {
            self.keys = Array(keys)
            self.offset = offset
        }
    }

    public let name: String
    public let rows: [Row]
    /// Карта «клавиша → соседние клавиши» (строчные символы).
    public let neighbors: [Character: [Character]]

    public init(name: String, rows: [Row]) {
        self.name = name
        self.rows = rows
        self.neighbors = Self.buildNeighbors(rows: rows)
    }

    public static let qwerty = KeyboardLayout(name: "QWERTY", rows: [
        Row("1234567890", offset: 0),
        Row("qwertyuiop", offset: 0.5),
        Row("asdfghjkl", offset: 0.75),
        Row("zxcvbnm", offset: 1.25),
    ])

    public static let jcuken = KeyboardLayout(name: "ЙЦУКЕН", rows: [
        Row("1234567890", offset: 0),
        Row("йцукенгшщзхъ", offset: 0.5),
        Row("фывапролджэ", offset: 0.75),
        Row("ячсмитьбю", offset: 1.25),
    ])

    public static let all: [KeyboardLayout] = [.qwerty, .jcuken]

    /// Есть ли символ (без учёта регистра) на этой раскладке.
    public func contains(_ character: Character) -> Bool {
        guard let key = Self.lowercasedKey(character) else { return false }
        return neighbors[key] != nil
    }

    /// Раскладка, на которой набирается буква. Для цифр и прочих символов — `nil`:
    /// цифры есть на обеих раскладках, их раскладку определяет контекст.
    public static func letterLayout(for character: Character) -> KeyboardLayout? {
        guard character.isLetter else { return nil }
        return all.first { $0.contains(character) }
    }

    /// Опечатка: случайная соседняя клавиша с сохранением регистра.
    /// `nil`, если символа нет на раскладке (пробел, пунктуация, эмодзи и т. д.).
    public func typo<R: RandomNumberGenerator>(for character: Character, using rng: inout R) -> Character? {
        guard let key = Self.lowercasedKey(character),
              let options = neighbors[key],
              let pick = options.randomElement(using: &rng)
        else { return nil }
        guard character.isUppercase, let upper = Self.singleCharacter(pick.uppercased()) else { return pick }
        return upper
    }

    private static func lowercasedKey(_ character: Character) -> Character? {
        singleCharacter(character.lowercased())
    }

    private static func singleCharacter(_ string: String) -> Character? {
        string.count == 1 ? string.first : nil
    }

    private static func buildNeighbors(rows: [Row]) -> [Character: [Character]] {
        var result: [Character: [Character]] = [:]
        for (rowIndex, row) in rows.enumerated() {
            for (keyIndex, key) in row.keys.enumerated() {
                let x = row.offset + Double(keyIndex)
                var list: [Character] = []
                for otherRowIndex in max(rowIndex - 1, 0)...min(rowIndex + 1, rows.count - 1) {
                    let other = rows[otherRowIndex]
                    for (otherIndex, otherKey) in other.keys.enumerated() where otherKey != key {
                        let distance = abs(other.offset + Double(otherIndex) - x)
                        let adjacent = otherRowIndex == rowIndex ? distance == 1 : distance < 1
                        if adjacent { list.append(otherKey) }
                    }
                }
                result[key] = list
            }
        }
        return result
    }
}

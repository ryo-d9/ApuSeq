import Foundation

enum TextDecoding {
    static let candidateEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian,
        .shiftJIS,
        .isoLatin1,
        .ascii
    ]

    static func decode(_ data: Data) -> String? {
        candidateEncodings.compactMap { String(data: data, encoding: $0) }.first
    }
}

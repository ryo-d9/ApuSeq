import Foundation

enum TextDecoding {
    private static let preferredEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian
    ]

    private static let fallbackEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian,
        .shiftJIS,
        .isoLatin1,
        .ascii
    ]

    static func decode(_ data: Data) -> String? {
        decode(data, using: preferredEncodings)
            ?? decodeUsingFoundationInference(data)
            ?? decode(data, using: fallbackEncodings)
    }

    private static func decode(_ data: Data, using encodings: [String.Encoding]) -> String? {
        encodings.lazy.compactMap { String(data: data, encoding: $0) }.first
    }

    private static func decodeUsingFoundationInference(_ data: Data) -> String? {
        var converted: NSString?
        var usedLossyConversion = ObjCBool(false)
        let suggestedEncodings = fallbackEncodings.map(\.rawValue)

        let detectedEncoding = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: suggestedEncodings,
                .useOnlySuggestedEncodingsKey: false
            ],
            convertedString: &converted,
            usedLossyConversion: &usedLossyConversion
        )

        guard detectedEncoding != 0, !usedLossyConversion.boolValue else { return nil }
        if let converted {
            return converted as String
        }
        return String(data: data, encoding: String.Encoding(rawValue: detectedEncoding))
    }
}

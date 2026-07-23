import Foundation

enum TextDecoding {
    private static let fallbackEncodings: [String.Encoding] = [
        .shiftJIS,
        .isoLatin1,
        .ascii
    ]

    static func decode(_ data: Data) -> String? {
        decode(data, as: .utf8)
            ?? decodeUsingFoundationInference(data)
            ?? decodeUTF16(data)
            ?? decode(data, using: fallbackEncodings)
    }

    private static func decode(_ data: Data, using encodings: [String.Encoding]) -> String? {
        encodings.lazy.compactMap { decode(data, as: $0) }.first
    }

    private static func decode(_ data: Data, as encoding: String.Encoding) -> String? {
        guard let decoded = String(data: data, encoding: encoding), isReadableText(decoded) else { return nil }
        return decoded
    }

    private static func decodeUTF16(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return decode(data, as: .utf16)
        }
        guard let bytePattern = utf16BytePattern(data) else { return nil }
        return decode(data, as: bytePattern)
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
            let decoded = converted as String
            return isReadableText(decoded) ? decoded : nil
        }
        return decode(data, as: String.Encoding(rawValue: detectedEncoding))
    }

    private static func utf16BytePattern(_ data: Data) -> String.Encoding? {
        let bytes = Array(data.prefix(64))
        guard bytes.count >= 4 else { return nil }
        let evenNulls = stride(from: 0, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
        let oddNulls = stride(from: 1, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
        let pairCount = bytes.count / 2
        if oddNulls * 2 >= pairCount { return .utf16LittleEndian }
        if evenNulls * 2 >= pairCount { return .utf16BigEndian }
        return nil
    }

    private static func isReadableText(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            scalar.value == 0 || (scalar.value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t")
        }
    }
}

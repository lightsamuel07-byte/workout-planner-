import Foundation

func persistenceMakeRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
        fatalError("Invalid regex: \(pattern)")
    }
}

func persistenceFullRange(of string: String) -> NSRange {
    NSRange(string.startIndex..<string.endIndex, in: string)
}

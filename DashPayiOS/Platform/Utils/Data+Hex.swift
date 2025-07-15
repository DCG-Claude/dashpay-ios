import Foundation

extension Data {
    /// Converts the Data to a lowercase hexadecimal string representation
    func toHexString() -> String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}
import Foundation

/// `application/x-www-form-urlencoded` encoding for OAuth token requests.
/// Built on `URLComponents` rather than a hand-rolled `CharacterSet`, since
/// a naive escape set risks leaving reserved characters (`+`, `&`, `=`)
/// unescaped in a value like an auth code — `URLComponents`'s query-string
/// percent-encoding already handles this correctly and is exactly the same
/// format as form encoding.
public enum CloudFormEncoding {
    public static func encode(_ items: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        return (components.percentEncodedQuery ?? "").data(using: .utf8) ?? Data()
    }
}

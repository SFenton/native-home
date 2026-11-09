import Foundation

/// Turns what a person types in the sign-in Server field into a ``HassServer``
/// (`.agents/design/house-config-states.md`, rule 4). A pure function: it never touches the network.
///
/// - Trims the text.
/// - With no scheme it adds `https://`, except for a local host (`*.local`, `localhost`, a single-label host name such as
///   `homeassistant`, or an RFC 1918, link-local or loopback IPv4 address), which gets `http://`. The port does not matter.
/// - Drops the user info, path, query, fragment and trailing slash, and keeps an explicit port.
/// - Accepts a bracketed IPv6 address (`[fe80::1]:8123`) and an internationalised host in Unicode or punycode; the URL carries
///   the punycode, ``displayText(for:includesScheme:)`` shows the Unicode.
/// - Plain `http://` is allowed only for a local host.
public enum HassServerAddress {
    /// Why an address was refused.
    public enum AddressError: Error, Sendable, Equatable {
        /// Nothing was typed.
        case empty
        /// The text is not an address (spaces, no host, a scheme other than http and https, a bad port).
        case invalid
        /// `http://` was typed for a host that is not on the local network.
        case insecureRemote
    }

    /// Parses `text`.
    /// - Parameter text: What the person typed.
    /// - Returns: The normalised server, or why it was refused.
    public static func parse(_ text: String) -> Result<HassServer, AddressError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard !trimmed.contains(where: \.isWhitespace) else { return .failure(.invalid) }

        var typedScheme: String?
        var rest = trimmed
        if let range = trimmed.range(of: "://") {
            typedScheme = String(trimmed[..<range.lowerBound]).lowercased()
            rest = String(trimmed[range.upperBound...])
            guard typedScheme == "http" || typedScheme == "https" else { return .failure(.invalid) }
        }
        // Parse the authority on its own, whatever follows it.
        guard let components = URLComponents(string: "x://" + rest),
              let host = components.host?.lowercased(), isPlausible(host: host) else { return .failure(.invalid) }
        let authority = rest.prefix { !"/?#".contains($0) }
        let hostAndPort = authority.split(separator: "@", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let port = components.port
        // An IPv6 literal is full of colons; only what follows its closing bracket can be a port.
        let afterHost = hostAndPort.hasPrefix("[") ? String(hostAndPort.drop { $0 != "]" }.dropFirst()) : hostAndPort
        let hasPortSeparator = hostAndPort.hasPrefix("[") ? !afterHost.isEmpty : hostAndPort.contains(":")
        if hasPortSeparator, port == nil || !(1...65535).contains(port ?? 0) { return .failure(.invalid) }

        let local = isLocal(host: host)
        let scheme = typedScheme ?? (local ? "http" : "https")
        if scheme == "http", !local { return .failure(.insecureRemote) }

        var built = URLComponents()
        built.scheme = scheme
        built.host = host
        built.port = port
        guard let url = built.url else { return .failure(.invalid) }
        return .success(HassServer(baseURL: url))
    }

    /// How a server reads to a person: its scheme (unless `includesScheme` is false), host and port. An internationalised host
    /// shows in Unicode (`münchen.example`), not the punycode (`xn--mnchen-3ya.example`) the URL carries on the wire, and an IPv6
    /// address keeps its brackets. Parsing the result gives the same server back.
    /// - Parameters:
    ///   - server: The parsed server.
    ///   - includesScheme: Whether to lead with `https://` or `http://`.
    public static func displayText(for server: HassServer, includesScheme: Bool = true) -> String {
        guard let components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false),
              let host = components.host else { return server.baseURL.absoluteString }
        let hostAndPort = components.port.map { "\(host):\($0)" } ?? host
        guard includesScheme, let scheme = components.scheme else { return hostAndPort }
        return "\(scheme)://\(hostAndPort)"
    }

    /// Whether `host` is on the local network: `*.local`, `localhost`, a single-label name, or a private, link-local or loopback
    /// IPv4 address, or a loopback, link-local or unique-local IPv6 address (bracketed or not).
    public static func isLocal(host: String) -> Bool {
        let host = host.lowercased()
        if let address = ipv6Address(host) { return isLocal(ipv6: address) }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") { return true }
        if !host.contains(".") { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ ($0 ?? -1) >= 0 && ($0 ?? 256) <= 255 }),
              let first = octets[0], let second = octets[1] else { return false }
        switch first {
        case 10, 127: return true
        case 172: return (16...31).contains(second)
        case 192: return second == 168
        case 169: return second == 254
        default: return false
        }
    }

    /// The address of an IPv6 literal, with or without its brackets, or `nil` when `host` is not one.
    private static func ipv6Address(_ host: String) -> in6_addr? {
        var text = host
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else { return nil }
            text = String(text.dropFirst().dropLast())
        }
        guard text.contains(":") else { return nil }
        var address = in6_addr()
        return inet_pton(AF_INET6, text, &address) == 1 ? address : nil
    }

    /// `::1`, `fe80::/10` (link-local) and the unique-local range are on the local network; so is an IPv4-mapped private address.
    private static func isLocal(ipv6 address: in6_addr) -> Bool {
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes[15] == 1 { return true }
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return true }
        if bytes[0] & 0xFE == 0xFC { return true }
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            return isLocal(host: bytes[12..<16].map(String.init).joined(separator: "."))
        }
        return false
    }

    private static func isPlausible(host: String) -> Bool {
        if host.hasPrefix("[") { return ipv6Address(host) != nil }
        guard !host.isEmpty, !host.hasPrefix("."), !host.hasSuffix("."), !host.hasPrefix("-") else { return false }
        return host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
    }
}

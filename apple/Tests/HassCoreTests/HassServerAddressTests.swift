import Foundation
@testable import HassCore
import Testing

/// What the sign-in Server field turns typed text into: the scheme, the local-host rule, trimming, paths and ports.
struct HassServerAddressTests {
    private func parsed(_ text: String) -> String? {
        if case let .success(server) = HassServerAddress.parse(text) { return server.baseURL.absoluteString }
        return nil
    }

    private func error(_ text: String) -> HassServerAddress.AddressError? {
        if case let .failure(error) = HassServerAddress.parse(text) { return error }
        return nil
    }

    @Test func aBareRemoteHostGetsHTTPS() {
        #expect(parsed("ha.example.com") == "https://ha.example.com")
        #expect(parsed("HA.Example.COM") == "https://ha.example.com")
        #expect(parsed("ha.example.com:443") == "https://ha.example.com:443")
    }

    @Test func localHostsGetHTTP() {
        #expect(parsed("homeassistant.local") == "http://homeassistant.local")
        #expect(parsed("homeassistant.local:8123") == "http://homeassistant.local:8123")
        #expect(parsed("localhost") == "http://localhost")
        #expect(parsed("10.0.0.1") == "http://10.0.0.1")
        #expect(parsed("172.16.0.1") == "http://172.16.0.1")
        #expect(parsed("172.31.255.254") == "http://172.31.255.254")
        #expect(parsed("192.168.0.1:8123") == "http://192.168.0.1:8123")
        #expect(parsed("169.254.10.1") == "http://169.254.10.1")
        #expect(parsed("127.0.0.1") == "http://127.0.0.1")
    }

    @Test func outsideThePrivateRangesIsRemote() {
        #expect(parsed("172.15.0.1") == "https://172.15.0.1")
        #expect(parsed("172.32.0.1") == "https://172.32.0.1")
        #expect(parsed("8.8.8.8") == "https://8.8.8.8")
        #expect(parsed("192.169.1.1") == "https://192.169.1.1")
        #expect(!HassServerAddress.isLocal(host: "999.1.1.1"))
    }

    @Test func aRemoteHostOnPort8123StillGetsHTTPS() {
        #expect(parsed("ha.example.com:8123") == "https://ha.example.com:8123")
        #expect(parsed("https://ha.example.com:8123") == "https://ha.example.com:8123")
        #expect(error("http://ha.example.com:8123") == .insecureRemote)
    }

    @Test func aSingleLabelHostNameIsLocal() {
        #expect(parsed("homeassistant") == "http://homeassistant")
        #expect(parsed("homeassistant:8123") == "http://homeassistant:8123")
    }

    @Test func aTypedSchemeIsKept() {
        #expect(parsed("https://homeassistant.local") == "https://homeassistant.local")
        #expect(parsed("HTTPS://ha.example.com") == "https://ha.example.com")
        #expect(parsed("http://homeassistant.local:8123") == "http://homeassistant.local:8123")
    }

    @Test func plainHTTPToARemoteHostIsRefused() {
        #expect(error("http://ha.example.com") == .insecureRemote)
        #expect(error("http://8.8.8.8:80") == .insecureRemote)
    }

    @Test func whitespaceIsTrimmed() {
        #expect(parsed("  ha.example.com \n") == "https://ha.example.com")
        #expect(error("ha example.com") == .invalid, "spaces inside are not an address")
    }

    @Test func emptyInputIsRefused() {
        #expect(error("") == .empty)
        #expect(error("   \n") == .empty)
    }

    @Test func pathQueryFragmentUserInfoAndTrailingSlashAreDropped() {
        #expect(parsed("https://ha.example.com/") == "https://ha.example.com")
        #expect(parsed("ha.example.com/lovelace/0?x=1#top") == "https://ha.example.com")
        #expect(parsed("homeassistant.local:8123/config/integrations") == "http://homeassistant.local:8123")
        #expect(parsed("https://alex:pw@ha.example.com:8443/a/b") == "https://ha.example.com:8443")
        #expect(parsed("ha.example.com?x=1") == "https://ha.example.com")
    }

    @Test func portsAreKeptAndValidated() {
        #expect(parsed("ha.example.com:8443") == "https://ha.example.com:8443")
        #expect(error("ha.example.com:99999") == .invalid)
        #expect(error("ha.example.com:0") == .invalid)
        #expect(error("ha.example.com:abc") == .invalid)
        #expect(error("ha.example.com:") == .invalid)
    }

    @Test func notAnAddressIsInvalid() {
        #expect(error("ftp://ha.example.com") == .invalid)
        #expect(error("https://") == .invalid)
        #expect(error("://x") == .invalid)
        #expect(error("/lovelace") == .invalid)
        #expect(error(".example.com") == .invalid)
        #expect(error("ha_example!.com") == .invalid)
    }

    private func display(_ text: String, includesScheme: Bool = true) -> String? {
        guard case let .success(server) = HassServerAddress.parse(text) else { return nil }
        return HassServerAddress.displayText(for: server, includesScheme: includesScheme)
    }

    /// Fails if: a bracketed IPv6 address is refused, loses its brackets or port, or a local one is not allowed plain http.
    @Test func bracketedIPv6AddressesAreAccepted() {
        #expect(parsed("[fe80::1]:8123") == "http://[fe80::1]:8123")
        #expect(parsed("http://[::1]") == "http://[::1]")
        #expect(parsed("[::1]:8123/lovelace") == "http://[::1]:8123")
        #expect(parsed("[::ffff:127.0.0.1]") == "http://[::ffff:127.0.0.1]", "an IPv4-mapped loopback address is local")
        #expect(error("http://[::ffff:8.8.8.8]") == .insecureRemote, "an IPv4-mapped public address is not")
        #expect(parsed("https://[2001:db8::1]:8443") == "https://[2001:db8::1]:8443")
        #expect(parsed("[2001:DB8::1]") == "https://[2001:db8::1]", "a public address gets https")
    }

    /// Fails if: a malformed IPv6 literal or port after the brackets is accepted, or plain http to a public IPv6 address is.
    @Test func malformedOrInsecureIPv6IsRefused() {
        #expect(error("[fe80::1") == .invalid)
        #expect(error("[not:ipv6]") == .invalid)
        #expect(error("[fe80::1]:99999") == .invalid)
        #expect(error("[fe80::1]:abc") == .invalid)
        #expect(error("[fe80::1]x") == .invalid)
        #expect(error("http://[2001:db8::1]") == .insecureRemote)
        #expect(error("fe80::1") == .invalid, "an IPv6 address needs its brackets")
    }

    /// Fails if: an internationalised host is refused, shown as punycode in the field, or does not round-trip.
    @Test func internationalisedHostsShowInUnicodeAndStayPunycodeOnTheWire() {
        #expect(parsed("münchen.example") == "https://xn--mnchen-3ya.example")
        #expect(display("münchen.example") == "https://münchen.example")
        #expect(display("xn--mnchen-3ya.example:8443") == "https://münchen.example:8443")
        #expect(display("münchen.example:8443", includesScheme: false) == "münchen.example:8443")
        #expect(display("[fe80::1]:8123", includesScheme: false) == "[fe80::1]:8123")
        #expect(display("ha.example.com") == "https://ha.example.com")
        let shown = display("münchen.example") ?? ""
        #expect(parsed(shown) == "https://xn--mnchen-3ya.example", "the shown text parses back to the same server")
    }

    @Test func theResultIsAServerThatBuildsURLs() throws {
        guard case let .success(server) = HassServerAddress.parse("homeassistant.local:8123") else { Issue.record("expected a server"); return }
        #expect(server.url("/auth/login_flow").absoluteString == "http://homeassistant.local:8123/auth/login_flow")
    }
}

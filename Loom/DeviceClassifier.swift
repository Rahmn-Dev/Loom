import Foundation

enum DeviceClassifier {
    static func classify(name: String, services: Set<String>, isGateway: Bool = false, isLocal: Bool = false) -> DeviceKind {
        if isGateway { return .router }
        if isLocal { return .computer }
        let haystack = ([name] + services.map { $0 }).joined(separator: " ").lowercased()
        if contains(haystack, ["iphone", "android", "phone"]) { return .phone }
        if contains(haystack, ["ipad", "tablet"]) { return .tablet }
        if contains(haystack, ["macbook", "laptop", "notebook"]) { return .laptop }
        if contains(haystack, ["imac", "mac-mini", "mac mini", "desktop", "workstation", "pc-"]) { return .desktop }
        if contains(haystack, ["appletv", "apple tv", "chromecast", "googlecast", "television", "smart-tv", "tv-"]) { return .television }
        if contains(haystack, ["homepod", "speaker", "sonos", "raop", "airplay"]) { return .speaker }
        if contains(haystack, ["printer", "ipp", "epson", "canon", "brother", "hp-"]) { return .printer }
        if contains(haystack, ["playstation", "xbox", "nintendo", "console"]) { return .gameConsole }
        if contains(haystack, ["nas", "synology", "qnap", "truenas", "server"]) { return .nasServer }
        if contains(haystack, ["apple watch", "applewatch", "wearable", "smartwatch"]) { return .wearable }
        if contains(haystack, ["hue", "homekit", "_hap", "light", "nest", "camera", "iot"]) { return .smartHome }
        if contains(haystack, ["router", "gateway", "access-point"]) { return .router }
        return .unknown
    }

    static func friendlyName(hostname: String?, ip: String) -> String {
        guard var name = hostname, !name.isEmpty else { return "Unknown Device" }
        if name.hasSuffix(".local.") { name.removeLast(7) }
        else if name.hasSuffix(".local") { name.removeLast(6) }
        return name.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contains(_ text: String, _ terms: [String]) -> Bool {
        terms.contains(where: text.contains)
    }
}

# Loom for macOS

A native SwiftUI local-first network discovery and observability app inspired by the supplied Loom mockup. Loom starts scanning as soon as it opens and only displays devices, services, activity, and findings produced by real local observations. Production views contain no demo data.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer
- Local Network permission (macOS asks on first launch)

## Run

Open `Loom.xcodeproj`, select the **Loom** scheme, and press **Run**.

On launch, Loom reads the IPv4 address and netmask of the default-route interface, calculates the real subnet host range, and actively probes it with a bounded 48-host worker pool. It never assumes `/24`. UDP probes trigger neighbor resolution, ICMP echo provides the same positive signal available to Terminal `ping`, and short targeted TCP checks add service evidence. A failed ICMP or TCP probe is never treated as proof that a device is offline. Any positive ICMP, TCP, or neighbor observation immediately creates an `Unknown Device`; hostname, MAC, vendor, Bonjour identity, and services enrich that same model asynchronously.

The neighbor table is re-read after every batch and after the sweep. Loom reads IPv4 link-layer neighbor routes directly through the native macOS routing-table API, with system `arp` parsing as an additional fallback. For a positively reachable host Loom also attempts a scoped lookup, then merges any available MAC into the device that is already on screen. Bonjour/mDNS and reverse-DNS results are merged continuously, so devices appear before the sweep finishes.

After the first sweep, Bonjour remains active, known devices are checked every 20 seconds, and a bounded active rescan runs at the interval selected in Settings. Subnets up to 4,094 hosts are swept in full; larger enterprise or VPN ranges use a 4,094-host window centered around this Mac, always including the gateway. The UI explicitly labels this safety limit.

## Product behavior

- **Devices:** filters, persistent MAC-aware identity, first/last seen, online state, hostname, observed MAC and MAC type, trust state, and observed services.
- **Device Inspector:** one shared inspector from Overview, Devices, and Network Map with detected identity, custom naming, IP/MAC/vendor/type, reachability history, services, and trust controls. Custom names are stored separately from detected names and follow the MAC identity across DHCP address changes.
- **Network Map:** the observed gateway is central; device lines mean shared LAN visibility and do not claim a physical route or access-point topology.
- **Activity:** locally persisted, de-noised observation events such as first discovery, return, apparent offline state, identity changes, and new services.
- **Services:** Bonjour results are marked `DISCOVERED`; direct TCP accepts are marked `OPEN`. Loom does not call an open port a vulnerability.
- **Security:** neutral findings derived from untrusted/new devices and actual service observations.
- **Settings:** launch scan, monitoring, discovery sources, bounded rescan interval, notifications, privacy, and local-history controls.

Device and activity JSON are stored in `~/Library/Application Support/Loom/`. Preferences use the app's local `UserDefaults`. A locally administered/randomized MAC is deliberately shown with vendor `Unknown`; Loom does not guess a vendor when identity is not reliable.

The code keeps SwiftUI views separate from the discovery engine, Bonjour resolver, reachability/service probes, device classifier, settings store, and device/activity repositories. Scan and name-resolution worker pools are bounded, cancellable, and do not block the main actor.

Debug builds write one detailed, freshly truncated scan trace to `~/Library/Application Support/Loom/scan-debug.log`. It records every generated candidate, attempted probe and mechanism, result, neighbor lookup, hostname resolution, model creation or exact drop reason, identity merge, and SwiftUI publication. Release builds omit this verbose per-address trace.

## Build and test

```sh
xcodegen generate
xcodebuild -project Loom.xcodeproj -scheme Loom -destination 'platform=macOS' -derivedDataPath work/DerivedData build
xcodebuild -project Loom.xcodeproj -scheme Loom -destination 'platform=macOS' -derivedDataPath work/TestDerivedData test
```

## Permissions and distribution limits

The app declares `NSLocalNetworkUsageDescription` and the Bonjour service types it browses. macOS may ask for Local Network access on first launch; discovery will be incomplete if the user denies it.

The active scan launches the system `/sbin/route`, `/sbin/ping`, and `/usr/sbin/arp` utilities to read the default route, observe ICMP replies, and enrich devices from the neighbor table, so App Sandbox is disabled for this V1. If macOS or the launch environment makes a neighbor observation unavailable, Loom keeps the MAC and vendor as `Unknown`; it never invents them and never withholds a device that was otherwise positively observed. A Developer ID distribution can use this architecture, but Mac App Store distribution would require replacing those subprocess-backed observations with approved sandbox-compatible implementations. Loom does not require router credentials and never authenticates to or scrapes a router administration page.

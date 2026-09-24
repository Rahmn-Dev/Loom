
<p align="center">
  <img width="128" height="128" alt="Loom-Icon-iOS-Default-128x128@2x" src="https://github.com/user-attachments/assets/77180c43-d911-4ca8-aea1-f14ce0a69388" />
</p>
<h1 align="center">Loom</h1>

**A beautiful, local-first network discovery and observability app for macOS.**

Loom automatically discovers devices on your local network, identifies them where possible, and continuously monitors their presence — entirely on your Mac.

<img width="1920" height="1280" alt="692_1x_shots_so" src="https://github.com/user-attachments/assets/d0bb2b38-f8ad-4f2f-91bb-7c4bdd0c3abb" />


> No account. No cloud. No router login. Your network observations stay on your Mac.

## Highlights

- **Automatic Network Discovery** — Scan the current LAN automatically on launch.
- **Live Network Map** — Explore devices through a visual network topology.
- **Device Identification** — Observe IP addresses, MAC addresses, hostnames, device types, and services when available.
- **Real-Time Monitoring** — Track devices as they appear, disappear, or return to the network.
- **Device Memory** — Rename, categorize, and remember devices across DHCP address changes.
- **Trusted Devices** — Mark known devices and quickly review unfamiliar ones.
- **Service Discovery** — Discover Bonjour/mDNS services and directly observed TCP services.
- **Activity History** — Keep a local timeline of meaningful network changes.
- **Privacy First** — No account, cloud backend, router credentials, or router scraping.

## Built for macOS

Loom is written natively in **Swift and SwiftUI** and designed specifically for macOS.

**Requirements**

- macOS 14+
- Xcode 16+
- Local Network permission

## Getting Started

Clone the repository and open:

```text
Loom.xcodeproj
```

Select the **Loom** scheme and press **Run**.

Loom begins discovering the current local network automatically when it launches.

---

## How Discovery Works

Loom determines the active network interface, reads its IPv4 address and subnet mask, calculates the actual subnet, and performs bounded concurrent discovery across the appropriate host range.

Discovery combines multiple observations:

- ICMP reachability
- Neighbor/ARP information
- Bonjour/mDNS
- Reverse DNS
- Targeted TCP service checks

A failed ICMP or TCP probe is **never treated as proof that a device is offline**.

As soon as Loom obtains a positive observation, the device can appear in the UI. Additional identity information such as hostname, MAC address, vendor, Bonjour identity, and services is resolved asynchronously.

Loom never assumes `/24`.

For unusually large networks, scanning is bounded to prevent accidentally probing tens of thousands of addresses.

## Device Identity

Loom separates **observed identity** from **user-defined identity**.

A device may contain:

- IP address
- Observed MAC address
- Hostname
- Detected device type
- Vendor when reliably identifiable
- First and last seen timestamps
- Observed services
- User-defined name
- User-defined category
- Trusted state

Custom device names are associated with persistent device identity when possible instead of only the current DHCP address.

Locally administered or randomized MAC addresses are preserved and identified as private/local addresses. Loom does not fabricate a vendor when one cannot be reliably determined.

## Network Map

The gateway is presented as the central network node while discovered devices surround it.

Connections in the map represent **shared LAN visibility**, not physical network routes or access-point topology.

Loom deliberately avoids claiming network topology it cannot actually observe.

## Services

Loom distinguishes between two types of service observations:

- `DISCOVERED` — advertised through protocols such as Bonjour/mDNS.
- `OPEN` — Loom directly observed a TCP connection being accepted.

An open port is not automatically classified as a vulnerability.

## Security

Loom provides a lightweight observational security view for the local network.

It can highlight:

- Newly discovered devices
- Untrusted devices
- Newly observed services
- Locally reachable services
- Relevant device identity changes

`Untrusted` means the device has **not yet been marked as trusted by the user**. It does not mean the device is malicious.

## Privacy

Loom is local-first.

Device and activity data are stored in:

```text
~/Library/Application Support/Loom/
```

Preferences are stored using local `UserDefaults`.

Loom does not require:

- A Loom account
- Cloud infrastructure
- Router credentials
- Router administration access
- Router-page scraping

## Architecture

The project keeps the SwiftUI presentation layer separate from network discovery and persistence.

Core responsibilities include:

```text
SwiftUI
   │
   ├── Device / Network State
   │
Discovery Engine
   ├── Interface & Subnet Detection
   ├── Active Discovery
   ├── Neighbor Resolution
   ├── Bonjour / mDNS
   ├── Reachability
   └── Service Discovery
   │
Identity & Monitoring
   ├── Device Resolution
   ├── Device Classification
   ├── Activity Tracking
   └── Network Monitoring
   │
Local Persistence
```

Scan and name-resolution worker pools are bounded, cancellable, and do not block the main actor.

## Debugging

Debug builds write a detailed scan trace to:

```text
~/Library/Application Support/Loom/scan-debug.log
```

The trace records candidate generation, probes, neighbor observations, hostname resolution, identity merging, device creation, filtering, and SwiftUI publication.

Verbose per-address tracing is omitted from Release builds.

## Build & Test

```sh
xcodegen generate

xcodebuild \
  -project Loom.xcodeproj \
  -scheme Loom \
  -destination 'platform=macOS' \
  -derivedDataPath work/DerivedData \
  build

xcodebuild \
  -project Loom.xcodeproj \
  -scheme Loom \
  -destination 'platform=macOS' \
  -derivedDataPath work/TestDerivedData \
  test
```

## Permissions & Distribution

Loom declares Local Network usage and the Bonjour service types required for discovery.

The current V1 also uses selected macOS system utilities for route, ICMP, and neighbor observations. App Sandbox is therefore disabled in the current architecture.

A Developer ID distribution can use this architecture. Mac App Store distribution would require replacing subprocess-backed functionality with sandbox-compatible implementations.

If macOS prevents an observation, Loom reports that information as unavailable rather than inventing it.

---

### Built with

**Swift · SwiftUI · Network.framework · Bonjour/mDNS**

Designed and built for macOS.

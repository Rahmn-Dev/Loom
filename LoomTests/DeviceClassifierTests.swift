import XCTest
@testable import Loom

private actor LiveDeviceCollector {
    private var devicesByAddress: [String: NetworkDevice] = [:]

    func consume(_ devices: [NetworkDevice]) {
        for device in devices {
            devicesByAddress[device.ipAddress] = device
        }
    }

    func device(at address: String) -> NetworkDevice? {
        devicesByAddress[address]
    }
}

final class DeviceClassifierTests: XCTestCase {
    func testClassifiesCommonBonjourServices() {
        XCTAssertEqual(DeviceClassifier.classify(name: "Living Room TV", services: ["_googlecast_tcp"]), .television)
        XCTAssertEqual(DeviceClassifier.classify(name: "Office Printer", services: ["_ipp_tcp"]), .printer)
        XCTAssertEqual(DeviceClassifier.classify(name: "Hue Bridge", services: ["_hap_tcp"]), .smartHome)
    }

    func testFriendlyNames() {
        XCTAssertEqual(DeviceClassifier.friendlyName(hostname: "MacBook-Air.local.", ip: "192.168.1.4"), "MacBook Air")
        XCTAssertEqual(DeviceClassifier.friendlyName(hostname: nil, ip: "192.168.1.44"), "Unknown Device")
    }

    func testIPOrderingValue() {
        XCTAssertLessThan(NetworkProbe.ipValue("192.168.1.9"), NetworkProbe.ipValue("192.168.1.20"))
    }

    func testScanPlanUsesActual24Subnet() {
        let info = NetworkInterfaceInfo(ipAddress: "192.168.50.42", netmask: "255.255.255.0", prefixLength: 24)
        let plan = NetworkProbe.scanPlan(for: info)
        XCTAssertEqual(plan.subnetHostCount, 254)
        XCTAssertEqual(plan.addresses.count, 253)
        XCTAssertTrue(plan.addresses.contains("192.168.50.1"))
        XCTAssertTrue(plan.addresses.contains("192.168.50.254"))
        XCTAssertFalse(plan.addresses.contains("192.168.50.42"))
        XCTAssertFalse(plan.isLimited)
    }

    func testScanPlanDoesNotAssume24() {
        let info = NetworkInterfaceInfo(ipAddress: "10.0.0.6", netmask: "255.255.255.240", prefixLength: 28)
        let plan = NetworkProbe.scanPlan(for: info)
        XCTAssertEqual(plan.subnetHostCount, 14)
        XCTAssertEqual(plan.addresses.count, 13)
        XCTAssertEqual(plan.addresses.first, "10.0.0.1")
        XCTAssertEqual(plan.addresses.last, "10.0.0.14")
    }

    func testVeryLargeSubnetIsBoundedAndIncludesGateway() {
        let info = NetworkInterfaceInfo(ipAddress: "10.20.30.40", netmask: "255.255.0.0",
                                        gateway: "10.20.0.1", prefixLength: 16)
        let plan = NetworkProbe.scanPlan(for: info)
        XCTAssertEqual(plan.subnetHostCount, 65_534)
        XCTAssertLessThanOrEqual(plan.addresses.count, 4_094)
        XCTAssertTrue(plan.addresses.contains("10.20.0.1"))
        XCTAssertTrue(plan.isLimited)
    }

    func testScanPlanUsesEntire23HostRange() {
        let info = NetworkInterfaceInfo(ipAddress: "192.168.101.12", netmask: "255.255.254.0", prefixLength: 23)
        let plan = NetworkProbe.scanPlan(for: info)
        XCTAssertEqual(plan.cidr, "192.168.100.0/23")
        XCTAssertEqual(plan.subnetHostCount, 510)
        XCTAssertEqual(plan.addresses.count, 509)
        XCTAssertTrue(plan.addresses.contains("192.168.100.1"))
        XCTAssertTrue(plan.addresses.contains("192.168.101.254"))
        XCTAssertFalse(plan.addresses.contains("192.168.101.12"))
    }

    func testPointToPoint31SelectsPeer() {
        let info = NetworkInterfaceInfo(ipAddress: "10.2.0.8", netmask: "255.255.255.254", prefixLength: 31)
        let plan = NetworkProbe.scanPlan(for: info)
        XCTAssertEqual(plan.addresses, ["10.2.0.9"])
        XCTAssertEqual(plan.subnetHostCount, 2)
    }

    func testPrivateMACDoesNotExposeVendorLabel() {
        let device = NetworkDevice(name: "Private device", ipAddress: "192.168.1.20",
                                   macAddress: "02:11:22:33:44:55", vendor: "Example Vendor")
        XCTAssertTrue(device.usesPrivateMAC)
        XCTAssertEqual(device.formattedMACAddress, "02:11:22:33:44:55")
        XCTAssertEqual(device.macTypeLabel, "Locally administered / private")
        XCTAssertEqual(device.vendorLabel, "Unknown")
    }

    func testGlobalMACTypeAndSingleDigitOctetsAreFormatted() {
        let device = NetworkDevice(name: "Observed device", ipAddress: "192.168.1.21",
                                   macAddress: "52:c:9:ed:cd:77")
        XCTAssertEqual(device.formattedMACAddress, "52:0C:09:ED:CD:77")
        XCTAssertEqual(device.macTypeLabel, "Locally administered / private")

        let global = NetworkDevice(name: "Global device", ipAddress: "192.168.1.22",
                                   macAddress: "00:1A:2B:3C:4D:5E")
        XCTAssertEqual(global.macTypeLabel, "Globally administered")
    }

    func testCustomNameIsSeparateAndSurvivesPersistence() throws {
        let device = NetworkDevice(name: "iphone-14.local", customName: "iPhone Ibu",
                                   ipAddress: "192.168.1.30", macAddress: "02:AA:BB:CC:DD:EE",
                                   kind: .phone, customKind: .tablet, isTrusted: true)
        XCTAssertEqual(device.detectedName, "iphone-14.local")
        XCTAssertEqual(device.displayName, "iPhone Ibu")
        XCTAssertEqual(device.kind, .phone)
        XCTAssertEqual(device.displayKind, .tablet)

        let data = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(NetworkDevice.self, from: data)
        XCTAssertEqual(decoded.customName, "iPhone Ibu")
        XCTAssertEqual(decoded.name, "iphone-14.local")
        XCTAssertEqual(decoded.displayName, "iPhone Ibu")
        XCTAssertEqual(decoded.macAddress, "02:AA:BB:CC:DD:EE")
        XCTAssertEqual(decoded.kind, .phone)
        XCTAssertEqual(decoded.customKind, .tablet)
        XCTAssertEqual(decoded.displayKind, .tablet)
        XCTAssertTrue(decoded.isTrusted)
    }

    func testDisplayNamePriorityUsesCustomizationThenDetectedNameThenHostnameThenIP() {
        let custom = NetworkDevice(name: "Living Room TV", customName: "TV Ruang Tengah",
                                   ipAddress: "192.168.1.12", hostname: "television.local")
        XCTAssertEqual(custom.displayName, "TV Ruang Tengah")

        let detected = NetworkDevice(name: "Living Room TV", ipAddress: "192.168.1.13",
                                     hostname: "television.local")
        XCTAssertEqual(detected.displayName, "Living Room TV")

        let hostname = NetworkDevice(name: "Unknown Device", ipAddress: "192.168.1.14",
                                     hostname: "rahman-macbook.local.")
        XCTAssertEqual(hostname.displayName, "rahman macbook")

        let fallback = NetworkDevice(name: "Unknown Device", ipAddress: "192.168.1.15")
        XCTAssertEqual(fallback.displayName, "Device 15")
    }

    func testCustomCategoryDoesNotOverwriteDetectedCategory() {
        var device = NetworkDevice(name: "Media device", ipAddress: "192.168.1.16",
                                   kind: .television, customKind: .gameConsole)
        XCTAssertEqual(device.displayKind, .gameConsole)
        XCTAssertEqual(device.detectedKindLabel, "Television")

        device.customKind = nil
        XCTAssertEqual(device.kind, .television)
        XCTAssertEqual(device.displayKind, .television)
    }

    func testMACIdentitySurvivesIPAddressChange() {
        let remembered = NetworkDevice(id: "remembered-id", name: "Phone", customName: "iPhone Ibu",
                                       ipAddress: "192.168.1.12", macAddress: "52:0c:09:ed:cd:77")
        let observation = NetworkDevice(name: "Unknown Device", ipAddress: "192.168.1.80",
                                        macAddress: "52:C:9:ED:CD:77")
        let match = DeviceIdentityResolver.match(for: observation, in: [remembered])
        XCTAssertEqual(match?.index, 0)
        XCTAssertTrue(match?.reason.hasPrefix("MAC") == true)
    }

    func testConflictingMACDoesNotReuseIdentityOnlyBecauseIPAddressMatches() {
        let remembered = NetworkDevice(name: "Old device", ipAddress: "192.168.1.12",
                                       macAddress: "00:11:22:33:44:55")
        let replacement = NetworkDevice(name: "New device", ipAddress: "192.168.1.12",
                                        macAddress: "00:AA:BB:CC:DD:EE")
        XCTAssertNil(DeviceIdentityResolver.match(for: replacement, in: [remembered]))
    }

    func testObservedServiceRoundTripsThroughPersistenceEncoding() throws {
        let service = NetworkServiceObservation(name: "SSH", port: 22, evidence: .open)
        let device = NetworkDevice(name: "Server", ipAddress: "192.168.1.9",
                                   serviceObservations: [service], isTrusted: true)
        let data = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(NetworkDevice.self, from: data)
        XCTAssertEqual(decoded.serviceObservations, [service])
        XCTAssertTrue(decoded.isTrusted)
    }

    func testARPParserReadsRealSingleDigitMACOctetsAndIgnoresIncompleteEntries() {
        let fixture = """
        ? (192.168.101.11) at (incomplete) on en0 ifscope [ethernet]
        ? (192.168.101.12) at 52:c:9:ed:cd:77 on en0 ifscope [ethernet]
        ? (192.168.101.13) at c:79:55:c9:22:c0 on en0 ifscope [ethernet]
        """
        let neighbors = NetworkProbe.parseARPTable(fixture)
        XCTAssertEqual(neighbors.count, 2)
        XCTAssertEqual(neighbors[0].ip, "192.168.101.12")
        XCTAssertEqual(neighbors[0].mac, "52:C:9:ED:CD:77")
        XCTAssertFalse(neighbors.contains { $0.ip == "192.168.101.11" })
    }

    func testLiveReachableHostFlowsThroughProductionProbeWhenConfigured() async throws {
        guard let target = ProcessInfo.processInfo.environment["LOOM_LIVE_TARGET"], !target.isEmpty else {
            throw XCTSkip("Set LOOM_LIVE_TARGET to run the opt-in LAN integration test")
        }

        let collector = LiveDeviceCollector()
        DiscoveryTrace.begin()
        await NetworkProbe.scan(addresses: [target], checkCommonPorts: true) { update in
            await collector.consume(update.devices)
        }
        DiscoveryTrace.finish("live integration test target=\(target)")

        let device = await collector.device(at: target)
        let nativeNeighbors = NetworkProbe.nativeIPv4Neighbors()
        XCTAssertNotNil(device, "A positively observed host must create a device without requiring MAC, hostname, Bonjour, vendor, or an open TCP service")
        XCTAssertEqual(device?.ipAddress, target)
        XCTAssertTrue(device?.isOnline == true)
        if nativeNeighbors.contains(where: { $0.ip == target }) {
            XCTAssertNotNil(device?.formattedMACAddress,
                            "When the test runner can read the neighbor table, its MAC must enrich the device")
        }
    }
}

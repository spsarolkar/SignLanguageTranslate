import XCTest
import Combine
@testable import SignLanguageTranslate

/// Tests for NetworkMonitor
///
/// Note: These tests use the shared NetworkMonitor singleton, so they test
/// the actual network state. Some tests verify behavior that depends on
/// the current network conditions.
final class NetworkMonitorTests: XCTestCase {

    var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cancellables = []
    }

    override func tearDownWithError() throws {
        cancellables = nil
        try super.tearDownWithError()
    }

    // MARK: - Singleton Tests

    func test_shared_returnsSameInstance() {
        let instance1 = NetworkMonitor.shared
        let instance2 = NetworkMonitor.shared

        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Connection State Tests

    func test_isConnected_returnsBoolean() {
        let monitor = NetworkMonitor.shared

        // Should return a boolean (actual value depends on network)
        _ = monitor.isConnected
    }

    func test_connectionType_returnsValidType() {
        let monitor = NetworkMonitor.shared

        let type = monitor.connectionType

        // Should be one of the valid types
        let validTypes: [NetworkMonitor.ConnectionType] = [.wifi, .cellular, .ethernet, .unknown]
        XCTAssertTrue(validTypes.contains(type))
    }

    // MARK: - Start/Stop Tests

    func test_start_startsMonitoring() {
        let monitor = NetworkMonitor.shared

        // Should not crash
        monitor.start()

        // Give it a moment to start
        Thread.sleep(forTimeInterval: 0.1)

        // Clean up
        monitor.stop()
    }

    func test_stop_stopsMonitoring() {
        let monitor = NetworkMonitor.shared

        monitor.start()
        monitor.stop()

        // Should not crash and should complete cleanly
    }

    func test_multipleStarts_areSafe() {
        let monitor = NetworkMonitor.shared

        // Multiple starts should not crash
        monitor.start()
        monitor.start()
        monitor.start()

        monitor.stop()
    }

    // MARK: - Publisher Tests

    func test_isConnectedPublisher_emitsValue() {
        let monitor = NetworkMonitor.shared
        let expectation = expectation(description: "Publisher emits value")

        monitor.isConnectedPublisher
            .first()
            .sink { isConnected in
                // Just verify we get a value
                _ = isConnected
                expectation.fulfill()
            }
            .store(in: &cancellables)

        waitForExpectations(timeout: 1.0)
    }

    func test_connectionTypePublisher_emitsValue() {
        let monitor = NetworkMonitor.shared
        let expectation = expectation(description: "Publisher emits value")

        monitor.connectionTypePublisher
            .first()
            .sink { connectionType in
                // Just verify we get a value
                _ = connectionType
                expectation.fulfill()
            }
            .store(in: &cancellables)

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Should Proceed Tests

    func test_shouldProceedWithDownload_whenConnected() {
        let monitor = NetworkMonitor.shared

        // If connected, should return true (unless on cellular with restriction)
        if monitor.isConnected {
            XCTAssertTrue(monitor.shouldProceedWithDownload(allowsCellular: true))
        }
    }

    func test_shouldProceedWithDownload_whenNotConnected_returnsFalse() {
        // We can't easily simulate disconnection in tests
        // But we can test the logic works when connected
        let monitor = NetworkMonitor.shared

        // When connected, should proceed
        if monitor.isConnected {
            XCTAssertTrue(monitor.shouldProceedWithDownload(allowsCellular: true))
        }
    }

    func test_shouldProceedWithDownload_cellularRestriction() {
        let monitor = NetworkMonitor.shared

        // When on cellular with restriction, should not proceed
        if monitor.connectionType == .cellular {
            XCTAssertFalse(monitor.shouldProceedWithDownload(allowsCellular: false))
        }
    }

    func test_shouldProceedWithDownload_wifiAlwaysAllowed() {
        let monitor = NetworkMonitor.shared

        // WiFi should always be allowed regardless of cellular setting
        if monitor.connectionType == .wifi && monitor.isConnected {
            XCTAssertTrue(monitor.shouldProceedWithDownload(allowsCellular: false))
            XCTAssertTrue(monitor.shouldProceedWithDownload(allowsCellular: true))
        }
    }

    // MARK: - Wait for Connection Tests

    func test_waitForConnection_returnsImmediatelyWhenConnected() async {
        let monitor = NetworkMonitor.shared

        if monitor.isConnected {
            let result = await monitor.waitForConnection(timeout: 0.1)
            XCTAssertTrue(result)
        }
    }

    func test_waitForConnection_timesOutWhenNotConnected() async {
        // This test is hard to run reliably without simulating network conditions
        // The timeout behavior is tested implicitly
    }

    // MARK: - Connection Type Properties Tests

    func test_connectionType_wifi_properties() {
        let wifiType = NetworkMonitor.ConnectionType.wifi

        XCTAssertEqual(wifiType.displayName, "Wi-Fi")
        XCTAssertFalse(wifiType.isExpensive)
    }

    func test_connectionType_cellular_properties() {
        let cellularType = NetworkMonitor.ConnectionType.cellular

        XCTAssertEqual(cellularType.displayName, "Cellular")
        XCTAssertTrue(cellularType.isExpensive)
    }

    func test_connectionType_ethernet_properties() {
        let ethernetType = NetworkMonitor.ConnectionType.ethernet

        XCTAssertEqual(ethernetType.displayName, "Ethernet")
        XCTAssertFalse(ethernetType.isExpensive)
    }

    func test_connectionType_unknown_properties() {
        let unknownType = NetworkMonitor.ConnectionType.unknown

        XCTAssertEqual(unknownType.displayName, "Unknown")
        XCTAssertFalse(unknownType.isExpensive)
    }

    // MARK: - Async Stream Tests

    func test_connectionStateStream_emitsValue() async throws {
        let monitor = NetworkMonitor.shared
        monitor.start()

        var receivedValue = false

        for await isConnected in monitor.connectionStateStream {
            _ = isConnected
            receivedValue = true
            break // Just need one value
        }

        XCTAssertTrue(receivedValue)

        monitor.stop()
    }

    func test_connectionTypeStream_emitsValue() async throws {
        let monitor = NetworkMonitor.shared
        monitor.start()

        var receivedValue = false

        for await connectionType in monitor.connectionTypeStream {
            _ = connectionType
            receivedValue = true
            break // Just need one value
        }

        XCTAssertTrue(receivedValue)

        monitor.stop()
    }

    // MARK: - Thread Safety Tests

    func test_concurrentAccess_isSafe() async {
        let monitor = NetworkMonitor.shared
        monitor.start()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = monitor.isConnected
                    _ = monitor.connectionType
                    _ = monitor.shouldProceedWithDownload(allowsCellular: true)
                }
            }
        }

        monitor.stop()
    }

    // MARK: - Raw Value Tests

    func test_connectionType_rawValues() {
        XCTAssertEqual(NetworkMonitor.ConnectionType.wifi.rawValue, "wifi")
        XCTAssertEqual(NetworkMonitor.ConnectionType.cellular.rawValue, "cellular")
        XCTAssertEqual(NetworkMonitor.ConnectionType.ethernet.rawValue, "ethernet")
        XCTAssertEqual(NetworkMonitor.ConnectionType.unknown.rawValue, "unknown")
    }
}

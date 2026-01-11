//
//  NetworkMonitor.swift
//  SignLanguageTranslate
//
//  Created on Phase 4.2 - Download Engine Implementation
//

import Foundation
import Network
import Combine

/// Monitors network connectivity status for download operations
final class NetworkMonitor: @unchecked Sendable {
    /// Shared singleton instance
    static let shared = NetworkMonitor()

    /// The underlying network path monitor
    private let monitor: NWPathMonitor

    /// Serial queue for monitor callbacks
    private let monitorQueue = DispatchQueue(label: "com.signlanguage.translate.network-monitor")

    /// Lock for thread-safe property access
    private let lock = NSLock()

    /// Internal storage for connection state
    private var _isConnected: Bool = true
    private var _connectionType: ConnectionType = .unknown

    /// Publisher for connection state changes
    private let connectionSubject = CurrentValueSubject<Bool, Never>(true)

    /// Publisher for connection type changes
    private let connectionTypeSubject = CurrentValueSubject<ConnectionType, Never>(.unknown)

    /// Whether the device is currently connected to the internet
    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    /// The current type of network connection
    var connectionType: ConnectionType {
        lock.lock()
        defer { lock.unlock() }
        return _connectionType
    }

    /// Publisher for observing connection state changes
    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        connectionSubject.eraseToAnyPublisher()
    }

    /// Publisher for observing connection type changes
    var connectionTypePublisher: AnyPublisher<ConnectionType, Never> {
        connectionTypeSubject.eraseToAnyPublisher()
    }

    /// Types of network connections
    enum ConnectionType: String, Sendable {
        case wifi
        case cellular
        case ethernet
        case unknown

        var displayName: String {
            switch self {
            case .wifi: return "Wi-Fi"
            case .cellular: return "Cellular"
            case .ethernet: return "Ethernet"
            case .unknown: return "Unknown"
            }
        }

        var isExpensive: Bool {
            self == .cellular
        }
    }

    private init() {
        monitor = NWPathMonitor()
        setupMonitor()
    }

    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
    }

    private func handlePathUpdate(_ path: NWPath) {
        let isConnected = path.status == .satisfied
        let connectionType = determineConnectionType(from: path)

        lock.lock()
        let wasConnected = _isConnected
        let previousType = _connectionType
        _isConnected = isConnected
        _connectionType = connectionType
        lock.unlock()

        // Notify subscribers of changes
        if isConnected != wasConnected {
            connectionSubject.send(isConnected)

            // Log significant state changes
            if isConnected {
                print("[NetworkMonitor] Network connection restored (\(connectionType.displayName))")
            } else {
                print("[NetworkMonitor] Network connection lost")
            }
        }

        if connectionType != previousType {
            connectionTypeSubject.send(connectionType)
        }
    }

    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .unknown
        }
    }

    /// Start monitoring network status
    func start() {
        monitor.start(queue: monitorQueue)
        print("[NetworkMonitor] Started monitoring network status")
    }

    /// Stop monitoring network status
    func stop() {
        monitor.cancel()
        print("[NetworkMonitor] Stopped monitoring network status")
    }

    /// Check if downloads should proceed based on network conditions
    /// - Parameter allowsCellular: Whether cellular downloads are permitted
    /// - Returns: true if downloads should proceed
    func shouldProceedWithDownload(allowsCellular: Bool = true) -> Bool {
        guard isConnected else { return false }

        if !allowsCellular && connectionType == .cellular {
            return false
        }

        return true
    }

    /// Wait for network to become available
    /// - Parameter timeout: Maximum time to wait
    /// - Returns: true if network became available within timeout
    func waitForConnection(timeout: TimeInterval = 30) async -> Bool {
        if isConnected { return true }

        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                cancellable?.cancel()
                continuation.resume(returning: false)
            }

            cancellable = connectionSubject
                .filter { $0 }
                .first()
                .sink { _ in
                    timeoutTask.cancel()
                    continuation.resume(returning: true)
                }
        }
    }
}

// MARK: - Async Stream Support

extension NetworkMonitor {
    /// An async stream of connection state changes
    var connectionStateStream: AsyncStream<Bool> {
        AsyncStream { continuation in
            let cancellable = connectionSubject
                .sink { isConnected in
                    continuation.yield(isConnected)
                }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    /// An async stream of connection type changes
    var connectionTypeStream: AsyncStream<ConnectionType> {
        AsyncStream { continuation in
            let cancellable = connectionTypeSubject
                .sink { connectionType in
                    continuation.yield(connectionType)
                }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

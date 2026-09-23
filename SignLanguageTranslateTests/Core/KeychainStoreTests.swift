import Foundation
import XCTest
@testable import SignLanguageTranslate

final class KeychainStoreTests: XCTestCase {

    private var store: KeychainStore!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: "com.signlanguagetranslate.tests.\(UUID().uuidString)")
        suiteName = "KeychainStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        for key in ["token", "legacy", "existing"] {
            store.delete(key)
        }
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSetAndRead_roundTrips() {
        XCTAssertTrue(store.set("secret-1", for: "token"))
        XCTAssertEqual(store.string(for: "token"), "secret-1")
    }

    func testSet_replacesExistingValue() {
        store.set("old", for: "token")
        store.set("new", for: "token")
        XCTAssertEqual(store.string(for: "token"), "new")
    }

    func testDelete_removesValue() {
        store.set("secret", for: "token")
        XCTAssertTrue(store.delete("token"))
        XCTAssertNil(store.string(for: "token"))
    }

    func testDelete_missingKey_succeeds() {
        XCTAssertTrue(store.delete("token"))
    }

    func testMigrate_movesValueAndClearsUserDefaults() {
        defaults.set("plaintext", forKey: "legacy")

        store.migrateFromUserDefaults(key: "legacy", defaults: defaults)

        XCTAssertEqual(store.string(for: "legacy"), "plaintext")
        XCTAssertNil(defaults.string(forKey: "legacy"))
    }

    func testMigrate_keepsExistingKeychainValue() {
        store.set("keychain", for: "existing")
        defaults.set("plaintext", forKey: "existing")

        store.migrateFromUserDefaults(key: "existing", defaults: defaults)

        XCTAssertEqual(store.string(for: "existing"), "keychain")
        XCTAssertNil(defaults.string(forKey: "existing"))
    }
}

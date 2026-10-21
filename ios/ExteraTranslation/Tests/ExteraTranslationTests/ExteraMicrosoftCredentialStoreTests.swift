import Foundation
import XCTest
@testable import ExteraTranslation

final class ExteraMicrosoftCredentialStoreTests: XCTestCase {
    func testCredentialWhitespaceAndOptionalRegionNormalizeWithoutKeychainIO() throws {
        let value = try ExteraMicrosoftCredentialStore.normalized(.init(subscriptionKey: "  fixture-key\n", region: " WestUS2 "))
        XCTAssertEqual(value.subscriptionKey, "fixture-key")
        XCTAssertEqual(value.region, "westus2")
        XCTAssertNil(try ExteraMicrosoftCredentialStore.normalized(.init(subscriptionKey: "fixture-key", region: " ")).region)
    }
    func testHeaderInjectionAndInvalidSecretsAreRejectedBeforeStorage() {
        for key in ["", " ", "fixture\r\nInjected: value", "embedded space", "nul\u{0}byte", "é", String(repeating: "a", count: 513)] {
            XCTAssertThrowsError(try ExteraMicrosoftCredentialStore.encoded(.init(subscriptionKey: key)))
        }
    }
    func testRegionIsAnIdentifierNotAnEndpointOrHTTPHeader() {
        for region in ["https://fixture.example", "eastus\nInjected", "a b", String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try ExteraMicrosoftCredentialStore.encoded(.init(subscriptionKey: "fixture-key", region: region)))
        }
    }
    func testStoredConfigurationRoundTripsBothCredentialFields() throws {
        let data = try ExteraMicrosoftCredentialStore.encoded(.init(subscriptionKey: "fixture-key", region: "eastus"))
        let value = try ExteraMicrosoftCredentialStore.decoded(data)
        XCTAssertEqual(value.subscriptionKey, "fixture-key")
        XCTAssertEqual(value.region, "eastus")
        XCTAssertNil(try ExteraMicrosoftCredentialStore.decoded(ExteraMicrosoftCredentialStore.encoded(.init(subscriptionKey: "fixture-key"))).region)
    }
    func testCorruptOrOversizedSavedDataDoesNotBecomeARequestCredential() {
        for data in [Data("not-json".utf8), Data("{\"subscriptionKey\":\"\"}".utf8), Data(repeating: 32, count: 4097)] {
            XCTAssertThrowsError(try ExteraMicrosoftCredentialStore.decoded(data)) { error in
                XCTAssertEqual(error as? ExteraMicrosoftCredentialStoreError, .corruptData)
            }
        }
    }
}

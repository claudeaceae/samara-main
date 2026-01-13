import XCTest

final class ContactsResolverTests: SamaraTestCase {

    func testResolveNameUsesEmailAndCachesResult() {
        var emailCalls = 0
        let resolver = ContactsResolver(
            resolvePhone: { _ in
                return "Phone Name"
            },
            resolveEmail: { email in
                emailCalls += 1
                return email == "tester@example.com" ? "Tester" : nil
            }
        )

        let first = resolver.resolveName(for: "tester@example.com")
        let second = resolver.resolveName(for: "tester@example.com")

        XCTAssertEqual(first, "Tester")
        XCTAssertEqual(second, "Tester")
        XCTAssertEqual(emailCalls, 1)
    }

    func testResolveNameUsesPhoneLookup() {
        var phoneCalls = 0
        let resolver = ContactsResolver(
            resolvePhone: { phone in
                phoneCalls += 1
                return phone == "+15555550123" ? "Tester" : nil
            },
            resolveEmail: { _ in nil }
        )

        let name = resolver.resolveName(for: "+15555550123")
        XCTAssertEqual(name, "Tester")
        XCTAssertEqual(phoneCalls, 1)
    }

    func testResolveNameReturnsNilForUnknownHandle() {
        let resolver = ContactsResolver(
            resolvePhone: { _ in nil },
            resolveEmail: { _ in nil }
        )

        XCTAssertNil(resolver.resolveName(for: "handle-without-contact"))
    }
}

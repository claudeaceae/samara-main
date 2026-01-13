import Foundation
import Contacts

/// Resolves phone numbers and emails to contact names from the system Contacts
final class ContactsResolver {
    typealias ContactLookup = (String) -> String?

    private let store: CNContactStore
    private let resolvePhoneHandler: ContactLookup
    private let resolveEmailHandler: ContactLookup
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    init(
        store: CNContactStore = CNContactStore(),
        resolvePhone: ContactLookup? = nil,
        resolveEmail: ContactLookup? = nil
    ) {
        self.store = store
        let storeRef = store
        self.resolvePhoneHandler = resolvePhone ?? { phone in
            ContactsResolver.resolvePhoneUsingContacts(phone, store: storeRef)
        }
        self.resolveEmailHandler = resolveEmail ?? { email in
            ContactsResolver.resolveEmailUsingContacts(email, store: storeRef)
        }
    }

    /// Resolve a single handle (phone number or email) to a contact name
    /// Returns nil if no matching contact is found
    func resolveName(for handle: String) -> String? {
        lock.lock()
        if let cached = cache[handle] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let name: String?
        if handle.contains("@") {
            name = resolveEmailHandler(handle)
        } else if handle.hasPrefix("+") || handle.first?.isNumber == true {
            name = resolvePhoneHandler(handle)
        } else {
            name = nil
        }

        if let resolved = name {
            lock.lock()
            cache[handle] = resolved
            lock.unlock()
        }

        return name
    }

    /// Resolve multiple handles at once (batch)
    /// Returns a dictionary of handle -> name for successfully resolved handles
    func resolveNames(for handles: [String]) -> [String: String] {
        var results: [String: String] = [:]
        for handle in handles {
            if let name = resolveName(for: handle) {
                results[handle] = name
            }
        }
        return results
    }

    /// Resolve a phone number to a contact name
    private static func resolvePhoneUsingContacts(_ phone: String, store: CNContactStore) -> String? {
        // Normalize phone number (keep only digits and +)
        let normalized = phone.filter { $0.isNumber || $0 == "+" }

        let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: normalized))
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor
        ]

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            if let contact = contacts.first {
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                return fullName.isEmpty ? nil : fullName
            }
        } catch {
            log("ContactsResolver: Failed to resolve phone \(phone): \(error)", level: .debug, component: "Contacts")
        }

        return nil
    }

    /// Resolve an email address to a contact name
    private static func resolveEmailUsingContacts(_ email: String, store: CNContactStore) -> String? {
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor
        ]

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            if let contact = contacts.first {
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                return fullName.isEmpty ? nil : fullName
            }
        } catch {
            log("ContactsResolver: Failed to resolve email \(email): \(error)", level: .debug, component: "Contacts")
        }

        return nil
    }
}

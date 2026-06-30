import Foundation
import Observation

@MainActor
@Observable
final class IdentityStore {
    private(set) var accounts: [Account] = []
    private var profiles: [String: DeckProfile] = [:]
    // Backs disk reads so headers asking for a profile every render don't hit
    // the filesystem each time. Non-observed: writing it from profile() during
    // a SwiftUI body pass must not mutate tracked state. The form is the only
    // writer of profile.json, so the only invalidation is forgetProfile.
    @ObservationIgnored private var profileCache: [String: DeckProfile] = [:]

    init() {
        accounts = Storage.readJSON([Account].self, at: accountsURL) ?? []
    }

    // MARK: Accounts

    func upsertAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        saveAccounts()
    }

    func deleteAccount(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        Keychain.delete(keyReference(id))
        saveAccounts()
    }

    func apiKey(for id: UUID) -> String {
        Keychain.get(keyReference(id)) ?? ""
    }

    func setAPIKey(_ value: String, for id: UUID) {
        Keychain.set(value, for: keyReference(id))
    }

    // MARK: Profiles

    func profile(_ slug: String) -> DeckProfile {
        if let saved = profiles[slug] { return saved }
        if let cached = profileCache[slug] { return cached }
        let loaded = Storage.readJSON(DeckProfile.self, at: profileURL(slug)) ?? DeckProfile()
        profileCache[slug] = loaded
        return loaded
    }

    func saveProfile(_ profile: DeckProfile, for slug: String) {
        profiles[slug] = profile
        profileCache[slug] = profile
        Storage.writeJSON(profile, to: profileURL(slug))
    }

    func forgetProfile(_ slug: String) {
        profiles[slug] = nil
        profileCache[slug] = nil
    }

    func effectiveCalendarSources(for slug: String, parent: String?) -> [String] {
        let own = profile(slug).calendarSources ?? []
        if !own.isEmpty { return own }
        if let parent { return profile(parent).calendarSources ?? [] }
        return []
    }

    // A sub-deck falls back to its parent's AI connector and instructions when
    // its own are unset, matching effectiveCalendarSources and the CLI's
    // effective_profile.
    func effectiveAccountID(for slug: String, parent: String?) -> UUID? {
        if let own = profile(slug).accountID { return own }
        if let parent { return profile(parent).accountID }
        return nil
    }

    func effectiveInstructions(for slug: String, parent: String?) -> String {
        let own = profile(slug).instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        if let parent { return profile(parent).instructions.trimmingCharacters(in: .whitespacesAndNewlines) }
        return ""
    }

    func accountName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }?.name
    }

    // MARK: Helpers

    private func saveAccounts() {
        Storage.writeJSON(accounts, to: accountsURL)
    }

    private func keyReference(_ id: UUID) -> String {
        "account/\(id.uuidString)"
    }

    private var accountsURL: URL {
        Storage.root.appendingPathComponent("accounts.json")
    }

    private func profileURL(_ slug: String) -> URL {
        Storage.deckDirectory(slug).appendingPathComponent("profile.json")
    }
}

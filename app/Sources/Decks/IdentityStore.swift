import Foundation
import Observation

@MainActor
@Observable
final class IdentityStore {
    private(set) var accounts: [Account] = []
    private var profiles: [String: DeckProfile] = [:]

    init() {
        accounts = Storage.readJSON([Account].self, at: accountsURL) ?? []
    }

    // MARK: Accounts

    func addAccount(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accounts.append(Account(name: trimmed))
        saveAccounts()
    }

    func updateAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
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
        if let profile = profiles[slug] { return profile }
        let profile = Storage.readJSON(DeckProfile.self, at: profileURL(slug)) ?? DeckProfile()
        profiles[slug] = profile
        return profile
    }

    func saveProfile(_ profile: DeckProfile, for slug: String) {
        profiles[slug] = profile
        Storage.writeJSON(profile, to: profileURL(slug))
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

// deviation: host-provided stand-in for Zen-Agent App/Credential/CredentialStore.swift:82-118;
// zen UI stays verbatim.
//
// Only the protocol is taken, verbatim: `ModelProvider.stream` declares `any CredentialStoring`
// in its signature (App/Provider/ModelProvider.swift:69), and the composer never calls it. The
// 451-line store and its Keychain backend stay out of this tree - the app talks to the relay, not
// to a provider adapter, so nothing here can provision or resolve a secret yet.

import Foundation

protocol CredentialStoring: Sendable {
    func provision(
        _ secret: SecretValue,
        as reference: CredentialReference,
        principalFingerprint: String?,
        at now: Date
    ) throws
    func refresh(_ secret: SecretValue, for reference: CredentialReference, at now: Date) throws
    func rebind(
        _ secret: SecretValue,
        as reference: CredentialReference,
        principalFingerprint: String,
        at now: Date
    ) throws
    func logout(_ reference: CredentialReference, at now: Date) throws

    func resolve(_ reference: CredentialReference) throws -> SecretValue?

    func resolve(frozenReference: CredentialReference, generation: Int) throws -> SecretValue?

    func metadata(for reference: CredentialReference) throws -> CredentialMetadata?
    func matchesBinding(_ reference: CredentialReference, generation: Int) throws -> Bool
}

import Foundation

/// The words a person reads where a code used to. The React Native app maps its
/// failures to sentences (link.ts errorText); this is the one native place doing it,
/// because every screen reads localizedDescription and TransportError answers that.
extension Error {
    var userText: String {
        guard let transport = self as? TransportError else {
            return (self as NSError).localizedDescription
        }
        switch transport.code {
        case .notPaired:
            return NativeLanguage.text("This phone is not paired with the computer yet.")
        case .pairingRejected:
            return NativeLanguage.text("The computer did not accept this phone. Show a new QR code on the computer and scan it again.")
        case .hostOffline, .serverUnreachable:
            return NativeLanguage.text("Could not reach your computer.")
        case .timeout:
            return NativeLanguage.text("The computer did not answer.")
        case .notConnected:
            return NativeLanguage.text("Not connected to the computer yet.")
        case .invalidFrame, .frameTooLarge, .invalidBase64:
            // The host's own code can matter in a support conversation; the transport's
            // own enum names never can, so they stay out of the sentence either way.
            if let wire = transport.wireCode {
                return NativeLanguage.text("Something went wrong ({code}).", ["code": wire])
            }
            return NativeLanguage.text("Something went wrong.")
        }
    }

    /// A refused identity has no retry that works: only the pairing sheet brings the
    /// phone back, so the caller needs to know this is that case.
    var needsPairing: Bool {
        guard let transport = self as? TransportError else { return false }
        return transport.code == .notPaired || transport.code == .pairingRejected
    }
}

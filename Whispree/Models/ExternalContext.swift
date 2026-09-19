import AppKit

/// Minimal target context for the hardened fork.
/// Only the previously active application is retained; no browser/terminal automation
/// or Apple Events are used.
enum ExternalContext {
    case app(NSRunningApplication)

    var app: NSRunningApplication {
        switch self {
        case let .app(app): app
        }
    }
}

import IOKit.pwr_mgt

/// The kind of sleep NoNap prevents while active.
///
/// Mirrors the behavior of the `caffeinate` command: `.system` matches a bare
/// `caffeinate` invocation (system stays awake, display may still sleep).
enum KeepAwakeMode: String, CaseIterable {
    /// Prevent system idle sleep; the display may still sleep. (Default — like `caffeinate`.)
    case system
    /// Prevent display sleep (which also keeps the system awake).
    case display
    /// Prevent both system and display sleep.
    case both

    /// Human-readable label shown in the Mode submenu.
    var title: String {
        switch self {
        case .system:  return "Prevent system sleep"
        case .display: return "Prevent display sleep"
        case .both:    return "Prevent both"
        }
    }

    /// The IOKit power-assertion types this mode must hold while active.
    var assertionTypes: [String] {
        switch self {
        case .system:  return [kIOPMAssertionTypePreventUserIdleSystemSleep]
        case .display: return [kIOPMAssertionTypePreventUserIdleDisplaySleep]
        case .both:    return [kIOPMAssertionTypePreventUserIdleSystemSleep,
                               kIOPMAssertionTypePreventUserIdleDisplaySleep]
        }
    }
}

import CoreGraphics

/// Screen Recording (TCC kTCCServiceScreenCapture), required for region capture.
///
/// Two quirks worth knowing, both different from Accessibility/Microphone:
///
/// 1. There is no Info.plist usage-description key for this permission —
///    macOS composes the consent dialog itself. Nothing to declare.
/// 2. The grant does not take effect until the app is relaunched, and
///    `CGPreflightScreenCaptureAccess()` caches its answer for the lifetime of
///    the process. So it keeps returning false in the very session where the
///    user granted it; don't poll it expecting a flip, and tell the user to
///    quit and reopen.
///
/// Note that spawning `/usr/sbin/screencapture` does not sidestep any of this:
/// that binary carries `com.apple.private.tcc.check-allow-on-responsible-process`
/// for kTCCServiceScreenCapture, so TCC checks the grant against Magpie, not
/// against the child process.
enum ScreenRecording {
    static var isTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestIfNeeded() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

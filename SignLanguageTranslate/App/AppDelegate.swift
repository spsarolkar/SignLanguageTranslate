import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Force initialization of background session to reconnect to any
        // pending tasks from previous app launches
        _ = BackgroundSessionManager.shared.session
        return true
    }

    // MARK: - Background URL Session Handling

    /// Called when the system needs to resume background URL session events
    ///
    /// This is called when:
    /// 1. A background download completes while the app is suspended
    /// 2. The app is relaunched after termination to handle completed downloads
    ///
    /// We store the completion handler and call it after all events are processed
    /// in `urlSessionDidFinishEvents(forBackgroundURLSession:)`
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Verify this is our session identifier
        guard identifier == "com.signlanguage.translate.background-downloads" else {
            // Unknown session, call completion handler immediately
            completionHandler()
            return
        }

        // Store the completion handler
        // BackgroundSessionManager will call this when all events are processed
        BackgroundSessionManager.shared.backgroundCompletionHandler = completionHandler

        // The session's delegate methods will be called after this returns
        // When all events are delivered, urlSessionDidFinishEvents will be called
        // and we'll invoke the completion handler there
    }
}

// Before (caused build error):
init(
    engine: DownloadEngine,
    progressTracker: DownloadProgressTracker = DownloadProgressTracker(),
    history: DownloadHistory = DownloadHistory()
)

// After (fixed):
init(
    engine: DownloadEngine,
    progressTracker: DownloadProgressTracker? = nil,
    history: DownloadHistory? = nil
) {
    self.engine = engine
    self.progressTracker = progressTracker ?? DownloadProgressTracker()
    self.history = history ?? DownloadHistory()
    setupDelegation()
}
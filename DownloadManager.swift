1. User taps "Download INCLUDE"
2. DownloadManager.startDownloads() → engine.start()
3. Engine processes queue via coordinator
4. For each pending task:
   - Validates network availability
   - Validates storage space
   - Starts download via BackgroundSessionManager
5. Progress updates via callbacks → delegate → UI
6. On complete: moves file, marks task complete
7. On error: saves resume data, retries if retryable (up to 3 times)
8. On network loss: pauses active downloads, saves resume data
9. On network restore: resumes processing
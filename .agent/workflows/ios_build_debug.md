---
description: Build the iOS project and diagnose errors if they occur
---

1.  **Run Build Command**
    - Execute `xcodebuild build -scheme SignLanguageTranslate -destination 'generic/platform=iOS' -quiet`
    - Capture the exit code and output.

2.  **Analyze Outcome**
    - **Step 2a: If Build Succeeds (Exit Code 0)**
        - Report success.
        - Stop.
    - **Step 2b: If Build Fails**
        - Read the full log.
        - Look for "error:" patterns.
        - Extract the file paths and line numbers of the errors.

3.  **Diagnosis**
    - For each unique error:
        - Read the file content around the error line.
        - Check for:
            - Syntax errors (missing braces, typos).
            - Type mismatches.
            - Actor isolation warnings/errors.
            - Missing imports.

4.  **Reporting**
    - Summarize the failures.
    - Creating a precise plan to fix them using `edit_file` tools.
    - (Optional) If the error is simple, apply the fix immediately.

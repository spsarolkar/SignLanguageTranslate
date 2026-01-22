---
description: Run tests and attempt to fix failures automatically
---

1.  **Run Tests**
    - Execute `xcodebuild test -scheme SignLanguageTranslate -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation),OS=latest' -quiet`
    - (Note: Adjust destination as needed for available simulators).

2.  **Check Results**
    - If successful, exit with success message.
    - If failed, parse the `xcodebuild` output to identify the failing Test Case and the Failure Message.

3.  **Analyze Failure**
    - For each failed test:
        - View the Test file content.
        - View the Code Under Test (the implementation).
        - Determine if the defect is in the Test (wrong expectation) or Code (bug).

4.  **Attempt Fix**
    - Apply a fix to the Code or Test.
    - **Wait** for tool completion.

5.  **Verify Fix**
    - Re-run the tests (Turbo Mode: run only the failing test suite if possible, otherwise run all).
    - If it passes, commit the fix (optional guidelines).
    - If it fails again, analyze the new error.
    - Retry up to 3 times.

6.  **Report**
    - List fixed tests.
    - List remaining broken tests.

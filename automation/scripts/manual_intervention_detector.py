"""
Manual Intervention Detector.
Identifies build/test errors that require manual intervention and cannot be fixed by Claude.
"""

from dataclasses import dataclass
from typing import Optional
from models import BuildError, TestFailure


@dataclass
class ManualInterventionRequired:
    """Represents a situation requiring manual intervention."""
    category: str  # e.g., "xcode_target", "dependency", "signing"
    title: str
    description: str
    instructions: list[str]
    affected_files: list[str]
    is_blocking: bool = True  # If True, automation should stop


class ManualInterventionDetector:
    """
    Detects errors that require manual intervention and cannot be fixed automatically.

    These are typically:
    - Xcode project configuration issues (target membership, schemes)
    - Code signing and provisioning
    - Missing dependencies that need to be added via Xcode
    - Simulator/device configuration issues
    """

    # Patterns that indicate manual intervention is needed
    # Format: (pattern_in_error, category, title, instructions)
    MANUAL_PATTERNS = [
        # XCTest module issues - test files not in test target
        {
            "patterns": ["No such module 'XCTest'", "no such module 'XCTest'"],
            "category": "xcode_target",
            "title": "Test File Not in Test Target",
            "description": "A test file was created but not added to the test target in Xcode.",
            "instructions": [
                "1. Open the Xcode project (SignLanguageTranslate.xcodeproj)",
                "2. In Project Navigator, find the affected test file(s)",
                "3. Select the file and open File Inspector (Cmd+Option+1)",
                "4. Under 'Target Membership', check the 'SignLanguageTranslateTests' checkbox",
                "5. Build the project (Cmd+B) to verify the fix",
                "6. Resume automation with: python scripts/main.py"
            ],
        },
        # SwiftData / SwiftUI module issues in main target
        {
            "patterns": ["No such module 'SwiftData'", "No such module 'SwiftUI'"],
            "category": "xcode_target",
            "title": "Source File Not in App Target",
            "description": "A source file was created but not added to the main app target.",
            "instructions": [
                "1. Open the Xcode project (SignLanguageTranslate.xcodeproj)",
                "2. Find the affected source file(s) in Project Navigator",
                "3. Select the file and open File Inspector (Cmd+Option+1)",
                "4. Under 'Target Membership', check the 'SignLanguageTranslate' checkbox",
                "5. Build the project (Cmd+B) to verify",
                "6. Resume automation"
            ],
        },
        # Duplicate symbol errors often need manual Xcode intervention
        {
            "patterns": ["duplicate symbol", "Duplicate symbol"],
            "category": "xcode_target",
            "title": "Duplicate Symbol Error",
            "description": "A symbol is defined in multiple places, often due to file being in multiple targets.",
            "instructions": [
                "1. Open Xcode and identify the duplicate file",
                "2. Check File Inspector for each file with the symbol",
                "3. Ensure each file is only in ONE target (either app OR test, not both)",
                "4. For shared code, create a proper shared framework/module",
                "5. Clean build folder (Cmd+Shift+K) and rebuild"
            ],
        },
        # Code signing issues
        {
            "patterns": [
                "Code Signing Error",
                "Provisioning profile",
                "signing certificate",
                "CODESIGNING"
            ],
            "category": "signing",
            "title": "Code Signing Configuration Required",
            "description": "The project requires code signing configuration.",
            "instructions": [
                "1. Open Xcode project settings",
                "2. Select the target and go to 'Signing & Capabilities'",
                "3. Select your development team",
                "4. For local development, enable 'Automatically manage signing'",
                "5. Ensure you have a valid Apple Developer account configured"
            ],
        },
        # Missing framework/library
        {
            "patterns": [
                "framework not found",
                "library not found",
                "ld: framework not found",
                "ld: library not found"
            ],
            "category": "dependency",
            "title": "Missing Framework or Library",
            "description": "A required framework or library is not linked to the target.",
            "instructions": [
                "1. Open Xcode project settings",
                "2. Select the target and go to 'Build Phases'",
                "3. Expand 'Link Binary With Libraries'",
                "4. Click '+' and add the missing framework",
                "5. If using SPM, check Package Dependencies in project settings"
            ],
        },
        # Simulator not found/available
        {
            "patterns": [
                "Unable to find a destination matching",
                "Simulator device not found",
                "no destination"
            ],
            "category": "simulator",
            "title": "Simulator Not Available",
            "description": "The specified simulator device is not available.",
            "instructions": [
                "1. Open Xcode > Window > Devices and Simulators",
                "2. Check available simulators",
                "3. If needed simulator is missing, add it via '+' button",
                "4. Update config/config.yaml with correct simulator name and OS version",
                "5. Alternatively, run: xcrun simctl list devices"
            ],
        },
        # Missing entitlements
        {
            "patterns": [
                "entitlements",
                "Entitlement"
            ],
            "category": "entitlements",
            "title": "Entitlements Configuration Required",
            "description": "App entitlements need to be configured in Xcode.",
            "instructions": [
                "1. Open Xcode project settings",
                "2. Select target > Signing & Capabilities",
                "3. Click '+Capability' to add required entitlements",
                "4. Configure the entitlement values as needed"
            ],
        },
        # Swift version mismatch
        {
            "patterns": [
                "compiled with Swift",
                "was compiled with Swift",
                "Swift version"
            ],
            "category": "swift_version",
            "title": "Swift Version Mismatch",
            "description": "There's a Swift version incompatibility.",
            "instructions": [
                "1. Check your Xcode version (should be Xcode 16+ for Swift 6)",
                "2. In project settings, verify Swift Language Version",
                "3. Clean derived data: rm -rf ~/Library/Developer/Xcode/DerivedData",
                "4. Clean and rebuild the project"
            ],
        },
        # Missing bridging header
        {
            "patterns": [
                "bridging header",
                "Bridging-Header.h"
            ],
            "category": "bridging_header",
            "title": "Objective-C Bridging Header Issue",
            "description": "There's an issue with the Objective-C bridging header.",
            "instructions": [
                "1. Check if bridging header file exists at the specified path",
                "2. In Build Settings, search for 'Objective-C Bridging Header'",
                "3. Verify the path is correct relative to project root",
                "4. Create the bridging header if missing"
            ],
        },
    ]

    # Errors that Claude can potentially fix (don't stop for these)
    RECOVERABLE_PATTERNS = [
        "cannot find type",
        "cannot find",
        "has no member",
        "undeclared type",
        "use of undeclared",
        "expected declaration",
        "expected expression",
        "missing argument",
        "extra argument",
        "cannot convert",
        "type mismatch",
        "ambiguous",
        "protocol",
        "does not conform",
        "initializer",
        "closure",
        "return type",
        "generic parameter",
    ]

    def __init__(self, max_same_error_retries: int = 3):
        """
        Initialize detector.

        Args:
            max_same_error_retries: How many times to retry the same error before
                                   considering it might need manual intervention
        """
        self.max_same_error_retries = max_same_error_retries
        self._error_counts: dict[str, int] = {}

    def check_build_errors(self, errors: list[BuildError]) -> Optional[ManualInterventionRequired]:
        """
        Check build errors for manual intervention requirements.

        Args:
            errors: List of build errors from xcodebuild

        Returns:
            ManualInterventionRequired if manual action needed, None otherwise
        """
        if not errors:
            return None

        affected_files = []

        for error in errors:
            error_text = f"{error.message} {error.file_path or ''}"

            # Check against manual intervention patterns
            for pattern_info in self.MANUAL_PATTERNS:
                for pattern in pattern_info["patterns"]:
                    if pattern.lower() in error_text.lower():
                        if error.file_path:
                            affected_files.append(error.file_path)

                        return ManualInterventionRequired(
                            category=pattern_info["category"],
                            title=pattern_info["title"],
                            description=pattern_info["description"],
                            instructions=pattern_info["instructions"],
                            affected_files=list(set(affected_files)),
                            is_blocking=True
                        )

        return None

    def check_test_failures(self, failures: list[TestFailure]) -> Optional[ManualInterventionRequired]:
        """
        Check test failures for manual intervention requirements.

        Args:
            failures: List of test failures

        Returns:
            ManualInterventionRequired if manual action needed, None otherwise
        """
        if not failures:
            return None

        # Test failures are generally fixable by Claude unless they indicate
        # configuration issues
        for failure in failures:
            error_text = failure.failure_message or ""

            for pattern_info in self.MANUAL_PATTERNS:
                for pattern in pattern_info["patterns"]:
                    if pattern.lower() in error_text.lower():
                        return ManualInterventionRequired(
                            category=pattern_info["category"],
                            title=pattern_info["title"],
                            description=pattern_info["description"],
                            instructions=pattern_info["instructions"],
                            affected_files=[failure.file_path] if failure.file_path else [],
                            is_blocking=True
                        )

        return None

    def check_repeated_errors(self, errors: list[BuildError], iteration: int) -> Optional[ManualInterventionRequired]:
        """
        Check if we're stuck on the same errors repeatedly.

        If Claude keeps producing the same errors after several attempts,
        it might indicate the error needs manual intervention.

        Args:
            errors: Current build errors
            iteration: Current iteration number

        Returns:
            ManualInterventionRequired if we seem stuck, None otherwise
        """
        if not errors or iteration < self.max_same_error_retries:
            return None

        # Create a signature of current errors
        error_sig = self._get_error_signature(errors)

        # Count occurrences
        self._error_counts[error_sig] = self._error_counts.get(error_sig, 0) + 1

        if self._error_counts[error_sig] >= self.max_same_error_retries:
            # Check if any of these are recoverable patterns
            has_recoverable = False
            for error in errors:
                for pattern in self.RECOVERABLE_PATTERNS:
                    if pattern.lower() in (error.message or "").lower():
                        has_recoverable = True
                        break
                if has_recoverable:
                    break

            if not has_recoverable:
                return ManualInterventionRequired(
                    category="repeated_failure",
                    title="Repeated Build Failures",
                    description=f"The same errors have occurred {self._error_counts[error_sig]} times.",
                    instructions=[
                        "1. Review the error messages below",
                        "2. Check if files need to be added to correct Xcode target",
                        "3. Check for any missing dependencies or configurations",
                        "4. Try building manually in Xcode to get more context",
                        "5. Fix the issue and resume automation"
                    ],
                    affected_files=[e.file_path for e in errors if e.file_path],
                    is_blocking=True
                )

        return None

    def reset_error_counts(self):
        """Reset error tracking (call when a phase completes successfully)."""
        self._error_counts.clear()

    def _get_error_signature(self, errors: list[BuildError]) -> str:
        """Create a signature string from errors for comparison."""
        # Sort and concatenate key error info to create comparable signature
        parts = sorted([
            f"{e.file_path}:{e.line_number}:{e.message[:50] if e.message else ''}"
            for e in errors
        ])
        return "|".join(parts[:5])  # Only use first 5 errors for signature

    def format_intervention_message(self, intervention: ManualInterventionRequired,
                                   errors: list = None) -> str:
        """
        Format a user-friendly message for the required intervention.

        Args:
            intervention: The intervention details
            errors: Optional list of actual errors for context

        Returns:
            Formatted message string
        """
        lines = [
            "",
            "=" * 70,
            "  MANUAL INTERVENTION REQUIRED",
            "=" * 70,
            "",
            f"  Category: {intervention.category}",
            f"  Issue: {intervention.title}",
            "",
            f"  {intervention.description}",
            "",
        ]

        if intervention.affected_files:
            lines.append("  Affected files:")
            for f in intervention.affected_files[:5]:
                lines.append(f"    - {f}")
            if len(intervention.affected_files) > 5:
                lines.append(f"    ... and {len(intervention.affected_files) - 5} more")
            lines.append("")

        lines.append("  Steps to fix:")
        for instruction in intervention.instructions:
            lines.append(f"    {instruction}")

        if errors:
            lines.append("")
            lines.append("  Error details:")
            for error in errors[:5]:
                if hasattr(error, 'message'):
                    err_loc = f"{error.file_path}:{error.line_number}" if error.file_path else ""
                    lines.append(f"    [{err_loc}] {error.message[:100]}")
                elif hasattr(error, 'failure_message'):
                    lines.append(f"    {error.failure_message[:100]}")

        lines.extend([
            "",
            "=" * 70,
            "  Automation paused. Fix the issue and resume with:",
            "    cd automation && python scripts/main.py",
            "=" * 70,
            ""
        ])

        return "\n".join(lines)

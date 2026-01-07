"""
Xcode build and test operations.
"""

import asyncio
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

from models import BuildResult, BuildError, TestResult, TestFailure
from logger import get_logger


class XcodeManager:
    """Manages Xcode build and test operations."""
    
    def __init__(self, config: dict):
        self.config = config
        self.project_path = Path(config["project"]["path"])
        self.scheme = config["project"]["scheme"]
        self.test_scheme = config["project"].get("test_scheme", self.scheme)
        
        self.simulator_name = config["simulator"]["name"]
        self.simulator_os = config["simulator"].get("os", "26.2")
        self.simulator_udid = config["simulator"].get("udid")
        
        self.build_timeout = config["automation"].get("build_timeout_seconds", 180)
        self.test_timeout = config["automation"].get("test_timeout_seconds", 300)
        
        self.logger = get_logger()
        self._cached_udid: Optional[str] = None
    
    def _get_destination(self) -> str:
        """Get xcodebuild destination string."""
        if self.simulator_udid:
            return f"id={self.simulator_udid}"
        return f"platform=iOS Simulator,name={self.simulator_name},OS={self.simulator_os}"
    
    async def _run_command(self, cmd: list[str], timeout: int) -> tuple[int, str, str]:
        """Run a command and return (returncode, stdout, stderr)."""
        self.logger.debug(f"Running: {' '.join(cmd[:5])}...")
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=timeout
            )
            return process.returncode, stdout.decode("utf-8", errors="replace"), stderr.decode("utf-8", errors="replace")
        except asyncio.TimeoutError:
            process.kill()
            await process.wait()
            raise TimeoutError(f"Command timed out after {timeout}s")
    
    async def get_simulator_udid(self) -> Optional[str]:
        """Get UDID of target simulator."""
        if self._cached_udid:
            return self._cached_udid
        
        if self.simulator_udid:
            self._cached_udid = self.simulator_udid
            return self._cached_udid
        
        try:
            returncode, stdout, _ = await self._run_command(
                ["xcrun", "simctl", "list", "devices", "-j"],
                timeout=30
            )
            
            if returncode != 0:
                return None
            
            import json
            data = json.loads(stdout)
            
            for runtime, devices in data.get("devices", {}).items():
                if "iOS" not in runtime:
                    continue
                for device in devices:
                    if device.get("name") == self.simulator_name and device.get("isAvailable", False):
                        self._cached_udid = device.get("udid")
                        self.logger.debug(f"Found simulator: {self.simulator_name} ({self._cached_udid})")
                        return self._cached_udid
            
            self.logger.warning(f"Simulator not found: {self.simulator_name}")
            return None
            
        except Exception as e:
            self.logger.error(f"Failed to get simulator UDID: {e}")
            return None
    
    async def boot_simulator(self) -> bool:
        """Boot the simulator if not already running."""
        udid = await self.get_simulator_udid()
        if not udid:
            return False
        
        try:
            # Check if already booted
            returncode, stdout, _ = await self._run_command(
                ["xcrun", "simctl", "list", "devices", "-j"],
                timeout=30
            )
            
            import json
            data = json.loads(stdout)
            
            for devices in data.get("devices", {}).values():
                for device in devices:
                    if device.get("udid") == udid:
                        if device.get("state") == "Booted":
                            self.logger.debug("Simulator already booted")
                            return True
            
            # Boot simulator
            self.logger.info(f"Booting simulator: {self.simulator_name}")
            returncode, _, stderr = await self._run_command(
                ["xcrun", "simctl", "boot", udid],
                timeout=60
            )
            
            if returncode != 0 and "already booted" not in stderr.lower():
                self.logger.error(f"Failed to boot simulator: {stderr}")
                return False
            
            # Wait for boot
            await asyncio.sleep(5)
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to boot simulator: {e}")
            return False
    
    async def build(self) -> BuildResult:
        """Build the project."""
        start_time = datetime.now()
        
        cmd = [
            "xcodebuild",
            "-project" if str(self.project_path).endswith(".xcodeproj") else "-workspace",
            str(self.project_path),
            "-scheme", self.scheme,
            "-destination", self._get_destination(),
            "-configuration", "Debug",
            "build"
        ]
        
        try:
            returncode, stdout, stderr = await self._run_command(cmd, self.build_timeout)
            duration = (datetime.now() - start_time).total_seconds()
            
            combined_output = stdout + "\n" + stderr
            errors, warnings = self._parse_build_output(combined_output)
            
            success = returncode == 0 and len(errors) == 0
            
            return BuildResult(
                success=success,
                output=stdout,
                error_output=stderr,
                duration_seconds=duration,
                errors=errors,
                warnings=warnings
            )
            
        except TimeoutError:
            duration = (datetime.now() - start_time).total_seconds()
            return BuildResult(
                success=False,
                output="",
                error_output=f"Build timed out after {self.build_timeout}s",
                duration_seconds=duration,
                errors=[BuildError(
                    file_path="",
                    line_number=None,
                    column_number=None,
                    message=f"Build timed out after {self.build_timeout}s"
                )]
            )
        except Exception as e:
            duration = (datetime.now() - start_time).total_seconds()
            return BuildResult(
                success=False,
                output="",
                error_output=str(e),
                duration_seconds=duration,
                errors=[BuildError(
                    file_path="",
                    line_number=None,
                    column_number=None,
                    message=str(e)
                )]
            )
    
    def _parse_build_output(self, output: str) -> tuple[list[BuildError], list[BuildError]]:
        """Parse xcodebuild output for errors and warnings."""
        errors = []
        warnings = []
        
        # Pattern: /path/to/file.swift:123:45: error: message
        pattern = r'^(.+?):(\d+):(\d+):\s*(error|warning):\s*(.+)$'
        
        for line in output.split('\n'):
            match = re.match(pattern, line.strip())
            if match:
                file_path = match.group(1)
                line_num = int(match.group(2))
                col_num = int(match.group(3))
                error_type = match.group(4)
                message = match.group(5)
                
                error = BuildError(
                    file_path=file_path,
                    line_number=line_num,
                    column_number=col_num,
                    message=message,
                    error_type=error_type
                )
                
                if error_type == "error":
                    errors.append(error)
                else:
                    warnings.append(error)
        
        # Also check for linker errors and other patterns
        if "error:" in output.lower() and not errors:
            # Generic error extraction
            for line in output.split('\n'):
                if "error:" in line.lower():
                    errors.append(BuildError(
                        file_path="",
                        line_number=None,
                        column_number=None,
                        message=line.strip()
                    ))
        
        return errors, warnings
    
    async def test(self) -> TestResult:
        """Run tests."""
        start_time = datetime.now()
        
        cmd = [
            "xcodebuild",
            "-project" if str(self.project_path).endswith(".xcodeproj") else "-workspace",
            str(self.project_path),
            "-scheme", self.test_scheme,
            "-destination", self._get_destination(),
            "-configuration", "Debug",
            "test"
        ]
        
        try:
            returncode, stdout, stderr = await self._run_command(cmd, self.test_timeout)
            duration = (datetime.now() - start_time).total_seconds()
            
            combined_output = stdout + "\n" + stderr
            failures, total, passed, failed, skipped = self._parse_test_output(combined_output)
            
            success = returncode == 0 and failed == 0
            
            return TestResult(
                success=success,
                output=stdout,
                error_output=stderr,
                duration_seconds=duration,
                total_tests=total,
                passed_tests=passed,
                failed_tests=failed,
                skipped_tests=skipped,
                failures=failures
            )
            
        except TimeoutError:
            duration = (datetime.now() - start_time).total_seconds()
            return TestResult(
                success=False,
                output="",
                error_output=f"Tests timed out after {self.test_timeout}s",
                duration_seconds=duration,
                failures=[TestFailure(
                    test_name="",
                    test_class="",
                    failure_message=f"Tests timed out after {self.test_timeout}s"
                )]
            )
        except Exception as e:
            duration = (datetime.now() - start_time).total_seconds()
            return TestResult(
                success=False,
                output="",
                error_output=str(e),
                duration_seconds=duration,
                failures=[TestFailure(
                    test_name="",
                    test_class="",
                    failure_message=str(e)
                )]
            )
    
    def _parse_test_output(self, output: str) -> tuple[list[TestFailure], int, int, int, int]:
        """Parse test output for failures and counts."""
        failures = []
        total = 0
        passed = 0
        failed = 0
        skipped = 0
        
        # Pattern for test case results
        # Test Case '-[TestClass testMethod]' passed (0.001 seconds).
        # Test Case '-[TestClass testMethod]' failed (0.001 seconds).
        result_pattern = r"Test Case '-\[(\w+)\s+(\w+)\]' (passed|failed)"
        
        for match in re.finditer(result_pattern, output):
            test_class = match.group(1)
            test_name = match.group(2)
            result = match.group(3)
            
            total += 1
            if result == "passed":
                passed += 1
            elif result == "failed":
                failed += 1
        
        # Pattern for failure details
        # /path/file.swift:123: error: -[TestClass testMethod] : XCTAssertEqual failed
        failure_pattern = r'^(.+?):(\d+):\s*error:\s*-\[(\w+)\s+(\w+)\]\s*:\s*(.+)$'
        
        for line in output.split('\n'):
            match = re.match(failure_pattern, line.strip())
            if match:
                failures.append(TestFailure(
                    test_class=match.group(3),
                    test_name=match.group(4),
                    failure_message=match.group(5),
                    file_path=match.group(1),
                    line_number=int(match.group(2))
                ))
        
        # Also look for "Executed X tests, with Y failures"
        summary_pattern = r'Executed (\d+) tests?, with (\d+) failures?'
        match = re.search(summary_pattern, output)
        if match:
            total = int(match.group(1))
            failed = int(match.group(2))
            passed = total - failed
        
        return failures, total, passed, failed, skipped
    
    async def clean(self):
        """Clean build folder."""
        cmd = [
            "xcodebuild",
            "-project" if str(self.project_path).endswith(".xcodeproj") else "-workspace",
            str(self.project_path),
            "-scheme", self.scheme,
            "clean"
        ]
        
        try:
            await self._run_command(cmd, 60)
            self.logger.debug("Build cleaned")
        except Exception as e:
            self.logger.warning(f"Clean failed: {e}")
    
    async def get_app_path(self) -> Optional[Path]:
        """Get path to built app in DerivedData."""
        # This is a simplified version - may need adjustment based on your setup
        home = Path.home()
        derived_data = home / "Library" / "Developer" / "Xcode" / "DerivedData"
        
        if not derived_data.exists():
            return None
        
        # Find project's derived data folder
        project_name = self.project_path.stem.replace(".xcodeproj", "").replace(".xcworkspace", "")
        
        for folder in derived_data.iterdir():
            if folder.name.startswith(project_name):
                app_path = folder / "Build" / "Products" / "Debug-iphonesimulator" / f"{project_name}.app"
                if app_path.exists():
                    return app_path
        
        return None

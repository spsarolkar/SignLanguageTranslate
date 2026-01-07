"""
Simulator screenshot capture.
"""

import asyncio
import shutil
from datetime import datetime
from pathlib import Path
from typing import Optional

from logger import get_logger
from xcode_manager import XcodeManager


class ScreenshotCapture:
    """Captures screenshots from iOS Simulator."""
    
    def __init__(self, config: dict, xcode_manager: XcodeManager):
        self.config = config
        self.xcode = xcode_manager
        
        self.screenshots_dir = Path(config.get("screenshots_dir", "screenshots"))
        self.screenshots_dir.mkdir(parents=True, exist_ok=True)
        
        self.dashboard_screenshots_dir = Path("dashboard/screenshots")
        self.dashboard_screenshots_dir.mkdir(parents=True, exist_ok=True)
        
        self.delay = config["automation"].get("screenshot_delay_seconds", 3)
        
        self.logger = get_logger()
    
    async def _run_simctl(self, args: list[str], timeout: int = 30) -> tuple[bool, str]:
        """Run simctl command."""
        cmd = ["xcrun", "simctl"] + args
        
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
            success = process.returncode == 0
            output = stdout.decode() if success else stderr.decode()
            return success, output
        except asyncio.TimeoutError:
            process.kill()
            return False, "Command timed out"
    
    async def install_app(self, app_path: Path) -> bool:
        """Install app on simulator."""
        udid = await self.xcode.get_simulator_udid()
        if not udid:
            self.logger.error("No simulator UDID available")
            return False
        
        success, output = await self._run_simctl(
            ["install", udid, str(app_path)],
            timeout=60
        )
        
        if not success:
            self.logger.error(f"Failed to install app: {output}")
        return success
    
    async def launch_app(self, bundle_id: str = None) -> bool:
        """Launch app on simulator."""
        udid = await self.xcode.get_simulator_udid()
        if not udid:
            return False
        
        bundle_id = bundle_id or self.config["project"]["bundle_id"]
        
        success, output = await self._run_simctl(
            ["launch", udid, bundle_id],
            timeout=30
        )
        
        if not success:
            self.logger.error(f"Failed to launch app: {output}")
        return success
    
    async def terminate_app(self, bundle_id: str = None) -> bool:
        """Terminate app on simulator."""
        udid = await self.xcode.get_simulator_udid()
        if not udid:
            return False
        
        bundle_id = bundle_id or self.config["project"]["bundle_id"]
        
        success, _ = await self._run_simctl(
            ["terminate", udid, bundle_id],
            timeout=30
        )
        return success
    
    async def capture(self, phase_id: str, suffix: str = "") -> Optional[Path]:
        """
        Capture screenshot from simulator.
        
        Args:
            phase_id: Phase identifier for filename
            suffix: Optional suffix for filename
            
        Returns:
            Path to captured screenshot or None if failed
        """
        udid = await self.xcode.get_simulator_udid()
        if not udid:
            self.logger.error("Cannot capture screenshot: no simulator UDID")
            return None
        
        # Ensure simulator is booted
        if not await self.xcode.boot_simulator():
            self.logger.error("Cannot capture screenshot: simulator not booted")
            return None
        
        # Generate filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe_phase_id = phase_id.replace(".", "_")
        filename = f"phase_{safe_phase_id}_{timestamp}"
        if suffix:
            filename += f"_{suffix}"
        filename += ".png"
        
        output_path = self.screenshots_dir / filename
        
        # Capture screenshot
        success, error = await self._run_simctl(
            ["io", udid, "screenshot", str(output_path)],
            timeout=30
        )
        
        if not success:
            self.logger.error(f"Failed to capture screenshot: {error}")
            return None
        
        if not output_path.exists():
            self.logger.error("Screenshot file not created")
            return None
        
        # Copy to dashboard directory
        dashboard_path = self.dashboard_screenshots_dir / filename
        shutil.copy2(output_path, dashboard_path)
        
        self.logger.screenshot(str(output_path))
        return output_path
    
    async def capture_with_app(self, phase_id: str) -> Optional[Path]:
        """
        Capture screenshot after launching the app.
        
        Boots simulator, installs and launches app, waits for UI, captures.
        """
        # Boot simulator
        if not await self.xcode.boot_simulator():
            return None
        
        # Get app path
        app_path = await self.xcode.get_app_path()
        if not app_path:
            self.logger.warning("App not found, capturing simulator home screen")
            return await self.capture(phase_id, suffix="no_app")
        
        # Install app
        if not await self.install_app(app_path):
            self.logger.warning("Failed to install app, capturing anyway")
        
        # Launch app
        if not await self.launch_app():
            self.logger.warning("Failed to launch app, capturing anyway")
        
        # Wait for UI to settle
        self.logger.debug(f"Waiting {self.delay}s for UI to settle...")
        await asyncio.sleep(self.delay)
        
        # Capture
        return await self.capture(phase_id)
    
    async def get_screenshot_list(self) -> list[dict]:
        """Get list of all captured screenshots."""
        screenshots = []
        
        for path in sorted(self.screenshots_dir.glob("*.png")):
            screenshots.append({
                "filename": path.name,
                "path": str(path),
                "timestamp": datetime.fromtimestamp(path.stat().st_mtime).isoformat(),
                "size_bytes": path.stat().st_size
            })
        
        return screenshots

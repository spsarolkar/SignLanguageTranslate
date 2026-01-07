"""
Dashboard generation for GitHub Pages.
"""

import asyncio
import json
from datetime import datetime
from pathlib import Path
from typing import Optional

import aiofiles

from models import ExecutionState, Status, PhaseConfig
from analytics_collector import AnalyticsCollector
from logger import get_logger


class DashboardGenerator:
    """Generates GitHub Pages dashboard content."""
    
    def __init__(self, config: dict, analytics: AnalyticsCollector):
        self.config = config
        self.analytics = analytics
        
        self.dashboard_config = config.get("github_pages", {})
        self.enabled = self.dashboard_config.get("enabled", True)
        self.auto_push = self.dashboard_config.get("auto_push", True)
        self.branch = self.dashboard_config.get("branch", "gh-pages")
        
        self.dashboard_dir = Path("dashboard")
        self.data_dir = self.dashboard_dir / "data"
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        self.logger = get_logger()
    
    async def update_status(self, state: ExecutionState, phase: PhaseConfig = None):
        """Update the status JSON file."""
        if not self.enabled:
            return
        
        try:
            # Get overall stats
            stats = await self.analytics.get_overall_stats()
            
            status_data = {
                "last_updated": datetime.now().isoformat(),
                "current_phase": state.current_phase,
                "current_phase_name": phase.name if phase else None,
                "current_step": state.current_step.value if state.current_step else None,
                "current_iteration": state.iteration,
                "status": state.status.value,
                "overall_progress": {
                    "total_phases": stats.get("total_phases", 0),
                    "completed_phases": stats.get("completed_phases", 0),
                    "failed_phases": stats.get("failed_phases", 0),
                    "percentage": stats.get("completion_percentage", 0)
                },
                "rate_limit_status": {
                    "is_limited": state.is_rate_limited,
                    "wait_until": state.rate_limit_until.isoformat() if state.rate_limit_until else None,
                    "consecutive_limits": state.consecutive_rate_limits,
                    "total_limits": state.total_rate_limits
                },
                "statistics": {
                    "total_iterations": stats.get("total_iterations", 0),
                    "avg_iterations_per_phase": round(stats.get("avg_iterations_per_phase", 0), 2),
                    "total_build_errors": stats.get("total_build_errors", 0),
                    "total_test_failures": stats.get("total_test_failures", 0),
                    "total_rate_limits": stats.get("total_rate_limits", 0),
                    "total_duration_minutes": round(stats.get("total_duration_minutes", 0), 1),
                    "total_input_tokens": stats.get("total_input_tokens", 0),
                    "total_output_tokens": stats.get("total_output_tokens", 0)
                }
            }
            
            await self._write_json("status.json", status_data)
            
        except Exception as e:
            self.logger.error(f"Failed to update status: {e}")
    
    async def update_history(self):
        """Update the history JSON file."""
        if not self.enabled:
            return
        
        try:
            phases = await self.analytics.get_phase_history()
            
            history_data = {
                "last_updated": datetime.now().isoformat(),
                "phases": phases
            }
            
            await self._write_json("history.json", history_data)
            
        except Exception as e:
            self.logger.error(f"Failed to update history: {e}")
    
    async def update_analytics(self):
        """Update the analytics JSON file."""
        if not self.enabled:
            return
        
        try:
            await self.analytics.export_to_json(self.data_dir / "analytics.json")
        except Exception as e:
            self.logger.error(f"Failed to update analytics: {e}")
    
    async def update_screenshots(self, screenshots: list[dict]):
        """Update the screenshots JSON file."""
        if not self.enabled:
            return
        
        try:
            screenshots_data = {
                "last_updated": datetime.now().isoformat(),
                "screenshots": screenshots
            }
            
            await self._write_json("screenshots.json", screenshots_data)
            
        except Exception as e:
            self.logger.error(f"Failed to update screenshots: {e}")
    
    async def update_all(self, state: ExecutionState, phase: PhaseConfig = None, 
                         screenshots: list[dict] = None):
        """Update all dashboard data files."""
        if not self.enabled:
            return
        
        await asyncio.gather(
            self.update_status(state, phase),
            self.update_history(),
            self.update_analytics(),
            self.update_screenshots(screenshots or [])
        )
    
    async def _write_json(self, filename: str, data: dict):
        """Write JSON data to file."""
        output_path = self.data_dir / filename
        async with aiofiles.open(output_path, 'w') as f:
            await f.write(json.dumps(data, indent=2))
    
    async def push_to_github_pages(self) -> bool:
        """Push dashboard changes to GitHub Pages branch."""
        if not self.auto_push:
            return True
        
        try:
            # This requires the git manager - we'll handle this in orchestrator
            self.logger.debug("Dashboard push requested")
            return True
        except Exception as e:
            self.logger.error(f"Failed to push dashboard: {e}")
            return False
    
    # Convenience methods for specific events
    
    async def on_phase_start(self, state: ExecutionState, phase: PhaseConfig):
        """Called when a phase starts."""
        if self.dashboard_config.get("update_on_phase_start", True):
            await self.update_status(state, phase)
    
    async def on_phase_complete(self, state: ExecutionState, phase: PhaseConfig):
        """Called when a phase completes."""
        if self.dashboard_config.get("update_on_phase_complete", True):
            await self.update_all(state, phase)
    
    async def on_phase_failed(self, state: ExecutionState, phase: PhaseConfig):
        """Called when a phase fails."""
        if self.dashboard_config.get("update_on_error", True):
            await self.update_all(state, phase)
    
    async def on_rate_limit(self, state: ExecutionState, phase: PhaseConfig = None):
        """Called when rate limit is hit."""
        if self.dashboard_config.get("update_on_rate_limit", True):
            await self.update_status(state, phase)
    
    async def on_iteration(self, state: ExecutionState, phase: PhaseConfig):
        """Called periodically during iterations."""
        # Only update status for iterations (less data)
        await self.update_status(state, phase)

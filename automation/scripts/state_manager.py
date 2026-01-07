"""
State persistence and management.
Handles saving/loading execution state for resume capability.
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Optional

import aiofiles

from models import ExecutionState, Step, Status, PhaseConfig
from logger import get_logger


class StateManager:
    """Manages execution state persistence."""
    
    def __init__(self, state_dir: Path):
        self.state_dir = Path(state_dir)
        self.state_dir.mkdir(parents=True, exist_ok=True)
        
        self.state_file = self.state_dir / "current_state.json"
        self.history_file = self.state_dir / "history.json"
        
        self._state: Optional[ExecutionState] = None
        self.logger = get_logger()
    
    async def load_state(self) -> ExecutionState:
        """Load state from file or create new."""
        if self.state_file.exists():
            try:
                async with aiofiles.open(self.state_file, "r") as f:
                    data = json.loads(await f.read())
                self._state = ExecutionState.from_dict(data)
                self.logger.debug(f"Loaded state: phase={self._state.current_phase}, step={self._state.current_step}")
            except Exception as e:
                self.logger.warning(f"Failed to load state: {e}, creating new")
                self._state = ExecutionState()
        else:
            self._state = ExecutionState()
        
        return self._state
    
    async def save_state(self):
        """Save current state to file."""
        if self._state is None:
            return
        
        self._state.last_updated = datetime.now()
        
        async with aiofiles.open(self.state_file, "w") as f:
            await f.write(json.dumps(self._state.to_dict(), indent=2))
        
        self.logger.debug("State saved")
    
    async def get_state(self) -> ExecutionState:
        """Get current state, loading if necessary."""
        if self._state is None:
            await self.load_state()
        return self._state
    
    async def reset_state(self):
        """Reset state to initial."""
        self._state = ExecutionState()
        await self.save_state()
        self.logger.info("State reset")
    
    # State update methods
    
    async def start_execution(self):
        """Mark execution as started."""
        state = await self.get_state()
        state.status = Status.RUNNING
        state.started_at = datetime.now()
        await self.save_state()
    
    async def start_phase(self, module_id: str, phase: PhaseConfig):
        """Start a new phase."""
        state = await self.get_state()
        state.current_module = module_id
        state.current_phase = phase.id
        state.current_step = Step.GENERATE
        state.iteration = 1
        state.consecutive_failures = 0
        state.last_error = None
        await self.save_state()
    
    async def advance_step(self, next_step: Step) -> ExecutionState:
        """Move to next step within phase."""
        state = await self.get_state()
        state.current_step = next_step
        await self.save_state()
        return state
    
    async def record_retry(self, step: Step) -> ExecutionState:
        """Record a retry, increment iteration counter."""
        state = await self.get_state()
        state.iteration += 1
        state.total_iterations += 1
        state.current_step = step
        await self.save_state()
        return state
    
    async def record_build_errors(self, count: int):
        """Record build errors."""
        state = await self.get_state()
        state.total_build_errors += count
        await self.save_state()
    
    async def record_test_failures(self, count: int):
        """Record test failures."""
        state = await self.get_state()
        state.total_test_failures += count
        await self.save_state()
    
    async def complete_phase(self, phase_id: str):
        """Mark phase as complete."""
        state = await self.get_state()
        if phase_id not in state.completed_phases:
            state.completed_phases.append(phase_id)
        state.current_step = Step.COMPLETE
        state.consecutive_failures = 0
        await self.save_state()
        await self._add_to_history(phase_id, success=True)
    
    async def fail_phase(self, phase_id: str, error: str):
        """Mark phase as failed."""
        state = await self.get_state()
        if phase_id not in state.failed_phases:
            state.failed_phases.append(phase_id)
        state.last_error = error
        state.consecutive_failures += 1
        await self.save_state()
        await self._add_to_history(phase_id, success=False, error=error)
    
    async def record_rate_limit(self, wait_until: datetime):
        """Record rate limit hit."""
        state = await self.get_state()
        state.is_rate_limited = True
        state.rate_limit_until = wait_until
        state.consecutive_rate_limits += 1
        state.total_rate_limits += 1
        state.status = Status.RATE_LIMITED
        await self.save_state()
    
    async def clear_rate_limit(self):
        """Clear rate limit status."""
        state = await self.get_state()
        state.is_rate_limited = False
        state.rate_limit_until = None
        state.consecutive_rate_limits = 0
        state.status = Status.RUNNING
        await self.save_state()
    
    async def pause_execution(self):
        """Pause execution."""
        state = await self.get_state()
        state.status = Status.PAUSED
        await self.save_state()
    
    async def complete_execution(self):
        """Mark entire execution as complete."""
        state = await self.get_state()
        state.status = Status.COMPLETE
        state.current_phase = None
        state.current_step = Step.COMPLETE
        await self.save_state()
    
    # History management
    
    async def _add_to_history(self, phase_id: str, success: bool, error: str = None):
        """Add phase result to history."""
        history = await self._load_history()
        
        entry = {
            "phase_id": phase_id,
            "success": success,
            "error": error,
            "timestamp": datetime.now().isoformat(),
            "iterations": self._state.iteration if self._state else 0
        }
        
        history["phases"].append(entry)
        
        async with aiofiles.open(self.history_file, "w") as f:
            await f.write(json.dumps(history, indent=2))
    
    async def _load_history(self) -> dict:
        """Load history from file."""
        if self.history_file.exists():
            try:
                async with aiofiles.open(self.history_file, "r") as f:
                    return json.loads(await f.read())
            except Exception:
                pass
        return {"phases": []}
    
    async def get_history(self) -> dict:
        """Get phase history."""
        return await self._load_history()
    
    # Query methods
    
    async def is_phase_completed(self, phase_id: str) -> bool:
        """Check if phase is already completed."""
        state = await self.get_state()
        return phase_id in state.completed_phases
    
    async def get_next_phase_id(self, all_phases: list[PhaseConfig]) -> Optional[str]:
        """Get next phase to execute."""
        state = await self.get_state()
        
        for phase in all_phases:
            if phase.id not in state.completed_phases:
                return phase.id
        
        return None
    
    async def get_resume_info(self) -> dict:
        """Get information for resuming execution."""
        state = await self.get_state()
        
        return {
            "can_resume": state.status in [Status.PAUSED, Status.RATE_LIMITED, Status.RUNNING],
            "current_phase": state.current_phase,
            "current_step": state.current_step.value if state.current_step else None,
            "iteration": state.iteration,
            "completed_count": len(state.completed_phases),
            "failed_count": len(state.failed_phases),
            "status": state.status.value,
            "claude_session_id": state.claude_session_id
        }
    
    # Session management
    
    async def save_session_id(self, session_id: str):
        """Save Claude session ID for persistence."""
        state = await self.get_state()
        state.claude_session_id = session_id
        await self.save_state()
        self.logger.debug(f"Saved Claude session ID: {session_id[:8]}...")
    
    async def get_session_id(self) -> Optional[str]:
        """Get saved Claude session ID."""
        state = await self.get_state()
        return state.claude_session_id
    
    async def clear_session_id(self):
        """Clear saved Claude session ID."""
        state = await self.get_state()
        if state.claude_session_id:
            self.logger.debug(f"Clearing Claude session ID: {state.claude_session_id[:8]}...")
        state.claude_session_id = None
        await self.save_state()

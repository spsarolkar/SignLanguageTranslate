"""
Data models for the automation system.
Contains dataclasses and enums for state management.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional
import json


class Step(str, Enum):
    """Steps within a phase execution."""
    GENERATE = "generate"
    BUILD = "build"
    TEST = "test"
    SCREENSHOT = "screenshot"
    COMMIT = "commit"
    COMPLETE = "complete"


class Status(str, Enum):
    """Overall execution status."""
    NOT_STARTED = "not_started"
    RUNNING = "running"
    PAUSED = "paused"
    RATE_LIMITED = "rate_limited"
    FAILED = "failed"
    COMPLETE = "complete"


class PhaseStatus(str, Enum):
    """Individual phase status."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass
class BuildError:
    """Represents a build error from xcodebuild."""
    file_path: str
    line_number: Optional[int]
    column_number: Optional[int]
    message: str
    error_type: str = "error"  # error, warning
    
    def to_dict(self) -> dict:
        return {
            "file_path": self.file_path,
            "line_number": self.line_number,
            "column_number": self.column_number,
            "message": self.message,
            "error_type": self.error_type
        }
    
    def __str__(self) -> str:
        loc = f"{self.file_path}"
        if self.line_number:
            loc += f":{self.line_number}"
            if self.column_number:
                loc += f":{self.column_number}"
        return f"{loc}: {self.error_type}: {self.message}"


@dataclass
class TestFailure:
    """Represents a test failure."""
    test_name: str
    test_class: str
    failure_message: str
    file_path: Optional[str] = None
    line_number: Optional[int] = None
    
    def to_dict(self) -> dict:
        return {
            "test_name": self.test_name,
            "test_class": self.test_class,
            "failure_message": self.failure_message,
            "file_path": self.file_path,
            "line_number": self.line_number
        }
    
    def __str__(self) -> str:
        return f"{self.test_class}.{self.test_name}: {self.failure_message}"


@dataclass
class BuildResult:
    """Result of a build operation."""
    success: bool
    output: str
    error_output: str
    duration_seconds: float
    errors: list[BuildError] = field(default_factory=list)
    warnings: list[BuildError] = field(default_factory=list)
    
    def to_dict(self) -> dict:
        return {
            "success": self.success,
            "duration_seconds": self.duration_seconds,
            "error_count": len(self.errors),
            "warning_count": len(self.warnings),
            "errors": [e.to_dict() for e in self.errors],
            "warnings": [w.to_dict() for w in self.warnings]
        }


@dataclass
class TestResult:
    """Result of a test operation."""
    success: bool
    output: str
    error_output: str
    duration_seconds: float
    total_tests: int = 0
    passed_tests: int = 0
    failed_tests: int = 0
    skipped_tests: int = 0
    failures: list[TestFailure] = field(default_factory=list)
    
    def to_dict(self) -> dict:
        return {
            "success": self.success,
            "duration_seconds": self.duration_seconds,
            "total_tests": self.total_tests,
            "passed_tests": self.passed_tests,
            "failed_tests": self.failed_tests,
            "skipped_tests": self.skipped_tests,
            "failures": [f.to_dict() for f in self.failures]
        }


@dataclass
class FileChange:
    """Represents a file change from Claude response."""
    path: str
    content: str
    action: str = "create"  # create, update, delete
    
    def to_dict(self) -> dict:
        return {
            "path": self.path,
            "action": self.action,
            "content_length": len(self.content)
        }


@dataclass
class ClaudeResponse:
    """Response from Claude API/CLI."""
    success: bool
    content: str
    files: list[FileChange] = field(default_factory=list)
    input_tokens: int = 0
    output_tokens: int = 0
    error: Optional[str] = None
    model: str = ""
    
    def to_dict(self) -> dict:
        return {
            "success": self.success,
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "file_count": len(self.files),
            "error": self.error,
            "model": self.model
        }


@dataclass
class PhaseConfig:
    """Configuration for a single phase."""
    id: str
    name: str
    prompt_file: str
    description: str = ""
    expected_files: list[str] = field(default_factory=list)
    tests_required: bool = True
    screenshot: bool = False
    
    @classmethod
    def from_dict(cls, data: dict) -> "PhaseConfig":
        return cls(
            id=data["id"],
            name=data["name"],
            prompt_file=data.get("prompt_file", ""),
            description=data.get("description", ""),
            expected_files=data.get("expected_files", []),
            tests_required=data.get("tests_required", True),
            screenshot=data.get("screenshot", False)
        )
    
    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "prompt_file": self.prompt_file,
            "description": self.description,
            "expected_files": self.expected_files,
            "tests_required": self.tests_required,
            "screenshot": self.screenshot
        }


@dataclass
class ModuleConfig:
    """Configuration for a module (group of phases)."""
    id: str
    name: str
    description: str
    phases: list[PhaseConfig] = field(default_factory=list)
    
    @classmethod
    def from_dict(cls, data: dict) -> "ModuleConfig":
        phases = [PhaseConfig.from_dict(p) for p in data.get("phases", [])]
        return cls(
            id=data["id"],
            name=data["name"],
            description=data.get("description", ""),
            phases=phases
        )
    
    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "phases": [p.to_dict() for p in self.phases]
        }


@dataclass
class PhaseResult:
    """Result of executing a phase."""
    phase_id: str
    success: bool
    iterations: int
    duration_seconds: float
    build_errors_fixed: int = 0
    test_failures_fixed: int = 0
    files_changed: int = 0
    screenshot_path: Optional[str] = None
    commit_hash: Optional[str] = None
    error_message: Optional[str] = None
    
    def to_dict(self) -> dict:
        return {
            "phase_id": self.phase_id,
            "success": self.success,
            "iterations": self.iterations,
            "duration_seconds": self.duration_seconds,
            "build_errors_fixed": self.build_errors_fixed,
            "test_failures_fixed": self.test_failures_fixed,
            "files_changed": self.files_changed,
            "screenshot_path": self.screenshot_path,
            "commit_hash": self.commit_hash,
            "error_message": self.error_message
        }


@dataclass
class ExecutionState:
    """Current execution state (persisted for resume)."""
    current_module: Optional[str] = None
    current_phase: Optional[str] = None
    current_step: Step = Step.GENERATE
    iteration: int = 0
    status: Status = Status.NOT_STARTED
    
    # History
    completed_phases: list[str] = field(default_factory=list)
    failed_phases: list[str] = field(default_factory=list)
    
    # Rate limit tracking
    is_rate_limited: bool = False
    rate_limit_until: Optional[datetime] = None
    consecutive_rate_limits: int = 0
    
    # Timing
    started_at: Optional[datetime] = None
    last_updated: Optional[datetime] = None
    
    # Error tracking
    last_error: Optional[str] = None
    consecutive_failures: int = 0
    
    # Statistics
    total_iterations: int = 0
    total_build_errors: int = 0
    total_test_failures: int = 0
    total_rate_limits: int = 0
    
    def to_dict(self) -> dict:
        return {
            "current_module": self.current_module,
            "current_phase": self.current_phase,
            "current_step": self.current_step.value if self.current_step else None,
            "iteration": self.iteration,
            "status": self.status.value,
            "completed_phases": self.completed_phases,
            "failed_phases": self.failed_phases,
            "is_rate_limited": self.is_rate_limited,
            "rate_limit_until": self.rate_limit_until.isoformat() if self.rate_limit_until else None,
            "consecutive_rate_limits": self.consecutive_rate_limits,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "last_updated": self.last_updated.isoformat() if self.last_updated else None,
            "last_error": self.last_error,
            "consecutive_failures": self.consecutive_failures,
            "total_iterations": self.total_iterations,
            "total_build_errors": self.total_build_errors,
            "total_test_failures": self.total_test_failures,
            "total_rate_limits": self.total_rate_limits
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> "ExecutionState":
        state = cls()
        state.current_module = data.get("current_module")
        state.current_phase = data.get("current_phase")
        state.current_step = Step(data["current_step"]) if data.get("current_step") else Step.GENERATE
        state.iteration = data.get("iteration", 0)
        state.status = Status(data.get("status", "not_started"))
        state.completed_phases = data.get("completed_phases", [])
        state.failed_phases = data.get("failed_phases", [])
        state.is_rate_limited = data.get("is_rate_limited", False)
        state.rate_limit_until = datetime.fromisoformat(data["rate_limit_until"]) if data.get("rate_limit_until") else None
        state.consecutive_rate_limits = data.get("consecutive_rate_limits", 0)
        state.started_at = datetime.fromisoformat(data["started_at"]) if data.get("started_at") else None
        state.last_updated = datetime.fromisoformat(data["last_updated"]) if data.get("last_updated") else None
        state.last_error = data.get("last_error")
        state.consecutive_failures = data.get("consecutive_failures", 0)
        state.total_iterations = data.get("total_iterations", 0)
        state.total_build_errors = data.get("total_build_errors", 0)
        state.total_test_failures = data.get("total_test_failures", 0)
        state.total_rate_limits = data.get("total_rate_limits", 0)
        return state


@dataclass
class DashboardStatus:
    """Status data for the dashboard."""
    last_updated: datetime
    current_phase: Optional[str]
    current_step: Optional[str]
    status: str
    overall_progress: dict
    current_iteration: int
    rate_limit_status: dict
    statistics: dict
    
    def to_dict(self) -> dict:
        return {
            "last_updated": self.last_updated.isoformat(),
            "current_phase": self.current_phase,
            "current_step": self.current_step,
            "status": self.status,
            "overall_progress": self.overall_progress,
            "current_iteration": self.current_iteration,
            "rate_limit_status": self.rate_limit_status,
            "statistics": self.statistics
        }

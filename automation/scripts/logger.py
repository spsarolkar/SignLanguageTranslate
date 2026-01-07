"""
Structured logging with Rich console output.
"""

import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.logging import RichHandler
from rich.theme import Theme

# Custom theme for console output
CUSTOM_THEME = Theme({
    "info": "cyan",
    "warning": "yellow",
    "error": "red bold",
    "success": "green bold",
    "phase": "magenta bold",
    "step": "blue",
    "progress": "cyan",
})

console = Console(theme=CUSTOM_THEME)


class AutomationLogger:
    """Logger with Rich console and file output."""
    
    def __init__(
        self,
        name: str = "automation",
        log_dir: str = "logs",
        console_level: str = "INFO",
        file_level: str = "DEBUG"
    ):
        self.name = name
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        
        # Create logger
        self.logger = logging.getLogger(name)
        self.logger.setLevel(logging.DEBUG)
        self.logger.handlers.clear()
        
        # Console handler with Rich
        console_handler = RichHandler(
            console=console,
            show_time=True,
            show_path=False,
            rich_tracebacks=True,
            tracebacks_show_locals=True
        )
        console_handler.setLevel(getattr(logging, console_level.upper()))
        console_handler.setFormatter(logging.Formatter("%(message)s"))
        self.logger.addHandler(console_handler)
        
        # File handler
        log_filename = f"automation_{datetime.now().strftime('%Y-%m-%d')}.log"
        file_handler = logging.FileHandler(
            self.log_dir / log_filename,
            encoding="utf-8"
        )
        file_handler.setLevel(getattr(logging, file_level.upper()))
        file_handler.setFormatter(logging.Formatter(
            "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
        ))
        self.logger.addHandler(file_handler)
    
    def debug(self, message: str, **kwargs):
        self.logger.debug(message, **kwargs)
    
    def info(self, message: str, **kwargs):
        self.logger.info(message, **kwargs)
    
    def warning(self, message: str, **kwargs):
        self.logger.warning(message, **kwargs)
    
    def error(self, message: str, **kwargs):
        self.logger.error(message, **kwargs)
    
    def exception(self, message: str, **kwargs):
        self.logger.exception(message, **kwargs)
    
    # Rich-formatted output methods
    def phase_start(self, phase_id: str, phase_name: str):
        """Log phase start with formatting."""
        console.print()
        console.rule(f"[phase]Phase {phase_id}: {phase_name}[/phase]", style="phase")
        self.info(f"Starting phase {phase_id}: {phase_name}")
    
    def phase_complete(self, phase_id: str, iterations: int, duration: float):
        """Log phase completion."""
        console.print(f"[success]✓ Phase {phase_id} completed[/success] "
                     f"(iterations: {iterations}, duration: {duration:.1f}s)")
        self.info(f"Phase {phase_id} completed - iterations: {iterations}, duration: {duration:.1f}s")
    
    def phase_failed(self, phase_id: str, error: str):
        """Log phase failure."""
        console.print(f"[error]✗ Phase {phase_id} failed: {error}[/error]")
        self.error(f"Phase {phase_id} failed: {error}")
    
    def step_start(self, step: str, iteration: int):
        """Log step start."""
        console.print(f"  [step]→ {step.capitalize()}[/step] (iteration {iteration})")
        self.debug(f"Step: {step}, iteration: {iteration}")
    
    def step_complete(self, step: str):
        """Log step completion."""
        console.print(f"    [success]✓ {step.capitalize()} succeeded[/success]")
        self.debug(f"Step {step} completed")
    
    def step_failed(self, step: str, error_count: int):
        """Log step failure."""
        console.print(f"    [error]✗ {step.capitalize()} failed ({error_count} errors)[/error]")
        self.debug(f"Step {step} failed with {error_count} errors")
    
    def build_error(self, error: str):
        """Log a build error."""
        console.print(f"      [error]• {error}[/error]")
        self.debug(f"Build error: {error}")
    
    def test_failure(self, test: str, message: str):
        """Log a test failure."""
        console.print(f"      [error]• {test}: {message}[/error]")
        self.debug(f"Test failure: {test} - {message}")
    
    def rate_limit(self, wait_seconds: int):
        """Log rate limit hit."""
        console.print(f"[warning]⏳ Rate limited. Waiting {wait_seconds}s...[/warning]")
        self.warning(f"Rate limited, waiting {wait_seconds} seconds")
    
    def progress(self, message: str):
        """Log progress message."""
        console.print(f"    [progress]{message}[/progress]")
        self.debug(message)
    
    def commit(self, commit_hash: str, message: str):
        """Log git commit."""
        short_hash = commit_hash[:8] if commit_hash else "unknown"
        console.print(f"    [success]📝 Committed: {short_hash}[/success]")
        self.info(f"Git commit: {short_hash} - {message[:50]}")
    
    def screenshot(self, path: str):
        """Log screenshot capture."""
        console.print(f"    [success]📸 Screenshot: {path}[/success]")
        self.info(f"Screenshot captured: {path}")
    
    def separator(self):
        """Print a separator line."""
        console.print()
        console.rule(style="dim")


# Global logger instance
_logger: Optional[AutomationLogger] = None


def get_logger() -> AutomationLogger:
    """Get or create the global logger."""
    global _logger
    if _logger is None:
        _logger = AutomationLogger()
    return _logger


def setup_logger(
    log_dir: str = "logs",
    console_level: str = "INFO",
    file_level: str = "DEBUG"
) -> AutomationLogger:
    """Setup and return the global logger."""
    global _logger
    _logger = AutomationLogger(
        log_dir=log_dir,
        console_level=console_level,
        file_level=file_level
    )
    return _logger

"""
Utility functions and helpers.
"""

import asyncio
import hashlib
import re
import shutil
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Optional

import yaml
from jinja2 import Environment, FileSystemLoader, select_autoescape


def load_yaml(path: Path) -> dict:
    """Load a YAML file."""
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def save_yaml(path: Path, data: dict):
    """Save data to a YAML file."""
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, default_flow_style=False, allow_unicode=True)


def load_text(path: Path) -> str:
    """Load a text file."""
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def save_text(path: Path, content: str):
    """Save content to a text file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def format_duration(seconds: float) -> str:
    """Format duration in human-readable format."""
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        minutes = int(seconds // 60)
        secs = int(seconds % 60)
        return f"{minutes}m {secs}s"
    else:
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        return f"{hours}h {minutes}m"


def format_datetime(dt: Optional[datetime]) -> str:
    """Format datetime for display."""
    if dt is None:
        return "N/A"
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def format_bytes(size: int) -> str:
    """Format bytes in human-readable format."""
    for unit in ["B", "KB", "MB", "GB"]:
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def calculate_percentage(current: int, total: int) -> float:
    """Calculate percentage safely."""
    if total == 0:
        return 0.0
    return (current / total) * 100


def truncate_string(s: str, max_length: int = 100, suffix: str = "...") -> str:
    """Truncate string with suffix."""
    if len(s) <= max_length:
        return s
    return s[:max_length - len(suffix)] + suffix


def hash_string(s: str) -> str:
    """Create SHA256 hash of string."""
    return hashlib.sha256(s.encode()).hexdigest()[:12]


def sanitize_filename(filename: str) -> str:
    """Sanitize string for use as filename."""
    # Remove or replace invalid characters
    sanitized = re.sub(r'[<>:"/\\|?*]', '_', filename)
    sanitized = re.sub(r'\s+', '_', sanitized)
    sanitized = re.sub(r'_+', '_', sanitized)
    return sanitized.strip('_')


def ensure_directory(path: Path) -> Path:
    """Ensure directory exists and return it."""
    path.mkdir(parents=True, exist_ok=True)
    return path


def copy_file(src: Path, dst: Path):
    """Copy file, creating parent directories if needed."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def get_timestamp() -> str:
    """Get current timestamp string."""
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def parse_iso_datetime(s: Optional[str]) -> Optional[datetime]:
    """Parse ISO format datetime string."""
    if not s:
        return None
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


class TemplateRenderer:
    """Jinja2 template renderer."""
    
    def __init__(self, templates_dir: Path):
        self.env = Environment(
            loader=FileSystemLoader(str(templates_dir)),
            autoescape=select_autoescape(['html', 'xml']),
            trim_blocks=True,
            lstrip_blocks=True
        )
        
        # Add custom filters
        self.env.filters['format_duration'] = format_duration
        self.env.filters['format_datetime'] = format_datetime
        self.env.filters['truncate'] = truncate_string
    
    def render(self, template_name: str, **kwargs) -> str:
        """Render a template with given context."""
        template = self.env.get_template(template_name)
        return template.render(**kwargs)
    
    def render_string(self, template_str: str, **kwargs) -> str:
        """Render a template string with given context."""
        template = self.env.from_string(template_str)
        return template.render(**kwargs)


class Debouncer:
    """Async debouncer for rate-limiting function calls."""
    
    def __init__(self, delay_seconds: float = 1.0):
        self.delay = delay_seconds
        self._task: Optional[asyncio.Task] = None
        self._callback = None
        self._args = None
        self._kwargs = None
    
    async def _execute(self):
        """Execute after delay."""
        await asyncio.sleep(self.delay)
        if self._callback:
            if asyncio.iscoroutinefunction(self._callback):
                await self._callback(*self._args, **self._kwargs)
            else:
                self._callback(*self._args, **self._kwargs)
    
    def call(self, callback, *args, **kwargs):
        """Schedule a debounced call."""
        self._callback = callback
        self._args = args
        self._kwargs = kwargs
        
        # Cancel existing task
        if self._task and not self._task.done():
            self._task.cancel()
        
        # Schedule new task
        self._task = asyncio.create_task(self._execute())
    
    def cancel(self):
        """Cancel pending call."""
        if self._task and not self._task.done():
            self._task.cancel()


class RateLimitTracker:
    """Track rate limit hits for backoff calculation."""
    
    def __init__(self, base_wait: int = 60, max_wait: int = 900, multiplier: float = 2.0):
        self.base_wait = base_wait
        self.max_wait = max_wait
        self.multiplier = multiplier
        self.consecutive_hits = 0
        self.last_hit: Optional[datetime] = None
        self.total_hits = 0
    
    def record_hit(self) -> int:
        """Record a rate limit hit and return wait time."""
        self.consecutive_hits += 1
        self.total_hits += 1
        self.last_hit = datetime.now()
        
        # Calculate wait with exponential backoff
        wait = min(
            self.base_wait * (self.multiplier ** (self.consecutive_hits - 1)),
            self.max_wait
        )
        
        # Add jitter (10% random variation)
        import random
        jitter = wait * 0.1 * random.random()
        
        return int(wait + jitter)
    
    def record_success(self):
        """Record a successful request, reset consecutive counter."""
        self.consecutive_hits = 0
    
    def get_wait_until(self, wait_seconds: int) -> datetime:
        """Get datetime when wait period ends."""
        return datetime.now() + timedelta(seconds=wait_seconds)
    
    def is_within_cooldown(self, cooldown_seconds: int = 60) -> bool:
        """Check if we're still in cooldown from last hit."""
        if self.last_hit is None:
            return False
        elapsed = (datetime.now() - self.last_hit).total_seconds()
        return elapsed < cooldown_seconds


def extract_code_blocks(text: str) -> list[dict]:
    """
    Extract code blocks from markdown text.
    Returns list of dicts with 'language', 'filename', and 'content'.
    """
    blocks = []
    
    # Pattern for fenced code blocks with optional filename
    # Matches: ```swift filename.swift or ```swift or ```
    pattern = r'```(\w+)?(?:\s+([^\n]+))?\n(.*?)```'
    
    for match in re.finditer(pattern, text, re.DOTALL):
        language = match.group(1) or ""
        filename = match.group(2) or ""
        content = match.group(3).strip()
        
        blocks.append({
            "language": language,
            "filename": filename.strip(),
            "content": content
        })
    
    return blocks


def extract_file_changes(response_text: str) -> list[tuple[str, str]]:
    """
    Extract file paths and contents from Claude response.
    Returns list of (path, content) tuples.
    """
    changes = []
    
    # Look for patterns like:
    # ### path/to/file.swift
    # or
    # **path/to/file.swift**
    # or
    # File: path/to/file.swift
    
    # Split by file markers
    file_pattern = r'(?:###\s*|File:\s*|\*\*)([\w/\-\.]+\.(?:swift|md|yaml|json|txt))\*?\*?'
    
    parts = re.split(file_pattern, response_text)
    
    # Parts will be: [intro, filename1, content1, filename2, content2, ...]
    for i in range(1, len(parts) - 1, 2):
        filename = parts[i].strip()
        content_section = parts[i + 1] if i + 1 < len(parts) else ""
        
        # Extract code from the content section
        code_blocks = extract_code_blocks(content_section)
        if code_blocks:
            # Use the first code block
            content = code_blocks[0]["content"]
            changes.append((filename, content))
    
    return changes

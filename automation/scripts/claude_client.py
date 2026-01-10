"""
Claude API/CLI client for code generation.
"""

import asyncio
import json
import os
import re
import tempfile
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional

from models import ClaudeResponse, FileChange
from logger import get_logger


class RateLimitError(Exception):
    """Raised when Claude API rate limit is hit."""
    def __init__(self, message: str, retry_after: int = None):
        super().__init__(message)
        self.retry_after = retry_after


class ClaudeClient:
    """Client for interacting with Claude via CLI or API."""
    
    def __init__(self, config: dict):
        self.config = config
        self.claude_config = config.get("claude", {})
        
        self.use_cli = self.claude_config.get("use_cli", True)
        self.model = self.claude_config.get("model", "claude-sonnet-4-20250514")
        self.max_tokens = self.claude_config.get("max_tokens", 16000)
        self.api_key_env = self.claude_config.get("api_key_env", "ANTHROPIC_API_KEY")
        
        self.logger = get_logger()
        self._api_client = None
        
        # Session management for CLI mode
        self._session_id: Optional[str] = None
        self._session_started: bool = False
    
    def start_session(self, session_id: str = None) -> str:
        """
        Start a new Claude session.
        
        Args:
            session_id: Optional specific session ID, or generate a new one
            
        Returns:
            The session ID being used
        """
        self._session_id = session_id or str(uuid.uuid4())
        self._session_started = False  # Will be set True after first successful call
        self.logger.info(f"New Claude session initialized: {self._session_id[:8]}...")
        return self._session_id
    
    def end_session(self):
        """End the current session and reset state."""
        if self._session_id:
            self.logger.info(f"Ending Claude session: {self._session_id[:8]}...")
        self._session_id = None
        self._session_started = False
    
    def get_session_id(self) -> Optional[str]:
        """Get current session ID."""
        return self._session_id
    
    async def send_prompt(self, prompt: str, context: str = None) -> ClaudeResponse:
        """
        Send prompt to Claude and get response.
        
        Args:
            prompt: The main prompt
            context: Optional context (e.g., existing code)
            
        Returns:
            ClaudeResponse with generated content
        """
        if self.use_cli:
            return await self._send_via_cli(prompt, context)
        else:
            return await self._send_via_api(prompt, context)
    
    async def _send_via_cli(self, prompt: str, context: str = None) -> ClaudeResponse:
        """Send prompt via Claude CLI (claude command)."""
        # Combine prompt and context
        full_prompt = prompt
        if context:
            full_prompt = f"{context}\n\n---\n\n{prompt}"

        # Log prompt size for visibility
        prompt_chars = len(full_prompt)
        prompt_lines = full_prompt.count('\n') + 1
        self.logger.info(f"Sending prompt to Claude CLI: {prompt_chars:,} chars, {prompt_lines} lines")

        try:
            # Build CLI command - use simple --print mode without session persistence
            # Session persistence via --session-id causes issues when sessions aren't cleaned up
            cmd = ["claude", "--print"]

            self.logger.debug(f"Running Claude CLI with flags: {' '.join(cmd[1:])}")

            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            # Track timing
            start_time = time.time()

            # Log that we're waiting
            self.logger.info("Waiting for Claude response... (this may take 1-5 minutes)")

            # Create a progress indicator task
            async def log_progress():
                elapsed = 0
                while True:
                    await asyncio.sleep(30)
                    elapsed += 30
                    self.logger.info(f"Still waiting for Claude... ({elapsed}s elapsed)")

            progress_task = asyncio.create_task(log_progress())

            try:
                # Set a timeout (10 minutes max)
                timeout = self.claude_config.get("timeout_seconds", 600)
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(input=full_prompt.encode('utf-8')),
                    timeout=timeout
                )
            except asyncio.TimeoutError:
                process.kill()
                progress_task.cancel()
                self.logger.error(f"Claude CLI timed out after {timeout}s")
                return ClaudeResponse(
                    success=False,
                    content="",
                    error=f"Timeout after {timeout} seconds",
                    model=self.model
                )
            finally:
                progress_task.cancel()
                try:
                    await progress_task
                except asyncio.CancelledError:
                    pass

            elapsed_time = time.time() - start_time

            stdout_text = stdout.decode('utf-8', errors='replace')
            stderr_text = stderr.decode('utf-8', errors='replace')

            # Log response stats
            response_chars = len(stdout_text)
            response_lines = stdout_text.count('\n') + 1
            self.logger.info(f"Claude responded in {elapsed_time:.1f}s: {response_chars:,} chars, {response_lines} lines")

            # Check for rate limit - check both stderr and stdout
            if self._is_rate_limit_error(stderr_text, stdout_text):
                retry_after = self._parse_retry_after(stderr_text) or self._parse_retry_after(stdout_text)
                # Default to 60 seconds if we can't parse a specific time
                if retry_after is None:
                    retry_after = 60
                    self.logger.warning(f"Rate limit hit but couldn't parse wait time, defaulting to {retry_after}s")
                else:
                    self.logger.warning(f"Rate limit hit. Will retry after {retry_after}s")
                raise RateLimitError("Rate limit exceeded", retry_after=retry_after)

            if process.returncode != 0:
                error_msg = stderr_text[:500] if stderr_text else "Unknown error"
                self.logger.error(f"Claude CLI error (exit code {process.returncode}): {error_msg}")
                return ClaudeResponse(
                    success=False,
                    content="",
                    error=stderr_text or f"Exit code {process.returncode}",
                    model=self.model
                )

            # Parse response for file changes
            files = self._extract_file_changes(stdout_text)
            self.logger.info(f"Extracted {len(files)} file changes from response")
            for f in files:
                self.logger.debug(f"  - {f.path} ({len(f.content):,} chars)")

            return ClaudeResponse(
                success=True,
                content=stdout_text,
                files=files,
                model=self.model
            )

        except FileNotFoundError:
            self.logger.error("Claude CLI not found. Make sure 'claude' is installed and in PATH.")
            return ClaudeResponse(
                success=False,
                content="",
                error="Claude CLI not found",
                model=self.model
            )
    
    async def _send_via_api(self, prompt: str, context: str = None) -> ClaudeResponse:
        """Send prompt via Anthropic API."""
        try:
            import anthropic
        except ImportError:
            raise RuntimeError("anthropic package not installed. Run: pip install anthropic")
        
        api_key = os.environ.get(self.api_key_env)
        if not api_key:
            raise RuntimeError(f"API key not found in environment variable: {self.api_key_env}")
        
        if self._api_client is None:
            self._api_client = anthropic.AsyncAnthropic(api_key=api_key)
        
        # Build messages
        messages = []
        
        if context:
            messages.append({
                "role": "user",
                "content": f"Here is the current project context:\n\n{context}"
            })
            messages.append({
                "role": "assistant", 
                "content": "I've reviewed the project context. What would you like me to help with?"
            })
        
        messages.append({
            "role": "user",
            "content": prompt
        })
        
        try:
            self.logger.debug(f"Calling Claude API with model {self.model}")
            
            response = await self._api_client.messages.create(
                model=self.model,
                max_tokens=self.max_tokens,
                messages=messages
            )
            
            content = ""
            for block in response.content:
                if hasattr(block, 'text'):
                    content += block.text
            
            # Parse response for file changes
            files = self._extract_file_changes(content)
            
            return ClaudeResponse(
                success=True,
                content=content,
                files=files,
                input_tokens=response.usage.input_tokens,
                output_tokens=response.usage.output_tokens,
                model=self.model
            )
            
        except anthropic.RateLimitError as e:
            retry_after = self._parse_retry_after(str(e))
            raise RateLimitError(str(e), retry_after=retry_after)
        except Exception as e:
            self.logger.error(f"Claude API error: {e}")
            return ClaudeResponse(
                success=False,
                content="",
                error=str(e),
                model=self.model
            )
    
    def _parse_retry_after(self, error_text: str) -> Optional[int]:
        """Try to parse retry-after value from error message."""
        error_lower = error_text.lower()

        # Pattern 1: Date-based reset messages with full date
        # "You've hit your limit · resets Jan 10 at 9:30am (Asia/Calcutta)"
        date_pattern = r'resets?\s+([a-z]{3})\s+(\d{1,2})\s+(?:at\s+)?(\d{1,2}):(\d{2})(am|pm)'
        date_match = re.search(date_pattern, error_lower)
        if date_match:
            try:
                month_str, day, hour, minute, ampm = date_match.groups()
                
                # Convert month name to number
                months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
                          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12}
                month = months.get(month_str, 1)
                
                # Convert hour to 24-hour format
                hour = int(hour)
                if ampm == 'pm' and hour != 12:
                    hour += 12
                elif ampm == 'am' and hour == 12:
                    hour = 0
                
                # Build the reset datetime
                now = datetime.now()
                year = now.year
                # If the date seems to be in the past, it's next year
                reset_date = datetime(year, month, int(day), hour, int(minute))
                if reset_date < now:
                    reset_date = datetime(year + 1, month, int(day), hour, int(minute))
                
                # Calculate seconds until reset + 60s buffer to ensure limit is cleared
                seconds_until_reset = int((reset_date - now).total_seconds()) + 60
                self.logger.info(f"Rate limit resets at {reset_date.strftime('%Y-%m-%d %H:%M')} (waiting {seconds_until_reset}s = reset + 60s buffer)")
                return max(seconds_until_reset, 60)  # At least 60 seconds
            except Exception as e:
                self.logger.debug(f"Failed to parse date-based reset time: {e}")

        # Pattern 2: Time-only reset messages (assumes today or tomorrow)
        # "You've hit your limit · resets 9:30am (Asia/Calcutta)"
        time_pattern = r'resets?\s+(\d{1,2}):(\d{2})(am|pm)'
        time_match = re.search(time_pattern, error_lower)
        if time_match:
            try:
                hour, minute, ampm = time_match.groups()
                
                # Convert hour to 24-hour format
                hour = int(hour)
                if ampm == 'pm' and hour != 12:
                    hour += 12
                elif ampm == 'am' and hour == 12:
                    hour = 0
                
                # Build the reset datetime (today first, tomorrow if in past)
                now = datetime.now()
                reset_date = now.replace(hour=hour, minute=int(minute), second=0, microsecond=0)
                if reset_date <= now:
                    # Reset time is in the past today, so it must be tomorrow
                    from datetime import timedelta
                    reset_date = reset_date + timedelta(days=1)
                
                # Calculate seconds until reset + 60s buffer to ensure limit is cleared
                seconds_until_reset = int((reset_date - now).total_seconds()) + 60
                self.logger.info(f"Rate limit resets at {reset_date.strftime('%Y-%m-%d %H:%M')} (waiting {seconds_until_reset}s = reset + 60s buffer)")
                return max(seconds_until_reset, 60)  # At least 60 seconds
            except Exception as e:
                self.logger.debug(f"Failed to parse time-based reset time: {e}")

        # Common patterns for rate limit reset time
        patterns = [
            r'retry.?after[:\s]+(\d+)',
            r'wait[:\s]+(\d+)\s*second',
            r'(\d+)\s*seconds?\s*(?:before|until)',
            r'try again in (\d+)\s*(?:second|minute|hour)',
            r'reset(?:s|ting)?\s*(?:in|after)\s*(\d+)',
            r'limit.*?(\d+)\s*(?:second|minute)',
            r'please wait (\d+)',
            r'available in (\d+)',
        ]

        for pattern in patterns:
            match = re.search(pattern, error_lower)
            if match:
                value = int(match.group(1))
                # If it mentions minutes, convert to seconds
                if 'minute' in error_lower[max(0, match.start()-20):match.end()+20]:
                    value *= 60
                # If it mentions hours, convert to seconds
                elif 'hour' in error_lower[max(0, match.start()-20):match.end()+20]:
                    value *= 3600
                self.logger.debug(f"Parsed retry-after from error: {value}s")
                return value

        return None

    def _is_rate_limit_error(self, stderr_text: str, stdout_text: str = "") -> bool:
        """Check if the error indicates a rate limit."""
        combined = (stderr_text + stdout_text).lower()
        rate_limit_indicators = [
            'rate limit',
            'rate_limit',
            'too many requests',
            'quota exceeded',
            'throttl',
            'overloaded',
            'capacity',
            '429',
            'try again later',
            'request limit',
            'hit your limit',
            "you've hit",
            'resets',
        ]
        return any(indicator in combined for indicator in rate_limit_indicators)
    
    def _extract_file_changes(self, response_text: str) -> list[FileChange]:
        """Extract file changes from Claude's response."""
        files = []
        
        # Pattern 1: ### path/to/file.swift followed by code block
        # Pattern 2: **path/to/file.swift** followed by code block
        # Pattern 3: File: path/to/file.swift followed by code block
        
        file_markers = [
            r'###\s+([\w/\-\.]+\.(?:swift|md|yaml|json|txt|py))',
            r'\*\*([\w/\-\.]+\.(?:swift|md|yaml|json|txt|py))\*\*',
            r'File:\s*([\w/\-\.]+\.(?:swift|md|yaml|json|txt|py))',
            r'`([\w/\-\.]+\.(?:swift|md|yaml|json|txt|py))`',
        ]
        
        combined_pattern = '|'.join(f'(?:{p})' for p in file_markers)
        
        # Find all file markers and their positions
        markers = []
        for match in re.finditer(combined_pattern, response_text, re.MULTILINE):
            filename = None
            for g in match.groups():
                if g:
                    filename = g
                    break
            if filename:
                markers.append((match.start(), match.end(), filename))
        
        # For each marker, extract the following code block
        for i, (start, end, filename) in enumerate(markers):
            next_pos = markers[i + 1][0] if i + 1 < len(markers) else len(response_text)
            section = response_text[end:next_pos]
            
            code_match = re.search(r'```(?:\w+)?\n(.*?)```', section, re.DOTALL)
            if code_match:
                content = code_match.group(1).strip()
                files.append(FileChange(
                    path=filename,
                    content=content,
                    action="create"
                ))
        
        return files
    
    def build_fix_prompt(self, original_prompt: str, errors: list, error_type: str = "build") -> str:
        """
        Build a prompt to fix errors.
        """
        error_list = "\n".join(f"- {str(e)}" for e in errors[:10])
        
        if error_type == "build":
            return f"""The previous code generation resulted in build errors. Please fix them.

## Build Errors
{error_list}

## Instructions
1. Analyze each error carefully
2. Generate corrected code for the affected files
3. Make sure to provide complete file contents, not just snippets
4. Ensure all imports are included
5. Fix any syntax errors or type mismatches

## Original Request
{original_prompt}

Please provide the corrected code files."""
        
        else:  # test failures
            return f"""The previous code generation resulted in test failures. Please fix them.

## Test Failures
{error_list}

## Instructions
1. Analyze each test failure
2. Fix the implementation code (not just the tests) if the logic is wrong
3. If tests are testing incorrect behavior, fix the tests
4. Provide complete corrected file contents
5. Ensure all edge cases are handled

## Original Request
{original_prompt}

Please provide the corrected code files."""
    
    async def check_available(self) -> bool:
        """Check if Claude is available."""
        if self.use_cli:
            # Check if claude command exists
            process = await asyncio.create_subprocess_exec(
                "which", "claude",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await process.communicate()
            return process.returncode == 0
        else:
            # Check for API key
            return os.environ.get(self.api_key_env) is not None

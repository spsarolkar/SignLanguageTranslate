"""
Claude API/CLI client for code generation.
"""

import asyncio
import json
import os
import re
import tempfile
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
        
        try:
            # Claude CLI: pipe prompt via stdin with --print flag for non-interactive output
            # The --print flag outputs response directly without interactive mode
            cmd = ["claude", "--print"]
            
            self.logger.debug(f"Running Claude CLI with --print flag")
            
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            # Send prompt via stdin
            stdout, stderr = await process.communicate(input=full_prompt.encode('utf-8'))
            
            stdout_text = stdout.decode('utf-8', errors='replace')
            stderr_text = stderr.decode('utf-8', errors='replace')
            
            # Check for rate limit
            if "rate limit" in stderr_text.lower() or "rate_limit" in stderr_text.lower():
                retry_after = self._parse_retry_after(stderr_text)
                raise RateLimitError("Rate limit exceeded", retry_after=retry_after)
            
            if process.returncode != 0:
                self.logger.error(f"Claude CLI error: {stderr_text}")
                return ClaudeResponse(
                    success=False,
                    content="",
                    error=stderr_text,
                    model=self.model
                )
            
            # Parse response for file changes
            files = self._extract_file_changes(stdout_text)
            
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
        patterns = [
            r'retry.?after[:\s]+(\d+)',
            r'wait[:\s]+(\d+)\s*second',
            r'(\d+)\s*seconds?\s*(?:before|until)',
        ]
        
        for pattern in patterns:
            match = re.search(pattern, error_text.lower())
            if match:
                return int(match.group(1))
        
        return None
    
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

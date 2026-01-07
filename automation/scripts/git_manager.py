"""
Git operations for committing changes.
"""

import asyncio
from datetime import datetime
from pathlib import Path
from typing import Optional

from jinja2 import Template

from models import PhaseConfig
from logger import get_logger


class GitManager:
    """Manages git operations."""
    
    def __init__(self, config: dict, project_root: Path):
        self.config = config
        self.project_root = project_root
        self.git_config = config.get("git", {})
        
        self.enabled = self.git_config.get("enabled", True)
        self.auto_commit = self.git_config.get("auto_commit", True)
        self.auto_push = self.git_config.get("auto_push", False)
        
        self.commit_template = self.git_config.get("commit_message_template", 
            "feat({{ module }}): Phase {{ phase_id }} - {{ phase_name }}")
        
        self.logger = get_logger()
    
    async def _run_git(self, args: list[str], timeout: int = 30) -> tuple[bool, str]:
        """Run git command in project root."""
        cmd = ["git"] + args
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=str(self.project_root)
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=timeout
            )
            success = process.returncode == 0
            output = stdout.decode().strip() if success else stderr.decode().strip()
            return success, output
        except asyncio.TimeoutError:
            process.kill()
            return False, "Command timed out"
    
    async def is_git_repo(self) -> bool:
        """Check if project is a git repository."""
        success, _ = await self._run_git(["rev-parse", "--git-dir"])
        return success
    
    async def has_changes(self) -> bool:
        """Check if there are uncommitted changes."""
        success, output = await self._run_git(["status", "--porcelain"])
        return success and len(output.strip()) > 0
    
    async def get_changed_files(self) -> list[str]:
        """Get list of changed files."""
        success, output = await self._run_git(["status", "--porcelain"])
        if not success:
            return []
        
        files = []
        for line in output.split('\n'):
            if line.strip():
                # Format: "XY filename" or "XY filename -> newname"
                parts = line[3:].split(' -> ')
                files.append(parts[-1])
        
        return files
    
    async def stage_all(self) -> bool:
        """Stage all changes."""
        success, output = await self._run_git(["add", "-A"])
        if not success:
            self.logger.error(f"Failed to stage changes: {output}")
        return success
    
    async def stage_files(self, files: list[str]) -> bool:
        """Stage specific files."""
        if not files:
            return True
        
        success, output = await self._run_git(["add"] + files)
        if not success:
            self.logger.error(f"Failed to stage files: {output}")
        return success
    
    async def commit(self, message: str) -> Optional[str]:
        """
        Commit staged changes.
        
        Returns:
            Commit hash if successful, None otherwise
        """
        success, output = await self._run_git(["commit", "-m", message])
        
        if not success:
            if "nothing to commit" in output.lower():
                self.logger.debug("Nothing to commit")
                return None
            self.logger.error(f"Failed to commit: {output}")
            return None
        
        # Get commit hash
        success, hash_output = await self._run_git(["rev-parse", "HEAD"])
        if success:
            return hash_output.strip()
        
        return "unknown"
    
    async def push(self, branch: str = None) -> bool:
        """Push commits to remote."""
        args = ["push"]
        if branch:
            args.extend(["origin", branch])
        
        success, output = await self._run_git(args, timeout=60)
        if not success:
            self.logger.error(f"Failed to push: {output}")
        return success
    
    async def create_branch(self, branch_name: str) -> bool:
        """Create and checkout a new branch."""
        success, output = await self._run_git(["checkout", "-b", branch_name])
        if not success:
            self.logger.error(f"Failed to create branch: {output}")
        return success
    
    async def checkout(self, branch: str) -> bool:
        """Checkout a branch."""
        success, output = await self._run_git(["checkout", branch])
        if not success:
            self.logger.error(f"Failed to checkout: {output}")
        return success
    
    async def get_current_branch(self) -> Optional[str]:
        """Get current branch name."""
        success, output = await self._run_git(["rev-parse", "--abbrev-ref", "HEAD"])
        return output if success else None
    
    def render_commit_message(self, phase: PhaseConfig, module_id: str, 
                               iterations: int, duration: float, description: str = "") -> str:
        """Render commit message from template."""
        template = Template(self.commit_template)
        
        return template.render(
            module=module_id,
            phase_id=phase.id,
            phase_name=phase.name,
            description=description or phase.description,
            iterations=iterations,
            duration=f"{duration:.1f}s",
            timestamp=datetime.now().isoformat()
        )
    
    async def commit_phase(self, phase: PhaseConfig, module_id: str,
                           iterations: int, duration: float) -> Optional[str]:
        """
        Commit changes for a completed phase.
        
        Returns:
            Commit hash if successful, None otherwise
        """
        if not self.enabled:
            self.logger.debug("Git disabled, skipping commit")
            return None
        
        if not await self.is_git_repo():
            self.logger.warning("Not a git repository, skipping commit")
            return None
        
        if not await self.has_changes():
            self.logger.debug("No changes to commit")
            return None
        
        # Stage all changes
        if not await self.stage_all():
            return None
        
        # Generate commit message
        message = self.render_commit_message(phase, module_id, iterations, duration)
        
        # Commit
        commit_hash = await self.commit(message)
        
        if commit_hash:
            self.logger.commit(commit_hash, message.split('\n')[0])
            
            # Push if auto-push enabled
            if self.auto_push:
                await self.push()
        
        return commit_hash
    
    async def get_commit_count(self) -> int:
        """Get total commit count."""
        success, output = await self._run_git(["rev-list", "--count", "HEAD"])
        if success:
            try:
                return int(output.strip())
            except ValueError:
                pass
        return 0
    
    async def stash_save(self, message: str = "automation-stash") -> bool:
        """Stash current changes."""
        success, output = await self._run_git(["stash", "save", message])
        return success
    
    async def stash_pop(self) -> bool:
        """Pop stashed changes."""
        success, output = await self._run_git(["stash", "pop"])
        return success

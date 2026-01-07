"""
Rate limit handling with exponential backoff.
"""

import random
from datetime import datetime, timedelta
from typing import Optional

from logger import get_logger


class RateLimitHandler:
    """Handles rate limit detection and backoff calculation."""
    
    def __init__(self, config: dict):
        automation_config = config.get("automation", {})
        
        self.base_wait = automation_config.get("rate_limit_base_wait_seconds", 60)
        self.max_wait = automation_config.get("rate_limit_max_wait_seconds", 900)
        self.multiplier = automation_config.get("rate_limit_backoff_multiplier", 2.0)
        
        # Proactive pacing settings
        self.delay_between_calls = automation_config.get("delay_between_claude_calls", 5)
        self.delay_after_failure = automation_config.get("delay_after_failure", 10)
        
        self.consecutive_hits = 0
        self.last_hit: Optional[datetime] = None
        self.last_success: Optional[datetime] = None
        self.total_hits = 0
        
        self.logger = get_logger()
    
    def calculate_wait(self, retry_after: int = None) -> int:
        """
        Calculate wait time after a rate limit hit.
        
        Args:
            retry_after: Server-provided retry-after value (if available)
            
        Returns:
            Number of seconds to wait
        """
        # Use server-provided value if available
        if retry_after and retry_after > 0:
            self.logger.debug(f"Using server retry-after: {retry_after}s")
            return retry_after
        
        # Calculate exponential backoff
        wait = min(
            self.base_wait * (self.multiplier ** self.consecutive_hits),
            self.max_wait
        )
        
        # Add jitter (±10%)
        jitter = wait * 0.1 * (random.random() * 2 - 1)
        wait = int(wait + jitter)
        
        self.logger.debug(f"Calculated backoff wait: {wait}s (consecutive: {self.consecutive_hits})")
        
        return max(wait, self.base_wait)
    
    def record_hit(self, retry_after: int = None) -> int:
        """
        Record a rate limit hit.
        
        Args:
            retry_after: Server-provided retry-after value
            
        Returns:
            Number of seconds to wait
        """
        self.consecutive_hits += 1
        self.total_hits += 1
        self.last_hit = datetime.now()
        
        wait_time = self.calculate_wait(retry_after)
        
        self.logger.rate_limit(wait_time)
        
        return wait_time
    
    def record_success(self):
        """Record a successful request, reset consecutive counter."""
        if self.consecutive_hits > 0:
            self.logger.debug(f"Rate limit cleared after {self.consecutive_hits} consecutive hits")
        self.consecutive_hits = 0
        self.last_success = datetime.now()
    
    def get_wait_until(self, wait_seconds: int) -> datetime:
        """Get datetime when wait period ends."""
        return datetime.now() + timedelta(seconds=wait_seconds)
    
    def is_in_cooldown(self, cooldown_seconds: int = None) -> bool:
        """Check if we should still be in cooldown from last hit."""
        if self.last_hit is None:
            return False
        
        cooldown = cooldown_seconds or self.base_wait
        elapsed = (datetime.now() - self.last_hit).total_seconds()
        
        return elapsed < cooldown
    
    def get_remaining_cooldown(self) -> int:
        """Get remaining cooldown time in seconds."""
        if self.last_hit is None:
            return 0
        
        elapsed = (datetime.now() - self.last_hit).total_seconds()
        remaining = self.base_wait - elapsed
        
        return max(0, int(remaining))
    
    def get_stats(self) -> dict:
        """Get rate limit statistics."""
        return {
            "consecutive_hits": self.consecutive_hits,
            "total_hits": self.total_hits,
            "last_hit": self.last_hit.isoformat() if self.last_hit else None,
            "is_in_cooldown": self.is_in_cooldown(),
            "remaining_cooldown": self.get_remaining_cooldown()
        }
    
    def reset(self):
        """Reset all rate limit tracking."""
        self.consecutive_hits = 0
        self.last_hit = None
        self.last_success = None
        # Don't reset total_hits - keep for statistics
    
    def get_pacing_delay(self) -> int:
        """
        Get recommended delay before next Claude call (proactive pacing).
        
        Returns:
            Number of seconds to wait before making the next call
        """
        if self.last_success is None:
            return 0  # No delay for first call
        
        elapsed = (datetime.now() - self.last_success).total_seconds()
        remaining = self.delay_between_calls - elapsed
        
        if remaining > 0:
            self.logger.debug(f"Pacing delay: {int(remaining)}s until next call allowed")
            return int(remaining)
        
        return 0
    
    def get_failure_delay(self) -> int:
        """
        Get delay to apply after a failure before retry.
        
        Returns:
            Number of seconds to wait after a failure
        """
        return self.delay_after_failure

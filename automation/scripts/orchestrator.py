"""
Main workflow orchestrator.
Coordinates the entire automation process.
"""

import asyncio
import sys
import select
from datetime import datetime
from pathlib import Path
from typing import Optional

from models import (
    ExecutionState, Step, Status, PhaseConfig, ModuleConfig,
    PhaseResult, ClaudeResponse
)
from utils import load_yaml, load_text, save_text, format_duration
from logger import get_logger, setup_logger
from state_manager import StateManager
from analytics_collector import AnalyticsCollector
from dashboard_generator import DashboardGenerator
from xcode_manager import XcodeManager
from screenshot_capture import ScreenshotCapture
from git_manager import GitManager
from claude_client import ClaudeClient, RateLimitError
from rate_limit_handler import RateLimitHandler
from manual_intervention_detector import ManualInterventionDetector, ManualInterventionRequired


class Orchestrator:
    """Main workflow orchestrator."""
    
    def __init__(self, config_path: Path = None):
        # Load configuration
        config_path = config_path or Path("config/config.yaml")
        self.config = load_yaml(config_path)
        
        # Setup logging
        log_config = self.config.get("logging", {})
        self.logger = setup_logger(
            log_dir=log_config.get("log_dir", "logs"),
            console_level=log_config.get("level", "INFO"),
            file_level=log_config.get("file_level", "DEBUG")
        )
        
        # Load phases
        phases_path = Path("config/phases.yaml")
        self.phases_config = load_yaml(phases_path)
        self.modules = [ModuleConfig.from_dict(m) for m in self.phases_config.get("modules", [])]
        
        # Build phase lookup
        self._phase_lookup = {}
        self._module_lookup = {}
        for module in self.modules:
            for phase in module.phases:
                self._phase_lookup[phase.id] = phase
                self._module_lookup[phase.id] = module.id
        
        # Initialize components
        self.state_manager = StateManager(Path(self.config.get("state_dir", "state")))
        
        analytics_config = self.config.get("analytics", {})
        self.analytics = AnalyticsCollector(analytics_config.get("database_path", "state/analytics.db"))
        
        self.dashboard = DashboardGenerator(self.config, self.analytics)
        
        self.xcode = XcodeManager(self.config)
        self.screenshots = ScreenshotCapture(self.config, self.xcode)
        
        project_root = Path(self.config["project"]["path"]).parent.parent
        self.git = GitManager(self.config, project_root)
        
        self.claude = ClaudeClient(self.config)
        self.rate_limiter = RateLimitHandler(self.config)

        # Manual intervention detection
        self.intervention_detector = ManualInterventionDetector(
            max_same_error_retries=self.config.get("automation", {}).get("max_same_error_retries", 3)
        )

        # Configuration
        automation_config = self.config.get("automation", {})
        self.max_retries_per_phase = automation_config.get("max_retries_per_phase", 15)
        self.pause_between_phases = automation_config.get("pause_between_phases_seconds", 5)
        self.confirmation_timeout = automation_config.get("confirmation_timeout_seconds", 20)
    
    async def initialize(self):
        """Initialize all components."""
        await self.analytics.initialize_db()
        await self.state_manager.load_state()
        self.logger.info("Orchestrator initialized")
    
    async def wait_for_user_confirmation(self, phase_name: str) -> bool:
        """
        Wait for user confirmation to continue or terminate.
        
        Returns:
            True to continue with next phase, False to terminate
        """
        print(f"\n{'='*60}")
        print(f"Phase '{phase_name}' completed successfully!")
        print(f"Press 'q' + Enter to quit, or wait {self.confirmation_timeout}s to continue...")
        print(f"{'='*60}")
        
        # Use asyncio to handle timeout
        loop = asyncio.get_event_loop()
        
        def check_input():
            if select.select([sys.stdin], [], [], 0)[0]:
                return sys.stdin.readline().strip().lower()
            return None
        
        start_time = asyncio.get_event_loop().time()
        while asyncio.get_event_loop().time() - start_time < self.confirmation_timeout:
            # Check for input in a non-blocking way
            user_input = await loop.run_in_executor(None, check_input)
            if user_input is not None:
                if user_input in ['q', 'quit', 'exit', 'stop']:
                    self.logger.info("User requested termination")
                    return False
                else:
                    # Any other input (including Enter) continues
                    return True
            await asyncio.sleep(0.5)
        
        self.logger.info(f"No input after {self.confirmation_timeout}s, continuing...")
        return True

    async def _wait_with_countdown(self, wait_seconds: int, reason: str = "Waiting"):
        """
        Wait for specified time with countdown display.

        Args:
            wait_seconds: Total seconds to wait
            reason: Reason for waiting (shown in display)
        """
        from datetime import timedelta

        resume_time = datetime.now() + timedelta(seconds=wait_seconds)
        
        # Format resume time - show full date if > 24 hours, otherwise just time
        if wait_seconds > 86400:  # > 24 hours
            resume_str = resume_time.strftime('%b %d at %I:%M%p')
        elif wait_seconds > 3600:  # > 1 hour
            resume_str = resume_time.strftime('today at %I:%M%p')
        else:
            resume_str = resume_time.strftime('%H:%M:%S')
        
        # Format wait duration human-readably
        days, remainder = divmod(wait_seconds, 86400)
        hours, remainder = divmod(remainder, 3600)
        mins, secs = divmod(remainder, 60)
        
        if days > 0:
            duration_str = f"{int(days)}d {int(hours)}h {int(mins)}m"
        elif hours > 0:
            duration_str = f"{int(hours)}h {int(mins)}m"
        elif mins > 0:
            duration_str = f"{int(mins)}m {int(secs)}s"
        else:
            duration_str = f"{int(secs)}s"

        print(f"\n{'='*60}")
        print(f"⏳ {reason}: waiting {duration_str} before resuming...")
        print(f"   Will auto-resume at: {resume_str}")
        print(f"   Press Ctrl+C to abort")
        print(f"{'='*60}")

        # Show countdown every 30 seconds for long waits, every 10 seconds for shorter ones
        # For very long waits (> 1 hour), show every 5 minutes
        if wait_seconds > 3600:
            interval = 300  # 5 minutes
        elif wait_seconds > 120:
            interval = 30
        else:
            interval = 10

        remaining = wait_seconds
        while remaining > 0:
            sleep_time = min(interval, remaining)
            await asyncio.sleep(sleep_time)
            remaining -= sleep_time

            if remaining > 0:
                days, remainder = divmod(remaining, 86400)
                hours, remainder = divmod(remainder, 3600)
                mins, secs = divmod(remainder, 60)
                
                # Use \r to overwrite the same line for cleaner output
                if days > 0:
                    print(f"\r   ⏳ {int(days)}d {int(hours)}h {int(mins)}m remaining...   ", end="", flush=True)
                elif hours > 0:
                    print(f"\r   ⏳ {int(hours)}h {int(mins)}m remaining...      ", end="", flush=True)
                elif mins > 0:
                    print(f"\r   ⏳ {int(mins)}m {int(secs)}s remaining...       ", end="", flush=True)
                else:
                    print(f"\r   ⏳ {int(secs)}s remaining...           ", end="", flush=True)

        print()  # Final newline after countdown
        print(f"{'='*60}\n")

    def get_all_phases(self) -> list[PhaseConfig]:
        """Get flat list of all phases."""
        phases = []
        for module in self.modules:
            phases.extend(module.phases)
        return phases
    
    def get_phase(self, phase_id: str) -> Optional[PhaseConfig]:
        """Get phase by ID."""
        return self._phase_lookup.get(phase_id)
    
    def get_module_id(self, phase_id: str) -> Optional[str]:
        """Get module ID for a phase."""
        return self._module_lookup.get(phase_id)
    
    async def run_all(self, resume: bool = True) -> bool:
        """
        Run all phases.
        
        Args:
            resume: If True, resume from saved state; if False, start fresh
        """
        await self.initialize()
        
        state = await self.state_manager.get_state()
        
        # Determine starting point
        if resume and state.status in [Status.PAUSED, Status.RATE_LIMITED, Status.RUNNING]:
            self.logger.info(f"Resuming from phase {state.current_phase}, step {state.current_step}")
        else:
            await self.state_manager.reset_state()
            state = await self.state_manager.get_state()
            self.logger.info("Starting fresh execution")
        
        await self.state_manager.start_execution()

        all_phases = self.get_all_phases()
        
        for phase in all_phases:
            # Skip completed phases
            if await self.state_manager.is_phase_completed(phase.id):
                self.logger.debug(f"Skipping completed phase {phase.id}")
                continue
            
            # Run phase
            result = await self.run_phase(phase.id)
            
            if not result.success:
                self.logger.error(f"Phase {phase.id} failed, stopping execution")
                return False
            
            # Ask user to continue or terminate (with timeout)
            should_continue = await self.wait_for_user_confirmation(phase.name)
            if not should_continue:
                self.logger.info("User requested termination after phase completion")
                await self.state_manager.pause_execution()
                return True  # Return True since phases completed successfully
            
            # Pause between phases
            if self.pause_between_phases > 0:
                await asyncio.sleep(self.pause_between_phases)
        
        await self.state_manager.complete_execution()
        self.logger.info("All phases completed successfully!")
        
        return True
    
    async def run_phase(self, phase_id: str) -> PhaseResult:
        """Run a single phase."""
        phase = self.get_phase(phase_id)
        if not phase:
            return PhaseResult(
                phase_id=phase_id,
                success=False,
                iterations=0,
                duration_seconds=0,
                error_message=f"Phase {phase_id} not found"
            )
        
        module_id = self.get_module_id(phase_id)
        start_time = datetime.now()
        
        self.logger.phase_start(phase_id, phase.name)
        
        # Initialize phase state
        await self.state_manager.start_phase(module_id, phase)
        await self.analytics.start_phase(phase_id, module_id, phase.name)
        
        state = await self.state_manager.get_state()
        await self.dashboard.on_phase_start(state, phase)
        
        # Load prompt
        prompt = await self._load_prompt(phase)
        if not prompt:
            return await self._fail_phase(phase, module_id, "Failed to load prompt", start_time)
        
        iteration = state.iteration
        original_prompt = prompt
        build_errors_fixed = 0
        test_failures_fixed = 0
        
        while iteration <= self.max_retries_per_phase:
            state = await self.state_manager.get_state()
            step_start = datetime.now()
            
            try:
                # GENERATE step
                if state.current_step == Step.GENERATE:
                    self.logger.step_start("generate", iteration)
                    await self.analytics.record_iteration_start(phase_id, iteration, "generate")
                    
                    # Apply proactive pacing delay before Claude call
                    pacing_delay = self.rate_limiter.get_pacing_delay()
                    if pacing_delay > 0:
                        self.logger.debug(f"Applying pacing delay: {pacing_delay}s")
                        await asyncio.sleep(pacing_delay)
                    
                    response = await self.claude.send_prompt(prompt)
                    
                    if not response.success:
                        iteration = await self._handle_step_failure(
                            phase_id, iteration, "generate", response.error or "Generation failed"
                        )
                        continue
                    
                    # Apply file changes
                    await self._apply_file_changes(response)
                    
                    # Record token usage
                    if response.input_tokens or response.output_tokens:
                        await self.analytics.record_token_usage(
                            phase_id, iteration, 
                            response.input_tokens, response.output_tokens,
                            response.model
                        )
                    
                    self.logger.step_complete("generate")
                    await self.analytics.record_iteration_complete(
                        phase_id, iteration, "generate",
                        (datetime.now() - step_start).total_seconds()
                    )
                    
                    self.rate_limiter.record_success()
                    await self.state_manager.advance_step(Step.BUILD)
                    state = await self.state_manager.get_state()
                
                # BUILD step
                if state.current_step == Step.BUILD:
                    self.logger.step_start("build", iteration)
                    await self.analytics.record_iteration_start(phase_id, iteration, "build")

                    result = await self.xcode.build()

                    if not result.success:
                        self.logger.step_failed("build", len(result.errors))

                        for error in result.errors[:5]:
                            self.logger.build_error(str(error))

                        # Check for manual intervention requirements
                        intervention = self.intervention_detector.check_build_errors(result.errors)
                        if not intervention:
                            intervention = self.intervention_detector.check_repeated_errors(result.errors, iteration)

                        if intervention and intervention.is_blocking:
                            # Manual intervention needed - stop automation
                            message = self.intervention_detector.format_intervention_message(
                                intervention, result.errors
                            )
                            print(message)
                            self.logger.warning(f"Manual intervention required: {intervention.title}")

                            await self.state_manager.pause_execution()
                            return await self._fail_phase(
                                phase, module_id,
                                f"Manual intervention required: {intervention.title}",
                                start_time
                            )

                        await self.analytics.record_build_errors(phase_id, iteration, result.errors)
                        await self.state_manager.record_build_errors(len(result.errors))
                        build_errors_fixed += len(result.errors)

                        # Generate fix prompt
                        prompt = self.claude.build_fix_prompt(original_prompt, result.errors, "build")

                        iteration = await self._handle_step_failure(
                            phase_id, iteration, "build",
                            f"{len(result.errors)} build errors"
                        )
                        await self.state_manager.advance_step(Step.GENERATE)
                        continue

                    # Build succeeded - reset error tracking
                    self.intervention_detector.reset_error_counts()

                    self.logger.step_complete("build")
                    await self.analytics.record_iteration_complete(
                        phase_id, iteration, "build", result.duration_seconds
                    )

                    await self.state_manager.advance_step(Step.TEST)
                    state = await self.state_manager.get_state()
                
                # TEST step
                if state.current_step == Step.TEST:
                    if not phase.tests_required:
                        self.logger.debug("Tests not required, skipping")
                        await self.state_manager.advance_step(Step.SCREENSHOT)
                        state = await self.state_manager.get_state()
                    else:
                        self.logger.step_start("test", iteration)
                        await self.analytics.record_iteration_start(phase_id, iteration, "test")

                        result = await self.xcode.test()

                        if not result.success:
                            self.logger.step_failed("test", len(result.failures))

                            for failure in result.failures[:5]:
                                self.logger.test_failure(
                                    f"{failure.test_class}.{failure.test_name}",
                                    failure.failure_message
                                )

                            # Check for manual intervention requirements
                            # Test failures can also indicate XCTest target issues
                            intervention = self.intervention_detector.check_test_failures(result.failures)

                            # Also check build errors in test output (e.g., "No such module 'XCTest'")
                            if not intervention and result.error_output:
                                # Parse error_output for build-like errors
                                from models import BuildError
                                test_build_errors = []
                                for line in result.error_output.split('\n'):
                                    if 'error:' in line.lower():
                                        test_build_errors.append(BuildError(
                                            file_path="",
                                            line_number=None,
                                            column_number=None,
                                            message=line.strip()
                                        ))
                                if test_build_errors:
                                    intervention = self.intervention_detector.check_build_errors(test_build_errors)

                            if intervention and intervention.is_blocking:
                                message = self.intervention_detector.format_intervention_message(
                                    intervention, result.failures
                                )
                                print(message)
                                self.logger.warning(f"Manual intervention required: {intervention.title}")

                                await self.state_manager.pause_execution()
                                return await self._fail_phase(
                                    phase, module_id,
                                    f"Manual intervention required: {intervention.title}",
                                    start_time
                                )

                            await self.analytics.record_test_failures(phase_id, iteration, result.failures)
                            await self.state_manager.record_test_failures(len(result.failures))
                            test_failures_fixed += len(result.failures)

                            # Generate fix prompt
                            prompt = self.claude.build_fix_prompt(original_prompt, result.failures, "test")

                            iteration = await self._handle_step_failure(
                                phase_id, iteration, "test",
                                f"{len(result.failures)} test failures"
                            )
                            await self.state_manager.advance_step(Step.GENERATE)
                            continue

                        self.logger.step_complete("test")
                        self.logger.progress(f"Tests: {result.passed_tests}/{result.total_tests} passed")

                        await self.analytics.record_iteration_complete(
                            phase_id, iteration, "test", result.duration_seconds
                        )

                        await self.state_manager.advance_step(Step.SCREENSHOT)
                        state = await self.state_manager.get_state()
                
                # SCREENSHOT step
                if state.current_step == Step.SCREENSHOT:
                    screenshot_path = None
                    
                    if phase.screenshot and self.config["automation"].get("capture_screenshots", True):
                        self.logger.step_start("screenshot", iteration)
                        screenshot_path = await self.screenshots.capture_with_app(phase_id)
                        
                        if screenshot_path:
                            await self.analytics.record_screenshot(phase_id, str(screenshot_path))
                    
                    await self.state_manager.advance_step(Step.COMMIT)
                    state = await self.state_manager.get_state()
                
                # COMMIT step
                if state.current_step == Step.COMMIT:
                    commit_hash = None
                    
                    if self.config["git"].get("auto_commit", True):
                        self.logger.step_start("commit", iteration)
                        
                        duration = (datetime.now() - start_time).total_seconds()
                        commit_hash = await self.git.commit_phase(
                            phase, module_id, iteration, duration
                        )
                        
                        if commit_hash:
                            changed_files = await self.git.get_changed_files()
                            await self.analytics.record_commit(
                                phase_id, commit_hash, phase.name, len(changed_files)
                            )
                    
                    await self.state_manager.advance_step(Step.COMPLETE)
                    state = await self.state_manager.get_state()
                
                # COMPLETE
                if state.current_step == Step.COMPLETE:
                    duration = (datetime.now() - start_time).total_seconds()
                    
                    await self.analytics.complete_phase(phase_id, iteration, duration)
                    await self.state_manager.complete_phase(phase_id)
                    
                    state = await self.state_manager.get_state()
                    await self.dashboard.on_phase_complete(state, phase)
                    
                    self.logger.phase_complete(phase_id, iteration, duration)
                    
                    return PhaseResult(
                        phase_id=phase_id,
                        success=True,
                        iterations=iteration,
                        duration_seconds=duration,
                        build_errors_fixed=build_errors_fixed,
                        test_failures_fixed=test_failures_fixed
                    )
            
            except RateLimitError as e:
                wait_time = self.rate_limiter.record_hit(e.retry_after)
                wait_until = self.rate_limiter.get_wait_until(wait_time)

                await self.state_manager.record_rate_limit(wait_until)
                await self.analytics.record_rate_limit(phase_id, wait_time)

                state = await self.state_manager.get_state()
                await self.dashboard.on_rate_limit(state, phase)

                # Show countdown for rate limit wait
                await self._wait_with_countdown(wait_time, "Rate limit")

                await self.state_manager.clear_rate_limit()
                self.logger.info("Rate limit cleared, resuming...")
                continue
            
            except KeyboardInterrupt:
                self.logger.warning("Interrupted by user")
                await self.state_manager.pause_execution()
                
                state = await self.state_manager.get_state()
                await self.dashboard.update_all(state, phase)
                
                raise
            
            except Exception as e:
                self.logger.exception(f"Unexpected error: {e}")
                iteration = await self._handle_step_failure(
                    phase_id, iteration, state.current_step.value, str(e)
                )
        
        # Max retries exceeded
        duration = (datetime.now() - start_time).total_seconds()
        return await self._fail_phase(
            phase, module_id,
            f"Max retries ({self.max_retries_per_phase}) exceeded",
            start_time
        )
    
    async def _load_prompt(self, phase: PhaseConfig) -> Optional[str]:
        """Load prompt from file."""
        prompt_path = Path("phases") / phase.prompt_file
        
        if not prompt_path.exists():
            self.logger.error(f"Prompt file not found: {prompt_path}")
            return None
        
        try:
            return load_text(prompt_path)
        except Exception as e:
            self.logger.error(f"Failed to load prompt: {e}")
            return None
    
    async def _apply_file_changes(self, response: ClaudeResponse):
        """Apply file changes from Claude response."""
        project_root = Path(self.config["project"]["path"]).parent
        
        for file_change in response.files:
            file_path = project_root / file_change.path
            
            self.logger.progress(f"Writing: {file_change.path}")
            
            try:
                save_text(file_path, file_change.content)
            except Exception as e:
                self.logger.error(f"Failed to write {file_change.path}: {e}")
    
    async def _handle_step_failure(self, phase_id: str, iteration: int, 
                                    step: str, error: str) -> int:
        """Handle a step failure and return new iteration number."""
        await self.analytics.record_iteration_failed(phase_id, iteration, step, error)
        
        state = await self.state_manager.record_retry(Step.GENERATE)
        await self.dashboard.on_iteration(state, self.get_phase(phase_id))
        
        # Apply delay after failure before retry
        failure_delay = self.rate_limiter.get_failure_delay()
        if failure_delay > 0:
            self.logger.debug(f"Applying failure delay: {failure_delay}s before retry")
            await asyncio.sleep(failure_delay)
        
        return iteration + 1
    
    async def _fail_phase(self, phase: PhaseConfig, module_id: str, 
                          error: str, start_time: datetime) -> PhaseResult:
        """Handle phase failure."""
        duration = (datetime.now() - start_time).total_seconds()
        
        await self.state_manager.fail_phase(phase.id, error)
        await self.analytics.fail_phase(phase.id, 0, duration)
        
        state = await self.state_manager.get_state()
        await self.dashboard.on_phase_failed(state, phase)
        
        self.logger.phase_failed(phase.id, error)
        
        return PhaseResult(
            phase_id=phase.id,
            success=False,
            iterations=state.iteration,
            duration_seconds=duration,
            error_message=error
        )
    
    async def get_status(self) -> dict:
        """Get current execution status."""
        state = await self.state_manager.get_state()
        stats = await self.analytics.get_overall_stats()
        
        return {
            "state": state.to_dict(),
            "stats": stats,
            "resume_info": await self.state_manager.get_resume_info()
        }

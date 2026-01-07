"""
Analytics collection and storage using SQLite.
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Optional

import aiosqlite

from models import BuildError, TestFailure, PhaseResult
from logger import get_logger


class AnalyticsCollector:
    """Collects and stores analytics in SQLite."""
    
    SCHEMA = """
    CREATE TABLE IF NOT EXISTS phases (
        id TEXT PRIMARY KEY,
        module_id TEXT,
        name TEXT,
        status TEXT,
        started_at TIMESTAMP,
        completed_at TIMESTAMP,
        total_iterations INTEGER DEFAULT 0,
        total_duration_seconds REAL DEFAULT 0
    );
    
    CREATE TABLE IF NOT EXISTS iterations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phase_id TEXT,
        iteration_number INTEGER,
        step TEXT,
        status TEXT,
        started_at TIMESTAMP,
        completed_at TIMESTAMP,
        duration_seconds REAL,
        error_message TEXT,
        FOREIGN KEY (phase_id) REFERENCES phases(id)
    );
    
    CREATE TABLE IF NOT EXISTS build_errors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phase_id TEXT,
        iteration_number INTEGER,
        file_path TEXT,
        line_number INTEGER,
        error_message TEXT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (phase_id) REFERENCES phases(id)
    );
    
    CREATE TABLE IF NOT EXISTS test_failures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phase_id TEXT,
        iteration_number INTEGER,
        test_class TEXT,
        test_name TEXT,
        failure_message TEXT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (phase_id) REFERENCES phases(id)
    );
    
    CREATE TABLE IF NOT EXISTS rate_limits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phase_id TEXT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        wait_seconds INTEGER
    );
    
    CREATE TABLE IF NOT EXISTS commits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phase_id TEXT,
        commit_hash TEXT,
        message TEXT,
        files_changed INTEGER DEFAULT 0,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (phase_id) REFERENCES phases(id)
    );
    
    CREATE TABLE IF NOT EXISTS screenshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phase_id TEXT,
        file_path TEXT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (phase_id) REFERENCES phases(id)
    );
    
    CREATE TABLE IF NOT EXISTS token_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phase_id TEXT,
        iteration_number INTEGER,
        input_tokens INTEGER DEFAULT 0,
        output_tokens INTEGER DEFAULT 0,
        model TEXT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (phase_id) REFERENCES phases(id)
    );
    
    CREATE INDEX IF NOT EXISTS idx_iterations_phase ON iterations(phase_id);
    CREATE INDEX IF NOT EXISTS idx_build_errors_phase ON build_errors(phase_id);
    CREATE INDEX IF NOT EXISTS idx_test_failures_phase ON test_failures(phase_id);
    """
    
    def __init__(self, db_path: str):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.logger = get_logger()
    
    async def initialize_db(self):
        """Initialize database with schema."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.executescript(self.SCHEMA)
            await db.commit()
        self.logger.debug("Analytics database initialized")
    
    # Phase tracking
    
    async def start_phase(self, phase_id: str, module_id: str, name: str):
        """Record phase start."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """INSERT OR REPLACE INTO phases (id, module_id, name, status, started_at)
                   VALUES (?, ?, ?, 'running', ?)""",
                (phase_id, module_id, name, datetime.now().isoformat())
            )
            await db.commit()
    
    async def complete_phase(self, phase_id: str, iterations: int, duration: float):
        """Record phase completion."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """UPDATE phases 
                   SET status = 'completed', completed_at = ?, 
                       total_iterations = ?, total_duration_seconds = ?
                   WHERE id = ?""",
                (datetime.now().isoformat(), iterations, duration, phase_id)
            )
            await db.commit()
    
    async def fail_phase(self, phase_id: str, iterations: int, duration: float):
        """Record phase failure."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """UPDATE phases 
                   SET status = 'failed', completed_at = ?, 
                       total_iterations = ?, total_duration_seconds = ?
                   WHERE id = ?""",
                (datetime.now().isoformat(), iterations, duration, phase_id)
            )
            await db.commit()
    
    # Iteration tracking
    
    async def record_iteration_start(self, phase_id: str, iteration: int, step: str):
        """Record iteration start."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """INSERT INTO iterations (phase_id, iteration_number, step, status, started_at)
                   VALUES (?, ?, ?, 'running', ?)""",
                (phase_id, iteration, step, datetime.now().isoformat())
            )
            await db.commit()
    
    async def record_iteration_complete(self, phase_id: str, iteration: int, step: str, duration: float):
        """Record iteration completion."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """UPDATE iterations 
                   SET status = 'completed', completed_at = ?, duration_seconds = ?
                   WHERE phase_id = ? AND iteration_number = ? AND step = ?""",
                (datetime.now().isoformat(), duration, phase_id, iteration, step)
            )
            await db.commit()
    
    async def record_iteration_failed(self, phase_id: str, iteration: int, step: str, error: str):
        """Record iteration failure."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """UPDATE iterations 
                   SET status = 'failed', completed_at = ?, error_message = ?
                   WHERE phase_id = ? AND iteration_number = ? AND step = ?""",
                (datetime.now().isoformat(), error, phase_id, iteration, step)
            )
            await db.commit()
    
    # Error tracking
    
    async def record_build_errors(self, phase_id: str, iteration: int, errors: list[BuildError]):
        """Record build errors."""
        async with aiosqlite.connect(self.db_path) as db:
            for error in errors:
                await db.execute(
                    """INSERT INTO build_errors (phase_id, iteration_number, file_path, line_number, error_message)
                       VALUES (?, ?, ?, ?, ?)""",
                    (phase_id, iteration, error.file_path, error.line_number, error.message)
                )
            await db.commit()
    
    async def record_test_failures(self, phase_id: str, iteration: int, failures: list[TestFailure]):
        """Record test failures."""
        async with aiosqlite.connect(self.db_path) as db:
            for failure in failures:
                await db.execute(
                    """INSERT INTO test_failures (phase_id, iteration_number, test_class, test_name, failure_message)
                       VALUES (?, ?, ?, ?, ?)""",
                    (phase_id, iteration, failure.test_class, failure.test_name, failure.failure_message)
                )
            await db.commit()
    
    # Other events
    
    async def record_rate_limit(self, phase_id: str, wait_seconds: int):
        """Record rate limit hit."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """INSERT INTO rate_limits (phase_id, wait_seconds) VALUES (?, ?)""",
                (phase_id, wait_seconds)
            )
            await db.commit()
    
    async def record_commit(self, phase_id: str, commit_hash: str, message: str, files_changed: int = 0):
        """Record git commit."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """INSERT INTO commits (phase_id, commit_hash, message, files_changed)
                   VALUES (?, ?, ?, ?)""",
                (phase_id, commit_hash, message, files_changed)
            )
            await db.commit()
    
    async def record_screenshot(self, phase_id: str, file_path: str):
        """Record screenshot capture."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """INSERT INTO screenshots (phase_id, file_path) VALUES (?, ?)""",
                (phase_id, file_path)
            )
            await db.commit()
    
    async def record_token_usage(self, phase_id: str, iteration: int, 
                                  input_tokens: int, output_tokens: int, model: str):
        """Record token usage."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """INSERT INTO token_usage (phase_id, iteration_number, input_tokens, output_tokens, model)
                   VALUES (?, ?, ?, ?, ?)""",
                (phase_id, iteration, input_tokens, output_tokens, model)
            )
            await db.commit()
    
    # Statistics queries
    
    async def get_overall_stats(self) -> dict:
        """Get overall statistics."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            
            # Phase counts
            cursor = await db.execute("SELECT COUNT(*) as total FROM phases")
            total_phases = (await cursor.fetchone())["total"]
            
            cursor = await db.execute("SELECT COUNT(*) as completed FROM phases WHERE status = 'completed'")
            completed_phases = (await cursor.fetchone())["completed"]
            
            cursor = await db.execute("SELECT COUNT(*) as failed FROM phases WHERE status = 'failed'")
            failed_phases = (await cursor.fetchone())["failed"]
            
            # Iteration counts
            cursor = await db.execute("SELECT COUNT(*) as total FROM iterations")
            total_iterations = (await cursor.fetchone())["total"]
            
            # Error counts
            cursor = await db.execute("SELECT COUNT(*) as total FROM build_errors")
            total_build_errors = (await cursor.fetchone())["total"]
            
            cursor = await db.execute("SELECT COUNT(*) as total FROM test_failures")
            total_test_failures = (await cursor.fetchone())["total"]
            
            # Rate limits
            cursor = await db.execute("SELECT COUNT(*) as total FROM rate_limits")
            total_rate_limits = (await cursor.fetchone())["total"]
            
            # Total duration
            cursor = await db.execute("SELECT SUM(total_duration_seconds) as total FROM phases")
            row = await cursor.fetchone()
            total_duration = row["total"] if row["total"] else 0
            
            # Token usage
            cursor = await db.execute(
                "SELECT SUM(input_tokens) as input, SUM(output_tokens) as output FROM token_usage"
            )
            row = await cursor.fetchone()
            total_input_tokens = row["input"] if row["input"] else 0
            total_output_tokens = row["output"] if row["output"] else 0
            
            return {
                "total_phases": total_phases,
                "completed_phases": completed_phases,
                "failed_phases": failed_phases,
                "completion_percentage": (completed_phases / total_phases * 100) if total_phases > 0 else 0,
                "total_iterations": total_iterations,
                "avg_iterations_per_phase": total_iterations / completed_phases if completed_phases > 0 else 0,
                "total_build_errors": total_build_errors,
                "total_test_failures": total_test_failures,
                "total_rate_limits": total_rate_limits,
                "total_duration_seconds": total_duration,
                "total_duration_minutes": total_duration / 60,
                "total_input_tokens": total_input_tokens,
                "total_output_tokens": total_output_tokens
            }
    
    async def get_phase_stats(self, phase_id: str) -> dict:
        """Get statistics for a specific phase."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            
            cursor = await db.execute("SELECT * FROM phases WHERE id = ?", (phase_id,))
            phase = await cursor.fetchone()
            
            if not phase:
                return {}
            
            cursor = await db.execute(
                "SELECT COUNT(*) as count FROM build_errors WHERE phase_id = ?", (phase_id,)
            )
            build_errors = (await cursor.fetchone())["count"]
            
            cursor = await db.execute(
                "SELECT COUNT(*) as count FROM test_failures WHERE phase_id = ?", (phase_id,)
            )
            test_failures = (await cursor.fetchone())["count"]
            
            return {
                "id": phase["id"],
                "name": phase["name"],
                "status": phase["status"],
                "iterations": phase["total_iterations"],
                "duration_seconds": phase["total_duration_seconds"],
                "build_errors": build_errors,
                "test_failures": test_failures
            }
    
    async def get_phase_history(self) -> list[dict]:
        """Get history of all phases."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            
            cursor = await db.execute(
                """SELECT p.*, 
                          (SELECT COUNT(*) FROM build_errors WHERE phase_id = p.id) as build_errors,
                          (SELECT COUNT(*) FROM test_failures WHERE phase_id = p.id) as test_failures
                   FROM phases p
                   ORDER BY p.started_at"""
            )
            rows = await cursor.fetchall()
            
            return [dict(row) for row in rows]
    
    async def get_timeline(self) -> list[dict]:
        """Get timeline of events."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            
            events = []
            
            # Phase events
            cursor = await db.execute(
                """SELECT 'phase_start' as type, id as phase_id, name, started_at as timestamp
                   FROM phases WHERE started_at IS NOT NULL
                   UNION ALL
                   SELECT 'phase_complete' as type, id as phase_id, name, completed_at as timestamp
                   FROM phases WHERE status = 'completed' AND completed_at IS NOT NULL
                   UNION ALL
                   SELECT 'phase_failed' as type, id as phase_id, name, completed_at as timestamp
                   FROM phases WHERE status = 'failed' AND completed_at IS NOT NULL
                   ORDER BY timestamp"""
            )
            
            rows = await cursor.fetchall()
            events.extend([dict(row) for row in rows])
            
            return events
    
    async def export_to_json(self, output_path: Path):
        """Export all analytics to JSON."""
        data = {
            "exported_at": datetime.now().isoformat(),
            "overall": await self.get_overall_stats(),
            "phases": await self.get_phase_history(),
            "timeline": await self.get_timeline()
        }
        
        with open(output_path, "w") as f:
            json.dump(data, f, indent=2)
        
        self.logger.debug(f"Analytics exported to {output_path}")

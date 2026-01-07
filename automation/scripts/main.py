"""
Main CLI entry point for the automation system.
"""

import asyncio
import sys
from pathlib import Path

import click
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

# Add scripts directory to path
sys.path.insert(0, str(Path(__file__).parent))

from orchestrator import Orchestrator
from state_manager import StateManager
from analytics_collector import AnalyticsCollector
from utils import load_yaml, format_duration


console = Console()


@click.group()
@click.option('--config', '-c', default='config/config.yaml', help='Path to config file')
@click.pass_context
def cli(ctx, config):
    """SignLanguageTranslate Automation System"""
    ctx.ensure_object(dict)
    ctx.obj['config_path'] = Path(config)


@cli.command()
@click.pass_context
def setup(ctx):
    """Validate setup and show configuration."""
    config_path = ctx.obj['config_path']
    
    console.print(Panel.fit("🔧 Setup Validation", style="bold blue"))
    
    # Check config exists
    if not config_path.exists():
        console.print(f"[red]✗ Config file not found: {config_path}[/red]")
        console.print("  Run: cp config/config.example.yaml config/config.yaml")
        return
    
    console.print(f"[green]✓ Config file found[/green]")
    
    # Load and validate config
    try:
        config = load_yaml(config_path)
        console.print("[green]✓ Config is valid YAML[/green]")
    except Exception as e:
        console.print(f"[red]✗ Config parse error: {e}[/red]")
        return
    
    # Check project path
    project_path = Path(config["project"]["path"])
    if project_path.exists():
        console.print(f"[green]✓ Project found: {project_path}[/green]")
    else:
        console.print(f"[yellow]⚠ Project not found: {project_path}[/yellow]")
    
    # Check phases directory
    phases_dir = Path("phases")
    if phases_dir.exists():
        phase_files = list(phases_dir.rglob("*.md"))
        console.print(f"[green]✓ Phases directory found ({len(phase_files)} prompt files)[/green]")
    else:
        console.print("[yellow]⚠ Phases directory not found[/yellow]")
    
    # Check Claude availability
    async def check_claude():
        from claude_client import ClaudeClient
        client = ClaudeClient(config)
        return await client.check_available()
    
    if asyncio.run(check_claude()):
        console.print("[green]✓ Claude available[/green]")
    else:
        console.print("[yellow]⚠ Claude not available (check CLI or API key)[/yellow]")
    
    console.print()
    console.print("[bold]Configuration Summary:[/bold]")
    console.print(f"  Model: {config.get('claude', {}).get('model', 'unknown')}")
    console.print(f"  Simulator: {config.get('simulator', {}).get('name', 'unknown')}")
    console.print(f"  Auto-commit: {config.get('git', {}).get('auto_commit', False)}")
    console.print(f"  Screenshots: {config.get('automation', {}).get('capture_screenshots', False)}")


@cli.command()
@click.option('--fresh', is_flag=True, help='Start fresh, ignore saved state')
@click.pass_context
def start(ctx, fresh):
    """Start or resume automation."""
    config_path = ctx.obj['config_path']
    
    async def run():
        orchestrator = Orchestrator(config_path)
        
        try:
            success = await orchestrator.run_all(resume=not fresh)
            return 0 if success else 1
        except KeyboardInterrupt:
            console.print("\n[yellow]Execution paused. Use 'resume' to continue.[/yellow]")
            return 130
    
    sys.exit(asyncio.run(run()))


@cli.command()
@click.pass_context
def resume(ctx):
    """Resume from saved state."""
    config_path = ctx.obj['config_path']
    
    async def run():
        orchestrator = Orchestrator(config_path)
        
        try:
            success = await orchestrator.run_all(resume=True)
            return 0 if success else 1
        except KeyboardInterrupt:
            console.print("\n[yellow]Execution paused. Use 'resume' to continue.[/yellow]")
            return 130
    
    sys.exit(asyncio.run(run()))


@cli.command('run-phase')
@click.argument('phase_id')
@click.pass_context
def run_phase(ctx, phase_id):
    """Run a specific phase."""
    config_path = ctx.obj['config_path']
    
    async def run():
        orchestrator = Orchestrator(config_path)
        await orchestrator.initialize()
        
        result = await orchestrator.run_phase(phase_id)
        
        if result.success:
            console.print(f"[green]✓ Phase {phase_id} completed[/green]")
            return 0
        else:
            console.print(f"[red]✗ Phase {phase_id} failed: {result.error_message}[/red]")
            return 1
    
    sys.exit(asyncio.run(run()))


@cli.command()
@click.pass_context
def status(ctx):
    """Show current execution status."""
    config_path = ctx.obj['config_path']
    
    async def show_status():
        orchestrator = Orchestrator(config_path)
        await orchestrator.initialize()
        
        status = await orchestrator.get_status()
        state = status['state']
        stats = status['stats']
        resume_info = status['resume_info']
        
        # Status panel
        status_color = {
            'not_started': 'dim',
            'running': 'blue',
            'paused': 'yellow',
            'rate_limited': 'yellow',
            'failed': 'red',
            'complete': 'green'
        }.get(state['status'], 'white')
        
        console.print(Panel.fit(
            f"[{status_color}]{state['status'].upper()}[/{status_color}]",
            title="Current Status"
        ))
        
        # Current phase
        if state['current_phase']:
            console.print(f"\n[bold]Current Phase:[/bold] {state['current_phase']}")
            console.print(f"[bold]Current Step:[/bold] {state['current_step']}")
            console.print(f"[bold]Iteration:[/bold] {state['iteration']}")
        
        # Progress
        console.print(f"\n[bold]Progress:[/bold]")
        completed = len(state['completed_phases'])
        total = stats.get('total_phases', 0) or len(state['completed_phases']) + len(state['failed_phases']) + (1 if state['current_phase'] else 0)
        console.print(f"  Completed: {completed}/{total} phases")
        
        # Statistics table
        table = Table(title="\nStatistics")
        table.add_column("Metric", style="cyan")
        table.add_column("Value", justify="right")
        
        table.add_row("Total Iterations", str(stats.get('total_iterations', 0)))
        table.add_row("Build Errors Fixed", str(stats.get('total_build_errors', 0)))
        table.add_row("Test Failures Fixed", str(stats.get('total_test_failures', 0)))
        table.add_row("Rate Limits Hit", str(stats.get('total_rate_limits', 0)))
        table.add_row("Total Duration", format_duration(stats.get('total_duration_seconds', 0)))
        
        console.print(table)
        
        # Resume info
        if resume_info['can_resume']:
            console.print(f"\n[green]Can resume from phase {resume_info['current_phase']}[/green]")
    
    asyncio.run(show_status())


@cli.command()
@click.confirmation_option(prompt='Are you sure you want to reset all state?')
@click.pass_context
def reset(ctx):
    """Reset all state and start fresh."""
    async def do_reset():
        state_manager = StateManager(Path("state"))
        await state_manager.reset_state()
        console.print("[green]State reset successfully[/green]")
    
    asyncio.run(do_reset())


@cli.command()
@click.pass_context
def dashboard(ctx):
    """Regenerate dashboard data."""
    config_path = ctx.obj['config_path']
    
    async def regenerate():
        config = load_yaml(config_path)
        analytics = AnalyticsCollector(config.get("analytics", {}).get("database_path", "state/analytics.db"))
        await analytics.initialize_db()
        
        from dashboard_generator import DashboardGenerator
        from state_manager import StateManager
        
        dashboard = DashboardGenerator(config, analytics)
        state_manager = StateManager(Path("state"))
        state = await state_manager.get_state()
        
        await dashboard.update_all(state)
        
        console.print("[green]Dashboard regenerated[/green]")
    
    asyncio.run(regenerate())


@cli.command('list-phases')
@click.pass_context
def list_phases(ctx):
    """List all phases with their status."""
    config_path = ctx.obj['config_path']
    
    async def show_phases():
        orchestrator = Orchestrator(config_path)
        await orchestrator.initialize()
        
        state = await orchestrator.state_manager.get_state()
        
        table = Table(title="Phases")
        table.add_column("ID", style="cyan")
        table.add_column("Name")
        table.add_column("Status", justify="center")
        table.add_column("Tests", justify="center")
        table.add_column("Screenshot", justify="center")
        
        for module in orchestrator.modules:
            table.add_row(f"[bold]{module.id}[/bold]", f"[bold]{module.name}[/bold]", "", "", "")
            
            for phase in module.phases:
                if phase.id in state.completed_phases:
                    status = "[green]✓ Done[/green]"
                elif phase.id in state.failed_phases:
                    status = "[red]✗ Failed[/red]"
                elif phase.id == state.current_phase:
                    status = "[blue]→ Running[/blue]"
                else:
                    status = "[dim]Pending[/dim]"
                
                tests = "✓" if phase.tests_required else "-"
                screenshot = "📸" if phase.screenshot else "-"
                
                table.add_row(f"  {phase.id}", phase.name, status, tests, screenshot)
        
        console.print(table)
    
    asyncio.run(show_phases())


@cli.command()
@click.argument('output', default='analytics_export.json')
@click.pass_context
def export(ctx, output):
    """Export analytics to JSON file."""
    async def do_export():
        analytics = AnalyticsCollector("state/analytics.db")
        await analytics.initialize_db()
        await analytics.export_to_json(Path(output))
        console.print(f"[green]Analytics exported to {output}[/green]")
    
    asyncio.run(do_export())


if __name__ == '__main__':
    cli()

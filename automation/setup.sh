#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

print_header "SignLanguageTranslate Automation Setup"

# Check required tools
print_header "Checking Required Tools"

MISSING_TOOLS=0

check_command "python3" || MISSING_TOOLS=1
check_command "pip3" || MISSING_TOOLS=1
check_command "git" || MISSING_TOOLS=1

# Check for Xcode tools (optional on non-Mac)
if [[ "$OSTYPE" == "darwin"* ]]; then
    check_command "xcodebuild" || print_warning "Xcode not found (needed for building)"
    check_command "xcrun" || print_warning "xcrun not found (needed for simulator)"
fi

# Check for Claude CLI
if command -v "claude" &> /dev/null; then
    print_success "Claude CLI is installed"
else
    print_warning "Claude CLI not found - will use API mode if configured"
fi

# Check Python version
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
REQUIRED_VERSION="3.11"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
    print_success "Python version $PYTHON_VERSION >= $REQUIRED_VERSION"
else
    print_error "Python version $PYTHON_VERSION < $REQUIRED_VERSION required"
    MISSING_TOOLS=1
fi

if [ $MISSING_TOOLS -eq 1 ]; then
    print_error "Please install missing tools and run setup again"
    exit 1
fi

# Check Xcode (Mac only)
if [[ "$OSTYPE" == "darwin"* ]]; then
    print_header "Checking Xcode Configuration"
    
    XCODE_PATH=$(xcode-select -p 2>/dev/null || echo "")
    if [ -n "$XCODE_PATH" ]; then
        print_success "Xcode path: $XCODE_PATH"
    else
        print_warning "Xcode command line tools not configured"
        echo "Run: xcode-select --install"
    fi
    
    # Check for iPad Pro (11-inch) (3rd generation) simulator
    print_header "Checking Simulator Availability"
    
    SIMULATOR_NAME="iPad Pro (11-inch) (3rd generation)"
    SIMULATOR_UDID=$(xcrun simctl list devices available 2>/dev/null | grep "$SIMULATOR_NAME" | head -1 | grep -oE '[0-9A-F-]{36}' || echo "")
    
    if [ -n "$SIMULATOR_UDID" ]; then
        print_success "Found simulator: $SIMULATOR_NAME"
        echo "  UDID: $SIMULATOR_UDID"
    else
        print_warning "Simulator '$SIMULATOR_NAME' not found"
        echo "Available iPad simulators:"
        xcrun simctl list devices available 2>/dev/null | grep -i "ipad" | head -10 || echo "  None found"
        echo ""
        echo "You may need to:"
        echo "1. Open Xcode → Settings → Platforms"
        echo "2. Download iOS 17.x simulator runtime"
        echo "3. Or update config.yaml with an available simulator"
    fi
fi

# Create Python virtual environment
print_header "Setting Up Python Environment"

if [ -d "venv" ]; then
    print_warning "Virtual environment already exists"
    read -p "Recreate? (y/N): " RECREATE
    if [ "$RECREATE" = "y" ] || [ "$RECREATE" = "Y" ]; then
        rm -rf venv
        python3 -m venv venv
        print_success "Virtual environment recreated"
    fi
else
    python3 -m venv venv
    print_success "Virtual environment created"
fi

# Activate and install dependencies
source venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1

print_success "Installing Python dependencies..."
pip install -r requirements.txt > /dev/null 2>&1
print_success "Dependencies installed"

# Initialize SQLite database
print_header "Initializing Database"

PYTHONPATH="$SCRIPT_DIR" python3 << 'EOF'
import asyncio
from scripts.analytics_collector import AnalyticsCollector

async def init():
    collector = AnalyticsCollector('state/analytics.db')
    await collector.initialize_db()
    print('Database initialized successfully')

asyncio.run(init())
EOF
print_success "Analytics database initialized"

# Create config from example if not exists
print_header "Checking Configuration"

if [ -f "config/config.yaml" ]; then
    print_success "config.yaml exists"
else
    if [ -f "config/config.example.yaml" ]; then
        cp config/config.example.yaml config/config.yaml
        print_success "Created config.yaml from example"
        print_warning "Please review and update config/config.yaml"
    else
        print_error "config.example.yaml not found"
    fi
fi

# Check for Anthropic API key (if using API mode)
print_header "Checking API Configuration"

if [ -n "$ANTHROPIC_API_KEY" ]; then
    print_success "ANTHROPIC_API_KEY is set"
else
    print_warning "ANTHROPIC_API_KEY not set in environment"
    echo "If using API mode, set it with:"
    echo "  export ANTHROPIC_API_KEY='your-key-here'"
fi

# Check Xcode project exists
print_header "Checking Project"

PROJECT_PATH="../SignLanguageTranslate.xcodeproj"
if [ -d "$PROJECT_PATH" ]; then
    print_success "Xcode project found"
else
    print_warning "Xcode project not found at $PROJECT_PATH"
    echo "Make sure the project exists or update config.yaml"
fi

# Create necessary directories
print_header "Creating Directories"

mkdir -p state logs screenshots dashboard/data dashboard/screenshots phases/module1 phases/module2
print_success "Directories created"

# Create .gitignore files
cat > state/.gitignore << 'EOF'
current_state.json
history.json
analytics.db
analytics.db-journal
EOF
print_success "State .gitignore created"

cat > logs/.gitignore << 'EOF'
*.log
EOF
print_success "Logs .gitignore created"

cat > screenshots/.gitignore << 'EOF'
*.png
!.gitkeep
EOF
print_success "Screenshots .gitignore created"

# Create .gitkeep files
touch state/.gitkeep logs/.gitkeep screenshots/.gitkeep dashboard/screenshots/.gitkeep
touch phases/module1/.gitkeep phases/module2/.gitkeep

# Generate initial dashboard data
print_header "Initializing Dashboard"

python3 << 'EOF'
import json
from datetime import datetime
from pathlib import Path

data_dir = Path('dashboard/data')
data_dir.mkdir(parents=True, exist_ok=True)

# Initial status
status = {
    "last_updated": datetime.now().isoformat(),
    "current_phase": None,
    "current_step": None,
    "status": "NOT_STARTED",
    "overall_progress": {
        "total_phases": 0,
        "completed_phases": 0,
        "failed_phases": 0,
        "percentage": 0
    },
    "statistics": {
        "total_iterations": 0,
        "total_build_errors": 0,
        "total_test_failures": 0,
        "total_rate_limits": 0,
        "total_duration_minutes": 0
    }
}

with open(data_dir / 'status.json', 'w') as f:
    json.dump(status, f, indent=2)

with open(data_dir / 'history.json', 'w') as f:
    json.dump({"phases": []}, f, indent=2)

with open(data_dir / 'analytics.json', 'w') as f:
    json.dump({"modules": [], "timeline": []}, f, indent=2)

with open(data_dir / 'screenshots.json', 'w') as f:
    json.dump({"screenshots": []}, f, indent=2)

print('Dashboard data initialized')
EOF
print_success "Dashboard data files created"

# Summary
print_header "Setup Complete!"

echo -e "Next steps:"
echo -e "  1. Review ${YELLOW}config/config.yaml${NC}"
echo -e "  2. Add phase prompts to ${YELLOW}phases/${NC} directory"
echo -e "  3. Activate virtual environment: ${GREEN}source automation/venv/bin/activate${NC}"
echo -e "  4. Run automation: ${GREEN}python scripts/main.py start${NC}"
echo ""
echo -e "Other commands:"
echo -e "  ${BLUE}python scripts/main.py status${NC}     - Check current status"
echo -e "  ${BLUE}python scripts/main.py resume${NC}     - Resume from saved state"
echo -e "  ${BLUE}python scripts/main.py list-phases${NC} - List all phases"
echo -e "  ${BLUE}python scripts/main.py dashboard${NC}  - Regenerate dashboard"
echo ""

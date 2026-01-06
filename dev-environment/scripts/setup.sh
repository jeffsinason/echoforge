#!/bin/bash
#
# EchoForge Development Environment - Initial Setup
# Run this ONCE before using start-all.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(dirname "$SCRIPT_DIR")"
ECHOFORGE_ROOT="$(dirname "$DEV_ENV_DIR")"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     EchoForge Development Environment - Initial Setup       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1,2)
echo -e "\n${YELLOW}[1/5] Checking Python version...${NC}"
echo -e "      Found Python ${PYTHON_VERSION}"

# Minimum Python 3.10
if [[ "$(echo "$PYTHON_VERSION < 3.10" | bc)" -eq 1 ]]; then
    echo -e "      ${RED}Error: Python 3.10+ required${NC}"
    exit 1
fi
echo -e "      ${GREEN}✓ Python version OK${NC}"

# =============================================================================
# Create .env if not exists
# =============================================================================
echo -e "\n${YELLOW}[2/5] Checking environment configuration...${NC}"

if [ ! -f "$DEV_ENV_DIR/.env" ]; then
    if [ -f "$DEV_ENV_DIR/.env.example" ]; then
        cp "$DEV_ENV_DIR/.env.example" "$DEV_ENV_DIR/.env"
        echo -e "      ${GREEN}✓ Created .env from .env.example${NC}"
        echo -e "      ${YELLOW}! Remember to add your ANTHROPIC_API_KEY to .env${NC}"
    else
        echo -e "      ${RED}Error: No .env.example found${NC}"
        exit 1
    fi
else
    echo -e "      ${GREEN}✓ .env already exists${NC}"
fi

# =============================================================================
# Setup Hub virtual environment
# =============================================================================
echo -e "\n${YELLOW}[3/5] Setting up Hub virtual environment...${NC}"

HUB_DIR="$ECHOFORGE_ROOT/hub/backend"
HUB_VENV="$HUB_DIR/.venv"

if [ -d "$HUB_VENV" ]; then
    echo -e "      ${GREEN}✓ Hub venv already exists${NC}"
else
    echo -n "      Creating venv..."
    python3 -m venv "$HUB_VENV"
    echo -e " ${GREEN}done${NC}"
fi

echo -n "      Installing dependencies..."
source "$HUB_VENV/bin/activate"
pip install --upgrade pip > /dev/null 2>&1
pip install -r "$HUB_DIR/requirements/development.txt" > /dev/null 2>&1
deactivate
echo -e " ${GREEN}done${NC}"

echo -e "      ${GREEN}✓ Hub environment ready${NC}"

# =============================================================================
# Setup Agent virtual environment
# =============================================================================
echo -e "\n${YELLOW}[4/5] Setting up Agent virtual environment...${NC}"

AGENT_DIR="$ECHOFORGE_ROOT/agent"
AGENT_VENV="$AGENT_DIR/.venv"

if [ -d "$AGENT_VENV" ]; then
    echo -e "      ${GREEN}✓ Agent venv already exists${NC}"
else
    echo -n "      Creating venv..."
    python3 -m venv "$AGENT_VENV"
    echo -e " ${GREEN}done${NC}"
fi

echo -n "      Installing dependencies..."
source "$AGENT_VENV/bin/activate"
pip install --upgrade pip > /dev/null 2>&1
pip install -r "$AGENT_DIR/requirements/development.txt" > /dev/null 2>&1
deactivate
echo -e " ${GREEN}done${NC}"

echo -e "      ${GREEN}✓ Agent environment ready${NC}"

# =============================================================================
# Install org-level tool dependencies
# =============================================================================
echo -e "\n${YELLOW}[5/5] Setting up organization tools...${NC}"

ORG_ROOT="$(dirname "$ECHOFORGE_ROOT")"
TOOLS_DIR="$ORG_ROOT/tools"

if [ -d "$TOOLS_DIR" ]; then
    TOOLS_VENV="$TOOLS_DIR/.venv"

    if [ -d "$TOOLS_VENV" ]; then
        echo -e "      ${GREEN}✓ Tools venv already exists${NC}"
    else
        echo -n "      Creating tools venv..."
        python3 -m venv "$TOOLS_VENV"
        echo -e " ${GREEN}done${NC}"
    fi

    echo -n "      Installing tool dependencies..."
    source "$TOOLS_VENV/bin/activate"
    pip install --upgrade pip > /dev/null 2>&1
    pip install PyYAML > /dev/null 2>&1
    deactivate
    echo -e " ${GREEN}done${NC}"

    echo -e "      ${GREEN}✓ Organization tools ready${NC}"
else
    echo -e "      ${YELLOW}! Organization tools directory not found (optional)${NC}"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    ${GREEN}Setup Complete!${BLUE}                          ║${NC}"
echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  Virtual environments created:                               ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    ${GREEN}✓${NC} hub/backend/.venv                                       ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    ${GREEN}✓${NC} agent/.venv                                             ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${YELLOW}Next steps:${NC}                                                 ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    1. Edit .env and add your ANTHROPIC_API_KEY              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}    2. Run: ./scripts/start-all.sh                           ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

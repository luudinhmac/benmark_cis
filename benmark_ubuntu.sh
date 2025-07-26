#!/bin/bash
set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # reset color

log() {
    echo -e "${GREEN}[+]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error_exit() {
    echo -e "${RED}[x] $1${NC}" >&2
    exit 1
}

usage() {
    cat << EOF
Usage: $0 <ubuntu_version>

Examples:
  $0 ubuntu2404
  $0 ubuntu2204

Supported versions:
  ubuntu2404
  ubuntu2204

EOF
    exit 1
}

if [ $# -ne 1 ]; then
    echo "Error: Missing required argument."
    usage
fi

UBUNTU_VER="$1"

case "$UBUNTU_VER" in
    ubuntu2404|ubuntu2204)
        log "Running CIS benchmark for $UBUNTU_VER..."
        ;;
    *)
        echo "Error: Unsupported version '$UBUNTU_VER'."
        usage
        ;;
esac

log "Updating system and installing required packages..."
sudo apt update
sudo apt install -y \
  cmake make gcc g++ python3 python3-pip python3-venv \
  libxml2-utils libxslt1-dev libopenscap-dev openscap-common libopenscap25t64 \
  openscap-utils git xsltproc

log "Checking oscap executable..."
if ! command -v oscap >/dev/null 2>&1; then
  error_exit "oscap command not found. Please check openscap-utils installation."
fi

export OPENSCAP_ROOT_DIR=$(dirname $(dirname $(which oscap)))
log "OPENSCAP_ROOT_DIR set to $OPENSCAP_ROOT_DIR"

log "Setting up Python virtual environment..."
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate

log "Upgrading pip and setuptools to avoid pkg_resources warnings..."
pip install --upgrade pip
pip install "setuptools<81" wheel

log "Installing required Python packages..."
pip install cmakelint pygithub json2html mypy openpyxl pandas \
    pcre2 pytest pytest-cov myst-parser sphinx sphinx_rtd_theme \
    prometheus-client trestle

if [ ! -d "content" ]; then
  log "Cloning ComplianceAsCode/content repository..."
  git clone https://github.com/ComplianceAsCode/content.git
fi
cd content

PATCH_LINE='warnings.filterwarnings("ignore", category=UserWarning, module="pkg_resources")'
TARGET_FILE="ssg/requirement_specs.py"
if ! grep -Fxq "$PATCH_LINE" "$TARGET_FILE"; then
  log "Patching to suppress pkg_resources warnings..."
  sed -i '1i\
import warnings\nwarnings.filterwarnings("ignore", category=UserWarning, module="pkg_resources")' "$TARGET_FILE"
fi

log "Creating build directory..."
mkdir -p build
cd build

log "Running CMake for $UBUNTU_VER..."
cmake -DSSG_TARGET_UBUNTU=$UBUNTU_VER .. || error_exit "CMake failed."

log "Building SCAP content..."
make -j"$(nproc)" || error_exit "Build failed."

if [ ! -f "ssg-${UBUNTU_VER}-ds.xml" ]; then
    error_exit "Datastream file ssg-${UBUNTU_VER}-ds.xml not found. Build may have failed."
fi

log "Running system evaluation using CIS Level 1 (server) profile..."
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
  --results results-${UBUNTU_VER}.xml \
  --report report-${UBUNTU_VER}.html \
  ./ssg-${UBUNTU_VER}-ds.xml

log "Evaluation completed. Report: $(realpath report-${UBUNTU_VER}.html)"

read -p "$(echo -e ${YELLOW}Do you want to automatically remediate issues? [y/N]: ${NC})" fix_choice
if [[ "$fix_choice" =~ ^[Yy]$ ]]; then
    log "Running remediation..."
    sudo oscap xccdf eval \
      --remediate \
      --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
      --results results-${UBUNTU_VER}-fix.xml \
      --report report-${UBUNTU_VER}-fix.html \
      ./ssg-${UBUNTU_VER}-ds.xml
    log "Remediation completed. Report: $(realpath report-${UBUNTU_VER}-fix.html)"
fi

DEST="$HOME/report-${UBUNTU_VER}.html"
cp "$(realpath report-${UBUNTU_VER}.html)" "$DEST"
log "Report copied to: $DEST"


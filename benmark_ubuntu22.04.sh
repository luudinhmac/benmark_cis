#!/bin/bash
set -e

echo "[+] Update and install package..."
sudo apt update
sudo apt install -y \
  cmake make gcc g++ python3 python3-pip python3-venv python3-setuptools \
  libxml2-utils libxslt1-dev libopenscap-dev openscap-common libopenscap25t64 \
  git xsltproc

echo "[+] Check pkg_resources (setuptools)..."
python3 -c "import pkg_resources" || { echo "Error: pkg_resources not esxits"; exit 1; }

echo "[+] Create virtual environment for Python (venv)..."
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
source venv/bin/activate

echo "[+] Upgrade pip and setuptools in venv..."
pip install --upgrade pip setuptools wheel

echo "[+] Install packge Python requirement in venv..."
pip install cmakelint pygithub json2html mypy openpyxl pandas \
    pcre2 pytest pytest-cov myst-parser sphinx sphinx_rtd_theme \
    prometheus-client trestle

echo "[+] Clone repo ComplianceAsCode content if not found..."
if [ ! -d "content" ]; then
  git clone https://github.com/ComplianceAsCode/content.git
fi
cd content

echo "[+] Create build foler..."
if [ ! -d "build" ]; then
  mkdir build
fi
cd build

echo "[+] Run cmake for Ubuntu 22.04 ..."
cmake -DSSG_TARGET_UBUNTU=ubuntu2204 ..

echo "[+] Biên dịch nội dung..."
make -j"$(nproc)"

echo "[+] Run Benmark CIS..."
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
  --results results-ubuntu2204.xml \
  --report report-ubuntu2204.html \
  ./ssg-ubuntu2204-ds.xml

echo "[+] Complete."

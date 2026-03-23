#!/bin/bash
# wayback + link finder + live check script
# Usage: ./wayback.sh domain.com

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Validate input ---
if [ -z "$1" ]; then
    echo -e "${RED}[!] Usage: $0 <domain>${NC}"
    echo -e "    Example: $0 domain.com"
    exit 1
fi

DOMAIN=$1
WAYMORE_DIR=~/.config/waymore/results/${DOMAIN}

# --- Tool check functions ---
check_go_tool() {
    local cmd=$1
    local install_path=$2
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${YELLOW}[~] $cmd not found. Installing...${NC}"
        go install "$install_path" 2>&1
        export PATH=$PATH:$(go env GOPATH)/bin
        if command -v "$cmd" &>/dev/null; then
            echo -e "${GREEN}[+] $cmd installed successfully.${NC}"
        else
            echo -e "${RED}[!] Failed to install $cmd. Check Go setup.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}[✓] $cmd is installed.${NC}"
    fi
}

check_python_tool() {
    local cmd=$1
    local pip_name=$2
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${YELLOW}[~] $cmd not found. Installing via pip...${NC}"
        pip install "$pip_name" --quiet
        if command -v "$cmd" &>/dev/null; then
            echo -e "${GREEN}[+] $cmd installed successfully.${NC}"
        else
            echo -e "${RED}[!] Failed to install $cmd. Check Python/pip setup.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}[✓] $cmd is installed.${NC}"
    fi
}

setup_gf_patterns() {
    local GF_DIR=~/.gf
    mkdir -p "$GF_DIR"

    PATTERN_COUNT=$(find "$GF_DIR" -name "*.json" 2>/dev/null | wc -l)

    if [ "$PATTERN_COUNT" -lt 5 ]; then
        echo -e "${YELLOW}[~] gf patterns not found or incomplete. Installing...${NC}"

        if ! command -v git &>/dev/null; then
            echo -e "${RED}[!] git is required to install gf patterns. Please install git.${NC}"
            return 1
        fi

        TMP_DIR=$(mktemp -d)

        echo -e "${YELLOW}    [~] Fetching tomnomnom/gf default patterns...${NC}"
        git clone --quiet https://github.com/tomnomnom/gf "$TMP_DIR/gf" 2>/dev/null
        if [ -d "$TMP_DIR/gf/examples" ]; then
            cp "$TMP_DIR/gf/examples/"*.json "$GF_DIR/" 2>/dev/null
            echo -e "${GREEN}    [+] Default patterns installed.${NC}"
        else
            echo -e "${RED}    [!] Failed to clone tomnomnom/gf.${NC}"
        fi

        echo -e "${YELLOW}    [~] Fetching 1ndianl33t/Gf-Patterns extended set...${NC}"
        git clone --quiet https://github.com/1ndianl33t/Gf-Patterns "$TMP_DIR/gf-patterns" 2>/dev/null
        if [ -d "$TMP_DIR/gf-patterns" ]; then
            cp "$TMP_DIR/gf-patterns/"*.json "$GF_DIR/" 2>/dev/null
            echo -e "${GREEN}    [+] Extended patterns installed.${NC}"
        else
            echo -e "${RED}    [!] Failed to clone 1ndianl33t/Gf-Patterns.${NC}"
        fi

        rm -rf "$TMP_DIR"

        PATTERN_COUNT=$(find "$GF_DIR" -name "*.json" | wc -l)
        echo -e "${GREEN}[+] gf setup complete. ${PATTERN_COUNT} patterns available in ~/.gf/${NC}"
    else
        echo -e "${GREEN}[✓] gf patterns already installed (${PATTERN_COUNT} patterns in ~/.gf/).${NC}"
    fi
}

# --- Check Go is available ---
if ! command -v go &>/dev/null; then
    echo -e "${RED}[!] Go is not installed. Please install Go: https://go.dev/doc/install${NC}"
    exit 1
fi

# --- Check all tools ---
echo -e "\n[*] Checking required tools...\n"
check_go_tool      "gau"          "github.com/lc/gau/v2/cmd/gau@latest"
check_go_tool      "waybackurls"  "github.com/tomnomnom/waybackurls@latest"
check_go_tool      "gf"           "github.com/tomnomnom/gf@latest"
check_go_tool      "httpx"        "github.com/projectdiscovery/httpx/cmd/httpx@latest"
check_python_tool  "waymore"      "waymore"
check_python_tool  "xnLinkFinder" "xnLinkFinder"
setup_gf_patterns

echo -e "\n[*] Starting recon for: ${DOMAIN}\n"

# --- gau ---
echo -e "${GREEN}[+] Running gau...${NC}"
echo "$DOMAIN" | gau --subs --o "${DOMAIN}_gau_wayback_output.txt"

# --- waybackurls ---
echo -e "${GREEN}[+] Running waybackurls...${NC}"
echo "$DOMAIN" | waybackurls > "${DOMAIN}_waybackurls_wayback_output.txt"

# --- waymore ---
echo -e "${GREEN}[+] Running waymore...${NC}"
waymore -i "$DOMAIN" -mode U
if [ -f "${WAYMORE_DIR}/waymore.txt" ]; then
    cp "${WAYMORE_DIR}/waymore.txt" "${DOMAIN}_waymore_wayback_output.txt"
else
    echo -e "${YELLOW}[~] waymore output not found at: ${WAYMORE_DIR}/waymore.txt${NC}"
fi

# --- Merge & deduplicate wayback results ---
echo -e "\n[*] Merging wayback results..."
cat *_wayback_output.txt 2>/dev/null | sort -u > "${DOMAIN}_all_wayback_output.txt"
TOTAL=$(wc -l < "${DOMAIN}_all_wayback_output.txt")
echo -e "${GREEN}[+] ${TOTAL} unique URLs saved to: ${DOMAIN}_all_wayback_output.txt${NC}"

# --- xnLinkFinder: crawl merged URL list ---
echo -e "\n${GREEN}[+] Running xnLinkFinder on collected URLs...${NC}"
xnLinkFinder \
    -i "${DOMAIN}_all_wayback_output.txt" \
    -o "${DOMAIN}_endpoints.txt" \
    -op "${DOMAIN}_parameters.txt" \
    -owl "${DOMAIN}_wordlist.txt" \
    -sf "$DOMAIN" \
    -sp "https://${DOMAIN}"

# --- xnLinkFinder: process waymore archived responses ---
if [ -d "$WAYMORE_DIR" ]; then
    echo -e "\n${GREEN}[+] Running xnLinkFinder on waymore archived responses...${NC}"
    xnLinkFinder \
        -i "$WAYMORE_DIR" \
        -o "${DOMAIN}_endpoints.txt" \
        -op "${DOMAIN}_parameters.txt" \
        -owl "${DOMAIN}_wordlist.txt" \
        -sf "$DOMAIN" \
        -sp "https://${DOMAIN}"
fi

# --- Final dedup across endpoints + wayback URLs ---
echo -e "\n[*] Building final deduplicated URL list..."
cat "${DOMAIN}_all_wayback_output.txt" "${DOMAIN}_endpoints.txt" 2>/dev/null \
    | sort -u > "${DOMAIN}_final.txt"
FINAL_TOTAL=$(wc -l < "${DOMAIN}_final.txt")
echo -e "${GREEN}[+] ${FINAL_TOTAL} unique URLs in final list: ${DOMAIN}_final.txt${NC}"

# --- httpx: probe final URL list ---
echo -e "\n${GREEN}[+] Running httpx on final URL list...${NC}"
httpx \
    -l "${DOMAIN}_final.txt" \
    -sc \
    -td \
    -fr \
    -title \
    -silent \
    | tee "${DOMAIN}_wayback_httpx_check.txt"

LIVE_TOTAL=$(wc -l < "${DOMAIN}_wayback_httpx_check.txt" 2>/dev/null || echo 0)
echo -e "${GREEN}[+] ${LIVE_TOTAL} live URLs saved to: ${DOMAIN}_wayback_httpx_check.txt${NC}"

# --- gf pattern matching on live URLs ---
mapfile -t GF_PATTERNS < <(find ~/.gf -name "*.json" 2>/dev/null \
    | xargs -I{} basename {} .json \
    | sort -u)

if [ ${#GF_PATTERNS[@]} -eq 0 ]; then
    echo -e "${RED}[!] No gf patterns found in ~/.gf/ — skipping gf step.${NC}"
else
    if [ -s "${DOMAIN}_wayback_httpx_check.txt" ]; then
        GF_INPUT="${DOMAIN}_wayback_httpx_check.txt"
        echo -e "\n[*] Running ${#GF_PATTERNS[@]} gf patterns on live URLs...\n"
    else
        GF_INPUT="${DOMAIN}_final.txt"
        echo -e "\n${YELLOW}[~] httpx produced no output, falling back to full URL list for gf...${NC}\n"
    fi

    mkdir -p "${DOMAIN}_gf_results"

    for pattern in "${GF_PATTERNS[@]}"; do
        OUTPUT="${DOMAIN}_gf_results/${pattern}.txt"
        MATCHES=$(gf "$pattern" < "$GF_INPUT" 2>/dev/null)
        if [ -n "$MATCHES" ]; then
            echo "$MATCHES" > "$OUTPUT"
            COUNT=$(echo "$MATCHES" | wc -l)
            echo -e "${GREEN}  [+] $pattern → ${COUNT} matches${NC}"
        else
            echo -e "${YELLOW}  [-] $pattern → no matches${NC}"
        fi
    done
fi

# --- Summary ---
echo -e "\n${GREEN}[✓] Done! Output files:${NC}"
echo -e "  ${DOMAIN}_all_wayback_output.txt    → merged wayback URLs"
echo -e "  ${DOMAIN}_endpoints.txt             → discovered endpoints (xnLinkFinder)"
echo -e "  ${DOMAIN}_parameters.txt            → potential parameters"
echo -e "  ${DOMAIN}_wordlist.txt              → target-specific wordlist"
echo -e "  ${DOMAIN}_final.txt                 → final deduplicated URL list"
echo -e "  ${DOMAIN}_wayback_httpx_check.txt   → live URLs with status/title/tech"
echo -e "  ${DOMAIN}_gf_results/               → gf pattern matches\n"

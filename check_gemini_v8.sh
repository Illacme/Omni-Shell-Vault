#!/usr/bin/env bash

# ==============================================================================
# 🛡️ Gemini API Sentinel - Global Edition (v9.1)
# ------------------------------------------------------------------------------
# Usage: Industrial-grade auditing tool for Gemini API connectivity & performance.
# Author: Antigravity AI
# License: MIT
# GitHub: https://github.com/Illacme/Omni-Shell-Vault
# ------------------------------------------------------------------------------
# Features: 
#   - Cross-platform support (macOS/BSD, Linux/GNU, Web-environments)
#   - Multi-protocol routing (Standard, Interaction API, TTS Modality)
#   - Autonomous self-healing (429 backoff with retryDelay parsing)
#   - High-precision benchmarking (Multi-path clock engine)
#   - Future-proof: Easily switch between v1beta, v1, v2beta, etc.
# ------------------------------------------------------------------------------

# Global Safety & Locale Isolation
set -o pipefail
export LC_ALL=C

# --- API Config ---
G_API_VERSION="v1beta" # Easily upgrade to v2 or v2beta here
G_BASE_URL="https://generativelanguage.googleapis.com/${G_API_VERSION}"

# --- Initialization ---
API_KEY=""
PROXY=""
TARGET_MODEL=""
ACTION="test" # test | list | all
VERBOSE=0
RETRY_MAX=1
DELAY=0
D_SEP="_SENTINEL_DATA_"

# Style Matrix (ANSI)
G="\033[32m"; R="\033[31m"; Y="\033[33m"; B="\033[34m"; C="\033[0m"; W="\033[1m"; K="\033[2m"
CHECK="✅"; CROSS="❌"; WATCH="⏳"; TAB="   └── "

# Statistics Registers (Bash 3.2+ Compatible)
declare -a RESULTS_NAME
declare -a RESULTS_STATUS
declare -a RESULTS_LATENCY
declare -a RESULTS_CODE
idx=0

# --- Helper Functions ---

usage() {
    echo -e "${B}${W}Gemini API Sentinel v9.0${C} - Global Edition"
    echo -e "------------------------------------------------"
    echo -e "${W}Usage:${C} $0 -k <API_KEY> [options]"
    echo ""
    echo -e "${Y}${W}Modes / 模式:${C}"
    echo -e "  -k <KEY>  : ${W}API Key${C} (Required / 必填)"
    echo -e "  -l        : ${W}List Mode${C} - List authorized models / 列表模式"
    echo -e "  -a        : ${W}Audit Mode${C} - Benchmarking full matrix / 全量压测"
    echo ""
    echo -e "${Y}${W}Options / 选项:${C}"
    echo -e "  -m <NAME> : ${W}Target Model${C} / 指定模型"
    echo -e "  -p <URL>  : ${W}Proxy URL${C} (e.g. http://127.0.0.1:7890) / 网络代理"
    echo -e "  -d <SEC>  : ${W}Delay${C} between scans (For Free Tier) / 扫描间隔"
    echo -e "  -v        : ${W}Verbose${C} mode / 详细模式"
    echo ""
    echo -e "${K}Example: $0 -k AIzaSy... -a -d 2${C}"
    exit 1
}

# High-Precision Timestamp Engine (Multi-Path Fallback)
get_ts() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(int(time.time() * 1000))'
    elif command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'print int(time * 1000)'
    elif date +%s%3N 2>/dev/null | grep -q "[0-9]\{13\}"; then
        date +%s%3N
    else
        # Fallback to seconds if no ms precision tool found
        echo "$(($(date +%s) * 1000))"
    fi
}

# --- Core Executor (Native Delimiter Protocol) ---
execute_request() {
    local METHOD=$1
    local URL=$2
    local DATA=$3
    local RETRY_COUNT=0
    local INTERNAL_SEP="---G-SENTINEL---"
    
    local USER_AGENT="Mozilla/5.0 (Sentinel/9.0 Global)"
    local CMD="curl -s --connect-timeout 20 -H 'Content-Type: application/json' -A '$USER_AGENT'"
    [ -n "$PROXY" ] && CMD="$CMD -x $PROXY"

    while [ $RETRY_COUNT -le $RETRY_MAX ]; do
        local T_START=$(get_ts)
        local RAW_RESP
        if [ "$METHOD" == "POST" ]; then
            RAW_RESP=$(eval "$CMD -X POST '$URL' -d '$DATA' -w '$INTERNAL_SEP%{http_code}'")
        else
            RAW_RESP=$(eval "$CMD -G '$URL' -w '$INTERNAL_SEP%{http_code}'")
        fi
        local T_END=$(get_ts)
        local LATENCY=$((T_END - T_START))

        local BODY="${RAW_RESP%$INTERNAL_SEP*}"
        local CODE="${RAW_RESP##*$INTERNAL_SEP}"
        CODE=$(echo "$CODE" | tr -d '[:space:]')

        # Advanced Backoff (429 Handling)
        if [[ "$CODE" == "429" ]]; then
            if echo "$BODY" | grep -Ei "PerDay|Daily" >/dev/null; then
                echo -e "\n${R}${CROSS} [Daily Limit] Daily quota exhausted. Skipping retries.${C}" >&2
                CODE="429_DAY"
                break
            fi

            if [ $RETRY_COUNT -lt $RETRY_MAX ]; then
                local WAIT=$(echo "$BODY" | grep -o 'retryDelay": "[0-9]*' | cut -d'"' -f3)
                [ -z "$WAIT" ] && WAIT=$(echo "$BODY" | grep -o 'retry in [0-9.]*' | awk '{print $NF}' | cut -d. -f1)
                [ -z "$WAIT" ] && WAIT=35 
                WAIT=$((WAIT + 2)) # Safety buffer

                echo -e "\n${Y}${WATCH} [Rate Limit] Cooling down for ${WAIT}s...${C}" >&2
                local i=$WAIT
                while [ $i -gt 0 ]; do
                    printf "\r${K}   └── Resuming in ${i}s...${C}" >&2
                    sleep 1; i=$((i-1))
                done
                printf "\r${G}   └── Re-triggering request!          ${C}\n" >&2
                RETRY_COUNT=$((RETRY_COUNT + 1))
                continue
            fi
        fi

        # 503 Service Unavailable Handling
        if [[ "$CODE" == "503" ]] && [ $RETRY_COUNT -lt $RETRY_MAX ]; then
            sleep 3
            RETRY_COUNT=$((RETRY_COUNT + 1))
            continue
        fi

        break
    done

    # Final Payload: Body + D_SEP + Code + D_SEP + Latency
    printf "%s%s%s%s%s" "$BODY" "$D_SEP" "$CODE" "$D_SEP" "$LATENCY"
    return 0
}

# --- Matrix Probe Engine ---
probe() {
    local M=$1
    local CLEAN_M=$(echo "$M" | sed 's/models\///g')
    local ENDPOINT
    local PAYLOAD

    # Routing Intelligence
    if [[ "$CLEAN_M" == *"deep-research"* ]]; then
        ENDPOINT="${G_BASE_URL}/interactions?key=${API_KEY}"
        PAYLOAD="{\"agent\": \"${CLEAN_M}\", \"input\": \"Ping\", \"background\": true}"
    elif [[ "$CLEAN_M" == *"-tts" ]]; then
        ENDPOINT="${G_BASE_URL}/models/${CLEAN_M}:generateContent?key=${API_KEY}"
        # TTS 终极对齐：移除非标准 responseModalities，改用 response_mime_type 结合 speechConfig
        PAYLOAD="{\"contents\": [{\"parts\": [{\"text\": \"Ping\"}]}], \"generationConfig\": {\"response_mime_type\": \"audio/wav\", \"speechConfig\": {\"voiceConfig\": {\"prebuiltVoiceConfig\": {\"voiceName\": \"Aoife\"}}}}}"
    else
        ENDPOINT="${G_BASE_URL}/models/${CLEAN_M}:generateContent?key=${API_KEY}"
        PAYLOAD="{\"contents\": [{\"parts\": [{\"text\": \"Ready? Result: One word.\"}]}]}"
    fi

    printf "${W}${WATCH} Testing [ %-38s ] ... ${C}" "$CLEAN_M"
    
    local RESP_PACK=$(execute_request "POST" "$ENDPOINT" "$PAYLOAD")
    
    # Atomic Slicing (Native Bash Parameter Expansion)
    local BODY="${RESP_PACK%%$D_SEP*}"
    local REMAIN="${RESP_PACK#*$D_SEP}"
    local CODE="${REMAIN%%$D_SEP*}"
    local LATENCY="${REMAIN#*$D_SEP}"

    # Map Status
    local DISPLAY_CODE=$(echo "$CODE" | sed 's/429_DAY/429/')
    RESULTS_NAME[$idx]="$CLEAN_M"
    RESULTS_LATENCY[$idx]="$LATENCY"
    RESULTS_CODE[$idx]="$DISPLAY_CODE"

    case $CODE in
        200|201|202) 
            echo -e "${G}${CHECK} SUCCESS${C} ${K}(${LATENCY}ms)${C}"
            RESULTS_STATUS[$idx]="OK"
            [ $VERBOSE -eq 1 ] && echo -e "${K}RAW: $BODY${C}"
            ;;
        429_DAY)
            echo -e "${R}${CROSS} 429 DAILY CAP${C}"
            RESULTS_STATUS[$idx]="DAY"
            ;;
        429) 
            echo -e "${R}${CROSS} 429 RATE${C}"
            RESULTS_STATUS[$idx]="RATE"
            [ $VERBOSE -eq 1 ] && echo -e "${Y}$BODY${C}"
            ;;
        400)
            if [[ "$BODY" == *"location is not supported"* ]]; then
                echo -e "${R}${CROSS} REGION${C}"
                RESULTS_STATUS[$idx]="GEO"
            else
                echo -e "${R}${CROSS} ERR 400${C}"
                RESULTS_STATUS[$idx]="ERR"
                [ $VERBOSE -eq 1 ] && echo -e "${Y}$BODY${C}"
            fi
            ;;
        *)
            echo -e "${Y}${CROSS} $CODE FAIL${C}"
            RESULTS_STATUS[$idx]="FAIL"
            [ $VERBOSE -eq 1 ] && echo -e "${Y}$BODY${C}"
            ;;
    esac
    idx=$((idx + 1))
}

# --- Reporter ---
draw_summary() {
    echo -e "\n${B}${W}📊 Gemini API Audit Report (v9.0 Global Edition)${C}"
    echo -e "${B}${K}---------------------------------------------------------------${C}"
    printf "${W}%-38s | %-6s | %-8s | %-6s${C}\n" "MODEL NAME" "STATUS" "LATENCY" "CODE"
    echo -e "${B}${K}---------------------------------------------------------------${C}"
    
    for ((i=0; i<idx; i++)); do
        local S_COLOR=$G
        [[ "${RESULTS_STATUS[i]}" != "OK" ]] && S_COLOR=$R
        printf "%-38s | ${S_COLOR}%-6s${C} | %6sms | %-6s\n" "${RESULTS_NAME[i]}" "${RESULTS_STATUS[i]}" "${RESULTS_LATENCY[i]}" "${RESULTS_CODE[i]}"
    done
    echo -e "\n${K}Audit Time: $(date '+%Y-%m-%d %H:%M:%S')${C}\n"
}

# --- Main Logic ---

while getopts "k:m:p:d:lav" opt; do
    case $opt in
        k) API_KEY=$OPTARG ;;
        m) TARGET_MODEL=$OPTARG ;;
        p) PROXY=$OPTARG ;;
        d) DELAY=$OPTARG ;;
        l) ACTION="list" ;;
        a) ACTION="all" ;;
        v) VERBOSE=1 ;;
        *) usage ;;
    esac
done

if [ -z "$API_KEY" ]; then usage; fi

echo -e "${B}${K}---------------------------------------------------------------${C}"
case $ACTION in
    "list")
        echo -e "🔍 ${W}Retrieving authorized models...${C}"
        RPACK=$(execute_request "GET" "${G_BASE_URL}/models?key=${API_KEY}")
        BODY="${RPACK%%$D_SEP*}"
        CODE="${RPACK#*$D_SEP}"; CODE="${CODE%%$D_SEP*}"
        
        if [ "$CODE" -eq 200 ]; then
            if command -v jq >/dev/null 2>&1; then
                MODELS=$(echo "$BODY" | jq -r '.models[] | select(.supportedGenerationMethods[]? | contains("generateContent")) | .name' | sed 's/models\///')
            else
                MODELS=$(echo "$BODY" | awk -v RS='{' '/generateContent/ && !/embedding/ && !/imagen/ && !/veo/ {print}' | grep -o '"name": "models/[^"]*"' | sed 's/"name": "models\///g' | sed 's/"//g' | sort | uniq)
            fi
            for M in $MODELS; do echo -e "${TAB}${M}"; done
        else
            echo -e "${R}🛑 Listing failed (HTTP $CODE)${C}"
        fi
        ;;
    "test")
        if [ -z "$TARGET_MODEL" ]; then
            echo -e "🔎 ${K}No model specified. Selecting priority model...${C}"
            RPACK=$(execute_request "GET" "${G_BASE_URL}/models?key=${API_KEY}")
            BODY="${RPACK%%$D_SEP*}"
            if command -v jq >/dev/null 2>&1; then
                TARGET_MODEL=$(echo "$BODY" | jq -r '.models[] | select(.supportedGenerationMethods[]? | contains("generateContent")) | .name' | head -n 1 | sed 's/models\///')
            else
                TARGET_MODEL=$(echo "$BODY" | awk -v RS='{' '/generateContent/ && !/embedding/ && !/imagen/ && !/veo/ {print}' | grep -o '"name": "models/[^"]*"' | head -n 1 | sed 's/"name": "models\///g' | sed 's/"//g' | head -n 1)
            fi
            [ -z "$TARGET_MODEL" ] && echo -e "${R}🛑 No models found.${C}" && exit 1
            echo -e "🎯 ${G}Selected: ${TARGET_MODEL}${C}"
        fi
        probe "$TARGET_MODEL"
        draw_summary
        ;;
    "all")
        echo -e "🚀 ${W}Starting Full Matrix Compatibility Scan...${C}"
        RPACK=$(execute_request "GET" "${G_BASE_URL}/models?key=${API_KEY}")
        BODY="${RPACK%%$D_SEP*}"
        CODE="${RPACK#*$D_SEP}"; CODE="${CODE%%$D_SEP*}"

        if [ "$CODE" -eq 200 ]; then
            if command -v jq >/dev/null 2>&1; then
                ALL_MODELS=$(echo "$BODY" | jq -r '.models[] | select(.supportedGenerationMethods[]? | contains("generateContent")) | .name')
            else
                ALL_MODELS=$(echo "$BODY" | awk -v RS='{' '/generateContent/ && !/embedding/ && !/imagen/ && !/veo/ {print}' | grep -o '"name": "models/[^"]*"' | sed 's/"name": "models\///g' | sed 's/"//g')
            fi
            [ "$DELAY" -eq 0 ] && DELAY=1
            echo -e "${K}Anti-throttle mode active. Scan interval: ${DELAY}s${C}"
            for AM in $ALL_MODELS; do probe "$AM"; sleep "$DELAY"; done
            draw_summary
        else
            echo -e "${R}🛑 Matrix retrieval failed (HTTP $CODE)${C}"
        fi
        ;;
esac

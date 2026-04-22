#!/bin/bash

# 🛡️ Gemini API Sentinel - 终极全功能探测工具 (v7.0)
# 职责：密钥验证、全模型矩阵压力测试、地区屏蔽探测、代理穿透、智能重试审计

# --- 参数初始化 ---
API_KEY=""
PROXY=""
TARGET_MODEL="gemini-2.0-flash"
ACTION="test" # test | list | all
VERBOSE=0
RETRY_MAX=2

# 🎨 视觉矩阵 (2026 极简风)
G="\033[32m"; R="\033[31m"; Y="\033[33m"; B="\033[34m"; C="\033[0m"; W="\033[1m"

usage() {
    echo -e "${B}${W}Gemini API Sentinel v7.0 - 终极探测指南${C}"
    echo -e "用法: $0 -k <API_KEY> [选项]"
    echo ""
    echo -e "选项:"
    echo -e "  -k : API 密钥 (必填)"
    echo -e "  -m : 指定探测模型 (默认: gemini-2.0-flash)"
    echo -e "  -l : 列表模式 - 获取授权列表"
    echo -e "  -a : 全量模式 - 压测所有模型"
    echo -e "  -p : 挂载代理 (例如 http://127.0.0.1:7890)"
    echo -e "  -v : 详细模式 - 审计原始报文"
    exit 1
}

while getopts "k:m:p:lav" opt; do
    case $opt in
        k) API_KEY=$OPTARG ;;
        m) TARGET_MODEL=$OPTARG ;;
        p) PROXY=$OPTARG ;;
        l) ACTION="list" ;;
        a) ACTION="all" ;;
        v) VERBOSE=1 ;;
        *) usage ;;
    esac
done

if [ -z "$API_KEY" ]; then usage; fi

# --- 网络总线构建 ---
CURL_BASE="curl -s --connect-timeout 15 -H 'Content-Type: application/json'"
[ -n "$PROXY" ] && CURL_BASE="$CURL_BASE -x $PROXY"

# --- 核心：安全请求执行器 (带自愈解析) ---
# 参数：1. 方法(GET/POST) 2. URL 3. DATA (选填)
execute_request() {
    local METHOD=$1
    local URL=$2
    local DATA=$3
    local RETRY_COUNT=0
    
    while [ $RETRY_COUNT -le $RETRY_MAX ]; do
        # 使用自定义分隔符保证解析绝对精准
        local RAW_RESP
        if [ "$METHOD" == "POST" ]; then
            RAW_RESP=$(eval "$CURL_BASE -X POST '$URL' -d '$DATA' -w '---HTTP_CODE---%{http_code}'")
        else
            RAW_RESP=$(eval "$CURL_BASE -G '$URL' -w '---HTTP_CODE---%{http_code}'")
        fi

        # 解析 Body 和 Code
        local BODY="${RAW_RESP%---HTTP_CODE---*}"
        local CODE="${RAW_RESP##*---HTTP_CODE---}"
        CODE=$(echo "$CODE" | tr -d '[:space:]')

        # 智能重试策略 (针对 429 和 503)
        if [[ "$CODE" == "429" || "$CODE" == "503" ]] && [ $RETRY_COUNT -lt $RETRY_MAX ]; then
            local WAIT_SEC=$(( (RETRY_COUNT + 1) * 2 ))
            [ $VERBOSE -eq 1 ] && echo -e "${Y}  [!] 遭遇 $CODE，正在执行第 $((RETRY_COUNT+1)) 次指数避退重试 (等待 ${WAIT_SEC}s)...${C}" >&2
            sleep $WAIT_SEC
            RETRY_COUNT=$((RETRY_COUNT + 1))
            continue
        fi

        echo "$BODY"
        echo "$CODE"
        return 0
    done
}

# --- 核心：模型发现引擎 ---
fetch_authorized_models() {
    local ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models?key=${API_KEY}"
    local RESP_DATA=$(execute_request "GET" "$ENDPOINT")
    
    local CODE=$(echo "$RESP_DATA" | tail -n 1)
    local BODY=$(echo "$RESP_DATA" | sed '$d')

    if [ "$CODE" -ne 200 ]; then
        echo -e "${R}🛑 API 清单获取失败 (HTTP $CODE)${C}" >&2
        return 1
    fi

    # 优先使用 jq 提高精准度
    if command -v jq >/dev/null 2>&1; then
        echo "$BODY" | jq -r '.models[] | select(.supportedGenerationMethods[] | contains("generateContent")) | .name' | sed 's/models\///'
    else
        echo "$BODY" | awk -v RS='{' '/generateContent/ {print}' | grep -o '"name": "models/[^"]*"' | sed 's/"name": "models\///g' | sed 's/"//g' | sort | uniq
    fi
}

# --- 核心：物理层探测引擎 ---
probe() {
    local M=$1
    local CLEAN_M=$(echo $M | sed 's/models\///g')
    local ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/${CLEAN_M}:generateContent?key=${API_KEY}"
    
    printf "${W}🧪 感知 [ %-32s ] ... ${C}" "$CLEAN_M"
    
    # 使用具备语义的探测词
    local TEST_PAYLOAD='{"contents": [{"parts": [{"text": "Hello Gemini, are you online? Respond with exactly one word: YES."}]}]}'
    local RESP_DATA=$(execute_request "POST" "$ENDPOINT" "$TEST_PAYLOAD")
    
    local ST=$(echo "$RESP_DATA" | tail -n 1)
    local BD=$(echo "$RESP_DATA" | sed '$d')
    
    case $ST in
        200) 
            echo -e "${G}✅ SUCCESS${C}"
            [ $VERBOSE -eq 1 ] && echo -e "${B}诊断预览:${C} $(echo "$BD" | grep -o '"text": "[^"]*"' | head -n 1 | cut -d'"' -f4)"
            ;;
        429) 
            echo -e "${R}❌ 429 RATE_LIMITED (配额枯竭)${C}"
            ;;
        400)
            if [[ "$BD" == *"location is not supported"* ]]; then
                echo -e "${R}⛔ REGION_BLOCKED (地区封锁)${C}"
            else
                echo -e "${R}❌ 400 BAD_REQUEST (格式错误)${C}"
            fi
            ;;
        403)
            echo -e "${R}❌ 403 FORBIDDEN (密钥无效/禁用)${C}"
            ;;
        503)
            echo -e "${Y}⚠️  503 OVERLOADED (服务过载/预览模型繁忙)${C}"
            ;;
        *)
            echo -e "${Y}⚠️  HTTP $ST (未知状态)${C}"
            ;;
    esac
}

# --- 逻辑调度中心 ---
echo -e "${B}${W}------------------------------------------------------------${C}"
case $ACTION in
    "list")
        echo -e "🔍 ${W}正在拉取当前授权算力矩阵...${C}"
        MODELS=$(fetch_authorized_models)
        [ $? -eq 0 ] && echo "$MODELS" | sed 's/^/   └── /'
        ;;
    "all")
        echo -e "🚀 ${W}启动全量授权模型物理压测...${C}"
        MODELS=$(fetch_authorized_models)
        if [ $? -eq 0 ]; then
            for M in $MODELS; do probe "$M"; done
        fi
        ;;
    "test")
        probe "$TARGET_MODEL"
        ;;
esac
echo -e "${B}${W}------------------------------------------------------------${C}"

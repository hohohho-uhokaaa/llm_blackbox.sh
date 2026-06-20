#!/usr/bin/env bash

set -e

# ==============================================================================
# 設計方針
# ==============================================================================
# - バックグラウンドで常時実行（無限ループ）cronに@rebootで登録する
# - 5分間2秒間隔でシステムリソースを収集を無限ループ
# - 二重起動を防止（重複実行によるリソース浪費を防止）
# - シェルからスクリプト実行時はctrl+cで安全に終了
# ==============================================================================

# ==============================================================================
# 使い方
# ==============================================================================
# 1. 実行権限を付与: chmod +x ./llm_blackbox.sh
# 2. 初回実行で必要なパッケージを自動インストール: ./llm_blackbox.sh
# 3. CSV_FILEの「あなたのユーザー名」を実際のユーザー名に置換
# 4. バックグラウンドで実行: nohup ./llm_blackbox.sh > /dev/null 2>&1 &
# 5. 停止: pkill -f llm_blackbox.sh
# ==============================================================================

# ==============================================================================
# Gemini分析用プロンプト（以下をコピーして使用）
# ==============================================================================
# 添付のCSVは、ローカルLLM（Ollama/Qwen）を実行してPCに負荷をかけていた時の
# システムの健康状態を2秒ごとに記録したブラックボックスログです。
# 以下の3点を実行し、エンジニア視点で詳細なレポートを作成してください。
#
# 1. Pythonのコードを実行し、Timeを横軸にしたリソース（RAM、Swap、CPU温度、
#    GPU/VRAM使用率、GPU温度、Disk_IO）の時系列折れ線グラフを生成・画像表示してください。
# 2. グラフから「推論が始まった瞬間」「ピークに達した瞬間」「終了（またはハング）
#    した瞬間」などの重要なイベント・転換点を読み取り、グラフ上にマッピングしてください。
# 3. ログ全体（特に後半や末尾）とTop_Processの推移から、私のPCのボトルネック
#    （メモリ不足、スワップ地獄、熱暴走、グラフィックエラーなど）をプロファイリングし、
#    今後快適にローカルLLMを回すための具体的な自衛策（対策）を提案してください。
#    スワップ地獄が観察された場合はSSDの寿命に関する警告や情報がわかれば併せて教えてください。
# ==============================================================================

# ==============================================================================
# 設定
CSV_FILE="/home/あなたのユーザー名/llm_blackbox_rich.csv"
SLEEP_INTERVAL=2

# ==============================================================================
# 二重起動防止
# ==============================================================================
if pgrep -f "$(basename "$0")" | grep -v $$ > /dev/null; then
    echo "[ERROR] すでに実行中です"
    exit 1
fi

# ==============================================================================
# シグナルトラップ（安全な終了処理）
# ==============================================================================
trap 'echo "[INFO] 終了シグナルを受信しました"; exit 0' SIGTERM SIGINT

# ==============================================================================
# 処理の説明
# ==============================================================================
# 1. OS自動判定とパッケージ自動インストール（sensors, sysstat）
# 2. CPU温度センサーのパターン自動検出（Tctl, Core 0, Package id 0）
# 3. CSVファイルの初期化（ヘッダー書き込み）
# 4. メインループ：RAM, Swap, CPU温度, GPU情報, ディスクI/O, トッププロセスを収集
# ==============================================================================
if ! command -v sensors &> /dev/null || ! command -v vmstat &> /dev/null; then
    echo "[INFO] 必要なコマンドが足りないため、OSのパッケージ管理を自動判定します..."
    
    if command -v dnf &> /dev/null; then
        # Fedora / RHEL系
        echo "[INFO] Fedora (RPM系) を検出しました。lm_sensors と sysstat をインストールします。"
        sudo dnf install -y lm_sensors sysstat
    elif command -v apt-get &> /dev/null; then
        # Ubuntu / Debian系
        echo "[INFO] Ubuntu (DEB系) を検出しました。lm-sensors と sysstat をインストールします。"
        sudo apt-get update && sudo apt-get install -y lm-sensors sysstat
    elif command -v apk &> /dev/null; then
        # Alpine Linux
        echo "[INFO] Alpine Linux を検出しました。lm-sensors と sysstat をインストールします。"
        sudo apk add lm-sensors sysstat
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        echo "[INFO] Arch Linux を検出しました。lm_sensors と sysstat をインストールします。"
        sudo pacman -S --noconfirm lm_sensors sysstat
    else
        # 想定外のマイナーLinuxの場合
        echo "[ERROR] 未知のOS環境です。手動で 'lm-sensors' と 'sysstat' をインストールしてください。"
        exit 1
    fi
fi

# CPU温度センサーのパターン自動検出（AMD/Intel対応）
TEMP_PATTERN=$(sensors 2>/dev/null | grep -E -o '(Tctl|Core 0|Package id 0)' | head -n 1)
[ -z "$TEMP_PATTERN" ] && TEMP_PATTERN="Tctl"

# CSVファイルの初期化（ヘッダー書き込み）
if [ ! -f "$CSV_FILE" ]; then
    echo "Timestamp,RAM_Used_MB,RAM_Free_MB,Swap_Used_MB,Swap_Free_MB,CPU_Temp,GPU_Util,VRAM_Util,GPU_Temp,Disk_IO_SR,\"Top_Process\",\"Ollama_Model\",Ollama_Mem,Code_Mem,Code_CPU,Ollama_API_Status,Continue_Log" > "$CSV_FILE"
fi

# メインループ：システムリソース収集
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # RAMとSwap情報
    FREE_OUT=$(free -m)
    RAM_INFO=$(echo "$FREE_OUT" | grep Mem | awk '{print $3","$4}')
    SWAP_INFO=$(echo "$FREE_OUT" | grep Swap | awk '{print $3","$4}')
    
    # CPU温度
    CPU_TEMP=$(sensors 2>/dev/null | grep -E "$TEMP_PATTERN" | head -n 1 | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
    [ -z "$CPU_TEMP" ] && CPU_TEMP="0"

    # GPU情報（NVIDIA GPUの場合）
    if command -v nvidia-smi &> /dev/null; then
        GPU_INFO=$(nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu --format=csv,noheader,nounits | sed 's/, /,/g')
    else
        GPU_INFO="0,0,0"
    fi

    # とりあえず手間かけずに取れそうなものは取ってみる
    # ディスクI/O（注: vmstat 1 1 により実際のログ間隔は約3秒）
    DISK_IO=$(vmstat 1 1 | tail -n 1 | awk '{print $9+$10}')

    # トッププロセス
    TOP_PROC=$(ps -eo comm,%mem --sort=-%mem | head -n 2 | tail -n 1 | awk '{print $1"("$2"%)"}')

    # ollamaモデル情報
    OLLAMA_MODEL=$(ollama ps 2>/dev/null | grep -v NAME | awk '{print $1","$2","$3}' | head -n 1)
    [ -z "$OLLAMA_MODEL" ] && OLLAMA_MODEL="0,0,0"

    # プロセスごとの詳細メモリ情報
    OLLAMA_MEM=$(ps -C ollama -o %mem --no-headers 2>/dev/null | head -n 1)
    [ -z "$OLLAMA_MEM" ] && OLLAMA_MEM="0"
    CODE_MEM=$(ps -C code -o %mem --no-headers 2>/dev/null | head -n 1)
    [ -z "$CODE_MEM" ] && CODE_MEM="0"

    # VSCode/ContinueのCPU使用率
    CODE_CPU=$(ps -C code -o %cpu --no-headers 2>/dev/null | head -n 1)
    [ -z "$CODE_CPU" ] && CODE_CPU="0"

    # Ollama APIステータス
    OLLAMA_API_STATUS=$(curl -s http://localhost:11434/api/ps 2>/dev/null | head -c 100)
    [ -z "$OLLAMA_API_STATUS" ] && OLLAMA_API_STATUS="0"

    # Continueログファイルから推論情報を抽出
    CONTINUE_LOG=$(tail -n 5 ~/.config/Continue/logs/*.log 2>/dev/null | grep -i "context\|inference" | tail -n 1 | head -c 50)
    [ -z "$CONTINUE_LOG" ] && CONTINUE_LOG="0"

    # CSVに追記
    echo "$TIMESTAMP,$RAM_INFO,$SWAP_INFO,$CPU_TEMP,$GPU_INFO,$DISK_IO,\"$TOP_PROC\",\"$OLLAMA_MODEL\",$OLLAMA_MEM,$CODE_MEM,$CODE_CPU,\"$OLLAMA_API_STATUS\",\"$CONTINUE_LOG\"" >> "$CSV_FILE"
    
    sleep $SLEEP_INTERVAL
done

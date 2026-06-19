#!/bin/bash

# ==============================================================================
# 🤖【Gemini 分析時の注意事項】
# 1. ログ採取時間は15分〜30分（約900行）を目安にすると、最高に綺麗なグラフになる。
# 2. もしPCがハングアップ（強制終了）した場合は、再起動後にこのCSVの「最末尾」を
#    そのままGeminiに投げれば、死ぬ2秒前までの惨状を分析できる。
# 3. 精度を極限まで高めたい時は、以下のFedora/Ubuntuシステムログ（死ぬ直前の数十行）も
#    一緒にテキストでコピペしてGeminiに渡すと、完璧な答え合わせができる。
#    👉 コマンド: journalctl -b -1 -g "(ollama|vscode-ide|Out of memory|thermal|Xid|amdgpu)" --no-pager
#
# 📋【Gemini への最強分析依頼プロンプト】(ここから下をコピーしてGeminiに投げる)
# 以下のプロンプトをコピペして $HOME/llm_blackbox_rich.csv を geminiのプロンプト入力欄に
# ドラッグして放り込んで丸投げすると、以下の3点を実行してくれる。
# 
# ↓以下プロンプト
# ------------------------------------------------------------------------------
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
# ------------------------------------------------------------------------------
# ↑プロンプトここまで
#
# ==============================================================================
# 4. 使い方
# cron に登録する前に chmod +x ./llm_blackbox.sh として、スクリプトにシェルでの実行権を
# 付け、その後に ./llm_blackbox.sh を1回だけ実行すると、必要なコマンドが自動でインストール
# されます。 その後、このスクリプトを cron に登録しておくと、2秒ごとにシステムの健康状態を
# 自動で記録し続けます。
# cron の登録は crontab -e で開き、以下の1行を追加してください。
# * * * * * /home/あなたのユーザー名/llm_blackbox.sh > /dev/null 2>&1
# (※「あなたのユーザー名」の部分は実際のFedoraやUbuntuのユーザー名に変えてください。
# pwd コマンドで確認できます)
#
# ==============================================================================
# 設定
CSV_FILE="$HOME/llm_blackbox_rich.csv"
# ------------------------------------------------------------------------------
# 🛠️【1. 二重起動防止の防壁】
# ------------------------------------------------------------------------------
# すでにこのスクリプトがバックグラウンドで動いている場合は、重複して走らないように即終了
if pgrep -f "$(basename "$0")" | grep -v $$ > /dev/null; then
    exit 0
fi
# ------------------------------------------------------------------------------
# 📦【2. OS自動判定 ＆ 不足コマンドの自動インストール】
# ------------------------------------------------------------------------------
# センサーコマンド(sensors)やディスクI/Oコマンド(vmstat)がない場合のみ自動インストール
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

# ------------------------------------------------------------------------------
# 🎛️【3. 環境ごとの温度センサー項目名の自動吸収】
# ------------------------------------------------------------------------------
# OSやCPUの種類（AMD/Intel）で変わる温度のラベル名（Tctl, Core 0, Package id 0）を自動検出
TEMP_PATTERN=$(sensors 2>/dev/null | grep -E -o '(Tctl|Core 0|Package id 0)' | head -n 1)
# 万が一見つからなかった場合の安全弁として Tctl をセット
[ -z "$TEMP_PATTERN" ] && TEMP_PATTERN="Tctl"

# ------------------------------------------------------------------------------
# 📊【4. CSVファイルの初期化（ヘッダー書き込み）】
# ------------------------------------------------------------------------------
if [ ! -f "$CSV_FILE" ]; then
    echo "Timestamp,RAM_Used_MB,RAM_Free_MB,Swap_Used_MB,Swap_Free_MB,CPU_Temp,GPU_Util,VRAM_Util,GPU_Temp,Disk_IO_SR,Top_Process" > "$CSV_FILE"
fi

# ------------------------------------------------------------------------------
# 🔄【5. メインループ：超軽量・ステルス健康診断記録】
# ------------------------------------------------------------------------------
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # ① RAMとSwap情報（freeコマンドから抽出）
    FREE_OUT=$(free -m)
    RAM_INFO=$(echo "$FREE_OUT" | grep Mem | awk '{print $3","$4}')
    SWAP_INFO=$(echo "$FREE_OUT" | grep Swap | awk '{print $3","$4}')
    
    # ② CPU温度（自動検出したパターンで数値を抽出）
    CPU_TEMP=$(sensors 2>/dev/null | grep -E "$TEMP_PATTERN" | head -n 1 | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
    [ -z "$CPU_TEMP" ] && CPU_TEMP="0"

    # ③ GPU情報（nvidia-smiが使える場合のみ取得、使えなければダミーの0をセット）
    if command -v nvidia-smi &> /dev/null; then
        GPU_INFO=$(nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu --format=csv,noheader,nounits | sed 's/, /,/g')
    else
        GPU_INFO="0,0,0"
    fi

    # ④ ディスクI/O（vmstatから1秒間のセクタ読み書きの合計値を取得）
    DISK_IO=$(vmstat 1 1 | tail -n 1 | awk '{print $9+$10}')

    # ⑤ メモリ消費トップのプロセス名と、そのプロセス単体のメモリ使用率(%)
    TOP_PROC=$(ps -eo comm,%mem --sort=-%mem | head -n 2 | tail -n 1 | awk '{print $1"("$2"%)"}')

    # カンマで1行に合体させてCSVに追記（プロセス名のカンマをエスケープ）
    echo "$TIMESTAMP,$RAM_INFO,$SWAP_INFO,$CPU_TEMP,$GPU_INFO,$DISK_IO,\"$TOP_PROC\"" >> "$CSV_FILE"
    
    # 2秒間お休み（休止状態になりCPU負荷を完全にゼロにします）
    sleep 2
done
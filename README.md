# LLM Blackbox Logger

システムの健康状態を2秒ごとに記録するブラックボックスロガー。ローカルLLM（Ollama/Qwenなど）実行時のリソース使用状況をCSVに記録し、GeminiなどのAIで分析可能にします。スクリプト中に/home\あなたの

## 機能

- **RAM/Swap監視**: 使用量と空き容量をMB単位で記録
- **CPU温度監視**: AMD/Intelの温度センサーを自動検出
- **GPU監視**: NVIDIA GPUの場合、使用率・VRAM使用率・温度を記録（自動検出）
- **ディスクI/O監視**: 読み書きセクタ数を記録
- **トッププロセス監視**: メモリ消費の多いプロセスとその使用率を記録
- **OS自動判定**: Fedora/RHEL系、Ubuntu/Debian系、Alpine Linux、Arch Linuxを自動判定
- **自動インストール**: 必要なパッケージ（lm_sensors, sysstat）がなければ自動インストール
- **二重起動防止**: 重複実行を自動防止

## 対応環境

- Fedora / RHEL系
- Ubuntu / Debian系
- Alpine Linux
- Arch Linux
- その他Linuxディストリビューション（手動インストールが必要）

## インストール手順

### 1. 実行権限の付与

```bash
chmod +x ./llm_blackbox.sh
```

### 2. 初回実行（自動インストール）

```bash
./llm_blackbox.sh
```

初回実行時、必要なパッケージ（lm_sensors, sysstat）が自動的にインストールされます。
cron登録後はOS起動時にシステム状態の収集、csvファイルへの追記が開始され、その後、2秒スリープして実行を30回繰り返し続けます。

### 3. cronへの登録

```bash
crontab -e
```

以下の行を追加してください（パスは実際の環境に合わせて変更）：

```cron
* * * * * /home/あなたのユーザー名/llm_blackbox.sh > 2>&1
```

ユーザー名は `pwd` コマンドで確認できます。

## 出力ファイル

記録されたデータはCSV形式で保存されます。

### 出力先

`$HOME/llm_blackbox_rich.csv`

### CSVフォーマット

```
Timestamp,RAM_Used_MB,RAM_Free_MB,Swap_Used_MB,Swap_Free_MB,CPU_Temp,GPU_Util,VRAM_Util,GPU_Temp,Disk_IO_SR,"Top_Process"
```

※Top_Processはプロセス名にカンマが含まれる場合に備えてダブルクォートで囲まれています

## Geminiでの分析方法

記録したCSVファイルをGeminiに投げて分析する際のプロンプト：

```
添付のCSVは、ローカルLLM（Ollama/Qwen）を実行してPCに負荷をかけていた時の
システムの健康状態を2秒ごとに記録したブラックボックスログです。
以下の3点を実行し、エンジニア視点で詳細なレポートを作成してください。

1. Pythonのコードを実行し、Timeを横軸にしたリソース（RAM、Swap、CPU温度、
   GPU/VRAM使用率、GPU温度、Disk_IO）の時系列折れ線グラフを生成・画像表示してください。
2. グラフから「推論が始まった瞬間」「ピークに達した瞬間」「終了（またはハング）
   した瞬間」などの重要なイベント・転換点を読み取り、グラフ上にマッピングしてください。
3. ログ全体（特に後半や末尾）とTop_Processの推移から、私のPCのボトルネック
   （メモリ不足、スワップ地獄、熱暴走、グラフィックエラーなど）をプロファイリングし、
   今後快適にローカルLLMを回すための具体的な自衛策（対策）を提案してください。
```

## 停止方法

```bash
# プロセスを停止
pkill -f llm_blackbox.sh

# cronから削除する場合は crontab -e で該当行を削除
```

## 技術詳細

### 自動検出機能

- **温度センサー**: Tctl, Core 0, Package id 0 を自動検出
- **GPU**: nvidia-smiコマンドの有無を自動判定
- **OS**: dnf（Fedora/RHEL）、apt-get（Ubuntu/Debian）、apk（Alpine Linux）、pacman（Arch Linux）を自動判定

### ログ採取の目安

- 15分〜30分（約900行）のログが最も綺麗なグラフになります
- PCがハングアップした場合、CSVの最末尾をGeminiに投げれば、死ぬ直前までの状況を分析できます

### システムログとの併用

精度を高めたい場合は、以下のコマンドでシステムログも取得してGeminiに渡してください：

```bash
journalctl -b -1 -g "(ollama|vscode-ide|Out of memory|thermal|Xid|amdgpu)" --no-pager
```

## Linuxユニバーサル仕様

このスクリプトは、特定のOSの深い部分（Fedora固有の dnf の仕組みなど）には一切依存せず、Linuxカーネルが吐き出す標準的な数値（/proc の情報）を拾っているだけです。
そのため、Fedora から Ubuntu に持っていっても、あるいは将来の新しいバージョンのOSに変えたとしても、ほぼ永久にそのまま使い回せる「一生モノのブラックボックスロガー」になっています。

### 共通コマンド

以下のコマンドは、FedoraでもUbuntuでも中身は完全に同じ（共通のパッケージ）なので、書き換える必要がありません。

- `free -m`（メモリとスワップの測定）
- `vmstat`（ディスクI/Oの測定）
- `ps`（メモリ消費トッププロセスの特定）
- `date`（タイムスタンプ）

### ディストリビューションによる注意点

一部、インストールされているパッケージの名前や、ハードウェアの構成によって出力が変わる部分があります。

#### sensors （CPU温度）

Ubuntuでも lm-sensors というパッケージを入れることで全く同じように使えます。ただし、CPUの「温度を指す文字列」が、AMDとIntel、あるいはマザーボードによって変わることがあります。

- **Fedora（AMD Ryzenなど）**: Tctl や Core 0
- **Ubuntu (Intel Coreなど)**: Package id 0 や Core 0

スクリプトではこれらを自動検出しますが、もし温度が 0 のまま動かない場合は、ターミナルで `sensors` とだけ打ってみて、出てきた温度の項目名を確認してください。

#### nvidia-smi （GPU情報）

これはOS（Fedora/Ubuntu）の差ではなく、「NVIDIAのグラフィックボードと公式ドライバーが入っているか」に依存します。スクリプト内では `if command -v nvidia-smi` を使って「NVIDIAのコマンドがあるときだけ動く」ように自動分岐させているので、NVIDIA環境ならそのまま動きますし、グラボがないPCなら自動的に安全なダミー値（0）を出力するようになっています。

#### Alpine Linux / Arch Linux

Alpine Linuxでは `apk`、Arch Linuxでは `pacman` を使用してパッケージを自動インストールします。パッケージ名は他のディストリビューションと同様に `lm-sensors` と `sysstat` です。

## ライセンス

MITライセンスとしてご利用ください

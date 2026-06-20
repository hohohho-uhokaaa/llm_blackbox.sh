# LLM Blackbox Logger

システムの健康状態を2秒ごとに記録するブラックボックスロガー。
ローカルLLM（Ollama/Qwenなど）実行時のリソース使用状況をCSVに記録し、GeminiなどのAIで分析可能にします。
結局、一旦、cronに@rebootで登録する無限ループに落ち着きました。
cronしなくてもスクリプトをターミナル等から起動したら ctrl+c で終了できます。
1回起動すると5分間2秒毎にcsvに書き出しますのでシェルから起動するなら `./llm_blackbox.sh &` がおすすめです。
他のアプリのログと混ぜてgemini等に投げると、どういう状況なのか解説してくれると思います。Pythonでフラフにするのはお約束
（主はNEC EWS-4800さわったことがあり、cronまじムズいが固定観念でしたが超絶ひさしぶりでさわったらやっぱりムズい）
本スクリプトはgeminiと相談しながら作ってみて、最終的にはdevinで仕上げてます。
あれこれ試してみてこれなら使えそうになるまでdevinにも修正提案を聞いていましたが、結果的にこれなら使えそうはdevinの提案をすべてAcceptすれば良いだけと学習しました。AIに飼いならされてしまえば人生は悟りの境地に入ることがわかりました。南無阿弥陀仏

## 機能

- **RAM/Swap監視**: 使用量と空き容量をMB単位で記録
- **CPU温度監視**: AMD/Intelの温度センサーを自動検出
- **GPU監視**: NVIDIA GPUの場合、使用率・VRAM使用率・温度を記録（自動検出）
- **ディスクI/O監視**: 読み書きセクタ数を記録
- **トッププロセス監視**: メモリ消費の多いプロセスとその使用率を記録
- **Ollamaモデル監視**: 実行中のOllamaモデル名、使用率、メモリ使用量を記録
- **Ollama API監視**: Ollama APIからの応答を記録
- **プロセス別メモリ監視**: ollama、codeプロセスの個別メモリ使用率を記録
- **VSCode CPU監視**: codeプロセスのCPU使用率を記録
- **Continueログ監視**: Continueログファイルから推論情報を抽出
- **OS自動判定**: Fedora/RHEL系、Ubuntu/Debian系、Alpine Linux、Arch Linuxを自動判定
- **自動インストール**: 必要なパッケージ（lm_sensors, sysstat）がなければ自動インストール
- **二重起動防止**: 重複実行によるリソース浪費を防止

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

### 2. CSV_FILEの設定

スクリプトのCSV_FILE行の「あなたのユーザー名」を実際のユーザー名に変更してください。

### 3. 初回実行（自動インストール）

```bash
./llm_blackbox.sh
```

初回実行時、必要なパッケージ（lm_sensors, sysstat）が自動的にインストールされます。

## 実行方法

llm_blackbox.shは以下の3通りの実行方法に対応しています。cron登録は必須ではありません。

### フォアグラウンドで実行（Ctrl+Cで終了）

```bash
./llm_blackbox.sh
```

**推奨**: テストや一時的な監視に最適です。Ctrl+Cで即座に終了できます。

### バックグラウンドで実行

```bash
nohup ./llm_blackbox.sh > /dev/null 2>&1 &
```

**用途**: 常時監視に最適です。ターミナルを閉じても実行し続けます。

### cronで実行

```bash
crontab -e
```

以下の行を追加してください（パスは実際の環境に合わせて変更）：

```cron
@reboot /home/あなたのユーザー名/llm_blackbox.sh > /dev/null 2>&1 &
```

**注意**: cronで実行する場合、二重起動防止機能が動作します。既に実行中のプロセスがある場合は新しいプロセスが起動しません。

## 停止方法

```bash
# Ctrl+Cで中止（フォアグラウンド実行の場合）
# または
pkill -f llm_blackbox.sh
```

## 出力ファイル

記録されたデータはCSV形式で保存されます。

### 出力先

`$HOME/llm_blackbox_rich.csv`

### CSVフォーマット

```
Timestamp,RAM_Used_MB,RAM_Free_MB,Swap_Used_MB,Swap_Free_MB,CPU_Temp,GPU_Util,VRAM_Util,GPU_Temp,Disk_IO_SR,"Top_Process","Ollama_Model",Ollama_Mem,Code_Mem,Code_CPU,"Ollama_API_Status","Continue_Log"
```

※Top_Processはプロセス名にカンマが含まれる場合に備えてダブルクォートで囲まれています
※Ollama_Modelは「モデル名,使用率,メモリ使用量」の形式です（例: qwen2.5-coder,50%,4GB）
※Ollama_API_StatusはOllama APIからの応答（最大100文字）
※Continue_LogはContinueログファイルからの推論情報（最大50文字）

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
   スワップ地獄が観察された場合はSSDの寿命に関する警告や情報がわかれば併せて教えてください。
```

## 停止方法

```bash
# Ctrl+Cで中止（フォアグラウンド実行の場合）
# または
pkill -f llm_blackbox_loop.sh
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

## llm_blackbox_rich.csvのサンプル

以下のようにcsv形式で観測された数値が追記されていきます。
追記の間隔は2秒ごと。観測時点でのトップ・プロセスが記録されます。
（csvフォーマットはこのドキュメントの102行目を参照）

2026-06-20 02:39:42,3293,6624,0,8191,46.6,0,0,0,31449,"chrome(4.5%)"
2026-06-20 02:39:44,3297,6619,0,8191,44.2,0,0,0,30711,"chrome(4.5%)"
2026-06-20 02:39:46,3284,6629,0,8191,43.9,0,0,0,30017,"chrome(4.5%)"
2026-06-20 02:39:48,3287,6625,0,8191,44.0,0,0,0,29348,"chrome(4.5%)"
2026-06-20 02:39:50,3293,6620,0,8191,52.2,0,0,0,28704,"chrome(4.5%)"
2026-06-20 02:39:52,3316,6596,0,8191,49.0,0,0,0,28088,"chrome(4.5%)"
2026-06-20 02:39:54,3335,6579,0,8191,46.1,0,0,0,27517,"chrome(4.5%)"
2026-06-20 02:39:56,3356,6554,0,8191,43.8,0,0,0,27027,"chrome(4.5%)"
2026-06-20 02:39:59,3364,6535,0,8191,43.8,0,0,0,26738,"chrome(4.5%)"
2026-06-20 02:40:01,3361,6534,0,8191,43.6,0,0,0,26260,"chrome(4.5%)"
2026-06-20 02:40:03,3351,6535,0,8191,43.8,0,0,0,25759,"chrome(4.5%)"
2026-06-20 02:40:05,3352,6534,0,8191,43.6,0,0,0,25268,"chrome(4.5%)"
2026-06-20 02:40:07,3364,6522,0,8191,43.6,0,0,0,24798,"chrome(4.5%)"
2026-06-20 02:40:09,2674,7209,0,8191,43.2,0,0,0,24374,"jetbrains-toolb(3.3%)"
2026-06-20 02:40:11,2702,7125,0,8191,53.6,0,0,0,24551,"jetbrains-toolb(3.3%)"
2026-06-20 02:40:13,2704,7123,0,8191,50.6,0,0,0,24114,"jetbrains-toolb(3.3%)"
2026-06-20 02:40:15,2694,7133,0,8191,47.5,0,0,0,23695,"jetbrains-toolb(3.3%)"
2026-06-20 02:40:17,2754,6897,0,8191,45.9,0,0,0,24486,"jetbrains-toolb(3.3%)"
2026-06-20 02:40:19,3032,6514,0,8191,57.0,0,0,0,24726,"jetbrains-toolb(3.3%)"
2026-06-20 02:40:21,3341,6167,0,8191,58.9,0,0,0,24490,"jetbrains-toolb(3.3%)"
2026-06-20 02:40:23,3791,5623,0,8191,59.4,0,0,0,24357,"jetbrains-toolb(3.3%)"
2026-06-20 02:40:26,3939,5414,0,8191,67.6,0,0,0,24194,"jetbrains-toolb(3.3%)"
2026-06-20 02:40:28,4165,5172,0,8191,64.4,0,0,0,23861,"code(4.1%)"
2026-06-20 02:40:30,4198,5108,0,8191,61.1,0,0,0,23628,"code(4.6%)"
2026-06-20 02:40:32,4314,4973,0,8191,58.6,0,0,0,23354,"code(5.3%)"
2026-06-20 02:40:34,4311,4860,0,8191,56.5,0,0,0,23478,"code(5.4%)"
2026-06-20 02:40:36,4319,4845,0,8191,53.5,0,0,0,23161,"code(5.4%)"
2026-06-20 02:40:38,4306,4858,0,8191,50.2,0,0,0,22823,"code(5.4%)"
2026-06-20 02:40:40,4300,4864,0,8191,47.0,0,0,0,22492,"code(5.4%)"

## ライセンス

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


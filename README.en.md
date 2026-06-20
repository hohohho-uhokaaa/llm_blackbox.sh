# LLM Blackbox Logger

A blackbox logger that records system health status every 2 seconds. It records resource usage during local LLM (Ollama/Qwen, etc.) execution to CSV for analysis with AI like Gemini.

Eventually, it settled on an infinite loop registered with @reboot in cron. Even without cron, you can exit by pressing Ctrl+C when starting the script from a terminal. Once started, it writes to CSV every 2 seconds for 5 minutes, so if starting from shell, `./llm_blackbox.sh &` is recommended. If you mix it with logs from other apps and throw them at Gemini, I think it will explain what kind of situation it is. Python graphing is a given (the author has used NEC EWS-4800, and cron was really difficult due to fixed ideas, but when I touched it after a long time, it was still difficult). This script was created while consulting with Gemini, and finally finished with Devin. I tried various things and asked Devin for modification suggestions until it became usable, but as a result, I learned that if it's usable, I just need to Accept all of Devin's suggestions. There is absolutely no need to rejoice or grieve over the inference that flows across the monitor at the speed of light. Once you are tamed by AI, your life enters the realm of enlightenment.

## Features

- **RAM/Swap Monitoring**: Records usage and free capacity in MB
- **CPU Temperature Monitoring**: Automatically detects AMD/Intel temperature sensors
- **GPU Monitoring**: Records utilization, VRAM utilization, and temperature for NVIDIA GPUs (auto-detect)
- **Disk I/O Monitoring**: Records read/write sector counts
- **Top Process Monitoring**: Records the process with highest memory usage and its usage rate
- **Ollama Model Monitoring**: Records running Ollama model name, utilization, and memory usage
- **Ollama API Monitoring**: Records response from Ollama API
- **Per-Process Memory Monitoring**: Records individual memory usage rates for ollama and code processes
- **VSCode CPU Monitoring**: Records CPU usage rate for code process
- **Continue Log Monitoring**: Extracts inference information from Continue log files
- **OS Auto-Detection**: Automatically detects Fedora/RHEL, Ubuntu/Debian, Alpine Linux, Arch Linux
- **Auto-Installation**: Automatically installs required packages (lm_sensors, sysstat) if not present
- **Duplicate Execution Prevention**: Prevents resource waste from duplicate execution

## Supported Environments

- Fedora / RHEL family
- Ubuntu / Debian family
- Alpine Linux
- Arch Linux
- Other Linux distributions (manual installation required)

## Installation Steps

### 1. Grant Execute Permissions

```bash
chmod +x ./llm_blackbox.sh
```

### 2. Configure CSV_FILE

Change "your username" in the script's CSV_FILE line to your actual username.

### 3. First Run (Auto-Installation)

```bash
./llm_blackbox.sh
```

On first run, required packages (lm_sensors, sysstat) will be automatically installed.

## Execution Methods

llm_blackbox.sh supports the following three execution methods. Cron registration is not mandatory.

### Foreground Execution (Exit with Ctrl+C)

```bash
./llm_blackbox.sh
```

**Recommended**: Ideal for testing and temporary monitoring. Can exit immediately with Ctrl+C.

### Background Execution

```bash
nohup ./llm_blackbox.sh > /dev/null 2>&1 &
```

**Use Case**: Ideal for continuous monitoring. Continues running even after closing the terminal.

### Cron Execution

```bash
crontab -e
```

Add the following line (change the path to match your actual environment):

```cron
@reboot /home/your username/llm_blackbox.sh > /dev/null 2>&1 &
```

**Note**: When running with cron, the duplicate execution prevention feature is active. If a process is already running, a new process will not start.

## Stopping Methods

```bash
# Stop with Ctrl+C (for foreground execution)
# or
pkill -f llm_blackbox.sh
```

## Output Files

Recorded data is saved in CSV format.

### Output Destination

`$HOME/llm_blackbox_rich.csv`

### CSV Format

```
Timestamp,RAM_Used_MB,RAM_Free_MB,Swap_Used_MB,Swap_Free_MB,CPU_Temp,GPU_Util,VRAM_Util,GPU_Temp,Disk_IO_SR,"Top_Process","Ollama_Model",Ollama_Mem,Code_Mem,Code_CPU,"Ollama_API_Status","Continue_Log"
```

※Top_Process is enclosed in double quotes to handle commas in process names
※Ollama_Model is in the format "model name,utilization,memory usage" (e.g., qwen2.5-coder,50%,4GB)
※Ollama_API_Status is the response from Ollama API (max 100 characters)
※Continue_Log is inference information from Continue log files (max 50 characters)

## Analysis with Gemini

Prompt for analyzing recorded CSV files with Gemini:

```
The attached CSV is a blackbox log recording system health status every 2 seconds while running a local LLM (Ollama/Qwen) and putting load on the PC.
Please execute the following 3 points and create a detailed report from an engineer's perspective.

1. Execute Python code to generate and display time-series line graphs with Time on the X-axis for resources (RAM, Swap, CPU temperature,
   GPU/VRAM utilization, GPU temperature, Disk_IO).
2. Read important events and transition points such as "moment inference started", "moment peak was reached", "moment ended (or hung)"
   from the graph and map them on the graph.
3. Profile my PC's bottlenecks (memory shortage, swap hell, thermal runaway, graphics errors, etc.) from the entire log (especially the latter half and end)
   and the transition of Top_Process, and propose specific self-defense measures (countermeasures) to comfortably run local LLMs in the future.
   If swap hell is observed, please also provide warnings or information about SSD lifespan if available.
```

## Stopping Methods

```bash
# Stop with Ctrl+C (for foreground execution)
# or
pkill -f llm_blackbox_loop.sh
```

## Technical Details

### Auto-Detection Features

- **Temperature Sensor**: Auto-detects Tctl, Core 0, Package id 0
- **GPU**: Auto-detects presence of nvidia-smi command
- **OS**: Auto-detects dnf (Fedora/RHEL), apt-get (Ubuntu/Debian), apk (Alpine Linux), pacman (Arch Linux)

### Log Collection Guidelines

- 15-30 minutes (approximately 900 lines) of logs produce the cleanest graphs
- If your PC hangs, you can analyze the situation right before death by throwing the end of the CSV to Gemini

### Combining with System Logs

To improve accuracy, also obtain system logs with the following command and pass them to Gemini:

```bash
journalctl -b -1 -g "(ollama|vscode-ide|Out of memory|thermal|Xid|amdgpu)" --no-pager
```

## Linux Universal Specification

This script does not depend on deep OS-specific parts (such as Fedora's unique dnf mechanism) at all, but simply picks up standard values output by the Linux kernel (/proc information).

Therefore, whether you move from Fedora to Ubuntu or change to a future new version of OS, it becomes a "lifetime blackbox logger" that can be used almost permanently as is.

### Common Commands

The following commands are completely identical in content (common packages) on both Fedora and Ubuntu, so there is no need to rewrite them.

- `free -m` (memory and swap measurement)
- `vmstat` (disk I/O measurement)
- `ps` (identifying top memory-consuming processes)
- `date` (timestamp)

### Distribution-Specific Notes

Some parts change depending on installed package names or hardware configuration.

#### sensors (CPU Temperature)

On Ubuntu as well, you can use it exactly the same way by installing the lm-sensors package. However, the "string pointing to temperature" for CPU may vary between AMD and Intel, or depending on the motherboard.

- **Fedora (AMD Ryzen, etc.)**: Tctl and Core 0
- **Ubuntu (Intel Core, etc.)**: Package id 0 and Core 0

The script auto-detects these, but if the temperature remains at 0, try typing just `sensors` in the terminal and check the temperature item name that appears.

#### nvidia-smi (GPU Information)

This is not a difference between OS (Fedora/Ubuntu), but depends on "whether NVIDIA graphics card and official driver are installed". In the script, `if command -v nvidia-smi` is used to automatically branch so that "it only runs when NVIDIA command exists", so it works as is in NVIDIA environments, and on PCs without graphics cards, it automatically outputs safe dummy values (0).

#### Alpine Linux / Arch Linux

On Alpine Linux, `apk` is used, and on Arch Linux, `pacman` is used to automatically install packages. Package names are `lm-sensors` and `sysstat`, same as other distributions.

## llm_blackbox_rich.csv Sample

Observed values are appended in CSV format as follows.
Append interval is every 2 seconds. The top process at the time of observation is recorded.
(See line 102 of this document for CSV format)

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

## License

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

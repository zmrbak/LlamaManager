# Llama Server 集群作业管理

## 文件说明

| 文件 | 用途 |
|------|------|
| `start_llama_jobs.sh` | 主脚本：读取配置、生成作业脚本、提交作业 |
| `stop_llama_jobs.sh` | 停止 llama_server 作业，清理生成文件（保留 llama_server.cfg） |
| `clean_jobs_force.sh` | 强制清理所有作业（含持续监控），清理完毕后删除日志文件 |
| `llama_server.cfg` | 配置文件（7 个参数，缺失时自动补全） |
| `job.txt` | 作业脚本（每次提交时自动生成） |
| `~/llama_server_status.txt` | 资源状态报告（NFS 共享，登录节点可直接 `cat`） |

## 快速开始

```bash
# 启动 llama_server 作业
./start_llama_jobs.sh

# 交互式登入计算节点（不分配 GPU，排队更快）
./start_llama_jobs.sh --login

# 停止作业并清理生成文件
./stop_llama_jobs.sh

# 强制清理所有作业（含残留记录）
./clean_jobs_force.sh

# 查看作业状态
jjobs

# 查看资源报告
cat ~/llama_server_status.txt
```

## 使用模式

| 命令 | 说明 |
|------|------|
| `./start_llama_jobs.sh` | 提交批处理作业，后台运行 llama-server |
| `./start_llama_jobs.sh --login` | 交互式登入计算节点（不分配 GPU），用于调试 |
| `./stop_llama_jobs.sh` | 停止 llama_server 作业，清理生成文件，保留配置 |
| `./clean_jobs_force.sh` | 强制清理所有作业记录，持续监控直到全部清除 |

**login 模式**不申请 GPU，只申请 1 个 CPU 核心，排队很快。登上后可手动 `bash job.txt` 启动服务。

## 配置文件 (llama_server.cfg)

配置文件包含 7 个参数，缺失时自动补全并重写。

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `API_TOKEN` | 自动生成 | API 访问密钥 |
| `QUEUE` | `gpu3` | 作业队列 |
| `NODE` | `gpu07` | 计算节点 |
| `MODEL` | `Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf` | 模型文件名 |
| `CUDA_LIB64` | `/public/home/10201401498/cuda-12.2/lib64` | CUDA lib64 目录 |
| `LLAMA_MODELS_HOME` | `models` | 模型文件目录 |
| `LLAMA_SERVER_BIN` | `llama.cpp-master/build/bin` | llama-server 二进制目录 |

> GCC 通过 `module avail` 自动检测最高版本并 `module load`，无需手动配置。

### 自动检测参数（不写入配置文件）

| 参数 | 默认行为 | 说明 |
|------|----------|------|
| `NGL` | `auto` | GPU 卸载层数：基于 VRAM 和模型大小自动计算 |
| `CONTEXT` | `auto` | Context 长度：基于剩余 VRAM 按档位分配 |
| `BATCH` | `1024` | 批处理大小 |
| `CORES` | `4` | 申请 CPU 核心数 |
| `MODEL_LAYERS` | `auto` | 模型层数：GGUF 元数据 → fallback 99 |

### 手动覆盖

如需覆盖自动检测，在配置文件中添加：

```bash
NGL=99
CONTEXT=8192
CORES=8
```

## 作业脚本 (job.txt)

每次提交时自动生成，包含完整执行流程：

1. JSUB 调度参数
2. 环境配置（自动检测最高 GCC + CUDA lib64）
3. 资源自动检测（GPU、CPU、内存）
4. 模型层数检测（GGUF 元数据 → fallback 99）
5. NGL / Context 自动计算
6. llama-server 启动命令

### 调试模式

`KEEP_JOB_FILE` 控制是否保留 `job.txt`：

```bash
KEEP_JOB_FILE=true   # 调试阶段
KEEP_JOB_FILE=false  # 生产环境
```

## 资源自动检测

| 检测项 | 方式 | 用途 |
|--------|------|------|
| GPU 型号/VRAM | `nvidia-smi` | 选空闲最多的 GPU，计算 NGL 和 Context |
| CPU 核心数 | `JSUB_SLOT` → cgroup → `nproc` | 设置线程数 |
| 系统内存 | `/proc/meminfo` | 记录到状态文件 |
| 模型文件大小 | `stat` | 计算 NGL 比例 |
| 模型层数 | GGUF 元数据 → fallback 99 | NGL 计算基础 |
| GCC 版本 | `module avail` | 自动检测最高版本 |

### NGL 自动计算

- VRAM 能放整个模型 → `NGL=99`
- VRAM 不足 → 按比例计算 GPU 层数
- 无法检测 → 默认 `99`

### Context 自动计算

| 剩余 VRAM | Context |
|-----------|---------|
| > 12 GB | 8192 |
| > 4 GB | 4096 |
| > 1 GB | 2048 |
| < 1 GB | 1024 |

## 状态文件 (~/llama_server_status.txt)

作业启动后自动写入，包含配置参数和资源检测结果：

```
# --- 配置参数 ---
API_TOKEN=llama_xxx...
QUEUE=gpu3
NODE=gpu07
MODEL=Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf
CUDA_LIB64=/public/home/10201401498/cuda-12.2/lib64
LLAMA_MODELS_HOME=/public/home/10201401498/models
LLAMA_SERVER_BIN=/public/home/10201401498/llama.cpp-master/build/bin

# --- 资源检测结果 ---
GPU_NAME=NVIDIA A100-PCIE-40GB
GPU_TOTAL_VRAM_MiB=40960
MODEL_LAYERS=48
NGL=99
CONTEXT=4096
API_URL=http://10.0.0.1:8080
HEALTH_URL=http://10.0.0.1:8080/health
STATUS=starting
```

状态：`starting` → 启动中 / `stopped` → 已停止

## 常用操作

```bash
./start_llama_jobs.sh              # 提交作业
./start_llama_jobs.sh --login      # 登入计算节点
./stop_llama_jobs.sh               # 停止作业 + 清理文件
./clean_jobs_force.sh              # 强制清理所有作业记录
jjobs                              # 查看作业状态
cat ~/llama_server_status.txt      # 查看资源报告
curl http://<节点IP>:8080/health    # 健康检查
vi llama_server.cfg                # 修改配置
```

## API 调用

```bash
curl http://<节点IP>:8080/v1/chat/completions \
  -H "Authorization: Bearer <API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-coder",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 256
  }'
```

API_TOKEN 在 `llama_server.cfg` 中查看，节点 IP 在状态文件的 `API_URL` 中查看。

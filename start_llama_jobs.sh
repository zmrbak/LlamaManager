#!/bin/bash
# start_llama_jobs.sh - 启动 Llama Server 作业
# 用法:
#   ./start_llama_jobs.sh          → 提交批处理作业（默认）
#   ./start_llama_jobs.sh --login  → 交互式登入计算节点（不分配 GPU）
#
# 配置文件包含：API_TOKEN / QUEUE / NODE / MODEL / CUDA_LIB64 / LLAMA_MODELS_HOME / LLAMA_SERVER_BIN
# NGL / CONTEXT / BATCH / MODEL_LAYERS 全部在计算节点自动检测

# ==========================================
# 命令行参数解析
# ==========================================
MODE="submit"
if [ "$1" = "--login" ] || [ "$1" = "-l" ]; then
    MODE="login"
fi

echo "=========================================="
echo "启动 Llama Server 作业"
echo "时间: $(date)"
echo "=========================================="

# ==========================================
# 调试模式开关
# KEEP_JOB_FILE=true  → 保留 job.txt（调试阶段）
# KEEP_JOB_FILE=false → 提交后自动删除（生产环境）
# ==========================================
KEEP_JOB_FILE=true

# ==========================================
# 配置文件
# ==========================================
CONFIG_FILE="llama_server.cfg"
JOB_FILE="job.txt"
STATUS_FILE="$HOME/llama_server_status.txt"

# 默认值（仅用于配置文件生成和未设置时的 fallback）
DEFAULT_QUEUE="gpu3"
DEFAULT_NODE="gpu07"
DEFAULT_MODEL="Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"
DEFAULT_CORES="4"
DEFAULT_CUDA_LIB64="$HOME/cuda-12.2/lib64"
DEFAULT_LLAMA_SERVER_BIN="$HOME/llama.cpp-master/build/bin"
DEFAULT_LLAMA_MODELS_HOME="$HOME/models"

# 配置文件模板（用于首次创建和补全重写）
write_config() {
    cat > "$CONFIG_FILE" << CONF
# Llama Server 配置文件
# auto 参数（NGL, CONTEXT, BATCH, MODEL_LAYERS）在计算节点自动检测，无需配置
# 如需强制覆盖，可手动添加:
#   NGL=99
#   CONTEXT=32768
#   BATCH=1024
#   MODEL_LAYERS=48

API_TOKEN=$1
QUEUE=$2
NODE=$3
MODEL=$4
CUDA_LIB64=$5
LLAMA_MODELS_HOME=$6
LLAMA_SERVER_BIN=$7
CONF
}

# 展开路径：~/ → $HOME，相对路径 → $HOME/相对，绝对路径 → 不变
expand_path() {
    local p="$1"
    if [[ "$p" == ~* ]]; then
        echo "${p/#\~/$HOME}"
    elif [[ "$p" == /* ]]; then
        echo "$p"
    else
        echo "$HOME/$p"
    fi
}

if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件不存在，创建默认配置..."
    API_TOKEN="llama_$(date +%s)_$(openssl rand -hex 16)"
    write_config "$API_TOKEN" "$DEFAULT_QUEUE" "$DEFAULT_NODE" "$DEFAULT_MODEL" "$DEFAULT_CUDA_LIB64" "$DEFAULT_LLAMA_MODELS_HOME" "$DEFAULT_LLAMA_SERVER_BIN"
    echo "已创建: $CONFIG_FILE"
    echo "  API_TOKEN: ${API_TOKEN:0:20}..."
    echo "  QUEUE: $DEFAULT_QUEUE"
    echo "  NODE: $DEFAULT_NODE"
    source "$CONFIG_FILE"
else
    echo "读取配置文件: $CONFIG_FILE"
    source "$CONFIG_FILE"

    # 兼容旧配置
    if [ -z "$MODEL" ] && [ -n "$MODEL_PATH" ]; then
        MODEL=$(basename "$MODEL_PATH")
        LLAMA_MODELS_HOME=$(dirname "$MODEL_PATH")
        echo "迁移旧配置: MODEL_PATH → MODEL=$MODEL, LLAMA_MODELS_HOME=$LLAMA_MODELS_HOME"
    fi
    if [ -z "$LLAMA_MODELS_HOME" ] && [ -n "$MODEL_DIR" ]; then
        LLAMA_MODELS_HOME="$MODEL_DIR"
        echo "迁移旧配置: MODEL_DIR → LLAMA_MODELS_HOME=$LLAMA_MODELS_HOME"
    fi

    # 必要参数缺失时补全并重写
    NEED_REWRITE=false
    if [ -z "$API_TOKEN" ]; then
        API_TOKEN="llama_$(date +%s)_$(openssl rand -hex 16)"
        NEED_REWRITE=true
    fi
    if [ -z "$QUEUE" ]; then
        QUEUE="$DEFAULT_QUEUE"
        NEED_REWRITE=true
    fi
    if [ -z "$NODE" ]; then
        NODE="$DEFAULT_NODE"
        NEED_REWRITE=true
    fi
    if [ -z "$MODEL" ]; then
        MODEL="$DEFAULT_MODEL"
        NEED_REWRITE=true
    fi
    if [ -z "$CUDA_LIB64" ]; then
        CUDA_LIB64="$DEFAULT_CUDA_LIB64"
        NEED_REWRITE=true
    fi
    if [ -z "$LLAMA_MODELS_HOME" ]; then
        LLAMA_MODELS_HOME="$DEFAULT_LLAMA_MODELS_HOME"
        NEED_REWRITE=true
    fi
    if [ -z "$LLAMA_SERVER_BIN" ]; then
        LLAMA_SERVER_BIN="$DEFAULT_LLAMA_SERVER_BIN"
        NEED_REWRITE=true
    fi

    if [ "$NEED_REWRITE" = true ]; then
        write_config "$API_TOKEN" "$QUEUE" "$NODE" "$MODEL" "$CUDA_LIB64" "$LLAMA_MODELS_HOME" "$LLAMA_SERVER_BIN"
        echo "已更新配置文件: $CONFIG_FILE (补全了缺失参数)"
    fi
fi

# 可选参数：配置中未设置时使用默认值或 auto
NGL="${NGL:-auto}"
CONTEXT="${CONTEXT:-auto}"
BATCH="${BATCH:-1024}"
MODEL_LAYERS="${MODEL_LAYERS:-auto}"
CORES="${CORES:-$DEFAULT_CORES}"

# 展开所有路径
CUDA_LIB64_EXPANDED=$(expand_path "$CUDA_LIB64")
LLAMA_MODELS_HOME_EXPANDED=$(expand_path "$LLAMA_MODELS_HOME")
LLAMA_SERVER_BIN_EXPANDED=$(expand_path "$LLAMA_SERVER_BIN")
MODEL_PATH_EXPANDED="$LLAMA_MODELS_HOME_EXPANDED/$MODEL"

echo ""
echo "配置信息:"
echo "  API_TOKEN: ${API_TOKEN:0:20}..."
echo "  QUEUE: $QUEUE | NODE: $NODE | CORES: $CORES"
echo "  MODEL: $MODEL → $MODEL_PATH_EXPANDED"
echo "  CUDA_LIB64: $CUDA_LIB64 → $CUDA_LIB64_EXPANDED"
echo "  LLAMA_SERVER_BIN: $LLAMA_SERVER_BIN → $LLAMA_SERVER_BIN_EXPANDED"
echo "  LLAMA_MODELS_HOME: $LLAMA_MODELS_HOME → $LLAMA_MODELS_HOME_EXPANDED"
echo "  NGL: $NGL | CONTEXT: $CONTEXT | BATCH: $BATCH | MODEL_LAYERS: $MODEL_LAYERS"
echo "  (auto 参数将在计算节点自动检测)"
echo "  KEEP_JOB_FILE: $KEEP_JOB_FILE (调试模式)"
echo ""

# ==========================================
# Login 模式：交互式登入计算节点
# ==========================================
if [ "$MODE" = "login" ]; then
    echo "=========================================="
    echo "交互式登入计算节点（不分配 GPU）"
    echo "=========================================="
    echo "命令: jsub -q $QUEUE -m $NODE -n 1 -I /bin/bash"
    echo ""
    exec jsub -q "$QUEUE" -m "$NODE" -n 1 -I /bin/bash
fi

# ==========================================
# 检查是否已有作业在运行
# ==========================================
EXISTING_JOB=$(jjobs -a 2>/dev/null | grep "llama_server" | grep -E "RUN|PEND" | head -1)

if [ -n "$EXISTING_JOB" ]; then
    JOB_ID=$(echo "$EXISTING_JOB" | awk '{print $1}')
    JOB_STAT=$(echo "$EXISTING_JOB" | awk '{print $3}')
    echo "已有 llama_server 作业在运行！"
    echo "   作业号: $JOB_ID | 状态: $JOB_STAT"
    echo "   停止命令: jctrl kill $JOB_ID"
    echo "=========================================="
    exit 1
fi

echo "没有正在运行的 llama_server 作业，可以启动"

# ==========================================
# 获取节点 IP
# ==========================================
if [ -z "$NODE" ]; then
    echo "错误: NODE 未配置"
    exit 1
fi
if [ -z "$QUEUE" ]; then
    echo "错误: QUEUE 未配置"
    exit 1
fi

GPU_IP=$(getent hosts "$NODE" | head -1 | awk '{print $1}')
if [ -z "$GPU_IP" ]; then
    echo "错误: 无法获取 $NODE IP 地址"
    exit 1
fi
echo "$NODE IP: $GPU_IP"
echo ""

# ==========================================
# 生成作业脚本文件
# ==========================================
echo "生成作业脚本: $JOB_FILE"

cat > "$JOB_FILE" << EOF
#!/bin/bash
# Llama Server 作业脚本 — 由 start_llama_jobs.sh 自动生成
# 可直接在计算节点上执行: bash job.txt
# ==========================================
#JSUB -q $QUEUE
#JSUB -m $NODE
#JSUB -gpgpu 1
#JSUB -n $CORES
#JSUB -o llama_server.%J.out
#JSUB -e llama_server.%J.err
#JSUB -J llama_server

# GCC 和 CUDA 环境设置
# 自动检测最高版本 GCC 并加载
GCC_VERSION=\$(module avail 2>&1 | grep -oE 'gcc/gcc-[0-9]+\\.[0-9]+\\.[0-9]+' | sort -V | tail -1)
if [ -n "\$GCC_VERSION" ]; then
    echo "加载 GCC: \$GCC_VERSION"
    module load "\$GCC_VERSION"
else
    echo "警告: 未检测到可用 GCC，尝试加载 gcc/gcc-11.4.0"
    module load gcc/gcc-11.4.0
fi
export LD_LIBRARY_PATH=$CUDA_LIB64_EXPANDED:\$LD_LIBRARY_PATH

# ==========================================
# 资源自动检测
# ==========================================
echo "=========================================="
echo "资源检测"
echo "=========================================="

# --- GPU 检测 ---
GPU_COUNT=\$(nvidia-smi -L | wc -l)
echo "GPU 数量: \$GPU_COUNT"

SELECTED_GPU=\$(nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits | sort -t',' -k2 -rn | head -1 | cut -d',' -f1 | tr -d ' ')
export CUDA_VISIBLE_DEVICES=\$SELECTED_GPU

GPU_NAME=\$(nvidia-smi --query-gpu=name --format=csv,noheader -i \$SELECTED_GPU | tr -d ' ')
GPU_TOTAL_VRAM=\$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits -i \$SELECTED_GPU | tr -d ' ')
GPU_FREE_VRAM=\$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i \$SELECTED_GPU | tr -d ' ')

echo "选中 GPU: \$SELECTED_GPU (\$GPU_NAME)"
echo "GPU 总 VRAM: \$GPU_TOTAL_VRAM MiB"
echo "GPU 空闲 VRAM: \$GPU_FREE_VRAM MiB"

# --- 本节点 IP ---
GPU_IP_LOCAL=\$(hostname -I | awk '{print \$1}')
echo "本节点 IP: \$GPU_IP_LOCAL"

# --- CPU 检测 ---
if [ -n "\$JSUB_SLOT" ]; then
    TOTAL_CPUS=\$JSUB_SLOT
elif [ -f /sys/fs/cgroup/cpu.max ]; then
    CGROUP_MAX=\$(head -1 /sys/fs/cgroup/cpu.max)
    CGROUP_PERIOD=\$(tail -1 /sys/fs/cgroup/cpu.max)
    if [ "\$CGROUP_MAX" != "max" ] && [ "\$CGROUP_MAX" != "-1" ]; then
        TOTAL_CPUS=\$((CGROUP_MAX / CGROUP_PERIOD))
    else
        TOTAL_CPUS=\$(nproc)
    fi
elif [ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
    QUOTA=\$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
    PERIOD=\$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
    if [ "\$QUOTA" != "-1" ]; then
        TOTAL_CPUS=\$((QUOTA / PERIOD))
    else
        TOTAL_CPUS=\$(nproc)
    fi
else
    TOTAL_CPUS=\$(nproc)
fi

THREADS=\$((TOTAL_CPUS - 1))
if [ \$THREADS -lt 1 ]; then THREADS=1; fi
echo "CPU 核心数: \$TOTAL_CPUS (分配给 llama-server: \$THREADS)"

# --- 内存检测 ---
TOTAL_MEM_GB=\$(awk '/MemTotal/ {printf "%.0f", \$2/1024/1024}' /proc/meminfo)
AVAIL_MEM_GB=\$(awk '/MemAvailable/ {printf "%.0f", \$2/1024/1024}' /proc/meminfo)
echo "系统总内存: \$TOTAL_MEM_GB GB | 可用: \$AVAIL_MEM_GB GB"

# --- 模型文件 ---
MODEL_FILE="$MODEL_PATH_EXPANDED"
if [ -f "\$MODEL_FILE" ]; then
    MODEL_SIZE_BYTES=\$(stat -c%s "\$MODEL_FILE" 2>/dev/null || stat -f%z "\$MODEL_FILE" 2>/dev/null || echo 0)
    MODEL_SIZE_MB=\$((MODEL_SIZE_BYTES / 1024 / 1024))
    echo "模型文件: \$MODEL_SIZE_MB MB"
else
    MODEL_SIZE_MB=0
    echo "警告: 模型文件不存在: \$MODEL_FILE"
fi

# ==========================================
# 模型层数自动检测
# ==========================================
MODEL_LAYERS_CONFIG="$MODEL_LAYERS"
if [ "\$MODEL_LAYERS_CONFIG" = "auto" ]; then
    echo "检测模型层数..."

    # 从 GGUF 元数据解析
    GGUF_LAYERS=0
    PY_CMD=""
    command -v python3 >/dev/null 2>&1 && PY_CMD=python3
    [ -z "\$PY_CMD" ] && command -v python >/dev/null 2>&1 && PY_CMD=python

    if [ -n "\$PY_CMD" ] && [ -f "\$MODEL_FILE" ]; then
        GGUF_LAYERS=\$(\$PY_CMD -c "
import struct,sys
try:
    f=open(sys.argv[1],'rb')
    if f.read(4)!=b'GGUF': raise ValueError
    f.read(4);f.read(8)
    nkv=struct.unpack('<Q',f.read(8))[0]
    TS={0:None,1:4,2:4,3:4,4:4,5:4,6:4,7:4,8:8,9:8,10:8}
    FM={4:'<I',5:'<i',8:'<Q',9:'<q',1:'<I',2:'<I',3:'<i',7:'<I',6:'<f',10:'<d'}
    for _ in range(nkv):
        kl=struct.unpack('<Q',f.read(8))[0]
        k=f.read(kl).decode('utf-8',errors='ignore').rstrip(chr(0))
        vt=struct.unpack('<I',f.read(4))[0]
        if vt==0:
            vl=struct.unpack('<Q',f.read(8))[0];f.read(vl)
        elif vt==11:
            f.read(4);ne=struct.unpack('<Q',f.read(8))[0]
            f.read(ne*4)
        elif vt in TS and TS[vt]:
            d=f.read(TS[vt])
            if 'block_count' in k or 'n_layer' in k:
                print(int(struct.unpack(FM.get(vt,'<I'),d)[0]))
                f.close();sys.exit(0)
        else:
            break
    f.close()
except:
    pass
print(0)
" "\$MODEL_FILE" 2>/dev/null || echo 0)
    fi

    if [ "\$GGUF_LAYERS" -gt 0 ] 2>/dev/null; then
        FINAL_MODEL_LAYERS=\$GGUF_LAYERS
        echo "模型层数: \$FINAL_MODEL_LAYERS (GGUF 元数据检测)"
    else
        FINAL_MODEL_LAYERS=99
        echo "模型层数: 99 (llama-server 自动调整)"
    fi
else
    FINAL_MODEL_LAYERS=\$MODEL_LAYERS_CONFIG
    echo "模型层数: \$FINAL_MODEL_LAYERS (配置指定)"
fi

# ==========================================
# NGL 自动计算
# ==========================================
NGL_CONFIG="$NGL"
if [ "\$NGL_CONFIG" = "auto" ]; then
    AVAIL_FOR_MODEL=\$((GPU_FREE_VRAM - 500))
    if [ \$AVAIL_FOR_MODEL -lt 0 ]; then AVAIL_FOR_MODEL=0; fi

    if [ \$MODEL_SIZE_MB -gt 0 ] && [ \$MODEL_SIZE_MB -le \$AVAIL_FOR_MODEL ]; then
        FINAL_NGL=99
        echo "NGL: VRAM 足够 → 99 (全部 \$FINAL_MODEL_LAYERS 层卸载到 GPU)"
    elif [ \$MODEL_SIZE_MB -gt 0 ] && [ \$FINAL_MODEL_LAYERS -lt 99 ]; then
        SIZE_PER_LAYER=\$((MODEL_SIZE_MB / FINAL_MODEL_LAYERS))
        FINAL_NGL=\$((AVAIL_FOR_MODEL / SIZE_PER_LAYER))
        if [ \$FINAL_NGL -lt 1 ]; then FINAL_NGL=1; fi
        if [ \$FINAL_NGL -gt 99 ]; then FINAL_NGL=99; fi
        echo "NGL: VRAM 不足全量卸载 → \$FINAL_NGL (\$((FINAL_MODEL_LAYERS - FINAL_NGL)) 层留在 CPU)"
    else
        FINAL_NGL=99
        echo "NGL: 默认 99 (llama-server 自动调整)"
    fi
else
    FINAL_NGL=\$NGL_CONFIG
    echo "NGL: 使用配置值 \$FINAL_NGL"
fi

# ==========================================
# Context 自动计算
# ==========================================
CONTEXT_CONFIG="$CONTEXT"
if [ "\$CONTEXT_CONFIG" = "auto" ]; then
    if [ \$FINAL_NGL -ge 99 ] || [ \$FINAL_NGL -ge \$FINAL_MODEL_LAYERS ]; then
        MODEL_ON_GPU_MB=\$MODEL_SIZE_MB
    else
        MODEL_ON_GPU_MB=\$((MODEL_SIZE_MB * FINAL_NGL / FINAL_MODEL_LAYERS))
    fi

    REMAINING_VRAM=\$((GPU_FREE_VRAM - MODEL_ON_GPU_MB - 500))
    echo "模型 GPU 占用估算: \$MODEL_ON_GPU_MB MiB, 剩余: \$REMAINING_VRAM MiB"

    # 每token约2bytes(KV cache), ~2 tokens/MiB for Q4, 留2GB安全余量
    SAFE_VRAM=\$((REMAINING_VRAM - 2000))
    if [ \$SAFE_VRAM -gt 0 ]; then
        FINAL_CONTEXT=\$((SAFE_VRAM * 2))
        # 模型上限保护: Qwen3-Coder-30B-A3B 最大支持 256K (262144)
        if [ \$FINAL_CONTEXT -gt 262144 ]; then
            FINAL_CONTEXT=262144
        fi
    else
        FINAL_CONTEXT=1024
        echo "警告: 剩余 VRAM 极少, context 降至 1024"
    fi
    echo "Context: 基于 VRAM → \$FINAL_CONTEXT tokens"
else
    FINAL_CONTEXT=\$CONTEXT_CONFIG
    echo "Context: 使用配置值 \$FINAL_CONTEXT"
fi

FINAL_BATCH=$BATCH
echo "Batch: \$FINAL_BATCH"

echo ""
echo "=========================================="
echo "最终启动参数"
echo "=========================================="
echo "模型: \$MODEL_FILE (\$MODEL_SIZE_MB MB)"
echo "GPU: \$SELECTED_GPU (\$GPU_NAME, \$GPU_TOTAL_VRAM MiB 总 / \$GPU_FREE_VRAM MiB 空闲)"
echo "层数: \$FINAL_NGL / \$FINAL_MODEL_LAYERS"
echo "Context: \$FINAL_CONTEXT | Threads: \$THREADS | Batch: \$FINAL_BATCH"
echo "Flash Attention: on"
echo "=========================================="

# ==========================================
# 写入状态文件（NFS 共享，登录节点可读）
# ==========================================
cat > "$STATUS_FILE" << STATUS
# llama_server 状态（自动生成）
# 更新时间: \$(date)

# --- 配置参数 ---
API_TOKEN=$API_TOKEN
QUEUE=$QUEUE
NODE=$NODE
MODEL=$MODEL
CUDA_LIB64=$CUDA_LIB64_EXPANDED
LLAMA_MODELS_HOME=$LLAMA_MODELS_HOME_EXPANDED
LLAMA_SERVER_BIN=$LLAMA_SERVER_BIN_EXPANDED

# --- 资源检测结果 ---
JOB_HOST=$NODE
JOB_QUEUE=$QUEUE
GPU_SELECTED=\$SELECTED_GPU
GPU_NAME=\$GPU_NAME
GPU_TOTAL_VRAM_MiB=\$GPU_TOTAL_VRAM
GPU_FREE_VRAM_MiB=\$GPU_FREE_VRAM
CPU_CORES=\$TOTAL_CPUS
CPU_THREADS=\$THREADS
MEMORY_TOTAL_GB=\$TOTAL_MEM_GB
MEMORY_AVAIL_GB=\$AVAIL_MEM_GB
MODEL=$MODEL
MODEL_SIZE_MB=\$MODEL_SIZE_MB
MODEL_LAYERS=\$FINAL_MODEL_LAYERS
NGL=\$FINAL_NGL
CONTEXT=\$FINAL_CONTEXT
BATCH=\$FINAL_BATCH
API_URL=http://\$GPU_IP_LOCAL:8080
HEALTH_URL=http://\$GPU_IP_LOCAL:8080/health
STATUS=starting
STATUS

# ==========================================
# 启动 Llama Server
# ==========================================
$LLAMA_SERVER_BIN_EXPANDED/llama-server \\
    -m "\$MODEL_FILE" \\
    -ngl \$FINAL_NGL \\
    -c \$FINAL_CONTEXT \\
    -t \$THREADS \\
    -b \$FINAL_BATCH \\
    --flash-attn on \\
    --host 0.0.0.0 \\
    --port 8080 \\
    --log-file llama_server.log \\
    --api-key $API_TOKEN

# llama-server 退出后更新状态
if [ -f "$STATUS_FILE" ]; then
    sed -i 's/STATUS=starting/STATUS=stopped/' "$STATUS_FILE" 2>/dev/null
fi
EOF

echo "已生成: $JOB_FILE"

# ==========================================
# 提交作业
# ==========================================
echo "提交作业..."
SUBMIT_OUTPUT=$(jsub < "$JOB_FILE" 2>&1)
echo "$SUBMIT_OUTPUT"

JOB_ID=$(echo "$SUBMIT_OUTPUT" | grep -oE 'Job <[0-9]+>' | grep -oE '[0-9]+' | head -1)

if [ "$KEEP_JOB_FILE" = false ]; then
    rm -f "$JOB_FILE"
    echo "已删除临时作业文件: $JOB_FILE"
else
    echo "调试模式: 保留 $JOB_FILE"
fi

echo ""
echo "=========================================="
echo "作业提交完成！"
echo ""
echo "API 地址: http://$GPU_IP:8080"
echo "队列: $QUEUE | 节点: $NODE | 作业号: $JOB_ID"
echo ""

# ==========================================
# 健康检查：先等作业从 PEND → RUN，再 curl
# ==========================================
HEALTH_URL="http://$GPU_IP:8080/health"

# 第一步：等待作业从 PEND 变为 RUN
echo "等待作业从排队进入运行..."
PEND_MAX=600  # 最多等 10 分钟排队
PEND_WAITED=0
while [ $PEND_WAITED -lt $PEND_MAX ]; do
    JOB_STAT=$(jjobs "$JOB_ID" 2>/dev/null | awk 'NR==2{print $3}')
    if [ "$JOB_STAT" = "RUN" ]; then
        echo "作业已开始运行！"
        break
    elif [ "$JOB_STAT" = "EXIT" ] || [ "$JOB_STAT" = "DONE" ]; then
        echo "注意: 作业状态为 $JOB_STAT，可能启动失败"
        echo "查看错误: cat llama_server.${JOB_ID}.err"
        echo "查看输出: cat llama_server.${JOB_ID}.out"
        break
    fi
    sleep 5
    PEND_WAITED=$((PEND_WAITED + 5))
    echo "  排队中... ($PEND_WAITED/$PEND_MAX 秒) 状态: ${JOB_STAT:-未知}"
done

if [ "$JOB_STAT" != "RUN" ]; then
    echo "作业未进入运行状态（当前: ${JOB_STAT:-未知}），跳过健康检查"
    echo "等作业变为 RUN 后手动测试: curl $HEALTH_URL"
else
    # 第二步：作业已在运行，等待服务就绪（模型加载需要时间）
    echo "等待服务就绪（模型加载中）..."
    RUN_MAX=180  # 最多等 3 分钟加载模型
    RUN_WAITED=0
    while [ $RUN_WAITED -lt $RUN_MAX ]; do
        if curl -s --max-time 3 "$HEALTH_URL" > /dev/null 2>&1; then
            echo "服务已就绪！健康检查: $HEALTH_URL"
            break
        fi
        sleep 3
        RUN_WAITED=$((RUN_WAITED + 3))
        echo "  加载中... ($RUN_WAITED/$RUN_MAX 秒)"
    done

    if [ $RUN_WAITED -ge $RUN_MAX ]; then
        echo "注意: 服务启动超时（$RUN_MAX 秒），请手动检查"
        echo "  curl $HEALTH_URL"
        echo "  tail -20 llama_server.${JOB_ID}.out"
    fi
fi

echo ""
echo "--- 检查方式 ---"
echo "作业状态:   jjobs $JOB_ID"
echo "启动日志:   tail -f llama_server.${JOB_ID}.out"
echo "资源报告:   cat $STATUS_FILE"
echo "健康检查:   curl http://$GPU_IP:8080/health"
echo ""
echo "--- 停止作业 ---"
echo "jctrl kill $JOB_ID"
echo ""
echo "修改配置: vi $CONFIG_FILE"
echo "=========================================="

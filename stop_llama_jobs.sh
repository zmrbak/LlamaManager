#!/bin/bash
# stop_llama_jobs.sh - 停止 Llama Server 作业并清理生成文件
# 用法: ./stop_llama_jobs.sh

CONFIG_FILE="llama_server.cfg"
STATUS_FILE="$HOME/llama_server_status.txt"
JOB_FILE="job.txt"

echo "=========================================="
echo "停止 Llama Server 作业"
echo "时间: $(date)"
echo "=========================================="

# ==========================================
# 1. 停止作业
# ==========================================
JOB_INFO=$(jjobs -a 2>/dev/null | grep "llama_server" | head -1)

if [ -n "$JOB_INFO" ]; then
    JOB_ID=$(echo "$JOB_INFO" | awk '{print $1}')
    JOB_STAT=$(echo "$JOB_INFO" | awk '{print $3}')
    echo "发现作业: $JOB_ID (状态: $JOB_STAT)"

    if [ "$JOB_STAT" = "RUN" ] || [ "$JOB_STAT" = "PEND" ]; then
        echo "停止作业: jctrl kill $JOB_ID"
        jctrl kill "$JOB_ID"
        # 等待作业状态变为 DONE/EXIT
        for i in $(seq 1 6); do
            sleep 1
            CUR_STAT=$(jjobs "$JOB_ID" 2>/dev/null | awk 'NR==2{print $3}')
            if [ "$CUR_STAT" = "DONE" ] || [ "$CUR_STAT" = "EXIT" ]; then
                echo "作业已停止 (状态: $CUR_STAT)"
                break
            fi
        done
    fi

    echo "删除作业记录: jctrl clean $JOB_ID"
    jctrl clean "$JOB_ID" 2>/dev/null
    echo "已删除作业记录"
else
    echo "没有 llama_server 作业"
fi

# ==========================================
# 2. 清理生成文件（保留 llama_server.cfg）
# ==========================================
echo ""
echo "清理生成文件..."

# job.txt
if [ -f "$JOB_FILE" ]; then
    rm -f "$JOB_FILE"
    echo "  已删除: $JOB_FILE"
fi

# 状态文件
if [ -f "$STATUS_FILE" ]; then
    rm -f "$STATUS_FILE"
    echo "  已删除: $STATUS_FILE"
fi

# 作业输出日志 llama_server.<JOBID>.out / .err
for f in llama_server.*.out llama_server.*.err; do
    if [ -f "$f" ]; then
        rm -f "$f"
        echo "  已删除: $f"
    fi
done

# llama-server 运行日志
if [ -f "llama_server.log" ]; then
    rm -f "llama_server.log"
    echo "  已删除: llama_server.log"
fi

echo ""
echo "保留配置文件: $CONFIG_FILE"
echo "=========================================="
echo "完成"

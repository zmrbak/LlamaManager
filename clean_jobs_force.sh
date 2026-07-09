#!/bin/bash
# clean_jobs_force.sh - 强制清理所有作业并持续监控

echo "=========================================="
echo "强制清理所有作业"
echo "时间: $(date)"
echo "=========================================="

# 获取所有作业号（包括已完成）
ALL_JOBS=$(jjobs -a 2>&1 | awk 'NR>1 && !/No job found/ {print $1}')

if [ -z "$ALL_JOBS" ]; then
    echo "没有找到任何作业"
    exit 0
fi

echo "找到作业: $ALL_JOBS"

# 终止所有正在运行或排队的作业
echo ""
echo ">>> 终止所有活跃作业..."
for job in $ALL_JOBS; do
    # 检查作业状态 - 使用 jjobs -w
    STATUS=$(jjobs -w $job 2>/dev/null | awk 'NR>1 {print $3}')
    case $STATUS in
        RUN|PEND|USUSP|SSUSP|PSUSP)
            echo "  终止作业 $job (状态: $STATUS)"
            jctrl kill -f $job 2>/dev/null
            ;;
        *)
            echo "  跳过作业 $job (状态: $STATUS)"
            ;;
    esac
done

sleep 2

# 清理所有记录
echo ""
echo ">>> 清理所有作业记录..."
for job in $ALL_JOBS; do
    jctrl clean $job 2>/dev/null
done

# 循环等待确认所有作业已清除，并持续kill
echo ""
echo "=========================================="
echo ">>> 监控中，持续清理残留作业..."
echo "=========================================="

COUNT=0
while true; do
    COUNT=$((COUNT + 1))
    echo ""
    echo "[第 $COUNT 次检查] 时间: $(date '+%H:%M:%S')"
    echo "----------------------------------------"
    
    # 获取当前所有作业
    OUTPUT=$(jjobs -a 2>&1)
    echo "$OUTPUT"
    
    # 检查是否有作业
    if echo "$OUTPUT" | grep -q "No job found"; then
        echo ""
        echo "=========================================="
        echo "✅ 所有作业已清理完成！"
        echo "总检查次数: $COUNT"
        echo "完成时间: $(date)"
        echo "=========================================="
        break
    fi
    
    # 获取当前活跃作业（从jjobs -a中提取作业号）
    ACTIVE_JOBS=$(echo "$OUTPUT" | awk 'NR>1 && !/No job found/ {print $1}')
    
    if [ -n "$ACTIVE_JOBS" ]; then
        echo ""
        echo ">>> 发现活跃作业，正在终止..."
        for job in $ACTIVE_JOBS; do
            # 使用 jjobs -w 获取作业状态（更可靠）
            STATUS=$(jjobs -w $job 2>/dev/null | awk 'NR>1 {print $3}')
            echo "  作业 $job 状态: $STATUS"
            
            # 直接终止所有非DONE/EXIT状态的作业
            if [ "$STATUS" != "DONE" ] && [ "$STATUS" != "EXIT" ] && [ -n "$STATUS" ]; then
                echo "  终止作业 $job (状态: $STATUS)"
                jctrl kill -f $job 2>/dev/null
                sleep 1
            elif [ "$STATUS" = "DONE" ] || [ "$STATUS" = "EXIT" ]; then
                echo "  清理作业 $job (状态: $STATUS)"
                jctrl clean $job 2>/dev/null
            else
                # 如果状态获取失败，直接尝试kill
                echo "  尝试终止作业 $job (状态未知)"
                jctrl kill -f $job 2>/dev/null
                sleep 1
            fi
        done
    fi
    
    # 等待5秒后再次检查
    sleep 5
done

rm llama_server.*

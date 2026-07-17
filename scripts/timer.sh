#!/bin/bash
echo "=========================================="
echo "START: $(date)"
START_TIME=$(date +%s)
echo "=========================================="

echo "Waiting for exploration to start..."
sleep 15

live_free() {
python2 - << 'PYEOF' 2>/dev/null
import rospy
from nav_msgs.msg import OccupancyGrid
rospy.init_node('cov_check', anonymous=True, disable_signals=True)
try:
    m = rospy.wait_for_message('/map_merge/map', OccupancyGrid, timeout=15)
    free = sum(1 for c in m.data if c == 0)
    occupied = sum(1 for c in m.data if c == 100)
    unknown = sum(1 for c in m.data if c == -1)
    total = len(m.data)
    print("{} {} {} {}".format(free, occupied, unknown, total))
except Exception:
    print("ERR")
PYEOF
}

PREV_FREE=0
STABLE_COUNT=0
STABLE_THRESHOLD=3
STABLE_START_TIME=0
COVERAGE_THRESHOLD=96.0

while true; do
    sleep 10
    ELAPSED=$(( $(date +%s) - START_TIME ))
    
    RESULT=$(live_free)
    
    if [ "$RESULT" = "ERR" ] || [ -z "$RESULT" ]; then
        echo "Map read failed, skipping."
        continue
    fi
    
    FREE=$(echo $RESULT | awk '{print $1}')
    OCCUPIED=$(echo $RESULT | awk '{print $2}')
    UNKNOWN=$(echo $RESULT | awk '{print $3}')
    TOTAL=$(echo $RESULT | awk '{print $4}')
    
    COV=$(python2 -c "
free=$FREE; occ=$OCCUPIED; unk=$UNKNOWN; total=$TOTAL
known = free + occ
pct = 100.0 * known / total if total > 0 else 0
free_pct = 100.0 * free / total if total > 0 else 0
print('{:.1f} {:.1f}'.format(pct, free_pct))
")
    
    KNOWN_PCT=$(echo $COV | awk '{print $1}')
    FREE_PCT=$(echo $COV | awk '{print $2}')
    FREE_INCREASE=$((FREE - PREV_FREE))
    
    echo "----------------------------------------"
    echo "Time elapsed:    ${ELAPSED} seconds ($((ELAPSED/60))m $((ELAPSED%60))s)"
    echo "Current time:    $(date)"
    echo "Free cells:      ${FREE} (change: +${FREE_INCREASE})"
    echo "Occupied cells:  ${OCCUPIED}"
    echo "Unknown cells:   ${UNKNOWN}"
    echo "Map coverage:    ${KNOWN_PCT}%"
    echo "Free space:      ${FREE_PCT}%"
    
    # Check if coverage threshold reached
    COVERAGE_MET=$(python2 -c "print('yes' if $KNOWN_PCT >= $COVERAGE_THRESHOLD else 'no')")
    
    if [ "$COVERAGE_MET" = "yes" ]; then
        if [ "$STABLE_COUNT" -eq 0 ]; then
            STABLE_START_TIME=$(date +%s)
            echo "Coverage threshold ${COVERAGE_THRESHOLD}% reached at: $(date)"
        fi
        STABLE_COUNT=$((STABLE_COUNT + 1))
        echo "Stable count: ${STABLE_COUNT}/${STABLE_THRESHOLD}"
    elif [ "$FREE_INCREASE" -le 50 ]; then
        if [ "$STABLE_COUNT" -eq 0 ]; then
            STABLE_START_TIME=$(date +%s)
            echo "Map stopped changing at: $(date)"
        fi
        STABLE_COUNT=$((STABLE_COUNT + 1))
        echo "Stable count: ${STABLE_COUNT}/${STABLE_THRESHOLD}"
    else
        STABLE_COUNT=0
        STABLE_START_TIME=0
    fi
    
    if [ "$STABLE_COUNT" -ge "$STABLE_THRESHOLD" ]; then
        END_TIME=$(date +%s)
        ACTUAL_DONE_TIME=$((STABLE_START_TIME - START_TIME))
        TOTAL_DURATION=$((END_TIME - START_TIME))
        echo "=========================================="
        echo "Exploration Complete!"
        echo "START: $(date -d @$START_TIME)"
        echo "END:   $(date)"
        echo ""
        echo "Map done at:     $(date -d @$STABLE_START_TIME)"
        echo "Actual exploration time: ${ACTUAL_DONE_TIME} seconds"
        echo "That is $((ACTUAL_DONE_TIME/60)) minutes and $((ACTUAL_DONE_TIME%60)) seconds"
        echo ""
        echo "Total script time: ${TOTAL_DURATION} seconds"
        echo "Final coverage:  ${KNOWN_PCT}%"
        echo "Final free:      ${FREE} cells (${FREE_PCT}%)"
        echo "Final occupied:  ${OCCUPIED} cells"
        echo "Final unknown:   ${UNKNOWN} cells"
        echo "=========================================="
        break
    fi
    
    PREV_FREE=$FREE
done

#!/bin/bash
# synth_check.sh

PART="xc7a35tcpg236-1"   # 파트 변경
TOP="distributed_fifo"
SRC="./distributed_fifo.v"

# 임시 TCL 생성
cat > /tmp/synth_check.tcl << 'EOF'
read_verilog $::env(SRC)
synth_design -top $::env(TOP) -part $::env(PART) -mode out_of_context

set bram_cells [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}]
set lut_ram    [get_cells -hierarchical -filter {REF_NAME =~ RAM*}]

if {[llength $bram_cells] > 0} {
    puts "RESULT:BRAM:[llength $bram_cells]"
    foreach cell $bram_cells {
        puts "  CELL:[get_property REF_NAME [get_cells $cell]]"
    }
} elseif {[llength $lut_ram] > 0} {
    puts "RESULT:LUTRAM:[llength $lut_ram]"
} else {
    puts "RESULT:NONE"
}
EOF

# 환경변수로 넘기기
export PART TOP SRC

# Vivado 실행 & 결과 파싱
OUTPUT=$(vivado -mode batch -source /tmp/synth_check.tcl 2>&1)

echo "=== 합성 결과 ==="
if echo "$OUTPUT" | grep -q "RESULT:BRAM"; then
    COUNT=$(echo "$OUTPUT" | grep "RESULT:BRAM" | cut -d: -f3)
    echo "✅ BRAM 합성 성공! (${COUNT}개)"
    echo "$OUTPUT" | grep "CELL:" | sed 's/CELL:/  - /'
elif echo "$OUTPUT" | grep -q "RESULT:LUTRAM"; then
    echo "⚠️  LUT-RAM으로 합성됨 (async read 때문일 가능성 높음)"
elif echo "$OUTPUT" | grep -q "RESULT:NONE"; then
    echo "❌ RAM 셀 없음 — FF/LUT으로 풀림"
else
    echo "💥 합성 에러 발생"
    echo "$OUTPUT" | grep -i "error"
fi

# 로그 저장
echo "$OUTPUT" > synth_log.txt
echo "전체 로그: synth_log.txt"
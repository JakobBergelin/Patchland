#!/usr/bin/env bash
# Runs the bot sim in parallel (--nofail) for both bots and prints per-round
# percentiles next to the current goals. Usage (from the project folder):
#   GODOT=/path/to/Godot_console.exe tests/balance.sh [procs] [runs_per_proc]
set -u
GODOT="${GODOT:-godot}"
PROCS="${1:-6}"
RUNS="${2:-3}"
OUT="$(mktemp -d)"
for bot in ${BOTS:-greedy casual}; do
  for p in $(seq 1 "$PROCS"); do
    "$GODOT" --headless --path . -s res://tests/run_sim.gd -- --bot "$bot" --nofail --runs "$RUNS" --seed $((p * 100)) > "$OUT/$bot-$p.txt" 2>&1 &
  done
done
wait
GOALS=$(grep -o 'const GOALS := \[.*\]' core/defs.gd | sed 's/.*\[//; s/\]//; s/ //g')
for bot in ${BOTS:-greedy casual}; do
  echo "== $bot bot ($((PROCS * RUNS)) runs, playing on after misses)"
  grep -h "^SCORES $bot " "$OUT"/$bot-*.txt | awk -v goals="$GOALS" '
    { split($3, s, ","); for (i = 1; i <= length(s); i++) v[i][++n[i]] = s[i] + 0 }
    END {
      split(goals, g, ",")
      printf "%-6s %10s %10s %10s %10s %8s\n", "round", "goal", "p25", "median", "p75", "clear%"
      for (i = 1; i <= length(g); i++) {
        m = n[i]; delete a
        for (j = 1; j <= m; j++) a[j] = v[i][j]
        asort(a)
        c = 0; for (j = 1; j <= m; j++) if (a[j] >= g[i]) c++
        printf "%-6d %10d %10d %10d %10d %7.0f%%\n", i, g[i], a[int(m * .25) + 1], a[int(m * .5) + 1], a[int(m * .75) + 1], 100 * c / m
      }
    }'
done
grep -h "illegal\|SCRIPT ERROR" "$OUT"/*.txt | head -5
rm -rf "$OUT"

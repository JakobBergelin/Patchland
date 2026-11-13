#!/usr/bin/env bash
# Whole runs (a miss ends the run) for each bot and unlock profile, in parallel.
# Prints win rate and how far runs got. Usage (from the project folder):
#   GODOT=/path/to/Godot_console.exe tests/runs.sh [procs] [runs_per_proc] [season]
set -u
GODOT="${GODOT:-godot}"
PROCS="${1:-4}"
RUNS="${2:-6}"
SEASON="${3:-1}"
OUT="$(mktemp -d)"
for profile in ${PROFILES:-starter mid all}; do
  for bot in greedy casual; do
    for p in $(seq 1 "$PROCS"); do
      "$GODOT" --headless --path . -s res://tests/run_sim.gd -- --bot "$bot" --profile "$profile" --season "$SEASON" --runs "$RUNS" --seed $((p * 1000 + 7)) > "$OUT/$profile-$bot-$p.txt" 2>&1 &
    done
  done
done
wait
echo "Season $SEASON, $((PROCS * RUNS)) runs per line"
for profile in ${PROFILES:-starter mid all}; do
  for bot in greedy casual; do
    grep -h "^run " "$OUT"/$profile-$bot-*.txt | sed 's/.*cleared \([0-9]*\)\/8.*/\1/' | awk -v p="$profile" -v b="$bot" '
      { n++; s += $1; if ($1 == 8) w++; h[$1]++ }
      END { printf "%-8s %-7s wins %3.0f%%  avg rounds cleared %.1f  [", p, b, 100 * w / n, s / n
            for (i = 0; i <= 8; i++) printf "%s%d", (i ? " " : ""), h[i] + 0; print "]" }'
  done
done
grep -h "illegal\|SCRIPT ERROR" "$OUT"/*.txt | head -3
rm -rf "$OUT"

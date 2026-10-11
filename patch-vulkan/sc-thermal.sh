#!/system/bin/sh
# Thermal guard: the kernel has no CPU_THERMAL, the only sensor is the battery (0.1 °C).
# Full speed while cool; step the CPU cap down as the battery heats up, back up with hysteresis.
# Li-ion: keep < 45 °C (esp. while charging). Writes persist.sc.cpu_max so sc_cpucap agrees, and sysfs directly.
# Log: /data/local/tmp/sc-thermal.log (level changes only).
FULL=2340000 MID=1644000 LOW=1056000 MIN=756000
cur=$FULL
log=/data/local/tmp/sc-thermal.log
while true; do
  t=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
  # FAIL-SAFE: if the sensor can't be read / isn't numeric, assume warm (42.0 °C) and cap to MID
  # rather than run full speed forever — this is the only thermal protection (no CPU_THERMAL).
  case "$t" in ''|*[!0-9-]*) t=420 ;; esac
  new=$cur
  if   [ "$t" -ge 460 ]; then new=$MIN
  elif [ "$t" -ge 430 ]; then [ "$cur" -gt $LOW ] && new=$LOW
  elif [ "$t" -ge 410 ]; then [ "$cur" -gt $MID ] && new=$MID
  elif [ "$t" -le 380 ]; then new=$FULL
  elif [ "$t" -le 400 ] && [ "$cur" -lt $MID ]; then new=$MID
  fi
  if [ "$new" != "$cur" ]; then
    cur=$new
    echo "$(date '+%m-%d %H:%M:%S') temp=$t cap=$cur" >> $log
  fi
  setprop persist.sc.cpu_max $cur
  for c in /sys/devices/system/cpu/cpu*/cpufreq; do
    [ "$(cat $c/scaling_max_freq)" = "$cur" ] || echo $cur > $c/scaling_max_freq
  done
  sleep 10
done

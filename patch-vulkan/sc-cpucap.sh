#!/system/bin/sh
# Kernel has no CPU_THERMAL and idles at max freq → the phone overheats (41.8 °C seen).
# cpufreq policy limits get reset (e.g. after screen sleep), so keep re-applying the cap.
# Override: setprop persist.sc.cpu_max <kHz> (2340000 = no cap).
while true; do
  max=$(getprop persist.sc.cpu_max)
  [ -n "$max" ] || max=1644000
  for c in /sys/devices/system/cpu/cpu*/cpufreq; do
    [ "$(cat $c/scaling_max_freq)" = "$max" ] || echo $max > $c/scaling_max_freq
  done
  sleep 20
done

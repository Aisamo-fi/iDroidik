#!/system/bin/sh
# App rendering mode (verified by the user 2026-09-15: no flicker, WebView works).
#   persist.sc.render unset/angle: HWUI on A10 SwiftShader GLES, but every app's GL goes through ANGLE on our
#                                  SwiftShader Vulkan (fixes WebView) — except SystemUI and the launcher, which
#                                  stay on native GLES (the shade flickered otherwise).
#   persist.sc.render=gl:  no ANGLE at all (WebView broken).
#   persist.sc.render=vk:  HWUI skiavk + ANGLE everywhere (fastest app start, but Aurora flickers).
# Re-run after installing apps so they get ANGLE too.
mode=$(getprop persist.sc.render)
if [ "$mode" = vk ]; then
  settings put global angle_gl_driver_all_angle 1
  exit 0
fi
[ "$(getprop debug.hwui.renderer)" = skiavk ] && setprop debug.hwui.renderer skiagl
settings put global angle_gl_driver_all_angle 0
if [ "$mode" = gl ]; then
  settings delete global angle_gl_driver_selection_pkgs >/dev/null
  settings delete global angle_gl_driver_selection_values >/dev/null
  exit 0
fi
# Launchers (the current home app included) stay native too.
home=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1 | cut -d/ -f1)
pkgs=$(pm list packages | sed 's/^package://' | grep -vxE "com\.android\.systemui|com\.android\.launcher3|app\.lawnchair.*|$home" | sort)
n=$(echo "$pkgs" | wc -l)
settings put global angle_gl_driver_selection_pkgs "$(echo "$pkgs" | paste -sd, -)"
settings put global angle_gl_driver_selection_values "$(yes angle | head -n "$n" | paste -sd, -)"

#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Android Memory Governor v1.
#
# Despite the historical name, this component is intentionally read-only. It
# measures the shared Android/Termux host and Fedora processes, records an
# explicit no-change policy receipt, and gives the UI evidence for decisions.
# Android remains the memory manager: LMKD, cached-app freezing, memcg, zRAM,
# reclaim and kernel parameters are outside this project.

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../scripts/lib/common.sh"

fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_init_state

MEMORY_STATE_DIR="${FEDORA_STATE_RECORD_DIR:-$FEDORA_STATE_DIR/state}"
MEMORY_LATEST="$MEMORY_STATE_DIR/memory-latest.json"
POLICY_RECEIPT="$MEMORY_STATE_DIR/android-policy-backup.json"
fedora_prepare_directories "$MEMORY_STATE_DIR" || exit 1
chmod 700 "$MEMORY_STATE_DIR" 2>/dev/null || true

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

json_string() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

json_nullable_string() {
  local value="${1:-}"
  if [[ -n "$value" ]]; then
    json_string "$value"
  else
    printf 'null'
  fi
}

json_number() {
  local value="${1:-}"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf 'null'
  fi
}

json_nullable_bool() {
  case "${1:-}" in
    true|false) printf '%s' "$1" ;;
    *) printf 'null' ;;
  esac
}

allowlist_array() {
  local section="$1"
  local file="${FEDORA_ANDROID_ALLOWLIST_FILE:-$FEDORA_INSTALL_ROOT/config/android-memory-allowlist.json}"
  local result='[' separator='' entry
  [[ -r "$file" ]] || { printf '[]'; return 0; }

  # The allowlist is deliberately parsed as reporting metadata only. Accept
  # exact Android package-shaped tokens from the named JSON array and fail
  # closed for everything else; this helper never calls pm, am or any policy
  # changing Android command.
  while IFS= read -r entry; do
    [[ "$entry" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]] || continue
    result+="${separator}$(json_string "$entry")"
    separator=','
  done < <(
    if command -v jq >/dev/null 2>&1; then
      jq -r --arg section "$section" '
        (.[$section] // [])
        | if type == "array" then .[] else empty end
        | select(type == "string" and test("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+$"))
      ' "$file" 2>/dev/null || true
    else
      # Keep a dependency-free fallback for the minimal Termux installation.
      # Handle both pretty-printed arrays and an empty/single-line array; do
      # not let an empty section bleed into the next JSON field.
      awk -v section="$section" '
        function emit(line) {
          while (match(line, /"[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+"/)) {
            token = substr(line, RSTART + 1, RLENGTH - 2)
            print token
            line = substr(line, RSTART + RLENGTH)
          }
        }
        !inside && $0 ~ "\\\"" section "\\\"[[:space:]]*:" {
          line = $0
          sub("^.*\\[", "", line)
          if (line ~ /]/) {
            sub(/].*$/, "", line)
            emit(line)
            exit
          }
          inside = 1
          emit(line)
          next
        }
        inside {
          line = $0
          if (line ~ /]/) {
            sub(/].*$/, "", line)
            emit(line)
            exit
          }
          emit(line)
        }
      ' "$file" 2>/dev/null || true
    fi
  )
  printf '%s]' "$result"
}

psi_avg10() {
  local line="${1:-}" field
  for field in $line; do
    case "$field" in
      avg10=*) printf '%s\n' "${field#avg10=}"; return 0 ;;
    esac
  done
}

recommendation_array() {
  local -a recommendations=()
  local available_percent swap_percent psi_pressure

  recommendations+=(
    "No Android policy action was taken; LMKD, cached-app reclaim and zRAM remain authoritative."
    "Treat cached/reclaimable RAM as useful cache, not as a leak; do not clear page cache or disable zRAM."
    "Major page faults are cumulative; compare before/after snapshots instead of interpreting one total as a rate."
  )

  if [[ "$mem_total" =~ ^[0-9]+$ && "$mem_available" =~ ^[0-9]+$ ]] && (( mem_total > 0 )); then
    available_percent=$((mem_available * 100 / mem_total))
    if (( available_percent < 12 )); then
      recommendations+=(
        "MemAvailable is ${available_percent}%: reduce Fedora-side application load or nested resolution first; Android services were not touched."
      )
    elif (( available_percent < 20 )); then
      recommendations+=(
        "MemAvailable is ${available_percent}%: monitor PSI and zRAM, and keep Fedora background applications closed."
      )
    else
      recommendations+=(
        "MemAvailable is ${available_percent}%: no immediate memory intervention is indicated by this snapshot."
      )
    fi
  else
    recommendations+=("MemAvailable could not be read reliably on this host; no pressure decision was made.")
  fi

  if [[ "$swap_total" =~ ^[0-9]+$ && "$swap_used" =~ ^[0-9]+$ ]] && (( swap_total > 0 )); then
    swap_percent=$((swap_used * 100 / swap_total))
    if (( swap_percent >= 80 )); then
      recommendations+=(
        "zRAM/swap usage is ${swap_percent}% of the visible swap pool: reduce Fedora-side workload and watch for thrashing; leave Android zRAM policy unchanged."
      )
    elif (( swap_percent >= 50 )); then
      recommendations+=("zRAM/swap usage is ${swap_percent}%: observe PSI and major faults before changing any workload.")
    fi
  fi

  psi_pressure="$(psi_avg10 "${psi_full:-}")"
  if [[ "$psi_pressure" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    && awk -v value="$psi_pressure" 'BEGIN { exit !(value >= 10) }'; then
    recommendations+=("Full memory PSI avg10 is ${psi_pressure}%: Fedora applications are the first safe workload to reduce; do not kill GNOME/Mutter or Android system services.")
  fi

  if [[ "$fedora_pss_kib" =~ ^[0-9]+$ && "$mem_available" =~ ^[0-9]+$ ]] \
    && (( mem_available > 0 && fedora_pss_kib > mem_available / 2 )); then
    recommendations+=("Measured Fedora-related PSS is over half of MemAvailable: inspect Firefox/VS Code/LibreOffice and Fedora background processes before blaming Android.")
  fi

  if [[ "$android_dumpsys_available" != 1 ]]; then
    recommendations+=("Android dumpsys meminfo was unavailable to this unprivileged probe; framework/app attribution is partial, not an exact total.")
  fi

  if [[ "${android_third_party_count_readable:-0}" != 1 ]]; then
    recommendations+=("The Android third-party package count was unavailable; package inventory is not being guessed or treated as an exact value.")
  fi

  case "${android_ramplus_zram_observed:-}" in
    true)
      recommendations+=("A zRAM-backed swap device is visible, but the Samsung RAM Plus setting and its configured amount are not readable from unprivileged Termux; do not resize it from Fedora.")
      ;;
    false)
      recommendations+=("No zRAM device was visible to the read-only probe; this does not prove Samsung RAM Plus is off, so verify it manually in Android Settings if needed.")
      ;;
    *)
      recommendations+=("Samsung RAM Plus is not directly readable from this unprivileged probe; only available swap/zRAM counters are reported and Android remains authoritative.")
      ;;
  esac
  if [[ "${android_ramplus_non_zram_swap_entries:-}" =~ ^[1-9][0-9]*$ ]]; then
    recommendations+=("A non-zRAM swap backend is visible, but its owner is not identified by this probe; do not label it RAM Plus or change it from Fedora.")
  fi

  local result='[' separator='' recommendation
  for recommendation in "${recommendations[@]}"; do
    result+="${separator}$(json_string "$recommendation")"
    separator=','
  done
  printf '%s]' "$result"
}

meminfo_value() {
  local key="$1"
  awk -v key="$key" '$1 == (key ":") { print $2; exit }' /proc/meminfo 2>/dev/null || true
}

swap_values() {
  local swap_total=0 swap_used=0 swap_entries=0 zram_entries=0 zram_used=0
  local swap_readable=0
  local device
  if [[ -r /proc/swaps ]]; then
    swap_readable=1
    while read -r device _ size used _; do
      [[ "$size" =~ ^[0-9]+$ ]] || continue
      [[ "$used" =~ ^[0-9]+$ ]] || continue
      swap_total=$((swap_total + size))
      swap_used=$((swap_used + used))
      swap_entries=$((swap_entries + 1))
      if [[ "$device" == *zram* ]]; then
        zram_entries=$((zram_entries + 1))
        zram_used=$((zram_used + used))
      fi
    done < <(tail -n +2 /proc/swaps 2>/dev/null || true)
  fi
  if (( swap_readable )); then
    printf '%s %s %s %s %s %s\n' "$swap_total" "$swap_used" "$swap_entries" \
      "$zram_entries" "$zram_used" "$swap_readable"
  else
    printf '%s %s %s %s %s %s\n' '' '' '' '' '' "$swap_readable"
  fi
}

sysfs_bytes_to_kib() {
  local path="$1"
  local raw=""
  [[ -r "$path" ]] || return 0
  raw="$(sed -nE 's/^[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$path" 2>/dev/null | sed -n '1p' || true)"
  [[ "$raw" =~ ^[0-9]+$ ]] || return 0
  printf '%s\n' "$(((raw + 1023) / 1024))"
}

collect_zram_state() {
  local swap_zram_entries="${1:-}"
  local swap_table_readable="${2:-0}"
  local swap_entry_count="${3:-}"
  local zram_path zram_device_count=0
  local zram_sysfs_visible=0 zram_stats_readable=0
  local non_zram_swap_entries=""
  local configured=0 configured_seen=0
  local original=0 original_seen=0
  local compressed=0 compressed_seen=0
  local physical=0 physical_seen=0
  local value

  android_ramplus_setting=not-readable
  android_ramplus_status=probe-unavailable
  android_ramplus_probe_readable=0
  android_ramplus_zram_observed=""
  android_ramplus_zram_device_count=""
  android_ramplus_zram_configured_kib=""
  android_ramplus_zram_original_kib=""
  android_ramplus_zram_compressed_kib=""
  android_ramplus_zram_physical_kib=""
  android_ramplus_compression_ratio=""
  android_ramplus_non_zram_swap_entries=""
  android_ramplus_backend_observation=unavailable

  if [[ "$swap_entry_count" =~ ^[0-9]+$ && "$swap_zram_entries" =~ ^[0-9]+$ ]]; then
    non_zram_swap_entries=$((swap_entry_count - swap_zram_entries))
    if (( non_zram_swap_entries < 0 )); then
      non_zram_swap_entries=0
    fi
    android_ramplus_non_zram_swap_entries="$non_zram_swap_entries"
  fi

  # Android/Samsung may deny sysfs to the Termux UID. Treat every field as
  # optional and never infer RAM Plus from a missing or partial sysfs view.
  for zram_path in /sys/block/zram[0-9]*; do
    [[ -d "$zram_path" ]] || continue
    zram_sysfs_visible=1
    zram_device_count=$((zram_device_count + 1))

    value="$(sysfs_bytes_to_kib "$zram_path/disksize")"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      configured=$((configured + value))
      configured_seen=1
      zram_stats_readable=1
    fi
    value="$(sysfs_bytes_to_kib "$zram_path/orig_data_size")"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      original=$((original + value))
      original_seen=1
      zram_stats_readable=1
    fi
    value="$(sysfs_bytes_to_kib "$zram_path/compr_data_size")"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      compressed=$((compressed + value))
      compressed_seen=1
      zram_stats_readable=1
    fi
    value="$(sysfs_bytes_to_kib "$zram_path/mem_used_total")"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      physical=$((physical + value))
      physical_seen=1
      zram_stats_readable=1
    fi
  done

  if (( zram_sysfs_visible )); then
    android_ramplus_probe_readable=1
    android_ramplus_zram_device_count="$zram_device_count"
  fi
  if (( configured_seen )); then
    android_ramplus_zram_configured_kib="$configured"
  fi
  if (( original_seen )); then
    android_ramplus_zram_original_kib="$original"
  fi
  if (( compressed_seen )); then
    android_ramplus_zram_compressed_kib="$compressed"
  fi
  if (( physical_seen )); then
    android_ramplus_zram_physical_kib="$physical"
  fi
  if (( original > 0 && compressed > 0 )); then
    android_ramplus_compression_ratio="$(awk -v original="$original" -v compressed="$compressed" \
      'BEGIN { printf "%.2f", original / compressed }')"
  fi

  if [[ "$swap_zram_entries" =~ ^[0-9]+$ ]] && (( swap_zram_entries > 0 )); then
    android_ramplus_zram_observed=true
  elif (( zram_device_count > 0 )); then
    android_ramplus_zram_observed=true
  elif (( swap_table_readable || zram_sysfs_visible )); then
    android_ramplus_zram_observed=false
  fi

  if (( swap_table_readable || zram_sysfs_visible || zram_stats_readable )); then
    android_ramplus_probe_readable=1
  fi
  if [[ "$android_ramplus_zram_observed" == true && "$non_zram_swap_entries" =~ ^[1-9][0-9]*$ ]]; then
    android_ramplus_backend_observation=zram-and-non-zram-swap
  elif [[ "$android_ramplus_zram_observed" == true ]]; then
    android_ramplus_backend_observation=zram
  elif [[ "$non_zram_swap_entries" =~ ^[1-9][0-9]*$ ]]; then
    android_ramplus_backend_observation=non-zram-swap
  elif [[ "$android_ramplus_zram_observed" == false ]]; then
    android_ramplus_backend_observation=none-observed
  fi
  case "${android_ramplus_zram_observed:-}" in
    true) android_ramplus_status=zram-observed-setting-unknown ;;
    false) android_ramplus_status=no-zram-observed-setting-unknown ;;
    *) android_ramplus_status=probe-unavailable ;;
  esac
}

vmstat_value() {
  local key="$1"
  awk -v key="$key" '$1 == key { print $2; exit }' /proc/vmstat 2>/dev/null || true
}

psi_line() {
  local group="$1"
  if [[ -r /proc/pressure/memory ]]; then
    awk -v group="$group" '$1 == group { sub(/^[^ ]+ /, ""); print; exit }' \
      /proc/pressure/memory 2>/dev/null || true
  fi
}

dumpsys_field_kib() {
  local file="$1"
  local label="$2"
  local line raw value unit
  line="$(grep -m1 -E "^[[:space:]]*${label}:" "$file" 2>/dev/null || true)"
  [[ -n "$line" ]] || return 0
  raw="${line#*:}"
  value="$(printf '%s\n' "$raw" | sed -nE 's/^[[:space:]]*([0-9,]+).*/\1/p' | tr -d ',')"
  [[ "$value" =~ ^[0-9]+$ ]] || return 0
  unit="$(printf '%s\n' "$raw" | sed -nE 's/^[[:space:]]*[0-9,]+[[:space:]]*([KMG])B?.*/\1/p')"
  case "$unit" in
    G) value=$((value * 1024 * 1024)) ;;
    M) value=$((value * 1024)) ;;
    K|'') ;;
    *) return 0 ;;
  esac
  printf '%s\n' "$value"
}

collect_android_dumpsys() {
  android_dumpsys_available=0
  android_dumpsys_total=""
  android_dumpsys_free=""
  android_dumpsys_used=""
  android_dumpsys_lost=""
  android_dumpsys_cached=""
  android_dumpsys_graphics=""
  android_dumpsys_app_summary=""
  local dump_file=""
  if [[ -x /system/bin/dumpsys ]]; then
    dump_file="$(mktemp "$MEMORY_STATE_DIR/.dumpsys-meminfo.XXXXXX" 2>/dev/null || true)"
  fi

  if [[ -n "$dump_file" && -f "$dump_file" && ! -L "$dump_file" ]] \
    && /system/bin/dumpsys meminfo --local > "$dump_file" 2>/dev/null \
    && [[ -s "$dump_file" ]]; then
    local total_ram
    total_ram="$(dumpsys_field_kib "$dump_file" 'Total RAM')"
    # A few Android builds return exit status 0 with an explanatory error
    # instead of a meminfo table. Require a real Total RAM field before
    # marking the rest of the attribution as readable.
    if [[ "$total_ram" =~ ^[0-9]+$ ]]; then
      android_dumpsys_available=1
      android_dumpsys_total="$total_ram"
      android_dumpsys_free="$(dumpsys_field_kib "$dump_file" 'Free RAM')"
      android_dumpsys_used="$(dumpsys_field_kib "$dump_file" 'Used RAM')"
      android_dumpsys_lost="$(dumpsys_field_kib "$dump_file" 'Lost RAM')"
      android_dumpsys_cached="$(dumpsys_field_kib "$dump_file" 'Cached RAM')"
      android_dumpsys_graphics="$(dumpsys_field_kib "$dump_file" 'Graphics')"
      local app_java="" app_native="" app_code="" app_stack="" app_private="" app_system=""
      app_java="$(dumpsys_field_kib "$dump_file" 'Java Heap')"
      app_native="$(dumpsys_field_kib "$dump_file" 'Native Heap')"
      app_code="$(dumpsys_field_kib "$dump_file" 'Code')"
      app_stack="$(dumpsys_field_kib "$dump_file" 'Stack')"
      app_private="$(dumpsys_field_kib "$dump_file" 'Private Other')"
      app_system="$(dumpsys_field_kib "$dump_file" 'System')"
      if [[ "$app_java" =~ ^[0-9]+$ && "$app_native" =~ ^[0-9]+$ \
        && "$app_code" =~ ^[0-9]+$ && "$app_stack" =~ ^[0-9]+$ \
        && "$app_private" =~ ^[0-9]+$ && "$app_system" =~ ^[0-9]+$ ]]; then
        android_dumpsys_app_summary=$((app_java + app_native + app_code + app_stack + app_private + app_system))
      fi
    fi
  fi
  [[ -z "$dump_file" ]] || rm -f -- "$dump_file"
}

android_third_party_count() {
  android_third_party_count_readable=0
  android_third_party_count_value=""
  local package_output=""
  if [[ -x /system/bin/pm ]] \
    && package_output="$(/system/bin/pm list packages -3 2>/dev/null)" \
    && { [[ -z "$package_output" ]] || awk '
      NF && $0 !~ /^package:[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$/ { invalid = 1 }
      END { exit invalid }
    ' <<< "$package_output"; }; then
    :
  elif [[ -x /system/bin/cmd ]] \
    && package_output="$(/system/bin/cmd package list packages -3 2>/dev/null)" \
    && { [[ -z "$package_output" ]] || awk '
      NF && $0 !~ /^package:[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$/ { invalid = 1 }
      END { exit invalid }
    ' <<< "$package_output"; }; then
    :
  else
    return 0
  fi
  # Some Android builds return exit status 0 with an explanatory error. An
  # empty result is a valid zero-package inventory; the validation above keeps
  # warning text from becoming a false package count.
  android_third_party_count_readable=1
  android_third_party_count_value="$(printf '%s\n' "$package_output" \
    | awk '/^package:/ { count += 1 } END { print count + 0 }')"
}

process_command_line() {
  local pid="$1"
  [[ -r "/proc/$pid/cmdline" ]] || return 0
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true
}

is_fedora_process() {
  local command_line="$1"
  case "$command_line" in
    *fedora-session*|*fedora-run*|*mutter-devkit*|*gnome-shell*|*gnome-settings-daemon*|*pipewire*|*wireplumber*|*ptyxis*|*gnome-console*|*gnome-terminal*|*proot*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

process_pss_kib() {
  local pid="$1"
  awk '/^Pss:/ { print $2; exit }' "/proc/$pid/smaps_rollup" 2>/dev/null || true
}

is_android_system_process() {
  local command_line="$1"
  case "$command_line" in
    *system_server*|*surfaceflinger*|*servicemanager*|*hwservicemanager*|*vndservicemanager*|\
    *zygote*|*zygote64*|*android.hardware.*|*audioserver*|*cameraserver*|*mediaserver*|\
    *media.extractor*|*netd*|*wificond*|*bluetooth*|*com.android.systemui*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

collect_android_process_memory() {
  android_system_process_count=""
  android_system_pss_kib=""
  android_system_pss_readable=0
  android_system_process_count_readable=0
  surfaceflinger_pss_kib=""
  surfaceflinger_pss_readable=0
  local process_dir pid command_line pss

  # This is a best-effort attribution only. Android may hide smaps_rollup from
  # an unprivileged Termux UID, and PSS for SurfaceFlinger is not GPU VRAM.
  for process_dir in /proc/[0-9]*; do
    [[ -r "$process_dir/cmdline" ]] || continue
    pid="${process_dir##*/}"
    command_line="$(process_command_line "$pid")"
    is_android_system_process "$command_line" || continue
    android_system_process_count_readable=1
    if [[ "$android_system_process_count" =~ ^[0-9]+$ ]]; then
      android_system_process_count=$((android_system_process_count + 1))
    else
      android_system_process_count=1
    fi
    pss="$(process_pss_kib "$pid")"
    [[ "$pss" =~ ^[0-9]+$ ]] || continue
    android_system_pss_readable=1
    if [[ "$android_system_pss_kib" =~ ^[0-9]+$ ]]; then
      android_system_pss_kib=$((android_system_pss_kib + pss))
    else
      android_system_pss_kib=$pss
    fi
    case "$command_line" in
      *surfaceflinger*)
        surfaceflinger_pss_readable=1
        if [[ "$surfaceflinger_pss_kib" =~ ^[0-9]+$ ]]; then
          surfaceflinger_pss_kib=$((surfaceflinger_pss_kib + pss))
        else
          surfaceflinger_pss_kib=$pss
        fi
        ;;
    esac
  done
}

collect_fedora_memory() {
  fedora_process_count=0
  fedora_pss_kib=""
  fedora_pss_readable=0
  gnome_pss_kib=""
  mutter_pss_kib=""
  pipewire_pss_kib=""
  local process_dir pid command_line pss

  for process_dir in /proc/[0-9]*; do
    [[ -r "$process_dir/cmdline" ]] || continue
    pid="${process_dir##*/}"
    command_line="$(process_command_line "$pid")"
    is_fedora_process "$command_line" || continue
    fedora_process_count=$((fedora_process_count + 1))
    pss="$(process_pss_kib "$pid")"
    if [[ "$pss" =~ ^[0-9]+$ ]]; then
      fedora_pss_readable=1
      if [[ "$fedora_pss_kib" =~ ^[0-9]+$ ]]; then
        fedora_pss_kib=$((fedora_pss_kib + pss))
      else
        fedora_pss_kib="$pss"
      fi
      case "$command_line" in
        *gnome-shell*)
          if [[ "$gnome_pss_kib" =~ ^[0-9]+$ ]]; then
            gnome_pss_kib=$((gnome_pss_kib + pss))
          else
            gnome_pss_kib="$pss"
          fi
          ;;
      esac
      case "$command_line" in
        *mutter-devkit*)
          if [[ "$mutter_pss_kib" =~ ^[0-9]+$ ]]; then
            mutter_pss_kib=$((mutter_pss_kib + pss))
          else
            mutter_pss_kib="$pss"
          fi
          ;;
      esac
      case "$command_line" in
        *pipewire*|*wireplumber*)
          if [[ "$pipewire_pss_kib" =~ ^[0-9]+$ ]]; then
            pipewire_pss_kib=$((pipewire_pss_kib + pss))
          else
            pipewire_pss_kib="$pss"
          fi
          ;;
      esac
    fi
  done
}

atomic_write() {
  local destination="$1"
  local parent temporary
  fedora_path_is_safe "$destination" || return 1
  if [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
    fedora_die "Memory report target is unsafe: $destination"
    return 1
  fi
  parent="${destination%/*}"
  [[ -n "$parent" ]] || parent="/"
  [[ -d "$parent" && ! -L "$parent" ]] || return 1
  temporary="$(mktemp "$parent/.memory-write.XXXXXX")" || return 1
  chmod 600 "$temporary" 2>/dev/null || true
  if ! cat > "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  [[ ! -L "$destination" ]] || {
    rm -f -- "$temporary"
    fedora_die "Memory report target became a symlink during update"
    return 1
  }
  mv -f -- "$temporary" "$destination"
  [[ -f "$destination" && ! -L "$destination" ]] || return 1
  chmod 600 "$destination" 2>/dev/null || true
}

write_no_change_evidence() {
  local timestamp
  timestamp="$(utc_now)"
  atomic_write "$POLICY_RECEIPT" <<EOF
{
  "schema": 1,
  "createdUtc": $(json_string "$timestamp"),
  "mode": "non-invasive-read-only",
  "androidChangesApplied": false,
  "restoreRequired": false,
  "changes": [],
  "restoreAction": "none",
  "reason": "Linux Mode leaves Android, One UI, packages, settings, services, kernel, LMKD and zRAM untouched.",
  "source": "fedora-shell Android Memory Governor"
}
EOF
}

capture_snapshot() {
  local label="${1:-now}"
  case "$label" in
    before|after|now) ;;
    *)
      fedora_die "snapshot label must be before, after or now"
      return 64
      ;;
  esac

  local timestamp mem_total mem_available mem_free cached buffers reclaimable shmem
  local swap_total swap_free swap_used swap_entries swap_total_from_table swap_table_readable
  local zram_entries zram_used major_faults third_party psi_some psi_full target
  mem_total="$(meminfo_value MemTotal)"
  mem_available="$(meminfo_value MemAvailable)"
  mem_free="$(meminfo_value MemFree)"
  cached="$(meminfo_value Cached)"
  buffers="$(meminfo_value Buffers)"
  reclaimable="$(meminfo_value SReclaimable)"
  shmem="$(meminfo_value Shmem)"
  swap_total="$(meminfo_value SwapTotal)"
  swap_free="$(meminfo_value SwapFree)"
  swap_used=""
  swap_entries=""
  read -r swap_total_from_table swap_used swap_entries zram_entries zram_used swap_table_readable < <(swap_values)
  [[ "$swap_total" =~ ^[0-9]+$ ]] || swap_total="$swap_total_from_table"
  major_faults="$(vmstat_value pgmajfault)"
  android_third_party_count
  third_party="$android_third_party_count_value"
  psi_some="$(psi_line some)"
  psi_full="$(psi_line full)"
  collect_android_dumpsys
  collect_android_process_memory
  collect_fedora_memory
  collect_zram_state "$zram_entries" "$swap_table_readable" "$swap_entries"
  timestamp="$(utc_now)"

  target="$MEMORY_LATEST"
  [[ "$label" == now ]] || target="$MEMORY_STATE_DIR/memory-$label.json"
  atomic_write "$target" <<EOF
{
  "schema": 1,
  "capturedUtc": $(json_string "$timestamp"),
  "label": $(json_string "$label"),
  "source": "read-only Termux, Android and /proc probes",
  "host": {
    "memTotalKiB": $(json_number "$mem_total"),
    "memAvailableKiB": $(json_number "$mem_available"),
    "memFreeKiB": $(json_number "$mem_free"),
    "cachedKiB": $(json_number "$cached"),
    "buffersKiB": $(json_number "$buffers"),
    "sReclaimableKiB": $(json_number "$reclaimable"),
    "shmemKiB": $(json_number "$shmem"),
    "swapTotalKiB": $(json_number "$swap_total"),
    "swapFreeKiB": $(json_number "$swap_free"),
    "swapUsedKiB": $(json_number "$swap_used"),
    "swapEntries": $(json_number "$swap_entries"),
    "swapReadable": $([[ "$swap_table_readable" == 1 ]] && printf true || printf false),
    "zramEntries": $(json_number "$zram_entries"),
    "zramUsedKiB": $(json_number "$zram_used"),
    "majorPageFaultsTotal": $(json_number "$major_faults"),
    "memoryPsiSome": $(json_nullable_string "$psi_some"),
    "memoryPsiSomeReadable": $([[ -n "$psi_some" ]] && printf true || printf false),
    "memoryPsiFull": $(json_nullable_string "$psi_full"),
    "memoryPsiFullReadable": $([[ -n "$psi_full" ]] && printf true || printf false)
  },
  "android": {
    "dumpsysMeminfoAvailable": $([[ "$android_dumpsys_available" == 1 ]] && printf true || printf false),
    "dumpsysTotalRamKiB": $(json_number "$android_dumpsys_total"),
    "dumpsysFreeRamKiB": $(json_number "$android_dumpsys_free"),
    "dumpsysUsedRamKiB": $(json_number "$android_dumpsys_used"),
    "dumpsysLostRamKiB": $(json_number "$android_dumpsys_lost"),
    "dumpsysCachedRamKiB": $(json_number "$android_dumpsys_cached"),
    "dumpsysGraphicsKiB": $(json_number "$android_dumpsys_graphics"),
    "dumpsysAppSummaryPssKiB": $(json_number "$android_dumpsys_app_summary"),
    "systemProcessCount": $(json_number "$android_system_process_count"),
    "systemProcessCountReadable": $([[ "$android_system_process_count_readable" == 1 ]] && printf true || printf false),
    "systemProcessPssKiB": $(json_number "$android_system_pss_kib"),
    "systemProcessPssReadable": $([[ "$android_system_pss_readable" == 1 ]] && printf true || printf false),
    "surfaceFlingerPssKiB": $(json_number "$surfaceflinger_pss_kib"),
    "surfaceFlingerPssReadable": $([[ "$surfaceflinger_pss_readable" == 1 ]] && printf true || printf false),
    "thirdPartyPackageCount": $(json_number "$third_party"),
    "thirdPartyPackageCountReadable": $([[ "${android_third_party_count_readable:-0}" == 1 ]] && printf true || printf false),
    "ramPlus": {
      "setting": $(json_string "$android_ramplus_setting"),
      "status": $(json_string "$android_ramplus_status"),
      "backendObservation": $(json_string "$android_ramplus_backend_observation"),
      "zramObserved": $(json_nullable_bool "$android_ramplus_zram_observed"),
      "nonZramSwapEntries": $(json_number "$android_ramplus_non_zram_swap_entries"),
      "zramDeviceCount": $(json_number "$android_ramplus_zram_device_count"),
      "zramConfiguredKiB": $(json_number "$android_ramplus_zram_configured_kib"),
      "zramOriginalDataKiB": $(json_number "$android_ramplus_zram_original_kib"),
      "zramCompressedDataKiB": $(json_number "$android_ramplus_zram_compressed_kib"),
      "zramPhysicalUsedKiB": $(json_number "$android_ramplus_zram_physical_kib"),
      "zramCompressionRatio": $(json_nullable_string "$android_ramplus_compression_ratio"),
      "probeReadable": $([[ "$android_ramplus_probe_readable" == 1 ]] && printf true || printf false),
      "readOnly": true,
      "measurementNote": "Samsung RAM Plus is an OEM Android setting. zRAM/sysfs observations are indirect and cannot prove its UI state or configured amount; the project never enables, disables or resizes it."
    },
    "allowlist": {
      "source": "config/android-memory-allowlist.json (reporting-only)",
      "mode": "reporting-only",
      "alwaysKeepPackages": $(allowlist_array alwaysKeepPackages),
      "userSelectedKeepPackages": $(allowlist_array userSelectedKeepPackages)
    },
    "measurementNote": "Android framework totals come from dumpsys when permitted; process PSS is best effort and does not represent GPU VRAM."
  },
  "fedora": {
    "processCount": $(json_number "$fedora_process_count"),
    "pssKiB": $(json_number "$fedora_pss_kib"),
    "gnomeShellPssKiB": $(json_number "$gnome_pss_kib"),
    "mutterDevkitPssKiB": $(json_number "$mutter_pss_kib"),
    "pipewirePssKiB": $(json_number "$pipewire_pss_kib"),
    "pssReadable": $([[ "$fedora_pss_readable" == 1 ]] && printf true || printf false),
    "measurementNote": "Best-effort sum of Fedora-related process PSS; shared pages are apportioned by the kernel and may be incomplete."
  },
  "gpu": {
    "memoryKiB": null,
    "memoryReadable": false,
    "measurementNote": "Android GPU-driver VRAM is not exposed as a reliable unprivileged Termux counter; SurfaceFlinger PSS above is not VRAM."
  },
  "recommendations": $(recommendation_array),
  "policy": {
    "androidChangesApplied": false,
    "memoryManager": "Android remains authoritative",
    "fedoraSideTuningOnly": true
  }
}
EOF
  write_no_change_evidence
  printf '%s\n' "$target"
}

print_memory() {
  local report="$MEMORY_LATEST"
  if [[ ! -f "$report" || -L "$report" ]]; then
    capture_snapshot now >/dev/null
  fi
  [[ -f "$report" && ! -L "$report" && -r "$report" ]] || {
    fedora_die "Memory report is missing or unsafe: $report"
    return 1
  }
  printf 'Read-only memory report: %s\n' "$report"
  sed -nE \
    -e 's/^[[:space:]]*"(memTotalKiB|memAvailableKiB|memFreeKiB|cachedKiB|buffersKiB|sReclaimableKiB|shmemKiB|swapTotalKiB|swapFreeKiB|swapUsedKiB|swapEntries|swapReadable|zramEntries|zramUsedKiB|majorPageFaultsTotal|memoryPsiSome|memoryPsiSomeReadable|memoryPsiFull|memoryPsiFullReadable)":[[:space:]]*(.*),?$/Host.\1 = \2/p' \
    -e 's/^[[:space:]]*"(dumpsysMeminfoAvailable|dumpsysTotalRamKiB|dumpsysFreeRamKiB|dumpsysUsedRamKiB|dumpsysLostRamKiB|dumpsysCachedRamKiB|dumpsysGraphicsKiB|dumpsysAppSummaryPssKiB|systemProcessCount|systemProcessCountReadable|systemProcessPssKiB|systemProcessPssReadable|surfaceFlingerPssKiB|surfaceFlingerPssReadable|thirdPartyPackageCount|thirdPartyPackageCountReadable)":[[:space:]]*(.*),?$/Android.\1 = \2/p' \
    -e 's/^[[:space:]]{6}"(setting|status|backendObservation|zramObserved|nonZramSwapEntries|zramDeviceCount|zramConfiguredKiB|zramOriginalDataKiB|zramCompressedDataKiB|zramPhysicalUsedKiB|zramCompressionRatio|probeReadable|readOnly)":[[:space:]]*(.*),?$/Android.ramPlus.\1 = \2/p' \
    -e 's/^[[:space:]]*"(processCount|pssKiB|gnomeShellPssKiB|mutterDevkitPssKiB|pipewirePssKiB|pssReadable)":[[:space:]]*(.*),?$/Fedora.\1 = \2/p' \
    "$report" || true
  printf 'Android policy receipt: %s (androidChangesApplied=false)\n' "$POLICY_RECEIPT"
  printf '%s\n' 'Read-only recommendations:'
  if command -v jq >/dev/null 2>&1; then
    jq -r '.recommendations[]? // empty' "$report" 2>/dev/null \
      | sed 's/^/  - /' || true
  else
    # The fallback understands both the compact array emitted by this script
    # and a pretty-printed array, without requiring another package.
    awk '
      function emit(line) {
        while (match(line, /"[^"]*"/)) {
          value = substr(line, RSTART + 1, RLENGTH - 2)
          gsub(/\\"/, "\"", value)
          printf "  - %s\n", value
          line = substr(line, RSTART + RLENGTH)
        }
      }
      /"recommendations": \[/ {
        line = $0
        sub(/^.*"recommendations"[[:space:]]*:[[:space:]]*\[/, "", line)
        if (line ~ /]/) {
          sub(/].*$/, "", line)
          emit(line)
          exit
        }
        inside = 1
        next
      }
      inside {
        line = $0
        if (line ~ /]/) {
          sub(/].*$/, "", line)
          emit(line)
          exit
        }
        emit(line)
      }
    ' "$report" || true
  fi
}

usage() {
  cat >&2 <<'EOF'
Usage: android-memory-governor.sh COMMAND

Read-only commands:
  snapshot [before|after|now]  capture a JSON memory snapshot
  memory                       capture if needed and print the latest report
  status                       print the latest report and no-change receipt
  restore-evidence             record that there is nothing to restore
EOF
}

command_name="${1:-status}"
case "$command_name" in
  snapshot)
    capture_snapshot "${2:-now}" >/dev/null
    ;;
  memory)
    capture_snapshot now >/dev/null
    print_memory
    ;;
  status)
    write_no_change_evidence
    print_memory
    ;;
  restore-evidence)
    write_no_change_evidence
    printf 'No Android changes were applied; no restore action is required.\n'
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    fedora_die "Unknown command: $command_name"
    exit 64
    ;;
esac

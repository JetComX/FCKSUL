#!/system/bin/sh

# FCKSUL v1.0
# The script is fully open-source, free to use, and follows the Apache-2.0 open-source license.
# Github: https://github.com/JetComX/FCKSUL

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    */*) ;;
    *) SCRIPT_PATH="$(pwd)/$SCRIPT_PATH" ;;
esac
SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="/data/local/tmp"

LOG_FILE="$SCRIPT_DIR/fcksul.log"
CONF_FILE="$SCRIPT_DIR/fcksul.conf"
PID_FILE="$SCRIPT_DIR/fcksul.pid"
DEBUG_FILE="$SCRIPT_DIR/fcksul.debug.log"
WHITELIST_FILE="$SCRIPT_DIR/fcksul.whitelist"
LOG_TAG="FCKSUL"
MAX_LOG_SIZE=1048576

log_to_file() {
    local level="$1"; shift
    local lv_upper=$(echo "$level" | tr 'a-z' 'A-Z')
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$lv_upper] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null
    if command -v timeout >/dev/null 2>&1; then
        timeout 1 log -p "$level" -t "$LOG_TAG" "$*" 2>/dev/null
    else
        log -p "$level" -t "$LOG_TAG" "$*" 2>/dev/null
    fi
}
log_msg() { log_to_file i "$@"; }
log_err() { log_to_file e "$@"; }
log_dbg() { log_to_file d "$@"; }
log_sep() { log_to_file i "--------------------日志标记-------------------"; }

safe_exec() {
    local t="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$t" "$@" 2>/dev/null
    else
        "$@" 2>/dev/null &
        local p=$!
        local waited=0
        while kill -0 "$p" 2>/dev/null; do
            sleep 0.5
            waited=$((waited + 1))
            if [ "$waited" -ge $((t * 2)) ]; then
                kill -9 "$p" 2>/dev/null
                wait "$p" 2>/dev/null
                return 124
            fi
        done
        wait "$p" 2>/dev/null
        return $?
    fi
}

rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        local size=$(wc -c < "$LOG_FILE" 2>/dev/null)
        size=${size:-0}
        if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "$LOG_FILE.old" 2>/dev/null
            log_msg "[LOG] 日志已轮转 -> $LOG_FILE.old"
        fi
    fi
}

check_root() {
    if [ "$(id -u 2>/dev/null)" = "0" ]; then
        return 0
    fi

    echo "[?] 没有找到 su 命令，再试试..."

    SU_BIN=""
    for p in /system/bin/su /system/xbin/su /sbin/su /su/bin/su /system/sbin/su; do
        if [ -x "$p" ]; then
            SU_BIN="$p"
            break
        fi
    done

    if [ -z "$SU_BIN" ] && command -v su >/dev/null 2>&1; then
        SU_BIN=$(command -v su)
    fi

    if [ -z "$SU_BIN" ]; then
        echo "[!] 还是没有找到 su 命令，你的设备可能没有Root权限 :("
        exit 1
    fi

    echo "[#] 找到 su 命令：$SU_BIN"
    exec "$SU_BIN" -c "sh '$SCRIPT_PATH'"
}

is_our_monitor() {
    local pid="$1"
    [ -z "$pid" ] && return 1
    [ ! -r "/proc/$pid/cmdline" ] && return 1
    local cmdline
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    echo "$cmdline" | grep -q -- "--monitor"
}

scan_all_monitors() {
    local pids=""
    if command -v pgrep >/dev/null 2>&1; then
        pids=$(safe_exec 2 pgrep -f -- "--monitor" 2>/dev/null)
    fi
    if [ -z "$pids" ]; then
        pids=$(safe_exec 3 ps -A -o PID,ARGS 2>/dev/null \
            | grep -- "--monitor" \
            | grep -v grep \
            | awk '{print $1}')
    fi
    for p in $pids; do
        [ -z "$p" ] && continue
        [ "$p" = "$$" ] && continue
        if is_our_monitor "$p"; then
            echo "$p"
        fi
    done
}

validate_time() {
    echo "$1" | grep -Eq '^([01][0-9]|2[0-3]):([0-5][0-9])$'
}

time_to_minutes() {
    local h=$(echo "$1" | cut -d: -f1 | sed 's/^0*//')
    local m=$(echo "$1" | cut -d: -f2 | sed 's/^0*//')
    [ -z "$h" ] && h=0
    [ -z "$m" ] && m=0
    echo $((h * 60 + m))
}

is_in_time_range() {
    [ -z "$START_TIME" ] && return 1
    [ -z "$END_TIME" ] && return 1
    local now_min=$(time_to_minutes "$(date '+%H:%M')")
    local start_min=$(time_to_minutes "$START_TIME")
    local end_min=$(time_to_minutes "$END_TIME")

    if [ "$start_min" -le "$end_min" ]; then
        [ "$now_min" -ge "$start_min" ] && [ "$now_min" -lt "$end_min" ] && return 0
    else
        { [ "$now_min" -ge "$start_min" ] || [ "$now_min" -lt "$end_min" ]; } && return 0
    fi
    return 1
}

is_past_today() {
    [ -z "$START_TIME" ] && return 1
    [ -z "$END_TIME" ] && return 1
    local start_min=$(time_to_minutes "$START_TIME")
    local end_min=$(time_to_minutes "$END_TIME")
    local now_min=$(time_to_minutes "$(date '+%H:%M')")
    if [ "$start_min" -le "$end_min" ]; then
        [ "$now_min" -ge "$end_min" ] && return 0
    fi
    return 1
}

load_config() {
    if [ -f "$CONF_FILE" ]; then
        . "$CONF_FILE"
        START_TIME="$START_TIME"
        END_TIME="$END_TIME"
        return 0
    fi
    return 1
}

save_config() {
    echo "START_TIME=$1" > "$CONF_FILE"
    echo "END_TIME=$2"  >> "$CONF_FILE"
    log_sep
    log_msg "新配置已保存"
    log_msg "开始时间: $1"
    log_msg "结束时间: $2"
    log_sep
}

get_foreground_package() {
    local pkg=""

    pkg=$(safe_exec 3 dumpsys activity activities \
        | grep -m1 -E 'mResumedActivity|topResumedActivity' \
        | grep -oE '[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+' \
        | head -1)

    if [ -z "$pkg" ]; then
        pkg=$(safe_exec 3 dumpsys window \
            | grep -m1 -E 'mCurrentFocus|mFocusedApp' \
            | grep -oE '[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+' \
            | head -1)
    fi

    if [ -z "$pkg" ]; then
        pkg=$(safe_exec 3 dumpsys activity top \
            | grep -m1 'ACTIVITY' \
            | awk '{print $2}' \
            | sed 's/\/.*//')
    fi

    echo "$pkg"
}

is_whitelisted() {
    local pkg="$1"

    case "$pkg" in
        com.android.systemui|com.android.launcher*)
            return 0 ;;
    esac

    if [ -f "$WHITELIST_FILE" ]; then
        while IFS= read -r w; do
            [ -z "$w" ] && continue
            case "$w" in \#*) continue ;; esac
            case "$pkg" in
                $w) return 0 ;;
            esac
        done < "$WHITELIST_FILE"
    fi

    return 1
}

kill_package_hard() {
    local pkg="$1"

    log_dbg "  -> am force-stop $pkg"
    safe_exec 3 am force-stop "$pkg"
    local rc=$?
    if [ "$rc" = "124" ]; then
        log_err "  -> am force-stop 超时 3 秒，已强制中断"
    fi

    local pids=""
    if command -v pidof >/dev/null 2>&1; then
        pids=$(safe_exec 2 pidof "$pkg" | tr '\n' ' ')
    fi

    if [ -z "$pids" ]; then
        pids=$(safe_exec 3 ps -A 2>/dev/null \
            | grep -F "$pkg" \
            | awk '{print $2}' | tr '\n' ' ')
    fi

    if [ -n "$pids" ] && [ "$pids" != " " ]; then
        log_dbg "  -> 残留进程 PID: $pids，kill -9"
        kill -9 $pids 2>/dev/null
    fi

    return $rc
}

monitor_loop() {
    echo $$ > "$PID_FILE"

    log_sep
    clear
    log_msg "监控循环启动 (pid=$$)"
    log_msg "限制时段: $START_TIME - $END_TIME"
    log_msg "当前时间: $(date '+%H:%M:%S')"

    if is_past_today; then
        log_msg "今天的限制时段已结束 (${END_TIME} 已过)，任务作废"
        log_msg "监控进程立即退出"
        log_sep
        rm -f "$PID_FILE"
        exit 0
    fi

    if is_in_time_range; then
        log_msg "当前已处于限制时段内，立即开始监控"
    else
        log_msg "当前不在限制时段，等待 ${START_TIME} 到来..."
    fi
    log_sep

    local in_range=0
    local last_pkg=""
    local last_heartbeat=$(date +%s)

    while true; do
        if ! load_config; then
            sleep 10; continue
        fi

        local now_str=$(date '+%H:%M:%S')
        local now_ts=$(date +%s)

        if [ "$in_range" -eq 1 ]; then
            if [ $((now_ts - last_heartbeat)) -ge 60 ]; then
                log_msg "[心跳] 监控运行中 (当前 $now_str，限制时段 $START_TIME-$END_TIME)"
                last_heartbeat=$now_ts
            fi
        fi

        if is_in_time_range; then
            if [ "$in_range" -eq 0 ]; then
                log_sep
                log_msg "进入限制时段"
                log_msg "开始: $START_TIME  结束: $END_TIME"
                log_msg "当前时间: $(date '+%Y-%m-%d') $now_str"
                log_sep
                in_range=1
                last_pkg=""
                last_heartbeat=$now_ts
            fi

            local loop_start=$(date +%s)

            local pkg=$(get_foreground_package)
            if [ -z "$pkg" ]; then
                sleep 1; continue
            fi

            if is_whitelisted "$pkg"; then
                if [ "$pkg" != "$last_pkg" ]; then
                    log_msg "[放过白名单] $pkg (当前 $now_str)"
                    last_pkg="$pkg"
                fi
                sleep 1; continue
            fi

            if [ "$pkg" != "$last_pkg" ]; then
                log_msg "[检测到] $pkg (当前 $now_str)"
                last_pkg="$pkg"
            fi

            local t0=$(date '+%H:%M:%S')
            kill_package_hard "$pkg"

            sleep 1
            local check=$(get_foreground_package)
            local t1=$(date '+%H:%M:%S')
            if [ "$check" = "$pkg" ]; then
                log_err "[未生效] $pkg ($t0 -> $t1)，追加 kill -9"
                kill_package_hard "$pkg"
            else
                log_msg "[已退出] $pkg  ($t0 -> $t1)"
            fi
            last_pkg=""

            local loop_end=$(date +%s)
            local cost=$((loop_end - loop_start))
            if [ "$cost" -gt 8 ]; then
                log_err "[警告] 本次循环耗时 ${cost}s，疑似某命令卡顿"
            fi

            sleep 1
        else
            if [ "$in_range" -eq 1 ]; then
                log_sep
                log_msg "离开限制时段"
                log_msg "时段配置: $START_TIME - $END_TIME"
                log_msg "离开时间: $(date '+%Y-%m-%d') $now_str"
                log_msg "任务完成，监控进程退出"
                log_sep
                rm -f "$PID_FILE"
                exit 0
            fi
            sleep 20
        fi
    done
}

stop_monitor() {
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$old_pid" ] && [ "$old_pid" != "$$" ]; then
            if is_our_monitor "$old_pid"; then
                kill "$old_pid" 2>/dev/null
                sleep 1
                kill -0 "$old_pid" 2>/dev/null && kill -9 "$old_pid" 2>/dev/null
                log_msg "已停止旧监控进程 PID=$old_pid"
            else
                log_dbg "PID $old_pid 不是本脚本进程，忽略"
            fi
        fi
        rm -f "$PID_FILE"
    fi

    local leftovers=$(scan_all_monitors)
    for p in $leftovers; do
        log_msg "扫描发现残留监控进程 PID=$p，强制清除"
        kill -9 "$p" 2>/dev/null
    done
}

start_monitor() {
    stop_monitor

    : > "$DEBUG_FILE" 2>/dev/null

    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$SCRIPT_PATH" --monitor >/dev/null 2>>"$DEBUG_FILE" &
    else
        nohup sh "$SCRIPT_PATH" --monitor >/dev/null 2>>"$DEBUG_FILE" &
    fi

    local waited=0
    while [ ! -f "$PID_FILE" ] && [ "$waited" -lt 20 ]; do
        sleep 0.5
        waited=$((waited + 1))
    done

    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        log_msg "监控进程已启动 PID=$pid (独立会话)"
        return 0
    else
        log_dbg "监控进程未生成 PID 文件，已等待 $((waited / 2)) 秒"
        if [ -s "$DEBUG_FILE" ]; then
            log_dbg "调试日志内容:"
            while IFS= read -r line; do
                log_dbg "  $line"
            done < "$DEBUG_FILE"
        fi
        return 1
    fi
}

show_app_info() {
    local pkg="$1"
    echo ""
    echo "───────────────────────────────────────"
    echo "              应用信息"
    echo "───────────────────────────────────────"
    echo "[*] 包名: $pkg"

    local dump=$(safe_exec 3 dumpsys package "$pkg" 2>/dev/null)

    local app_name=""
    if [ -n "$dump" ]; then
        app_name=$(echo "$dump" | grep -m1 "nonLocalizedLabel=" | sed 's/.*nonLocalizedLabel=//;s/ .*//')
        [ "$app_name" = "null" ] && app_name=""
        [ "$app_name" = "0" ] && app_name=""
    fi
    if [ -n "$app_name" ]; then
        echo "[*] 应用名: $app_name"
    fi

    local apk_path=$(safe_exec 3 pm path "$pkg" 2>/dev/null | sed 's/package://' | head -1)
    [ -n "$apk_path" ] && echo "[*] APK 路径: $apk_path"

    local version=""
    if [ -n "$dump" ]; then
        version=$(echo "$dump" | grep -m1 "versionName=" | sed 's/.*versionName=//' | cut -d' ' -f1)
    fi
    [ -n "$version" ] && echo "[*] 版本: $version"

    if safe_exec 3 pm list packages -s 2>/dev/null | grep -q "^package:$pkg$"; then
        echo "[*] 类型: 系统应用"
    else
        echo "[*] 类型: 第三方应用"
    fi

    local launcher_act=$(safe_exec 3 cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -1)
    if [ -n "$launcher_act" ] && echo "$launcher_act" | grep -q "$pkg"; then
        echo "[*] 入口: $launcher_act"
    fi

    echo "───────────────────────────────────────"
}

whitelist_add() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "              添加白名单"
    echo "═══════════════════════════════════════"
    printf "[?] 请输入应用包名（如 com.tencent.mm）： "
    read input_pkg

    if [ -z "$input_pkg" ]; then
        echo "[!] 包名为空，已取消"
        return
    fi

    if ! echo "$input_pkg" | grep -Eq '^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$'; then
        echo "[!] 包名格式不正确"
        return
    fi

    if ! safe_exec 3 pm list packages "$input_pkg" 2>/dev/null | grep -q "^package:$input_pkg$"; then
        echo "[!] 系统中未安装该应用: $input_pkg"
        return
    fi

    if is_whitelisted "$input_pkg"; then
        echo "[!] 该应用已在白名单中"
        show_app_info "$input_pkg"
        return
    fi

    show_app_info "$input_pkg"

    printf "[?] 确认添加到白名单？(y/n): "
    read confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "$input_pkg" >> "$WHITELIST_FILE"
        log_msg "用户添加白名单: $input_pkg"
        echo "[*] 已添加: $input_pkg"
    else
        echo "[*] 已取消"
    fi
}

whitelist_del() {
    if [ ! -f "$WHITELIST_FILE" ] || [ ! -s "$WHITELIST_FILE" ]; then
        echo "[!] 用户白名单为空"
        return
    fi

    echo ""
    echo "═══════════════════════════════════════"
    echo "              删除白名单"
    echo "═══════════════════════════════════════"
    echo "[*] 当前用户白名单:"
    local i=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in \#*) continue ;; esac
        i=$((i + 1))
        echo "    $i) $line"
    done < "$WHITELIST_FILE"

    if [ "$i" -eq 0 ]; then
        echo "    (空)"
        return
    fi

    echo ""
    printf "[?] 请输入要删除的包名: "
    read del_pkg

    if [ -z "$del_pkg" ]; then
        echo "[*] 已取消"
        return
    fi

    if grep -q "^$del_pkg$" "$WHITELIST_FILE" 2>/dev/null; then
        grep -v "^$del_pkg$" "$WHITELIST_FILE" > "$WHITELIST_FILE.tmp"
        mv "$WHITELIST_FILE.tmp" "$WHITELIST_FILE"
        log_msg "用户删除白名单: $del_pkg"
        echo "[*] 已删除: $del_pkg"
    else
        echo "[!] 未在白名单中找到: $del_pkg"
    fi
}

whitelist_list() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "              白名单列表"
    echo "═══════════════════════════════════════"
    echo "[*] 内置白名单（不可删除）:"
    echo "    com.android.systemui        系统 UI"
    echo "    com.android.launcher*       桌面（通配）"
    echo ""
    echo "[*] 用户白名单:"
    if [ -f "$WHITELIST_FILE" ] && [ -s "$WHITELIST_FILE" ]; then
        local found=0
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            case "$line" in \#*) continue ;; esac
            echo "    $line"
            found=1
        done < "$WHITELIST_FILE"
        [ "$found" = "0" ] && echo "    (空)"
    else
        echo "    (空)"
    fi
    echo "═══════════════════════════════════════"
    echo ""
}

whitelist_menu() {
    while true; do
        echo ""
        echo "╔═════════════════════╗"
        echo "║     白名单管理      ║"
        echo "╠═════════════════════╣"
        echo "║  1. 查看白名单      ║"
        echo "║  2. 添加白名单      ║"
        echo "║  3. 删除白名单      ║"
        echo "║  4. 返回            ║"
        echo "╚═════════════════════╝"
        printf "[?] 请选择 [1-4]: "
        read wl_choice

        case "$wl_choice" in
            1) whitelist_list; printf "\n[*] 按回车继续..."; read dummy ;;
            2) whitelist_add; printf "\n[*] 按回车继续..."; read dummy ;;
            3) whitelist_del; printf "\n[*] 按回车继续..."; read dummy ;;
            4) return ;;
            *) echo "[!] 无效选择"; sleep 1 ;;
        esac
    done
}

diagnose() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "              诊断信息"
    echo "═══════════════════════════════════════"
    echo "[*] 当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "[*] 时间段:   ${START_TIME:-未设置} - ${END_TIME:-未设置}"
    echo "[*] timeout:  $(command -v timeout || echo '不存在')"
    echo "[*] setsid:   $(command -v setsid || echo '不存在')"
    echo "[*] pgrep:    $(command -v pgrep || echo '不存在')"
    echo ""
    echo "[*] 前台包名: [$(get_foreground_package)]"
    echo ""
    echo "[*] 全系统监控进程扫描"
    local all=$(scan_all_monitors)
    if [ -z "$all" ]; then
        echo "[*] 无监控进程运行"
    else
        for p in $all; do
            echo "[*] PID $p: $(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)"
        done
    fi
    echo ""
    echo "[*] PID 文件"
    if [ -f "$PID_FILE" ]; then
        echo "[*] 内容: $(cat "$PID_FILE")"
    else
        echo "[*] 不存在"
    fi
    echo ""
    echo "[*] 调试日志（最后 10 行）"
    if [ -s "$DEBUG_FILE" ]; then
        tail -n 10 "$DEBUG_FILE"
    else
        echo "[*] (空)"
    fi
}

show_help() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "              使用说明"
    echo "═══════════════════════════════════════"
    echo "[*] 1. 选择菜单 1 设置限制时间段"
    echo "[*]    输入开始与结束时间（24 小时制）"
    echo "[*]    例如 06:00 到 13:00"
    echo "[*]"
    echo "[*] 2. 时间段内，任何非白名单应用切到前台"
    echo "[*]    都会被强制退出（1~2 秒响应）"
    echo "[*]"
    echo "[*] 3. 使用菜单 3 可管理白名单"
    echo "[*]    白名单内的应用在限制时段可正常使用"
    echo "[*]    内置白名单：systemui、launcher"
    echo "[*]"
    echo "[*] 4. 时间段结束，监控进程自动退出"
    echo "[*]    不会残留后台进程"
    echo "[*]"
    echo "[*] 5. 菜单 6 退出时会清理所有相关进程"
    echo "═══════════════════════════════════════"
    echo ""
}

setup_time() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "              设置限制时间段"
    echo "═══════════════════════════════════════"
    echo ""
    local start_input end_input

    while true; do
        printf "[?] 请输入开始时间（如 06:00）： "
        read start_input
        validate_time "$start_input" && break
        echo "[!] 格式错误！请输入 HH:MM（00:00 - 23:59）"
    done

    while true; do
        printf "[?] 请输入结束时间（如 13:00）： "
        read end_input
        validate_time "$end_input" && break
        echo "[!] 格式错误！请输入 HH:MM（00:00 - 23:59）"
    done

    echo ""
    echo "───────────────────────────────────────"
    echo "[*] 开始时间: $start_input"
    echo "[*] 结束时间: $end_input"
    echo "[*] 当前时间: $(date '+%H:%M:%S')"

    if [ "$(time_to_minutes "$start_input")" -le "$(time_to_minutes "$end_input")" ]; then
        if [ "$(time_to_minutes "$(date '+%H:%M')")" -ge "$(time_to_minutes "$end_input")" ]; then
            echo ""
            echo "[!] 注意：今天的结束时间 ${end_input} 已过"
            echo "[!] 监控进程启动后将立即退出，不会执行"
        fi
    fi

    echo "───────────────────────────────────────"
    printf "[?] 确认保存并启动监控？(y/n): "
    read confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        save_config "$start_input" "$end_input"
        START_TIME="$start_input"
        END_TIME="$end_input"
        if start_monitor; then
            echo ""
            echo "[*] 设置成功！监控已启动（独立会话运行）。"
        else
            echo ""
            echo "[!] 设置已保存，但监控未启动。"
            echo "[!] 可能原因：1) 今天时段已过  2) 启动异常"
            echo "[!] 请通过菜单 4 查看诊断信息。"
        fi
        echo "[*] 日志文件: $LOG_FILE"
        echo "[*] 调试日志: $DEBUG_FILE"
    else
        echo "[*] 已取消，未保存。"
    fi
}

show_status() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "              当前状态"
    echo "═══════════════════════════════════════"
    if load_config; then
        echo "[*] 限制时间段: $START_TIME - $END_TIME"
        if is_in_time_range; then
            echo "[*] 当前状态: 限制中（所有应用会被强制退出）"
        else
            echo "[*] 当前状态: 非限制时段"
        fi
    else
        echo "[!] 限制时间段: 未设置"
    fi
    echo "[*] 当前时间: $(date '+%Y-%m-%d %H:%M:%S')"

    local all=$(scan_all_monitors)
    if [ -n "$all" ]; then
        echo "[*] 监控进程: 运行中"
        for p in $all; do
            echo "[*]            PID=$p"
        done
    else
        echo "[*] 监控进程: 未运行"
    fi
    echo "[*] 日志文件: $LOG_FILE"
    echo "[*] 配置文件: $CONF_FILE"
    echo "═══════════════════════════════════════"
    echo ""
}

kill_all_related() {
    log_sep
    log_msg "用户退出脚本"
    log_msg "开始清理所有进程..."

    local my_pid=$$
    local kill_list=""

    if [ -f "$PID_FILE" ]; then
        local p=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$p" ] && kill_list="$kill_list $p"
        rm -f "$PID_FILE"
    fi

    local monitors=$(scan_all_monitors)
    [ -n "$monitors" ] && kill_list="$kill_list $monitors"

    local by_path=""
    if command -v pgrep >/dev/null 2>&1; then
        by_path=$(safe_exec 2 pgrep -f "$SCRIPT_PATH" 2>/dev/null)
    fi
    if [ -z "$by_path" ]; then
        by_path=$(safe_exec 3 ps -A -o PID,ARGS 2>/dev/null \
            | grep -F "$SCRIPT_PATH" \
            | grep -v grep \
            | awk '{print $1}')
    fi
    [ -n "$by_path" ] && kill_list="$kill_list $by_path"

    local ppid=$PPID
    if [ -n "$ppid" ] && [ "$ppid" != "0" ] && [ "$ppid" != "1" ]; then
        local pname=$(cat /proc/$ppid/comm 2>/dev/null)
        case "$pname" in
            su|magisk|ksud)
                kill_list="$kill_list $ppid"
                ;;
        esac
    fi

    local unique_list=""
    for p in $kill_list; do
        [ -z "$p" ] && continue
        [ "$p" = "$my_pid" ] && continue
        case " $unique_list " in
            *" $p "*) ;;
            *) unique_list="$unique_list $p" ;;
        esac
    done

    for p in $unique_list; do
        if kill -0 "$p" 2>/dev/null; then
            local cmd=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | cut -c1-80)
            log_msg "终止进程 PID=$p ($cmd)"
            kill -9 "$p" 2>/dev/null
        fi
    done

    sleep 1

    local leftover=$(scan_all_monitors)
    if [ -n "$leftover" ]; then
        log_err "仍有残留进程: $leftover"
    else
        log_msg "清理完毕，无残留"
    fi

    log_msg "脚本退出"
    log_sep
    exit 0
}

main_menu() {
    while true; do
        echo ""
        echo "╔═════════════════════╗"
        echo "║       FCKSUL        ║"
        echo "║     版本: v1.0      ║"
        echo "╠═════════════════════╣"
        echo "║  1. 设置限制时间段  ║"
        echo "║  2. 查看当前状态    ║"
        echo "║  3. 白名单管理      ║"
        echo "║  4. 诊断            ║"
        echo "║  5. 咋用？          ║"
        echo "║  6. 退出            ║"
        echo "╚═════════════════════╝"
        printf "[?] 请选择 [1-6]: "
        read choice

        case "$choice" in
            1) setup_time; printf "\n[*] 按回车返回主菜单..."; read dummy ;;
            2) show_status; printf "\n[*] 按回车返回主菜单..."; read dummy ;;
            3) whitelist_menu ;;
            4) diagnose; printf "\n[*] 按回车返回主菜单..."; read dummy ;;
            5) show_help; printf "\n[*] 按回车返回主菜单..."; read dummy ;;
            6) echo "[*] 准备退出..."; kill_all_related ;;
            *) echo "[!] 无效选择"; sleep 1 ;;
        esac
    done
}

trap '' HUP

if [ "$1" = "--monitor" ]; then
    if [ "$(id -u)" != "0" ]; then
        echo "[!] 意外错误（应该是monitor）"
        exit 1
    fi

    rotate_log
    if load_config; then
        monitor_loop
    else
        echo "[*] 无配置" >&2
        exit 1
    fi
    exit 0
fi

check_root
log_sep
log_msg "脚本启动"
log_msg "Root 权限已获取 UID=$(id -u)  设备=$(getprop ro.product.model 2>/dev/null)"
log_msg "Android 版本: $(getprop ro.build.version.release 2>/dev/null)"
log_msg "脚本目录: $SCRIPT_DIR"
log_msg "timeout: $(command -v timeout || echo '无')  setsid: $(command -v setsid || echo '无')"
log_sep

rotate_log

if [ -f "$PID_FILE" ] || [ -n "$(scan_all_monitors)" ]; then
    log_msg "启动前清理旧监控进程..."
    stop_monitor
fi

if load_config; then
    if [ ! -f "$PID_FILE" ]; then
        start_monitor
    fi
fi

main_menu
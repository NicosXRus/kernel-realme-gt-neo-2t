#!/system/bin/sh
# Boot service for RMX3357 (MT6893); runs post-/data-decrypt

# Main System Optimization & Debloat (runs after boot completed)
(
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 2
    done
    sleep 5

    write_node() {
        [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null
    }

    # Telemetry and logging
    setprop persist.sys.hans.enable false
    setprop sys.hans.enable false

    # Stop MediaTek debug & baseband loggers
    for svc in emdlogger connsyslogger mobile_log_d bt_dump wifi_dump lbs_dbg netdiag; do
        stop "$svc" 2>/dev/null
    done

    # Stop ColorOS telemetry & crash aggregators (oiface kept running for GPU DVFS & touch-boost)
    for svc in common_dcs criticallog phoenix_log_manager; do
        stop "$svc" 2>/dev/null
    done

    # ART runtime
    setprop dalvik.vm.heapstartsize 12m
    total_ram_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [ -n "$total_ram_kb" ] && [ "$total_ram_kb" -ge 10000000 ]; then
        setprop dalvik.vm.heapgrowthlimit 512m
        setprop dalvik.vm.heapsize 768m
    else
        setprop dalvik.vm.heapgrowthlimit 384m
        setprop dalvik.vm.heapsize 512m
    fi
    setprop dalvik.vm.heapminfree 12m
    setprop dalvik.vm.heapmaxfree 48m
    setprop dalvik.vm.heaptargetutilization 0.70

    
    write_node /proc/perfmgr/boost_ctrl/eas_ctrl/sched_boost 0

    # VFS security
    write_node /proc/sys/fs/protected_symlinks 1
    write_node /proc/sys/fs/protected_hardlinks 1
    write_node /proc/sys/fs/protected_fifos 2
    write_node /proc/sys/fs/protected_regular 2

    # Cpusets
    write_node /dev/cpuset/restricted/cpus 0-3
    write_node /dev/cpuset/foreground/cpus 0-7

    # IRQ affinity (pin BT and housekeeping to little cores)
    sync_bt_affinity() {
        
        bt_pid=$(pidof com.android.bluetooth 2>/dev/null)
        if [ -n "$bt_pid" ]; then
            for _pid in $bt_pid; do
            for task in /proc/"$_pid"/task/*; do
                [ -r "$task/comm" ] || continue
                read -r comm < "$task/comm" 2>/dev/null
                case "$comm" in
                    bt_a2dp_source_*|bt_stack_manage*|bta_media_*|BluetoothA2dp*)
                        tid="${task##*/}"
                        [ -w /dev/cpuset/system-background/tasks ] && echo "$tid" > /dev/cpuset/system-background/tasks 2>/dev/null
                        taskset -p 0f "$tid" >/dev/null 2>&1
                        ;;
                esac
            done
            done
        fi

        
        hal_pid=$(pidof android.hardware.bluetooth@1.1-service-mediatek 2>/dev/null)
        if [ -n "$hal_pid" ]; then
            for _pid in $hal_pid; do
                [ -w /dev/cpuset/system-background/cgroup.procs ] && echo "$_pid" > /dev/cpuset/system-background/cgroup.procs 2>/dev/null
                for task in /proc/"$_pid"/task/*; do
                    [ -d "$task" ] || continue
                    tid="${task##*/}"
                    taskset -p 0f "$tid" >/dev/null 2>&1
                done
            done
        fi

        
        [ -w /proc/irq/18/smp_affinity ] && echo 01 > /proc/irq/18/smp_affinity 2>/dev/null   # TX DMA -> Core 0
        [ -w /proc/irq/19/smp_affinity ] && echo 02 > /proc/irq/19/smp_affinity 2>/dev/null   # RX DMA -> Core 1
        [ -w /proc/irq/228/smp_affinity ] && echo 04 > /proc/irq/228/smp_affinity 2>/dev/null # BT Wakeup -> Core 2
        [ -w /proc/irq/17/smp_affinity ] && echo 08 > /proc/irq/17/smp_affinity 2>/dev/null   # BTIF -> Core 3
        [ -w /proc/irq/281/smp_affinity ] && echo 08 > /proc/irq/281/smp_affinity 2>/dev/null # BTCVSD -> Core 3

        
        for b in android.hardware.health@2.1-service android.hardware.power.stats-impl.oplus android.hardware.thermal@2.0-service.mtk; do
            spid=$(pidof "$b" 2>/dev/null)
            if [ -n "$spid" ]; then
                for _pid in $spid; do
                    [ -w /dev/cpuset/system-background/cgroup.procs ] && echo "$_pid" > /dev/cpuset/system-background/cgroup.procs 2>/dev/null
                    for task in /proc/"$_pid"/task/*; do
                        [ -d "$task" ] || continue
                        tid="${task##*/}"
                        taskset -p 0f "$tid" >/dev/null 2>&1
                    done
                done
            fi
        done

        
        ril_pid=$(pidof mtkfusionrild 2>/dev/null)
        if [ -n "$ril_pid" ]; then
            for _pid in $ril_pid; do
                [ -w /dev/cpuset/system-background/cgroup.procs ] && echo "$_pid" > /dev/cpuset/system-background/cgroup.procs 2>/dev/null
            done
        fi
    }
    sync_bt_affinity

    
    write_node /proc/sys/kernel/sched_migration_cost_ns 200000
    write_node /proc/sys/kernel/timer_migration 1
    write_node /sys/module/ged/parameters/gx_force_cpu_boost 0
    write_node /sys/module/ged/parameters/boost_amp 1
    write_node /sys/kernel/ged/hal/dvfs_margin_value 15
    write_node /sys/module/ged/parameters/gx_fb_dvfs_margin 150

    # Storage and VM
    for dev in /sys/block/sd*; do
        if [ -d "$dev/queue" ]; then
            write_node "$dev/queue/nr_requests" 256
            write_node "$dev/queue/read_ahead_kb" 256
            write_node "$dev/queue/rq_affinity" 1
            write_node "$dev/queue/nomerges" 0
            write_node "$dev/queue/add_random" 0
        fi
    done

    write_node /proc/sys/vm/swappiness 20
    write_node /proc/sys/vm/vfs_cache_pressure 70
    write_node /proc/sys/vm/dirty_expire_centisecs 200
    write_node /proc/sys/vm/dirty_writeback_centisecs 100
    write_node /proc/sys/vm/dirty_ratio 20

    # TCP tuning
    write_node /proc/sys/net/ipv4/tcp_congestion_control cubic
    write_node /proc/sys/net/ipv4/tcp_ecn 2
    write_node /proc/sys/net/ipv4/tcp_slow_start_after_idle 0
    write_node /proc/sys/net/ipv4/tcp_autocorking 0
    write_node /proc/sys/net/ipv4/tcp_fastopen 3

    
    chown root:system /proc/config.gz && chmod 0440 /proc/config.gz 2>/dev/null || true
    setprop persist.vendor.aee.log.status 0
    stop aee_aed 2>/dev/null || true
    stop aee_aed64 2>/dev/null || true
    stop aee_aedv 2>/dev/null || true
    stop aee_aedv64 2>/dev/null || true
) &

# Launch power profile sync daemon
case "$0" in
    /*) MODDIR="${0%/*}" ;;
    *)  MODDIR="/data/adb/modules/rmx3357_neocore_companion" ;;
esac
if [ -f "$MODDIR/power_sync.sh" ] && ! pgrep -f "$MODDIR/power_sync.sh" >/dev/null 2>&1; then
    nohup /system/bin/sh "$MODDIR/power_sync.sh" >/dev/null 2>&1 < /dev/null &
fi

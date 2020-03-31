#! /vendor/bin/sh

# Copyright (c) 2012-2013, 2016-2018, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

target=`getprop ro.board.platform`

function configure_zram_parameters() {
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    low_ram=`getprop ro.config.low_ram`

    # Zram disk - 75% for Go devices.
    # For 512MB Go device, size = 384MB, set same for Non-Go.
    # For 1GB Go device, size = 768MB, set same for Non-Go.
    # For >=2GB Non-Go devices, size = 50% of RAM size. Limit the size to 4GB.
    # And enable lz4 zram compression for Go targets.

    let RamSizeGB="( $MemTotal / 1048576 ) + 1"
    diskSizeUnit=M
    if [ $RamSizeGB -le 3 ]; then
        let zRamSizeMB="( $RamSizeGB * 1024 ) * 3 / 4"
    else
        let zRamSizeMB="( $RamSizeGB * 1024 ) / 2"
    fi

    # use MB avoid 32 bit overflow
    if [ $zRamSizeMB -gt 4096 ]; then
        let zRamSizeMB=4096
    fi

    if [ "$low_ram" == "true" ]; then
        echo lz4 > /sys/block/zram0/comp_algorithm
    fi

    if [ -f /sys/block/zram0/disksize ]; then
        if [ -f /sys/block/zram0/use_dedup ]; then
            echo 1 > /sys/block/zram0/use_dedup
        fi

        echo "$zRamSizeMB""$diskSizeUnit" > /sys/block/zram0/disksize

        # ZRAM may use more memory than it saves if SLAB_STORE_USER
        # debug option is enabled.
        if [ -e /sys/kernel/slab/zs_handle ]; then
            echo 0 > /sys/kernel/slab/zs_handle/store_user
        fi
        if [ -e /sys/kernel/slab/zspage ]; then
            echo 0 > /sys/kernel/slab/zspage/store_user
        fi

        mkswap /dev/block/zram0
        swapon /dev/block/zram0 -p 32758
    fi
}

function configure_read_ahead_kb_values() {
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    # Set 128 for <= 3GB &
    # set 512 for >= 4GB targets.
    if [ $MemTotal -le 3145728 ]; then
        echo 128 > /sys/block/mmcblk0/bdi/read_ahead_kb
        echo 128 > /sys/block/mmcblk0/queue/read_ahead_kb
        echo 128 > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
        echo 128 > /sys/block/mmcblk0rpmb/queue/read_ahead_kb
        echo 128 > /sys/block/dm-0/queue/read_ahead_kb
        echo 128 > /sys/block/dm-1/queue/read_ahead_kb
        echo 128 > /sys/block/dm-2/queue/read_ahead_kb
    else
        echo 512 > /sys/block/mmcblk0/bdi/read_ahead_kb
        echo 512 > /sys/block/mmcblk0/queue/read_ahead_kb
        echo 512 > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
        echo 512 > /sys/block/mmcblk0rpmb/queue/read_ahead_kb
        echo 512 > /sys/block/dm-0/queue/read_ahead_kb
        echo 512 > /sys/block/dm-1/queue/read_ahead_kb
        echo 512 > /sys/block/dm-2/queue/read_ahead_kb
    fi
}

function disable_core_ctl() {
    if [ -f /sys/devices/system/cpu/cpu0/core_ctl/enable ]; then
        echo 0 > /sys/devices/system/cpu/cpu0/core_ctl/enable
    else
        echo 1 > /sys/devices/system/cpu/cpu0/core_ctl/disable
    fi
}

function enable_swap() {
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    SWAP_ENABLE_THRESHOLD=1048576
    swap_enable=`getprop ro.vendor.qti.config.swap`

    # Enable swap initially only for 1 GB targets
    if [ "$MemTotal" -le "$SWAP_ENABLE_THRESHOLD" ] && [ "$swap_enable" == "true" ]; then
        # Static swiftness
        echo 1 > /proc/sys/vm/swap_ratio_enable
        echo 70 > /proc/sys/vm/swap_ratio

        # Swap disk - 200MB size
        if [ ! -f /data/vendor/swap/swapfile ]; then
            dd if=/dev/zero of=/data/vendor/swap/swapfile bs=1m count=200
        fi
        mkswap /data/vendor/swap/swapfile
        swapon /data/vendor/swap/swapfile -p 32758
    fi
}

function configure_memory_parameters() {
    # Set Memory parameters.
    #
    # Set per_process_reclaim tuning parameters
    # All targets will use vmpressure range 50-70,
    # All targets will use 512 pages swap size.
    #
    # Set Low memory killer minfree parameters
    # 32 bit Non-Go, all memory configurations will use 15K series
    # 32 bit Go, all memory configurations will use uLMK + Memcg
    # 64 bit will use Google default LMK series.
    #
    # Set ALMK parameters (usually above the highest minfree values)
    # vmpressure_file_min threshold is always set slightly higher
    # than LMK minfree's last bin value for all targets. It is calculated as
    # vmpressure_file_min = (last bin - second last bin ) + last bin
    #
    # Set allocstall_threshold to 0 for all targets.
    #

ProductName=`getprop ro.product.name`
low_ram=`getprop ro.config.low_ram`

if [ "$ProductName" == "msmnile" ] || [ "$ProductName" == "kona" ] || [ "$ProductName" == "sdmshrike_au" ]; then
      # Enable ZRAM
      configure_zram_parameters
      # configure_read_ahead_kb_values
      echo 0 > /proc/sys/vm/page-cluster
else
    arch_type=`uname -m`
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    # Set parameters for 32-bit Go targets.
    if [ $MemTotal -le 1048576 ] && [ "$low_ram" == "true" ]; then
        # Disable KLMK, ALMK, PPR & Core Control for Go devices
        echo 0 > /sys/module/lowmemorykiller/parameters/enable_lmk
        echo 0 > /sys/module/lowmemorykiller/parameters/enable_adaptive_lmk
        echo 0 > /sys/module/process_reclaim/parameters/enable_process_reclaim
        disable_core_ctl
        # Enable oom_reaper for Go devices
        if [ -f /proc/sys/vm/reap_mem_on_sigkill ]; then
            echo 1 > /proc/sys/vm/reap_mem_on_sigkill
        fi
    else

        # Read adj series and set adj threshold for PPR and ALMK.
        # This is required since adj values change from framework to framework.
        adj_series=`cat /sys/module/lowmemorykiller/parameters/adj`
        adj_1="${adj_series#*,}"
        set_almk_ppr_adj="${adj_1%%,*}"

        # PPR and ALMK should not act on HOME adj and below.
        # Normalized ADJ for HOME is 6. Hence multiply by 6
        # ADJ score represented as INT in LMK params, actual score can be in decimal
        # Hence add 6 considering a worst case of 0.9 conversion to INT (0.9*6).
        # For uLMK + Memcg, this will be set as 6 since adj is zero.
        set_almk_ppr_adj=$(((set_almk_ppr_adj * 6) + 6))
        echo $set_almk_ppr_adj > /sys/module/lowmemorykiller/parameters/adj_max_shift

        # Calculate vmpressure_file_min as below & set for 64 bit:
        # vmpressure_file_min = last_lmk_bin + (last_lmk_bin - last_but_one_lmk_bin)
        if [ "$arch_type" == "aarch64" ]; then
            minfree_series=`cat /sys/module/lowmemorykiller/parameters/minfree`
            minfree_1="${minfree_series#*,}" ; rem_minfree_1="${minfree_1%%,*}"
            minfree_2="${minfree_1#*,}" ; rem_minfree_2="${minfree_2%%,*}"
            minfree_3="${minfree_2#*,}" ; rem_minfree_3="${minfree_3%%,*}"
            minfree_4="${minfree_3#*,}" ; rem_minfree_4="${minfree_4%%,*}"
            minfree_5="${minfree_4#*,}"

            vmpres_file_min=$((minfree_5 + (minfree_5 - rem_minfree_4)))
            echo $vmpres_file_min > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
            if [ $MemTotal -gt 5505024 ]; then
                echo "18432,23040,27648,32256,85296,120640" > /sys/module/lowmemorykiller/parameters/minfree
            else
                echo "18432,23040,27648,32256,55296,100640" > /sys/module/lowmemorykiller/parameters/minfree
            fi
        else
            # Set LMK series, vmpressure_file_min for 32 bit non-go targets.
            # Disable Core Control, enable KLMK for non-go 8909.
            if [ "$ProductName" == "msm8909" ]; then
                disable_core_ctl
                echo 1 > /sys/module/lowmemorykiller/parameters/enable_lmk
            fi
        echo "15360,19200,23040,26880,34415,43737" > /sys/module/lowmemorykiller/parameters/minfree
        echo 53059 > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
        fi

        # Enable adaptive LMK for all targets &
        # use Google default LMK series for all 64-bit targets >=2GB.
        echo 0 > /sys/module/lowmemorykiller/parameters/enable_adaptive_lmk

        # Enable oom_reaper
        if [ -f /sys/module/lowmemorykiller/parameters/oom_reaper ]; then
            echo 1 > /sys/module/lowmemorykiller/parameters/oom_reaper
        fi

        # Set PPR parameters
        if [ -f /sys/devices/soc0/soc_id ]; then
            soc_id=`cat /sys/devices/soc0/soc_id`
        else
            soc_id=`cat /sys/devices/system/soc/soc0/id`
        fi

        case "$soc_id" in
          # Do not set PPR parameters for premium targets
          # sdm845 - 321, 341
          # msm8998 - 292, 319
          # msm8996 - 246, 291, 305, 312
          "321" | "341" | "292" | "319" | "246" | "291" | "305" | "312")
            ;;
          *)
            #Set PPR parameters for all other targets.
            echo $set_almk_ppr_adj > /sys/module/process_reclaim/parameters/min_score_adj
            echo 0 > /sys/module/process_reclaim/parameters/enable_process_reclaim
            echo 50 > /sys/module/process_reclaim/parameters/pressure_min
            echo 70 > /sys/module/process_reclaim/parameters/pressure_max
            echo 30 > /sys/module/process_reclaim/parameters/swap_opt_eff
            echo 512 > /sys/module/process_reclaim/parameters/per_swap_size
            ;;
        esac
    fi

    # Set allocstall_threshold to 0 for all targets.
    echo 0 > /sys/module/vmpressure/parameters/allocstall_threshold

    configure_zram_parameters

    # configure_read_ahead_kb_values

    enable_swap
fi
}

function enable_memory_features()
{
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    if [ $MemTotal -le 2097152 ]; then
        #Enable B service adj transition for 2GB or less memory
        setprop ro.vendor.qti.sys.fw.bservice_enable true
        setprop ro.vendor.qti.sys.fw.bservice_limit 5
        setprop ro.vendor.qti.sys.fw.bservice_age 5000

        #Enable Delay Service Restart
        setprop ro.vendor.qti.am.reschedule_service true
    fi
}

function start_hbtp()
{
        # Start the Host based Touch processing but not in the power off mode.
        bootmode=`getprop ro.bootmode`
        if [ "charger" != $bootmode ]; then
                start vendor.hbtp
        fi
}

case "$target" in
    "sdm660")

        # Set the default IRQ affinity to the primary cluster. When a
        # CPU is isolated/hotplugged, the IRQ affinity is adjusted
        # to one of the CPU from the default IRQ affinity mask.
        echo f > /proc/irq/default_smp_affinity

        if [ -f /sys/devices/soc0/soc_id ]; then
                soc_id=`cat /sys/devices/soc0/soc_id`
        else
                soc_id=`cat /sys/devices/system/soc/soc0/id`
        fi

        if [ -f /sys/devices/soc0/hw_platform ]; then
                hw_platform=`cat /sys/devices/soc0/hw_platform`
        else
                hw_platform=`cat /sys/devices/system/soc/soc0/hw_platform`
        fi

        panel=`cat /sys/class/graphics/fb0/modes`
        if [ "${panel:5:1}" == "x" ]; then
            panel=${panel:2:3}
        else
            panel=${panel:2:4}
        fi

        #Apply settings for sdm660, sdm636,sda636
        case "$soc_id" in
                "317" | "324" | "325" | "326" | "345" | "346" )

            # cpuset settings
            echo 0-7 > /dev/cpuset/top-app/cpus
            echo 0-1 > /dev/cpuset/background/cpus
            echo 0-2 > /dev/cpuset/system-background/cpus
            echo 0-2,4-7 > /dev/cpuset/foreground/cpus

            # disable thermal bcl hotplug to switch governor
            echo 0 > /sys/module/msm_thermal/core_control/enabled

            # online CPU0
            echo 1 > /sys/devices/system/cpu/cpu0/online
            # configure governor settings for little cluster
            echo "schedutil" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
            echo 20000 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/down_rate_limit_us
            echo 500 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/up_rate_limit_us
            echo 633600 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
            # online CPU4
            echo 1 > /sys/devices/system/cpu/cpu4/online
            # configure governor settings for big cluster
            echo "schedutil" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
            echo 20000 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/down_rate_limit_us
            echo 500 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/up_rate_limit_us
            echo 1113600 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq

            # bring all cores online
            echo 1 > /sys/devices/system/cpu/cpu0/online
            echo 1 > /sys/devices/system/cpu/cpu1/online
            echo 1 > /sys/devices/system/cpu/cpu2/online
            echo 1 > /sys/devices/system/cpu/cpu3/online
            echo 1 > /sys/devices/system/cpu/cpu4/online
            echo 1 > /sys/devices/system/cpu/cpu5/online
            echo 1 > /sys/devices/system/cpu/cpu6/online
            echo 1 > /sys/devices/system/cpu/cpu7/online

            # configure LPM
            echo N > /sys/module/lpm_levels/system/pwr/cpu0/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/cpu1/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/cpu2/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/cpu3/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/cpu4/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/cpu5/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/cpu6/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/cpu7/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/pwr-l2-dynret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/perf-l2-dynret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/pwr-l2-ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/perf-l2-ret/idle_enabled
            # enable LPM
            echo 0 > /sys/module/lpm_levels/parameters/sleep_disabled

            # re-enable thermal and BCL hotplug
            echo 1 > /sys/module/msm_thermal/core_control/enabled

            #Enable input boost configuration
            echo "0:1401600" > /sys/module/cpu_boost/parameters/input_boost_freq
            echo 60 > /sys/module/cpu_boost/parameters/input_boost_ms
            echo "0:0 1:0 2:0 3:0 4:1747200 5:0 6:0 7:0" > /sys/module/cpu_boost/parameters/powerkey_input_boost_freq
            echo 400 > /sys/module/cpu_boost/parameters/powerkey_input_boost_ms

            # Set Memory parameters
            configure_memory_parameters

            # set lmk minfree for MemTotal greater than 6G
	    arch_type=`uname -m`
	    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	    MemTotal=${MemTotalStr:16:8}
	    if [ "$arch_type" == "aarch64" ] && [ $MemTotal -gt 5505024 ]; then
	        echo "18432,23040,27648,32256,85296,120640" > /sys/module/lowmemorykiller/parameters/minfree
	    fi

            # Enable bus-dcvs
            for cpubw in /sys/class/devfreq/*qcom,cpubw*
            do
                echo "bw_hwmon" > $cpubw/governor
                echo 50 > $cpubw/polling_interval
                echo "1525 3143 5859 7759 9887 10327 11863 13763" > $cpubw/bw_hwmon/mbps_zones
                echo 4 > $cpubw/bw_hwmon/sample_ms
                echo 85 > $cpubw/bw_hwmon/io_percent
                echo 100 > $cpubw/bw_hwmon/decay_rate
                echo 50 > $cpubw/bw_hwmon/bw_step
                echo 20 > $cpubw/bw_hwmon/hist_memory
                echo 0 > $cpubw/bw_hwmon/hyst_length
                echo 80 > $cpubw/bw_hwmon/down_thres
                echo 0 > $cpubw/bw_hwmon/low_power_ceil_mbps
                echo 34 > $cpubw/bw_hwmon/low_power_io_percent
                echo 20 > $cpubw/bw_hwmon/low_power_delay
                echo 0 > $cpubw/bw_hwmon/guard_band_mbps
                echo 250 > $cpubw/bw_hwmon/up_scale
                echo 1600 > $cpubw/bw_hwmon/idle_mbps
            done

            echo "cpufreq" > /sys/class/devfreq/soc:qcom,mincpubw/governor

            # Start cdsprpcd only for sdm660 and disable for sdm630
            start vendor.cdsprpcd
##D2SP&F7A has no hbtp feature
#            # Start Host based Touch processing
#                case "$hw_platform" in
#                        "MTP" | "Surf" | "RCM" | "QRD" )
#                        start_hbtp
#                        ;;
#                esac
#end
            ;;
        esac
        #Apply settings for sdm630 and Tahaa
        case "$soc_id" in
            "318" | "327" | "385" )

            # Start Host based Touch processing
            case "$hw_platform" in
                "MTP" | "Surf" | "RCM" | "QRD" )
                start_hbtp
                ;;
            esac

            # Setting b.L scheduler parameters
            echo 85 > /proc/sys/kernel/sched_upmigrate
            echo 85 > /proc/sys/kernel/sched_downmigrate
            echo 900 > /proc/sys/kernel/sched_group_upmigrate
            echo 900 > /proc/sys/kernel/sched_group_downmigrate
            echo 0 > /proc/sys/kernel/sched_select_prev_cpu_us
            echo 400000 > /proc/sys/kernel/sched_freq_inc_notify
            echo 400000 > /proc/sys/kernel/sched_freq_dec_notify
            echo 3 > /proc/sys/kernel/sched_spill_nr_run

            #init task load, restrict wakeups to preferred cluster
            echo 15 > /proc/sys/kernel/sched_init_task_load
            echo 1 > /proc/sys/kernel/sched_restrict_cluster_spill
            echo 50000 > /proc/sys/kernel/sched_short_burst_ns

            # cpuset settings
            echo 0-3 > /dev/cpuset/background/cpus
            echo 0-3 > /dev/cpuset/system-background/cpus

            # disable thermal bcl hotplug to switch governor
            echo 0 > /sys/module/msm_thermal/core_control/enabled
            for mode in /sys/devices/soc.0/qcom,bcl.*/mode
            do
                echo -n disable > $mode
            done
            for hotplug_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_mask
            do
                bcl_hotplug_mask=`cat $hotplug_mask`
                echo 0 > $hotplug_mask
            done
            for hotplug_soc_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_soc_mask
            do
                bcl_soc_hotplug_mask=`cat $hotplug_soc_mask`
                echo 0 > $hotplug_soc_mask
            done
            for mode in /sys/devices/soc.0/qcom,bcl.*/mode
            do
                echo -n enable > $mode
            done

            # online CPU0
            echo 1 > /sys/devices/system/cpu/cpu0/online
            # configure governor settings for Big cluster(CPU0 to CPU3)
            echo "interactive" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
            echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/use_sched_load
            echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/use_migration_notif
            echo "19000 1344000:39000" > /sys/devices/system/cpu/cpu0/cpufreq/interactive/above_hispeed_delay
            echo 85 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/go_hispeed_load
            echo 20000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/timer_rate
            echo 1344000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/hispeed_freq
            echo 0 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/io_is_busy
            echo "85 1344000:80" > /sys/devices/system/cpu/cpu0/cpufreq/interactive/target_loads
            echo 39000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/min_sample_time
            echo 0 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/max_freq_hysteresis
            echo 787200 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
            echo 0 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/ignore_hispeed_on_notif

            # online CPU4
            echo 1 > /sys/devices/system/cpu/cpu4/online
            # configure governor settings for Little cluster(CPU4 to CPU7)
            echo "interactive" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
            echo 1 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/use_sched_load
            echo 1 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/use_migration_notif
            echo "19000 1094400:39000" > /sys/devices/system/cpu/cpu4/cpufreq/interactive/above_hispeed_delay
            echo 85 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/go_hispeed_load
            echo 20000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/timer_rate
            echo 1094400 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/hispeed_freq
            echo 0 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/io_is_busy
            echo "85 1094400:80" > /sys/devices/system/cpu/cpu4/cpufreq/interactive/target_loads
            echo 39000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/min_sample_time
            echo 0 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/max_freq_hysteresis
            echo 614400 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq
            echo 0 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/ignore_hispeed_on_notif

            # bring all cores online
            echo 1 > /sys/devices/system/cpu/cpu0/online
            echo 1 > /sys/devices/system/cpu/cpu1/online
            echo 1 > /sys/devices/system/cpu/cpu2/online
            echo 1 > /sys/devices/system/cpu/cpu3/online
            echo 1 > /sys/devices/system/cpu/cpu4/online
            echo 1 > /sys/devices/system/cpu/cpu5/online
            echo 1 > /sys/devices/system/cpu/cpu6/online
            echo 1 > /sys/devices/system/cpu/cpu7/online

            # configure LPM
            echo N > /sys/module/lpm_levels/system/perf/cpu0/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/cpu1/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/cpu2/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/cpu3/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/cpu4/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/cpu5/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/cpu6/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/cpu7/ret/idle_enabled
            echo N > /sys/module/lpm_levels/system/pwr/pwr-l2-dynret/idle_enabled
            echo N > /sys/module/lpm_levels/system/perf/perf-l2-dynret/idle_enabled
            # enable LPM
            echo 0 > /sys/module/lpm_levels/parameters/sleep_disabled

            # re-enable thermal and BCL hotplug
            echo 1 > /sys/module/msm_thermal/core_control/enabled
            for mode in /sys/devices/soc.0/qcom,bcl.*/mode
            do
                echo -n disable > $mode
            done
            for hotplug_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_mask
            do
                echo $bcl_hotplug_mask > $hotplug_mask
            done
            for hotplug_soc_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_soc_mask
            do
                echo $bcl_soc_hotplug_mask > $hotplug_soc_mask
            done
            for mode in /sys/devices/soc.0/qcom,bcl.*/mode
            do
                echo -n enable > $mode
            done

            # Set Memory parameters
            configure_memory_parameters

            # Enable bus-dcvs
            for cpubw in /sys/class/devfreq/*qcom,cpubw*
            do
                echo "bw_hwmon" > $cpubw/governor
                echo 50 > $cpubw/polling_interval
                echo 762 > $cpubw/min_freq
                echo "1525 3143 4173 5195 5859 7759 9887 10327" > $cpubw/bw_hwmon/mbps_zones
                echo 4  > $cpubw/bw_hwmon/sample_ms
                echo 85 > $cpubw/bw_hwmon/io_percent
                echo 20 > $cpubw/bw_hwmon/hist_memory
                echo 0  > $cpubw/bw_hwmon/hyst_length
                echo 100 > $cpubw/bw_hwmon/decay_rate
                echo 50 > $cpubw/bw_hwmon/bw_step
                echo 80 > $cpubw/bw_hwmon/down_thres
                echo 0  > $cpubw/bw_hwmon/low_power_ceil_mbps
                echo 50 > $cpubw/bw_hwmon/low_power_io_percent
                echo 20 > $cpubw/bw_hwmon/low_power_delay
                echo 0  > $cpubw/bw_hwmon/guard_band_mbps
                echo 250 > $cpubw/bw_hwmon/up_scale
                echo 1600 > $cpubw/bw_hwmon/idle_mbps
            done

            for memlat in /sys/class/devfreq/*qcom,memlat-cpu*
            do
                echo "mem_latency" > $memlat/governor
                echo 10 > $memlat/polling_interval
                echo 400 > $memlat/mem_latency/ratio_ceil
            done

            echo "cpufreq" > /sys/class/devfreq/soc:qcom,mincpubw/governor
            ;;
        esac
    ;;
esac


chown -h system /sys/devices/system/cpu/cpufreq/ondemand/sampling_rate
chown -h system /sys/devices/system/cpu/cpufreq/ondemand/sampling_down_factor
chown -h system /sys/devices/system/cpu/cpufreq/ondemand/io_is_busy

emmc_boot=`getprop vendor.boot.emmc`
case "$emmc_boot"
    in "true")
        chown -h system /sys/devices/platform/rs300000a7.65536/force_sync
        chown -h system /sys/devices/platform/rs300000a7.65536/sync_sts
        chown -h system /sys/devices/platform/rs300100a7.65536/force_sync
        chown -h system /sys/devices/platform/rs300100a7.65536/sync_sts
    ;;
esac

# Post-setup services
setprop vendor.post_boot.parsed 1

# Let kernel know our image version/variant/crm_version
if [ -f /sys/devices/soc0/select_image ]; then
    image_version="10:"
    image_version+=`getprop ro.build.id`
    image_version+=":"
    image_version+=`getprop ro.build.version.incremental`
    image_variant=`getprop ro.product.name`
    image_variant+="-"
    image_variant+=`getprop ro.build.type`
    oem_version=`getprop ro.build.version.codename`
    echo 10 > /sys/devices/soc0/select_image
    echo $image_version > /sys/devices/soc0/image_version
    echo $image_variant > /sys/devices/soc0/image_variant
    echo $oem_version > /sys/devices/soc0/image_crm_version
fi

# Parse misc partition path and set property
misc_link=$(ls -l /dev/block/bootdevice/by-name/misc)
real_path=${misc_link##*>}
setprop persist.vendor.mmi.misc_dev_path $real_path

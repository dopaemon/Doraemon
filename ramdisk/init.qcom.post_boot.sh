#! /vendor/bin/sh

exec > /dev/kmsg 2>&1

if [ ! -f /sbin/recovery ] && [ ! -f /dev/.post_boot ]; then
  # Run once
  touch /dev/.post_boot

  # Setup readahead
  find /sys/devices -name read_ahead_kb | while read node; do echo 2048 > $node; done


  # Hook up to existing init.qcom.post_boot.sh
  while [ ! -f /vendor/bin/init.qcom.post_boot.sh ]; do
    sleep 1
  done
  if ! mount | grep -q /vendor/bin/init.qcom.post_boot.sh; then
    # Replace msm_irqbalance.conf
    echo "PRIO=1,1,1,1,0,0,0,0
#arch_timer, arm-pmu, arch_mem_timer, msm_drm, glink_lpass, kgsl
IGNORED_IRQ=19,21,38,115,188,332" > /dev/msm_irqbalance.conf
    chmod 644 /dev/msm_irqbalance.conf
    mount --bind /dev/msm_irqbalance.conf /vendor/etc/msm_irqbalance.conf
    chcon "u:object_r:vendor_configs_file:s0" /vendor/etc/msm_irqbalance.conf
    killall msm_irqbalance

    mount --bind "$0" /vendor/bin/init.qcom.post_boot.sh
    chcon "u:object_r:qti_init_shell_exec:s0" /vendor/bin/init.qcom.post_boot.sh

    exit
  fi
fi

# Setup readahead
find /sys/devices -name read_ahead_kb | while read node; do echo 128 > $node; done


# Disable wsf, beacause we are using efk.
# wsf Range : 1..1000 So set to bare minimum value 1.
echo 1 > /proc/sys/vm/watermark_scale_factor


# Enable bus-dcvs
for device in /sys/devices/platform/soc
do
    for cpubw in $device/*cpu-cpu-llcc-bw/devfreq/*cpu-cpu-llcc-bw
    do
	echo "bw_hwmon" > $cpubw/governor
	echo 40 > $cpubw/polling_interval
	echo "2288 4577 7110 9155 12298 14236 15258" > $cpubw/bw_hwmon/mbps_zones
	echo 4 > $cpubw/bw_hwmon/sample_ms
	echo 50 > $cpubw/bw_hwmon/io_percent
	echo 20 > $cpubw/bw_hwmon/hist_memory
	echo 10 > $cpubw/bw_hwmon/hyst_length
	echo 30 > $cpubw/bw_hwmon/down_thres
	echo 0 > $cpubw/bw_hwmon/guard_band_mbps
	echo 250 > $cpubw/bw_hwmon/up_scale
	echo 1600 > $cpubw/bw_hwmon/idle_mbps
	echo 14236 > $cpubw/max_freq
    done

    for llccbw in $device/*cpu-llcc-ddr-bw/devfreq/*cpu-llcc-ddr-bw
    do
	echo "bw_hwmon" > $llccbw/governor
	echo 40 > $llccbw/polling_interval
	echo "1720 2929 3879 5931 6881 7980" > $llccbw/bw_hwmon/mbps_zones
	echo 4 > $llccbw/bw_hwmon/sample_ms
	echo 80 > $llccbw/bw_hwmon/io_percent
	echo 20 > $llccbw/bw_hwmon/hist_memory
	echo 10 > $llccbw/bw_hwmon/hyst_length
	echo 30 > $llccbw/bw_hwmon/down_thres
	echo 0 > $llccbw/bw_hwmon/guard_band_mbps
	echo 250 > $llccbw/bw_hwmon/up_scale
	echo 1600 > $llccbw/bw_hwmon/idle_mbps
	echo 6881 > $llccbw/max_freq
    done

    for npubw in $device/*npu-npu-ddr-bw/devfreq/*npu-npu-ddr-bw
    do
	echo 1 > /sys/devices/virtual/npu/msm_npu/pwr
	echo "bw_hwmon" > $npubw/governor
	echo 40 > $npubw/polling_interval
	echo "1720 2929 3879 5931 6881 7980" > $npubw/bw_hwmon/mbps_zones
	echo 4 > $npubw/bw_hwmon/sample_ms
	echo 80 > $npubw/bw_hwmon/io_percent
	echo 20 > $npubw/bw_hwmon/hist_memory
	echo 6  > $npubw/bw_hwmon/hyst_length
	echo 30 > $npubw/bw_hwmon/down_thres
	echo 0 > $npubw/bw_hwmon/guard_band_mbps
	echo 250 > $npubw/bw_hwmon/up_scale
	echo 0 > $npubw/bw_hwmon/idle_mbps
	echo 0 > /sys/devices/virtual/npu/msm_npu/pwr
    done

done

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

# blkio
echo 2000 > /dev/blkio/blkio.group_idle
echo 0 > /dev/blkio/background/blkio.group_idle
echo 1000 > /dev/blkio/blkio.weight
echo 200 > /dev/blkio/background/blkio.weight


# UFS powersave
echo 1 > /sys/devices/platform/soc/1d84000.ufshc/clkgate_enable
echo 1 > /sys/devices/platform/soc/1d84000.ufshc/hibern8_on_idle_enable

# lpm_level
echo N > /sys/module/lpm_levels/parameters/sleep_disabled


# Remove unused swapfile
rm -f /data/vendor/swap/swapfile 2>/dev/null
sync

# Setup swap
echo 4294967296 > /sys/devices/virtual/block/vbswap0/disksize
echo 135 > /proc/sys/vm/swappiness
chmod 755 /sbin/mkswap
/sbin/mkswap /dev/block/vbswap0
swapon /dev/block/vbswap0 -p 32758

# s2idle
echo "s2idle" > /sys/power/mem_sleep

# Disable sleep_disabled
echo N > /sys/module/lpm_levels/parameters/sleep_disabled

exit 0

# Binary will be appended afterwards
ELF          ?    ?	      @       @          @ 8  @         @       @       @       ?      ?                                                                                                                    ?      ?     ?     ?      ?                   ?      ?     ?     ?      ?                                     ?       ?              Q?td                                                  R?td   ?      ?     ?     X      X             /system/bin/linker64       ?      Android    r19c                                                            5345600                                                                                   
                                                                                                                     	                                       ?	                    p             ?     
      t      J                                                                  b                      ?     ?            j                      '                      O                      w    ??p             ?     ?            ,                      ]                      !                      8                      p    ??p                                   ?     ?            ?    ???             i                      >                      U                       libdl.so libc.so fprintf calloc close __sF getpagesize fsync __libc_init open lseek __cxa_atexit perror fwrite _edata __bss_start _end main __PREINIT_ARRAY__ __FINI_ARRAY__ __INIT_ARRAY__ LIBC                                   
          c    ?       ?           
      ?           ?     ?           ?     ?           ?     ?       
                                                                                            	           (                  0                  8                  @                  H                  P                  X                  `                  h                          ?{???  ??G???? ? ? ? ??  ?@? ? ??  ?@?" ? ??  ?
@?B ? ??  ?@?b ? ??  ?@?? ? ??  ?@?? ? ??  ?@?? ? ??  ?@?? ? ??  ?"@?? ??  ?&@?"? ??  ?*@?B? ??  ?.@?b? ??  ?2@??? ??  ?6@??? ?? ?  ?? ??{??  ??G??  ?)?G??  ?J?G? g? N??=? ??  ?B?G?? ????? ?????@  ?  ??_?  ??'??  ?B??? ???????_?? q?W??O??{??? ?? T @?? 2???? 1` T?2??? *????? ??*???*?????@?? T????? *?? ?? 2?2?~@?? 2?????  ? ? ?   ? ?.????????@??2?*?????@?????@?R?*7  )?@?????????* Q}@??*?*????  ?!0?B?R?*?????*?????*?????{C??OB??WA??*?_???_??  ?" @??G?  ?!0.? ??????? 2y???   ? ?.?f???? 2t????  ??G?   ? ?/?a?R??? 2|???? 2j???Usage: %s /path/to/swapfile
 Failed to open file Setting up swapspace version 1, size = %jd bytes
 image is too small
 SWAPSPACE2                                                                                                                                                                                                                                                                                                                                                                                                                           ????????        ????????        ????????                             
               ?     !                     ?                          ?                          ?             ?             `      
       ?                                           ?            P                           H             ?             x       	              ???o    ?      ???o           ???o    z      ???o                                                                                           ?     
      ?             ?     ?                             ?      ?      ?      ?      ?      ?      ?      ?      ?      ?      ?      ?      ?      ?      Android (5058415 based on r339409) clang version 8.0.2 (https://android.googlesource.com/toolchain/clang 40173bab62ec746213857d083c0e8b0abb568790) (https://android.googlesource.com/toolchain/llvm 7a6618d69e7e8111e1d49dc9e7813767c5ca756a) (based on LLVM 8.0.2svn)  .shstrtab .interp .note.android.ident .hash .dynsym .dynstr .gnu.version .gnu.version_r .rela.dyn .rela.plt .text .rodata .preinit_array .init_array .fini_array .dynamic .got .got.plt .bss .comment                                                                                                                                                     ?                              '             ?      ?      ?                            -             `      `      X                          5             ?      ?      ?                              =   ???o       z      z      2                            J   ???o       ?      ?                                   Y             ?      ?      x                            c      B       H      H      P                          h             ?      ?                                   m             ?	      ?	      ?                             s             ?      ?      ?                              {             ?     ?                                   ?             ?     ?                                   ?             ?     ?                                   ?             ?     ?      ?                           ?             ?     ?      0                             ?             ?     ?      ?                             ?             p     p                                    ?      0               p                                                        w      ?                              

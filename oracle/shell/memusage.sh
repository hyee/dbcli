#!/bin/bash

echo "Memory Summary By User:"
echo "======================="
(echo "user rss(MB) vmem(MB)";
 for user in $(users | tr ' ' '\n' | sort -u); do
   echo $user $(ps -U $user --no-headers -o rss,vsz \
     | awk '{rss+=$1; vmem+=$2} END{print int(rss/1024)" "int(vmem/1024)}')
 done | sort -k3
) | column -t

echo "============================================================"
echo 
echo "Oracle Memory Usage:"
echo "===================="
total_shmsize=0
total_hugepagesize=0
total=0

for pid in `ps -ef |  grep -E "ora_pmon|asm_pmon"|egrep -v "grep"|  awk '{print $2}' | uniq`; do
    echo
    echo "-----------------------------------------------------------"
    sid=` ps -eaf|grep $pid | grep -v " grep "|awk '{print substr($NF,10)}'`
    echo "Instance $sid:"
    FNAME="/proc/$pid/smaps"
    if [[ -r $FNAME && -w $FNAME ]]; then
        shmsize=`grep -A 1 'SYSV00000000' $FNAME | grep "^Size:" | awk 'BEGIN{sum=0}{sum+=$2}END{print sum/1024}' |  awk -F"." '{print $1}'`
        hugepagesize=`grep -B 11 'KernelPageSize:     2048 kB' $FNAME | grep "^Size:" | awk 'BEGIN{sum=0}{sum+=$2}END{print sum/1024}' | awk -F"." '{print $1}'`
        echo "  INSTANCE SGA (SMALL/HUGE page)"  : $shmsize "MB"
        echo "  INSTANCE SGA (HUGE PAGE)" $hugepagesize "MB"
        echo "  Percent Huge page :"  $(( $hugepagesize *100 / $shmsize  )) "%"
        total_hugepagesize=$(( $total_hugepagesize + $hugepagesize ))
    else
        smon=`ps -eaf | grep -- "$sid" |grep ora_smon_| grep -v " grep " | awk '{print $2}'`
        shmsize=`pmap $smon 2>&1 | grep "K .*SYSV00000000"| sort | awk '{print $1 " " substr($2,1,length($2)-1)}' | uniq | awk ' BEGIN { sum=0 } { sum+=$2} END {print sum/1024}'`
        echo "  INSTANCE SGA (SMALL/HUGE page)"  : $shmsize "MB"
    fi
    pids=`ps -eaf | grep -- "$sid" | grep -v " grep " | awk '{print $2}'`
    mem=`pmap $pids 2>&1 | grep "K " | sort | awk '{print $1 " " substr($2,1,length($2)-1)}' | uniq | awk ' BEGIN { sum=0 } { sum+=$2} END {print sum/1024}'`
    pga=`echo "$mem - $shmsize"|bc`
    echo "  Non-SGA Memory: $pga MB"
    echo "  Total Used Memory:  $mem MB"
    total_shmsize=$(( $shmsize + $total_shmsize ))
    total=`echo "$total + $mem"|bc`
done
echo
echo "-----------------------------------------------------------"
echo "All Instances:"
echo "  SGA TOTAL (SMALL/HUGE page)"  : $total_shmsize "MB"
if [[ $total_hugepagesize > 0 ]]; then
    echo "  SGA TOTAL (HUGE PAGE)" $total_hugepagesize "MB"
    echo "  Percent Huge page :"  $(( $total_hugepagesize *100 / $total_shmsize  )) "%"
fi
pga=`echo "$total - $total_shmsize"|bc`
echo "  Non-SGA Memory: $pga MB"
echo "  Total Used Memory: $total MB"
#!/bin/bash
page_size=$(getconf PAGE_SIZE)
proc() {
    eval "$1" | while IFS= read -r line
    do
       pid=$(echo $line | awk '{print $2}')
       if [ -e "/proc/$pid/statm" ]; then
           memory_pages=$(awk '{print $3}' "/proc/$pid/statm")
           echo $(($memory_pages * $page_size /1024)) "$line"
       else
           echo "0 $line"
       fi
    done           
}


echo "============================================================"
echo "Memory Summary By User:"
echo "============================================================"
(echo "User RSS(MB) SHARE(MB)  VMEM(MB)  COUNT"
 echo "---- ------- --------   --------  -----"
 proc "ps aux --no-headers"| awk '{rss[$2]+=$7;vmem[$2]+=$6;pct[$2]+=$1;c[$2]+=1}; END {for (i in rss) {print i,int(rss[i]/1024),int(pct[i]/1024),int(vmem[i]/1024),c[i]}}' \
       | sort -k2 | awk '{rss+=$2;vmem+=$4;pct+=$3;c1+=$5; print $0};END {print "TOTAL",rss,pct,vmem,c1}') | column -t
echo "============================================================"
echo 
echo "Oracle Memory Usage:"
echo "============================================================"
total_shmsize=0
total_hugepagesize=0
total=0

for pid in `ps -ef |  grep -E "ora_pmon|asm_pmon|db_pmon"|egrep -v "grep"|  awk '{print $2}' | uniq`; do
    sid=`ps -eaf|grep $pid | grep -v " grep "|awk '{print substr($NF,10)}'`
    echo "Instance \"$sid\":"
    echo "*****************"
    (echo "Type RSS(MB) SHARE(MB)  VMEM(MB)  COUNT"
     echo "---- ------- --------   --------  -----"
     proc "ps aux --no-headers|grep -E \" (ora_|oracle|db_|asm_)\"|grep $sid| grep -v grep" |awk '{
              i="local";
              if(index($12, "_pmon_") != 0)
                i="pmon";
              else if(index($12, "_smon_") != 0)
                i="smon";
              else if(index($12, "_dbw") != 0)
                i="dbwr"; 
              else if(index($12, "_lg") != 0)
                i="lgwr";                  
              else if(index($13, "NO") != 0)  
                i="remote";
              rss[i]+=$7;vmem[i]+=$6;pct[i]+=$1;c[i]+=1}
              END {for (i in rss) {print i,int(rss[i]/1024),int(pct[i]/1024),int(vmem[i]/1024),c[i]}
     }' | sort -k2 | awk '{rss+=$2;vmem+=$4;pct+=$3;c1+=$5; print $0};END {print "TOTAL",rss,pct,vmem,c1}') | column -t
    echo " "
    FNAME="/proc/$pid/smaps"
    if [[ -r $FNAME && -w $FNAME ]]; then
        shmsize=`grep -A 1 'SYSV00000000' $FNAME | grep "^Size:" | awk 'BEGIN{sum=0}{sum+=$2}END{print sum/1024}' |  awk -F"." '{print $1}'`
        hugepagesize=`grep -B 11 'KernelPageSize:     2048 kB' $FNAME | grep "^Size:" | awk 'BEGIN{sum=0}{sum+=$2}END{print sum/1024}' | awk -F"." '{print $1}'`
        echo "SGA (SMALL/HUGE page) :" $shmsize "MB"
        echo "SGA (HUGE PAGE)       :" $hugepagesize "MB"
        echo "Percent Huge page     :" $(( $hugepagesize *100 / $shmsize  )) "%"
        total_hugepagesize=$(( $total_hugepagesize + $hugepagesize ))
    else
        smon=`ps -eaf |grep -E " (ora_|oracle|db_|asm_)"| grep -- "$sid" |grep _smon_| grep -v " grep " | awk '{print $2}'`
        shmsize=`pmap $smon 2>&1 | grep "K .*SYSV00000000"| sort | awk '{print $1 " " substr($2,1,length($2)-1)}' | uniq | awk ' BEGIN { sum=0 } { sum+=$2} END {print sum/1024}'`
        echo "SGA (SMALL/HUGE page) :" $shmsize "MB"
    fi
    pids=`ps -eaf |grep -E " (ora_|oracle|db_|asm_)"| grep -- "$sid" | grep -v " grep " | awk '{print $2}'`
    pga=`pmap -x $pids 2>&1  | egrep "^\w{16}" | grep -v shmid | awk ' BEGIN { sum=0 } { sum+=$3} END {print sum/1024}'`
    mem=`echo "$pga + $shmsize"|bc`
    echo "Non-SGA Memory        : $pga MB"
    echo "Total Used Memory     : $mem MB"
    total_shmsize=$(( $shmsize + $total_shmsize ))
    total=`echo "$total + $mem"|bc`
    echo "-----------------------------------"
    echo
done
echo "All Instances:"
echo "**************"
echo "SGA TOTAL (SMALL/HUGE page):" $total_shmsize "MB"
if [[ $total_hugepagesize > 0 ]]; then
    echo "SGA TOTAL (HUGE PAGE)      :" $total_hugepagesize "MB"
    echo "Percent Huge page          :" $(( $total_hugepagesize *100 / $total_shmsize  )) "%"
fi
pga=`echo "$total - $total_shmsize"|bc`
echo "Non-SGA Memory             : $pga MB"
echo "Total Used Memory          : $total MB"
echo "============================================================"
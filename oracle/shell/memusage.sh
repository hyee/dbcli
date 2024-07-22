#!/bin/bash
page_size=$(getconf PAGE_SIZE)

pga=0
fmap() {
   pga=0
   echo "$1" | while IFS= read -r line
   do
       #mb=$(pmap -x $line 2>&1  | egrep "^\w{16}" | grep -v shmid | awk ' BEGIN { sum=0 } { sum+=$3} END {print int(sum/1024)}')
       #pmap -x 237878 | egrep "^\w{16}" |grep -v SYSV00000000 | sort -nk3| tail -20
       mb=`pmap -x  $line  | grep "total kB" | awk '{print int($4/1024)}'`
       pga=$(( $pga + $mb ))
       echo "PID $line: $mb MB"
   done
}

echo "============================================================"
echo "Memory Summary By User:"
echo "============================================================"
(echo "User RSS(MB) VMEM(MB)  COUNT"
 echo "---- ------- --------  -----"
 ps aux --no-headers| awk '{rss[$1]+=$6;vmem[$1]+=$5;c[$1]+=1}; END {for (i in rss) {print i,int(rss[i]/1024),int(vmem[i]/1024),c[i]}}' \
       | sort -k2 | awk '{rss+=$2;vmem+=$3;c1+=$4; print $0};END {print "TOTAL",rss,vmem,c1}') | column -t
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
    (echo "Type RSS(MB) VMEM(MB)  COUNT"
     echo "---- ------- --------  -----"
     ps aux --no-headers|grep -E " (ora_|oracle|db_|asm_)"|grep $sid| grep -v grep |awk '{
              i="Others";
              if(index($11, "_pmon_") != 0)
                i="pmon";
              else if(index($11, "_smon_") != 0)
                i="smon";
              else if(index($11, "_dbw") != 0)
                i="dbwr"; 
              else if(index($11, "_lg") != 0)
                i="lgwr";                  
              else if(index($12, "NO") != 0)  
                i="remote";
              else if(index($12, "YES") != 0)  
                i="local";
              rss[i]+=$6;vmem[i]+=$5;c[i]+=1}
              END {for (i in rss) {print i,int(rss[i]/1024),int(vmem[i]/1024),c[i]}
     }' | sort -k2 | awk '{rss+=$2;vmem+=$3;c1+=$4; print $0};END {print "TOTAL",rss,vmem,c1}') | column -t
    echo " "
    
    pids=`ps -eaf |grep -E " (ora_|oracle|db_|asm_)"| grep -- "$sid" | grep -v " grep " | awk '{print $2}'`
    #echo "Top Processes: "
    #echo ".............."
    #fmap "$pids"| sort -nk3 | tail -10 | column -t
    #echo " "
    
    FNAME="/proc/$pid/smaps"
    can=`cat $FNAME 2>/dev/null | wc -l`
    if [[ "$can" != "0" ]]; then
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
    mems=$(pmap -Xp $pids 2>&1 | grep -E '^\s*\w{8,16}\s+'| awk '{
        rss+=$7;
        pss+=$8;
        if(index($21, "KSIPC_MGA_NMSPC")!=0) 
            c+=$7;
        else if(index($21, "/")==1) 
            f+=$7;
        } END {print rss/1024,c/1024,f/1024, pss/1024}')
   
    pga=$(echo $mems|awk '{print $1}')
    file=$(echo $mems|awk '{print $2}')
    mga=$(echo $mems|awk '{print $3}')
    pss=$(echo $mems|awk '{print $4}')
    mem=`echo "$pga + $shmsize"|bc`
    echo "Non-SGA Memory        : $pga MB (Files=$file, MGA=$mga, PSS=$pss)"
    echo "Total Used Memory     : $mem MB"
    total_shmsize=$(( $shmsize + $total_shmsize ))
    total=`echo "$total + $mem"|bc`
    echo "-----------------------------------"
    echo
done
echo "All Instances:"
echo "**************"
echo "SGA TOTAL (SMALL/HUGE page):" $total_shmsize "MB"
pga=`echo "$total - $total_shmsize"|bc`

if [ "$total_hugepagesize" -gt "0" ]; then
    echo "SGA TOTAL (HUGE PAGE)      :" $total_hugepagesize "MB"
    echo "Percent Huge page          :" $(( $total_hugepagesize *100 / $total_shmsize  )) "%"
    if [ "$total_hugepagesize" -gt "$total_shmsize" ]; then
        total=`echo "$total + $total_hugepagesize - $total_shmsize"|bc`
    fi
fi

if [[ -r /proc/meminfo ]]; then
    hugepage_total=$(cat /proc/meminfo|grep HugePages_Total|awk '{print $2*2}')
    echo "HugePages_Total            : $hugepage_total MB (/proc/meminfo)"
    if [ "$hugepage_total" -gt "$total_hugepagesize" ]; then
        total=`echo "$total + $hugepage_total - $total_hugepagesize"|bc`
    fi
fi

echo "Non-SGA Memory             : $pga MB"
echo "Total Used Memory          : $total MB"
echo "============================================================"
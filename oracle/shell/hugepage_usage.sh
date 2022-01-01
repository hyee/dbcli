#https://github.com/hatem-mahmoud/scripts/blob/master/hugepage_usage_ins.sh
total_shmsize=0
total_hugepagesize=0

for pid in `ps -ef | grep ora_pmon_|egrep -v "grep|+ASM"|  awk '{print $2}'`
do
echo
echo "-----------------------------------------------------------"
echo
ps -ef | grep $pid | grep -v grep

shmsize=`grep -A 1 'SYSV00000000' /proc/$pid/smaps | grep "^Size:" | awk 'BEGIN{sum=0}{sum+=$2}END{print sum/1024}' |  awk -F"." '{print $1}'`
hugepagesize=`grep -B 11 'KernelPageSize:     2048 kB' /proc/$pid/smaps | grep "^Size:" | awk 'BEGIN{sum=0}{sum+=$2}END{print sum/1024}' | awk -F"." '{prin
t $1}'`

echo "INSTANCE SGA (SMALL/HUGE page)"  : $shmsize "MB"
echo "INSTANCE SGA (HUGE PAGE)" $hugepagesize "MB"

echo "Percent Huge page :"  $(( $hugepagesize *100 / $shmsize  )) "%"


total_shmsize=$(( $shmsize + $total_shmsize ))
total_hugepagesize=$(( $total_hugepagesize + $hugepagesize ))

done

echo
echo "-----------------------------------------------------------"
echo "-----------------------------------------------------------"
echo

echo "SGA TOTAL (SMALL/HUGE page)"  : $total_shmsize "MB"
echo "SGA TOTAL (HUGE PAGE)" $total_hugepagesize "MB"
echo "Percent Huge page :"  $(( $total_hugepagesize *100 / $total_shmsize  )) "%"
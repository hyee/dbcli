# edb360 collector
echo "Start edb360."
for INST in $(ps axo cmd | grep ora_pmo[n] | sed 's/^ora_pmon_//' | grep -v 'sed '); do
        if [ $INST = "$( cat /etc/oratab | grep -v ^# | grep -v ^$ | awk -F: '{ print $1 }' | grep $INST )" ]; then
                echo "$INST: instance name = db_unique_name (single instance database)"
                export ORACLE_SID=$INST; export ORAENV_ASK=NO; . oraenv
        else
                # remove last char (instance nr) and look for name again
                LAST_REMOVED=$(echo "${INST:0:$(echo ${#INST}-1 | bc)}")
                if [ $LAST_REMOVED = "$( cat /etc/oratab | grep -v ^# | grep -v ^$ | awk -F: '{ print $1 }' | grep $LAST_REMOVED )" ]; then
                        echo "$INST: instance name with last char removed = db_unique_name (RAC: instance number added)"
                        export ORACLE_SID=$LAST_REMOVED; export ORAENV_ASK=NO; . oraenv; export ORACLE_SID=$INST
                elif [[ "$(echo $INST | sed 's/.*\(_[12]\)/\1/')" =~ "_[12]" ]]; then
                        # remove last two chars (rac one node addition) and look for name again
                        LAST_TWO_REMOVED=$(echo "${INST:0:$(echo ${#INST}-2 | bc)}")
                        if [ $LAST_TWO_REMOVED = "$( cat /etc/oratab | grep -v ^# | grep -v ^$ | awk -F: '{ print $1 }' | grep $LAST_TWO_REMOVED )" ]; then
                                echo "$INST: instance name with either _1 or _2 removed = db_unique_name (RAC one node)"
                                export ORACLE_SID=$LAST_TWO_REMOVED; export ORAENV_ASK=NO; . oraenv; export ORACLE_SID=$INST
                        fi
                else
                        echo "couldn't find instance $INST in oratab"
                        continue
                fi
        fi

sqlplus -s /nolog <<EOF
connect / as sysdba

@sql/edb360_0a_main.sql T
EOF

done
zip -qmT esp_requirements_host.zip res_requirements_*.txt esp_requirements_*.csv cpuinfo_model_name.txt 
zip -qmT edb360_output.zip edb360_*.zip esp_requirements_host.zip
zip -r osw_output.zip `ps -ef | grep OSW | grep FM | awk -F 'OSW' '{print $2}' | cut -f 3 -d ' '`

echo "End edb360 collector. Output: edb360_output.zip and osw_output.zip"

/*[[ Get preferences and stats of the target object. Usage: @@NAME [<object_name>]
]]*/
ora _find_object "&V1" 1
set feed off serveroutput on
DECLARE
    owner       varchar2(30):=:object_owner;
    object_name varchar2(128) := :object_name;
    partname    varchar2(128) := :object_subname;
    typ         varchar2(100):=:object_type;
    st          date;
    et          date;
    status      varchar2(100);
    val         number;
    numrows     int;
    numblks     int;
    avgrlen     int;
    cachedblk   int;
    cachehit    int;
    im_imcu_count  INT;
    im_block_count INT;
    type t is table of varchar2(100);
    --SOURCE:  SYS.OPTSTAT_HIST_CONTROL$/SYS.OPTSTAT_USER_PREFS$
    prefs t:= t('ANDV_ALGO_INTERNAL_OBSERVE',
                'APPROXIMATE_NDV',
                'APPROXIMATE_NDV_ALGORITHM',
                'AUTOSTATS_TARGET',
                'AUTO_STAT_EXTENSIONS',
                'CASCADE',
                'CONCURRENT',
                'DEBUG',
                'DEGREE',
                'ENABLE_HYBRID_HISTOGRAMS',
                'ENABLE_TOP_FREQ_HISTOGRAMS',
                'ESTIMATE_PERCENT',
                'GATHER_AUTO',
                'GATHER_SCAN_RATE',
                'GLOBAL_TEMP_TABLE_STATS',
                'GRANULARITY',
                'INCREMENTAL',
                'INCREMENTAL_INTERNAL_CONTROL',
                'INCREMENTAL_LEVEL',
                'INCREMENTAL_STALENESS',
                'JOB_OVERHEAD',
                'JOB_OVERHEAD_PERC',
                'METHOD_OPT',
                'MON_MODS_ALL_UPD_TIME',
                'NO_INVALIDATE',
                'OPTIONS',
                'PREFERENCE_OVERRIDES_PARAMETER',
                'PUBLISH',
                'SCAN_RATE',
                'SKIP_TIME',
                'SNAPSHOT_UPD_TIME',
                'SPD_RETENTION_WEEKS',
                'STALE_PERCENT',
                'STATS_RETENTION',
                'STAT_CATEGORY',
                'SYS_FLAGS',
                'TABLE_CACHED_BLOCKS',
                'TRACE',
                'WAIT_TIME_TO_UPDATE_STATS');
BEGIN
    IF typ IS NOT NULL and typ NOT like 'TABLE%' THEN
        RAISE_APPLICATION_ERROR(-20001,'Only table is supported!');
    END IF;

    $IF DBMS_DB_VERSION.VERSION<11 $THEN
        for i in 1..prefs.count loop
            begin
                dbms_output.put_line(rpad('Param - '||prefs(i),40)||': '||dbms_stats.get_param(prefs(i)));
            exception when others then null;
            end;
        end loop;    
    $ELSE
        for i in 1..prefs.count loop
            begin
                dbms_output.put_line(rpad('Prefs - '||prefs(i),40)||': '||dbms_stats.get_prefs(prefs(i),owner,object_name));
            exception when others then null;
            end;
        end loop;
    $END
    
    IF owner IS NULL THEN
        --SOURCE: SYS.AUX_STATS$
        prefs := t('iotfrspeed',
                   'ioseektim',
                    'seadtim',
                    'mreadtim',
                    'cpuspeed ',
                    'cpuspeednw',
                    'mbrc',
                    'maxthr',
                    'slavethr');
        for i in 1..prefs.count loop
            begin
                DBMS_STATS.GET_SYSTEM_STATS(status,st,et,prefs(i),val);
                dbms_output.put_line(rpad('System Stats - '||prefs(i),40)||': '||round(val,3));
            exception when others then null;
            end;
        end loop;
    ELSE
        DBMS_STATS.GET_TABLE_STATS (
                ownname     => owner, 
                tabname     => object_name, 
                partname    => partname,
                numrows     => numrows, 
                numblks     => numblks,
                avgrlen     => avgrlen,
                cachedblk   => cachedblk,
                cachehit    => cachehit);
        dbms_output.put_line(rpad('Table Stats - numrows',40)||': '||numrows);
        dbms_output.put_line(rpad('Table Stats - numblks',40)||': '||numblks);
        dbms_output.put_line(rpad('Table Stats - avgrlen',40)||': '||avgrlen);
        dbms_output.put_line(rpad('Table Stats - cachedblk',40)||': '||cachedblk);
        dbms_output.put_line(rpad('Table Stats - cachehit',40)||': '||cachehit);
        $IF DBMS_DB_VERSION.VERSION>12 OR (DBMS_DB_VERSION.VERSION>11 AND DBMS_DB_VERSION.RELEASE>1) $THEN
            DBMS_STATS.GET_TABLE_STATS (
                ownname       => owner, 
                tabname       => object_name, 
                partname      => partname,
                numrows       => numrows, 
                numblks       => numblks,
                avgrlen       => avgrlen,
                im_imcu_count => im_imcu_count,
                im_block_count=> im_block_count,
                scanrate      => val);
            dbms_output.put_line(rpad('Table Stats - im_block_count',40)||': '||im_imcu_count);
            dbms_output.put_line(rpad('Table Stats - im_block_count',40)||': '||im_block_count);
            dbms_output.put_line(rpad('Table Stats - scanrate',40)||': '||round(val,3));
        $END
    END IF;
END;
/
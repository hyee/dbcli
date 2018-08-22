/*[[
	Invalidates all cursors present in gv$sql which refer to the specific table. Usage: @@NAME [owner.]<table>[.partition] [<column_name>]
	--[[
		@check_access_dba: dba_tab_cols={dba_} default={all_}
	--]]
]]*/
ora _find_object "&V1"
DECLARE
    oname     VARCHAR2(128) := :object_owner;
    tab       VARCHAR2(128) := :object_name;
    part      VARCHAR2(128) := :object_subname;
    ttype     VARCHAR2(128) := :object_type;
    col       VARCHAR2(128) := upper(:V2);
    histogram VARCHAR2(128);
    dtype     VARCHAR2(128);
    dtypefull VARCHAR2(128);

    srec      DBMS_STATS.STATREC;
    distcnt   NUMBER;
    density   NUMBER;
    nullcnt   NUMBER;
    avgclen   NUMBER;
    avgrlen   NUMBER;
    samples   NUMBER;
    pops      NUMBER;
    pop_based NUMBER;
    numrows   NUMBER;
    numbcks   NUMBER;
    numblks   NUMBER;
    notnulls  NUMBER;
    buckets   NUMBER;
    prevb     NUMBER;
    cnt       NUMBER;
    flags     NUMBER;

    analyzed DATE;
    gstats   VARCHAR2(3);
    ustats   VARCHAR2(3);

    PROCEDURE calc_density IS
    BEGIN
        /*  EP         = EndPoint
            NewDensity = (1-PopBktCnt/BktCnt)/(NDV-PopValCnt)
            BktCnt     = MAX(EP_number)
            PopBktCnt  = SUM(<number of popular buckets>)
            PopValCnt  = Count(<number of popular buckets>)
            Buckets    = current_EP_number - previous_EP_number
            Popular EP values:
                HEIGHT BALANCED: The EP whose buckets > 1
                HYBRID         : The EP whose buckets > BktCnt/NUM_BUCKETS
        
        */
        numbcks := srec.bkvals(srec.epc);
        numrows := greatest(numrows, 1);
        samples := nvl(NULLIF(samples, 0), numrows);
        numbcks := NULLIF(numbcks, 0);
        cnt     := 0;
        pops    := 0;
    
        CASE histogram
            WHEN 'HYBRID' THEN
                pop_based := numbcks / srec.epc;
            WHEN 'HEIGHT BALANCED' THEN
                pop_based := 1;
            ELSE
                pop_based := NULL;
        END CASE;
    
        FOR i IN 1 .. srec.epc LOOP
            buckets := srec.bkvals(i) - prevb;
            $IF dbms_db_version.version>11 $THEN
            buckets := nvl(nullif(srec.rpcnts(i), 0), buckets);
            $END
            IF buckets > pop_based THEN
                cnt  := cnt + 1;
                pops := pops + buckets;
            END IF;
            prevb := srec.bkvals(i);
        END LOOP;
    
        density := coalesce((1 - pops / numbcks) / nullif(distcnt - cnt, 0), density);
    END;

    PROCEDURE load_stats(rec IN OUT NOCOPY DBMS_STATS.STATREC) IS
        msg VARCHAR2(2000);
        cnt PLS_INTEGER;
    BEGIN
        BEGIN
            SELECT a.*
            INTO   histogram, samples, analyzed, gstats, ustats
            FROM   (SELECT histogram, nvl2(num_buckets, nvl(sample_size, 0), NULL) samples, last_analyzed, global_stats, user_stats
                    FROM   &CHECK_ACCESS_DBA.part_col_statistics b
                    WHERE  b.owner = oname
                    AND    b.table_name = tab
                    AND    b.column_name = col
                    AND    b.partition_name = part
                    UNION ALL
                    SELECT histogram, nvl2(num_buckets, nvl(sample_size, 0), NULL) samples, last_analyzed, global_stats, user_stats
                    FROM   &CHECK_ACCESS_DBA.subpart_col_statistics b
                    WHERE  b.owner = oname
                    AND    b.table_name = tab
                    AND    b.column_name = col
                    AND    b.subpartition_name = part
                    UNION ALL
                    SELECT histogram, nvl2(num_buckets, nvl(sample_size, 0), NULL) samples, last_analyzed, global_stats, user_stats
                    FROM   &CHECK_ACCESS_DBA.tab_col_statistics b
                    WHERE  b.owner = oname
                    AND    b.table_name = tab
                    AND    b.column_name = col
                    AND    part IS NULL) a;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20001, 'No such column: ' || col);
        END;
    
        IF histogram IS NULL OR samples IS NULL THEN
            raise_application_error(-20001, 'Target column on the ' || lower(ttype) || ' is not analyzed!');
        END IF;
    
        CASE
            WHEN histogram = 'FREQUENCY' AND dbms_db_version.version > 11 THEN
                flags := 4096;
            WHEN histogram = 'TOP-FREQUENCY' THEN
                flags := 8192;
            ELSE
                flags := 0;
        END CASE;
    
        BEGIN
            DBMS_STATS.GET_TABLE_STATS(ownname  => oname,
                                       tabname  => tab,
                                       partname => part,
                                       numrows  => numrows,
                                       numblks  => numblks,
                                       avgrlen  => avgrlen);
        
            DBMS_STATS.GET_COLUMN_STATS(srec     => rec,
                                        ownname  => oname,
                                        tabname  => tab,
                                        partname => part,
                                        colname  => col,
                                        distcnt  => distcnt,
                                        density  => density,
                                        nullcnt  => nullcnt,
                                        avgclen  => avgclen);
            notnulls := numrows - nullcnt;
        
            IF flags > 0 AND bitand(srec.eavs, flags) = 0 THEN
                srec.eavs := srec.eavs + flags;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                msg := TRIM('Unable to get table/column stats due to ' || SQLERRM);
                raise_application_error(-20001, msg);
        END;
    END;
BEGIN
    dbms_output.enable(null);
    IF tab IS NULL THEN
        raise_application_error(-20001, 'Please input the target table!');
    END IF;
    FOR r IN (SELECT *
              FROM   &check_access_dba.tab_cols
              WHERE  owner = oname
              AND    table_name = tab
              AND    NUM_DISTINCT > 0
              AND    (col IS NULL OR column_name=col)
              ORDER  BY COLUMN_ID) LOOP
        col       := r.column_name;
        dtypefull := r.data_type;
        dtype     := regexp_substr(dtypefull, '^\w+');
        load_stats(srec);
        calc_density;
        dbms_output.put_line(utl_lms.format_message(
                'Flushing column#%s %s: histogram=%s   num_buckets=%s   num_nulls=%s   distincts=%s   avgclen=%s   density=%s',
                rpad(r.column_id,4),
                rpad('"'||col||'"',32),
                rpad('"'||histogram||'"',17),
                rpad(dbms_xplan.format_number(srec.bkvals(srec.epc)),7),
                rpad(dbms_xplan.format_number(nullcnt),7),
                rpad(dbms_xplan.format_number(distcnt),7),
                rpad(avgclen,4),to_char(density*100,'fm990.099999')||'%'));
        DBMS_STATS.SET_COLUMN_STATS(ownname       => oname,
                                    tabname       => tab,
                                    colname       => col,
                                    distcnt       => distcnt,
                                    density       => density,
                                    nullcnt       => nullcnt,
                                    srec          => srec,
                                    avgclen       => avgclen,
                                    no_invalidate => FALSE,
                                    force         => TRUE);
    END LOOP;
END;
/
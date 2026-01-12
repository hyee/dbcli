/*[[
    Show materialized view stats. Usage: @@NAME {[[<owner>].<name>] [yymmddhh24mi] [yymmddhh24mi] [-count]} | [<refresh_id>] |
    <name>       : can be MLOG name, MVIEW name or source table/view name
    <refresh_id> : specify DBA_MVREF_RUN_STATS.REFRESH_ID
    -count       : count the records of relative MLOG$ tables(since Oracle 12.1)

    If REG_ID is null, then MV is not registered and could lead to MLOG$ table records not being cleaned
    --[[
        @check_access_obj: sys.mlog$/sys.slog$/sys.reg_snap$/sys.snap$={1} default={0}
        @check_access_dba: dba_mviews={dba_} default={all_}
        @check_access_cfg: DBA_MVREF_STATS/DBA_MVREF_STATS_SYS_DEFAULTS={1} default={0}
        &filter: default={1=1} f={}
        @ver12:  12.1={1} default={0}
        @ver18:  12.2={1} default={0}
        &count:  default={0} count={&ver12}
        @snapid: 19.11={s.snapid} default={to_number(null) snapid}
        &v2    : default={&starttime}
        &v3    : default={&endtime}
    --]]
]]*/
set feed off verify off autohide col
ora _find_object "&V1" 1
var c1 refcursor "TOP MVIEWS/MLOGS MAPPINGS ORDER BY REFRESH TIME"
var c2 refcursor "RECENT REFRESHED MVIEWS"
var c3 refcursor "MVREF_STATS PARAMETERS"
var c4 refcursor "DBA_MVREF_RUN_STATS"
col "mv_since,mlog_gap,FULL|TIME,INCR|TIME,RUN|SECS" for smhd2

DECLARE
    c3 SYS_REFCURSOR;
    c4 SYS_REFCURSOR;
    stmt1 VARCHAR2(32767);
    own   VARCHAR2(128):=:object_owner;
    nam   VARCHAR2(128):=:object_name;
    typ   VARCHAR2(128):=:object_type;
    obj   VARCHAR2(256):='%s='''||own||''' AND %s='''||nam||'''';
    rid   INT  := regexp_substr(:V1,'^\d+$');
    st    DATE := nvl(to_date(:v2,'YYMMDDHH24MISS'),date'2000-1-1');
    ed    DATE := nvl(to_date(:v3,'YYMMDDHH24MISS'),sysdate+1);
BEGIN
    IF &check_access_obj=1 THEN
        stmt1 := q'~
        SELECT #count# a.*
        FROM(
            SELECT /*+native_full_outer_join*/*
            FROM   (SELECT r.snapshot_id reg_id,
                           s.mowner,
                           s.master,
                           s.mlink,
                           s.snapid      mv_id,
                           sowner        mv_owner,
                           snapname      mv_name,
                           s.mv_time,
                           round(86400 * (sysdate-s.mv_time)) mv_since,
                           decode(bitand(r.flag, 32),32, 'PRIMARY KEY',decode(bitand(r.flag, 536870912), 536870912, 'OBJECT ID', 'ROWID')) "REFRESH"
                    FROM   (SELECT /*+merge*/r.mowner,r.master,s.snapid,s.mlink,sowner,vname snapname,r.snaptime mv_time 
                            FROM   sys.snap$ s 
                            JOIN   sys.snap_reftime$ r
                            USING  (vname,sowner)) s
                    LEFT   JOIN sys.reg_snap$ r
                    USING  (sowner, snapname)
                    WHERE #fs#) mview
            #jo# JOIN (
                    SELECT s.snapid reg_id,
                           '|' "|",
                           round(86400 * (m.youngest - least(m.oldest, m.oldest_pk))) mlog_gap,
                           m.log mlog,
                           mowner,
                           master,
                           least(m.oldest, m.oldest_pk) oldest,
                           m.youngest
                    FROM   sys.slog$ s
                    LEFT   JOIN sys.mlog$ m
                    USING  (mowner, master)
                    WHERE #fm#) mlog
            USING  (reg_id,mowner,master)
            WHERE #ft#
            ORDER BY greatest(mv_since,nvl(mlog_gap,0)*10) desc,mv_name,master) a
        WHERE ROWNUM<=30~';
    ELSE
        stmt1 := q'~
        SELECT #count# a.*
        FROM(
            SELECT /*+native_full_outer_join*/*
            FROM   (SELECT mview_id reg_id,
                           mowner,
                           master,
                           mlink,
                           snapid        mv_id,
                           sowner        mv_owner,
                           snapname      mv_name,
                           mv_time,
                           round(86400 * (sysdate-mv_time)) mv_since,
                           refresh_method "REFRESH"
                    FROM   (SELECT /*+merge*/r1.mview_id,r.master_owner mowner,r.master,&snapid,s.master_link mlink,owner sowner,name snapname,s.last_refresh mv_time,r1.refresh_method
                            FROM   &check_access_dba.snapshots s 
                            JOIN   &check_access_dba.mview_refresh_times r
                            USING  (owner,NAME)
                            LEFT JOIN &check_access_dba.registered_mviews r1
                            USING  (owner,NAME)) s
                    WHERE #fs#
                    ) mview
            #jo# JOIN (
                    SELECT snapshot_id reg_id,
                           '|' "|",
                           NULL mlog_gap,
                           m.log_table mlog,
                           log_owner mowner,
                           master,
                           NULL oldest,
                           NULL youngest
                    FROM   &check_access_dba.snapshot_logs m
                    WHERE #fm#) mlog
            USING  (reg_id,mowner,master)
            WHERE #ft#
            ORDER BY greatest(mv_since,nvl(mlog_gap,0)*10) desc,mv_name,master) a
        WHERE ROWNUM<=30~';
    END IF;

    IF &count=1 THEN
        stmt1 :=q'~WITH FUNCTION do_count(OWNER VARCHAR2,NAME VARCHAR2) RETURN INT DETERMINISTIC IS
            c INT;
            stmt VARCHAR2(300):=utl_lms.format_message('SELECT /*+index_ffs(a)*/ COUNT(1) FROM "%s"."%s" a WHERE XID$$ IS NOT NULL',OWNER,NAME);
        BEGIN
            IF NAME IS NULL THEN RETURN NULL; END IF;
            EXECUTE IMMEDIATE stmt INTO c;
            RETURN c;
        EXCEPTION WHEN OTHERS THEN 
            RETURN NULL;
        END;~'||stmt1;
        stmt1 := replace(stmt1,'#count#','do_count(mowner,mlog) MLOG_ROWS,');
    ELSE
        stmt1 := replace(stmt1,'#count#');
    END IF;

    IF nam IS NULL THEN
        stmt1 := replace(stmt1,'#fs#','1=1');
        stmt1 := replace(stmt1,'#fm#','1=1');
        stmt1 := replace(stmt1,'#ft#',:filter);
        stmt1 := replace(stmt1,'#jo#','FULL');
    ELSIF typ='MATERIALIZED VIEW' THEN
        stmt1 := replace(stmt1,'#fs#',utl_lms.format_message(obj,'sowner','snapname'));
        stmt1 := replace(stmt1,'#fm#','1=1');
        stmt1 := replace(stmt1,'#ft#','1=1');
        stmt1 := replace(stmt1,'#jo#','LEFT');
    ELSIF typ='TABLE' and nam NOT like 'MLOG$%' THEN
        stmt1 := replace(stmt1,'#fs#',utl_lms.format_message(obj,'mowner','master'));
        stmt1 := replace(stmt1,'#fm#',utl_lms.format_message(obj,'mowner','master'));
        stmt1 := replace(stmt1,'#ft#','1=1');
        stmt1 := replace(stmt1,'#jo#','FULL');
    ELSE
        stmt1 := replace(stmt1,'#fs#','1=1');
        stmt1 := replace(stmt1,'#fm#',utl_lms.format_message(obj,'mowner','m.log'));
        stmt1 := replace(stmt1,'#ft#','1=1');
        stmt1 := replace(stmt1,'#jo#','RIGHT');
    END IF;
    --dbms_output.put_line(stmt1);
    OPEN :c1 FOR stmt1;

    stmt1 :=q'~
    SELECT * FROM(
        SELECT /*+outline_leaf use_nl(b) push_pred(b)*/DISTINCT
               owner,summary_name mv_name,
               b.LAST_REFRESH_SCN "REFRESH|LAST_SCN",
               b.LAST_REFRESH_DATE "REFRESH|LAST_DATE",
               b.REFRESH_METHOD "REFRESH|METHOD",
               b.FULLREFRESHTIM "FULL|TIME",
               b.INCREFRESHTIM "INCR|TIME"
        FROM   &check_access_dba.summaries b
        #ft#
        AND    b.LAST_REFRESH_DATE BETWEEN :st AND :ed
        ORDER BY "REFRESH|LAST_DATE" DESC
    ) WHERE ROWNUM<=30~';
    IF nam IS NULL THEN
        stmt1 := replace(stmt1,'#ft#','WHERE 1=1');
    ELSIF typ='MATERIALIZED VIEW' THEN
        stmt1 := replace(stmt1,'#ft#','WHERE '||utl_lms.format_message(obj,'owner','summary_name'));
    ELSIF typ='TABLE' and nam NOT like 'MLOG$%' THEN
        stmt1 := replace(stmt1,'#ft#',
            'JOIN &check_access_dba.summary_detail_tables a USING (owner,summary_name) WHERE '
            ||utl_lms.format_message(obj,'a.detail_owner','a.detail_relation'));
    ELSE
        stmt1 := replace(stmt1,'#ft#',
            'JOIN &check_access_dba.summary_detail_tables a USING (owner,summary_name) 
             JOIN &check_access_dba.snapshot_logs s ON (a.detail_owner=s.log_owner AND a.detail_relation=s.master) 
             WHERE '||utl_lms.format_message(obj,'s.log_owner','s.log_table'));
    END IF;

    --dbms_output.put_line(stmt1);
    OPEN :c2 FOR stmt1 USING st,ed;

    $IF &check_access_cfg=1 $THEN
    OPEN c3 FOR 
        SELECT '<SYSTEM>' MV_OWNER,
               '<DEFAULT>' MV_NAME,
               max(decode(PARAMETER_NAME,'COLLECTION_LEVEL',value)) COLLECTION_LEVEL,
               max(decode(PARAMETER_NAME,'RETENTION_PERIOD',0+value)) RETENTION_PERIOD
        FROM   DBA_MVREF_STATS_SYS_DEFAULTS
        UNION ALL
        SELECT * FROM (
            SELECT mv_owner,mv_name,collection_level,retention_period
            FROM   dba_mvref_stats_params
            WHERE  nam IS NULL 
            OR    (mv_owner=own AND mv_name=nam)
            ORDER  BY 1,2,3
        ) WHERE ROWNUM<=30;
    IF nam IS NULL AND rid IS NULL THEN
        OPEN c3 FOR
            SELECT REFRESH_ID "REFRESH|ID",
                   RUN_OWNER "RUN|OWNER",
                   START_TIME "START|TIME",
                   END_TIME "END|TIME",
                   ELAPSED_TIME "RUN|SECS",
                   NUM_MVS "NUM|MVS",
                   regexp_count(BASE_TABLES, ',') + 1 "BASE|TABLES",
                   METHOD "REFRESH|METHOD",
                   PARALLELISM "RUN|DEGREE",
                   PUSH_DEFERRED_RPC "PUSH|RPC",
                   REFRESH_AFTER_ERRORS "REFRESH|ERRORS",
                   PURGE_OPTION "PURGE|OPTION",
                   HEAP_SIZE "HEAP|SIZE",
                   ATOMIC_REFRESH "ATOMIC|REFRESH",
                   NESTED "IS|NESTED",
                   OUT_OF_PLACE "OUT-OF|PLACE",
                   NUMBER_OF_FAILURES "NUM|FAILS",
                   COMPLETE_STATS_AVAILABLE "STATS|AVAIL",
                   ROLLBACK_SEG "ROLLBACK|SEG"
            FROM   (SELECT * 
                    FROM DBA_MVREF_RUN_STATS 
                    WHERE nvl(END_TIME,START_TIME) BETWEEN st AND ed
                    ORDER BY START_TIME DESC)
            WHERE  ROWNUM <= 30;
    ELSE
        stmt1 := q'~
            SELECT MV_OWNER              "MVIEW|OWNER",
                   MV_NAME               "MVIEW|NAME",
                   REFRESH_ID            "REFRESH|ID",
                   START_TIME            "START|TIME",
                   END_TIME              "END|TIME",
                   ELAPSED_TIME          "RUN|SECS",
                   REFRESH_METHOD        "REFRESH|METHOD",
                   REFRESH_OPTIMIZATIONS "REFRESH|OPTIMIZ",
                   ADDITIONAL_EXECUTIONS "ADDITIONAL|EXECUTIONS",
                   INITIAL_NUM_ROWS      "INIT|ROWS",
                   FINAL_NUM_ROWS        "FINAL|ROWS"
            FROM   (SELECT /*+outline_leaf use_nl(b) push_pred(b)*/ b.*
                    FROM DBA_MVREF_STATS b
                    #ft#
                    AND  nvl(END_TIME,START_TIME) BETWEEN :st AND :ed
                    ORDER BY b.START_TIME DESC)
            WHERE  ROWNUM <= 50~';
        IF nam IS NULL THEN
            stmt1 := replace(stmt1,'#ft#','WHERE REFRESH_ID='||rid);
        ELSIF typ='MATERIALIZED VIEW' THEN
            stmt1 := replace(stmt1,'#ft#','WHERE '||utl_lms.format_message(obj,'MV_OWNER','MV_NAME'));
        ELSIF typ='TABLE' and nam NOT like 'MLOG$%' THEN
            stmt1 := replace(stmt1,'#ft#',
                'JOIN &check_access_dba.summary_detail_tables a ON (b.mv_owner=a.owner AND b.mv_name=a.summary_name) 
                 WHERE '||utl_lms.format_message(obj,'a.detail_owner','a.detail_relation'));
        ELSE
            stmt1 := replace(stmt1,'#ft#',
                'JOIN &check_access_dba.summary_detail_tables a ON (b.mv_owner=a.owner AND b.mv_name=a.summary_name) 
                 JOIN &check_access_dba.snapshot_logs s ON (a.detail_owner=s.log_owner AND a.detail_relation=s.master) 
                 WHERE '||utl_lms.format_message(obj,'s.log_owner','s.log_table'));
        END IF;

        --dbms_output.put_line(stmt1);
        OPEN c4 FOR stmt1 USING st,ed;
    END IF;
    $END
    :c3 := c3;
    :c4 := c4;
END;
/

print c1
print c2
print c3
print c4
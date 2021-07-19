/*[[
    Search all xtables that contains the specific address. Usage: @@NAME <addr> [<inst_id>]
    The operation could be time-consuming.

    Example:
    ========
    SQL> @@NAME 0000000063778CF8
    TABLE_NAME    COLUMN_NAME   REFS
    ------------- ------------- ---------------------------------------------------------------------------
    X$KGLDP       KGLHDPAR      GV$ACCESS,GV$OBJECT_DEPENDENCY
    X$KGLLK       KGLHDPAR      GV$ACCESS,GV$LIBCACHE_LOCKS,GV$OPEN_CURSOR
    X$KGLNA       KGLHDADR      GV$SQLTEXT,GV$SQLTEXT_WITH_NEWLINES
    X$KGLNA1      KGLHDADR      GV$SQLTEXT_WITH_NEWLINES
    X$KGLOB       KGLHDPAR      GV$ACCESS,GV$DB_OBJECT_CACHE,GV$DB_PIPES,GV$OBJECT_DEPENDENCY,GV$_SEQUENCES
    X$KGLOBXML    KGLHDADR
    X$KGLRD       KGLHDPDR
    X$KKSCS       KGLHDPAR
    X$KKSPCIB     KKSCSPHD
    X$KKSSRD      PARADDR       GV$SQL_REDIRECTION
    X$KQLFBC      KQLFBC_PADD   GO$SQL_BIND_CAPTURE
    X$KQLFSQCE    KQLFSQCE_PHAD GV$SQL_OPTIMIZER_ENV
    X$KQLFXPL     KQLFXPL_PHAD  GV$SQL_PLAN
    X$QESRSTATALL PHADD_QESRS   GV$SQL_PLAN_STATISTICS_ALL


    --[[
        @ARGS: 1
        &V2: default={&instance}
    --]]
]]*/
set feed off
var c REFCURSOR;

DECLARE
    col  VARCHAR2(128);
    addr RAW(8):=hextoraw(:V1);
    res  SYS.ODCICOLINFOLIST2:=SYS.ODCICOLINFOLIST2();
    i    PLS_INTEGER:=0;
BEGIN
    FOR r IN (SELECT kqftanam t, 
                     listagg(c.kqfconam,',') within group(order by c.kqfconam) cols,
                     'CASE :addr '||listagg('WHEN '||c.kqfconam||' THEN '''||c.kqfconam||'''',' ') within group(order by c.kqfconam)||' END' info,
                     (select listagg(view_name,',') within group(order by view_name) from v$fixed_view_definition where instr(lower(view_definition),lower(kqftanam))>0) refs
              FROM   x$kqfta t, x$kqfco c
              WHERE  c.kqfcotab = t.indx
              AND    lower(kqftanam) NOT IN ('x$ksmsp','x$ktuqqry')
              AND    substr(lower(kqftanam),1,5) NOT in ('x$dbg','x$dia')
              AND    INSTR(kqfconam, ' ') = 0
              AND    kqfcodty = 23
              AND    c.kqfcosiz IN (8)
              GROUP BY kqftanam) LOOP
        col := NULL;
        BEGIN
            EXECUTE IMMEDIATE 'SELECT * FROM TABLE(GV$(CURSOR(select '||r.info||' info from ' || r.t || ' where inst_id=nvl(0+''&V2'',inst_id) and rownum<2 and :addr IN(' || r.cols ||')))) where rownum<2'
                INTO col using addr,addr;
        EXCEPTION
            WHEN OTHERS THEN
                null;
        END;
        IF col IS NOT NULL THEN
            i := i+1;
            res.extend;
            res(i) := SYS.ODCICOLINFO(r.t,col,r.refs,null,null,null,null,null,null,null);
        END IF;
    END LOOP;
    OPEN :c for SELECT TableSchema table_name,TableName column_name,ColName refs from table(res) order by 1;
END;
/
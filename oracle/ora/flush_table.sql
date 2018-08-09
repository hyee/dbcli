/*[[
	Invalidates all cursors present in v$sql which refer to the specific table. Usage: @@NAME [owner.]<table>
	Refer to: http://joze-senegacnik.blogspot.com/2009/12/force-cursor-invalidation.html
	--[[
		@check_access_dba: dba_tab_columns={dba_tab_columns} default={all_tab_columns}
	--]]
]]*/
ora _find_object "&V1" 1
DECLARE
    m_srec    DBMS_STATS.STATREC;
    m_distcnt NUMBER;
    m_density NUMBER;
    m_nullcnt NUMBER;
    m_avgclen NUMBER;
    m_colname VARCHAR2(128);
BEGIN
    DBMS_STATS.GET_COLUMN_STATS(ownname => :OBJECT_OWNER,
                                tabname => :OBJECT_NAME,
                                colname => m_colname,
                                distcnt => m_distcnt,
                                density => m_density,
                                nullcnt => m_nullcnt,
                                srec    => m_srec,
                                avgclen => m_avgclen);
    $IF dbms_db_version.version >11 $THEN
    m_srec.rpcnts := NULL;
    $END
    DBMS_STATS.SET_COLUMN_STATS(ownname       => :OBJECT_OWNER,
                                tabname       => :OBJECT_NAME,
                                colname       => m_colname,
                                distcnt       => m_distcnt,
                                density       => m_density,
                                nullcnt       => m_nullcnt,
                                srec          => m_srec,
                                avgclen       => m_avgclen,
                                no_invalidate => FALSE,
                                force         => TRUE);
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -6532 THEN
            FOR r IN (SELECT *
                      FROM   &check_access_dba
                      WHERE  owner = :OBJECT_OWNER
                      AND    table_name = :OBJECT_NAME
                      AND    NUM_DISTINCT > 0) LOOP
                DBMS_STATS.GET_COLUMN_STATS(ownname => :OBJECT_OWNER,
                                            tabname => :OBJECT_NAME,
                                            colname => r.column_name,
                                            distcnt => m_distcnt,
                                            density => m_density,
                                            nullcnt => m_nullcnt,
                                            srec    => m_srec,
                                            avgclen => m_avgclen);
                $IF dbms_db_version.version >11 $THEN
                m_srec.rpcnts := NULL;
                $END
                DBMS_STATS.SET_COLUMN_STATS(ownname       => :OBJECT_OWNER,
                                            tabname       => :OBJECT_NAME,
                                            colname       => r.column_name,
                                            distcnt       => m_distcnt,
                                            density       => m_density,
                                            nullcnt       => m_nullcnt,
                                            srec          => m_srec,
                                            avgclen       => m_avgclen,
                                            no_invalidate => FALSE,
                                            force         => TRUE);
            END LOOP;
        ELSE
            RAISE;
        END IF;
END;
/
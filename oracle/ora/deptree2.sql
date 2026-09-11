/*[[Shows the accessible dependencies of the given object. Usage: @@NAME [owner.]object_name
    Sample Output:
    ==============
    ORCL> @@NAME dbms_workload_repository
    ## OBJECT_NAME                             OBJECT_TYPE  OBJECT_ID DATA_OBJECT_ID STATUS CREATED             LAST_DDL_TIME       TIMESTAMP           TEMPORARY
    -- --------------------------------------- ------------ --------- -------------- ------ ------------------- ------------------- ------------------- ---------
     1 *SYS.DBMS_WORKLOAD_REPOSITORY           PACKAGE           8460                VALID  2011-08-28 22:12:37 2013-12-20 15:54:50 2013-12-20 15:27:20 N
     2 *   PUBLIC.DBMS_WORKLOAD_REPOSITORY     SYNONYM           8461                VALID  2011-08-28 22:12:37 2013-12-20 15:27:22 2013-12-20 15:27:22 N
     3 *   SYS.DBA_HIST_BASELINE               VIEW             10965                VALID  2011-08-28 22:14:31 2013-12-20 15:34:12 2011-08-28 22:14:31 N
     4 *      PUBLIC.DBA_HIST_BASELINE         SYNONYM          10966                VALID  2011-08-28 22:14:31 2013-12-20 15:34:13 2013-12-20 15:34:13 N
     5 *         DBSNMP.BSLN_INTERNAL          PACKAGE          24593                VALID  2013-12-20 15:39:48 2013-12-20 15:39:48 2013-12-20 15:39:48 N
     6 *            DBSNMP.BSLN_INTERNAL       PACKAGE BODY     24594                VALID  2013-12-20 15:39:48 2013-12-20 15:39:48 2013-12-20 15:39:48 N
     7 *            DBSNMP.BSLN                PACKAGE BODY     24595                VALID  2013-12-20 15:39:49 2013-12-20 15:39:49 2013-12-20 15:39:49 N
     8 *         DBSNMP.BSLN_INTERNAL          PACKAGE BODY     24594                VALID  2013-12-20 15:39:48 2013-12-20 15:39:48 2013-12-20 15:39:48 N
     9 *         DBSNMP.MGMT_BSLN_INTERVALS    VIEW             24599                VALID  2013-12-20 15:39:49 2013-12-20 15:39:49 2013-12-20 15:39:49 N
    10 *      SYS.DBMS_SQLTUNE                 PACKAGE BODY     11972                VALID  2011-08-28 22:15:37 2013-12-20 16:02:51 2013-12-20 16:02:51 N
    11 *      SYS.DBMS_MANAGEMENT_PACKS        PACKAGE BODY     11987                VALID  2011-08-28 22:15:40 2013-12-20 16:04:16 2013-12-20 15:36:42 N
    12 *   SYS.DBA_HIST_BASELINE_DETAILS       VIEW             10967                VALID  2011-08-28 22:14:31 2013-12-20 15:34:12 2011-08-28 22:14:31 N
    13 *      PUBLIC.DBA_HIST_BASELINE_DETAILS SYNONYM          10968                VALID  2011-08-28 22:14:31 2013-12-20 15:34:13 2013-12-20 15:34:13 N
    14 *   SYS.DBMS_WORKLOAD_REPOSITORY        PACKAGE BODY     11961                VALID  2011-08-28 22:15:25 2013-12-20 15:36:16 2013-12-20 15:36:16 N
    15 *   SYS.DBMS_SWRF_INTERNAL              PACKAGE BODY     11962                VALID  2011-08-28 22:15:25 2013-12-20 15:36:16 2013-12-20 15:36:16 N
    16 *   SYS.DBMS_WORKLOAD_CAPTURE           PACKAGE BODY     11979                VALID  2011-08-28 22:15:39 2013-12-20 16:10:14 2013-12-20 16:10:14 N
    17 *   SYS.DBMS_WORKLOAD_REPLAY            PACKAGE BODY     11980                VALID  2011-08-28 22:15:39 2013-12-20 16:10:15 2013-12-20 16:10:15 N
    18 *   SYS.DBMS_MANAGEMENT_PACKS           PACKAGE BODY     11987                VALID  2011-08-28 22:15:40 2013-12-20 16:04:16 2013-12-20 15:36:42 N
    19 *   DBSNMP.MGMT_BSLN_INTERVALS          VIEW             24599                VALID  2013-12-20 15:39:49 2013-12-20 15:39:49 2013-12-20 15:39:49 N
    --[[
        @ARGS: 1
        @CHECK_ACCESS_OBJ: DBA_OBJECTS={DBA_OBJECTS} default={all_objects}
    ]]--
]]*/

ora _find_object &V1
set feed off
var cur REFCURSOR;

DECLARE
    c        INT;
    o        dbmsoutput_linesarray;
    v_trunc  PLS_INTEGER := 0;
    v_notice VARCHAR2(200) := '*** TRUNCATED: dbms_output buffer(1MB) overflow, the tree below is incomplete ***';
    v_schema VARCHAR2(130);
    v_name   VARCHAR2(130);
BEGIN
    dbms_output.disable;
    dbms_output.enable(NULL);
    v_schema := CASE WHEN dbms_db_version.version >= 12 AND :object_owner <> upper(:object_owner)
                     THEN '"' || :object_owner || '"' ELSE :object_owner END;
    v_name   := CASE WHEN dbms_db_version.version >= 12 AND :object_name <> upper(:object_name)
                     THEN '"' || :object_name || '"' ELSE :object_name END;
    BEGIN
        dbms_utility.get_dependency(:object_type, v_schema, v_name);
    EXCEPTION WHEN OTHERS THEN
        IF instr(sqlerrm, 'ORU-10027') != 0 THEN
            v_trunc := 1;
        ELSIF instr(sqlerrm, 'ORU-10013') != 0 AND :object_name <> upper(:object_name) THEN
            raise_application_error(-20001, 'dbms_utility.get_dependency cannot handle the case sensitive name '
                || :object_owner || '.' || :object_name);
        ELSE
            RAISE;
        END IF;
    END;
    dbms_output.get_lines(o, c);
    EXECUTE IMMEDIATE 'alter session set nls_date_format=''YYYY-MM-DD HH24:MI:SS''';

    OPEN :cur FOR
        SELECT /*+no_merge(o)*/
               r "#",
               object_name,
               p_type object_type,
               0 + regexp_substr(info, '[^/]+', 1, 1) OBJECT_ID,
               nullif(0 + regexp_substr(info, '[^/]+', 1, 2), 0) DATA_OBJECT_ID,
               regexp_substr(info, '[^/]+', 1, 6) STATUS,
               to_date(regexp_substr(info, '[^/]+', 1, 3)) CREATED,
               to_date(regexp_substr(info, '[^/]+', 1, 4)) LAST_DDL_TIME,
               to_date(regexp_substr(info, '[^/]+', 1, 5)) TIMESTAMP,
               regexp_substr(info, '[^/]+', 1, 7) TEMPORARY
        FROM   (SELECT r, object_name, p_type,
                       (SELECT object_id || '/' || nvl(data_object_id, 0) || '/' || created || '/' ||
                               last_ddl_time || '/' || TIMESTAMP || '/' || status || '/' || temporary
                        FROM   &check_access_obj
                        WHERE  owner = regexp_substr(obj, '[^\.]+', 1, 1)
                        AND    object_name = substr(obj, instr(obj, '.') + 1)
                        AND    object_type = p_type) info
                FROM   (SELECT rownum r,
                               regexp_replace(column_value, '([\* ]+)(.*) ([^ \(]+).*', '\1\3') object_name,
                               regexp_replace(column_value, '([\* ]+)(.*) ([^ \(]+).*', '\2') p_type,
                               regexp_replace(column_value, '([\* ]+)(.*) ([^ \(]+).*', '\3') obj
                        FROM   TABLE(o)
                        WHERE  column_value LIKE '*%')
                UNION ALL
                SELECT 0, v_notice, 'WARNING', to_char(NULL)
                FROM   dual
                WHERE  v_trunc = 1) o
        ORDER  BY r;
END;
/

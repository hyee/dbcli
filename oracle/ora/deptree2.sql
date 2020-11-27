/*[[Shows the accessible dependencies on the given object. Usage: @@NAME [owner.]object_name
    Sample Output:
    ==============
    ORCL> ora deptree2 dbms_workload_repository
    ##               OBJECT_NAME               OBJECT_TYPE  OBJECT_ID DATA_OBJECT_ID STATUS       CREATED          LAST_DDL_TIME         TIMESTAMP      TEMPORARY
    ------------------------------------------ ------------ --------- -------------- ------ ------------------- ------------------- ------------------- ---------
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
    c   INT;
    o   DBMSOUTPUT_LINESARRAY;
BEGIN
    dbms_output.disable;
    dbms_output.enable(NULL);
    dbms_utility.get_dependency(:object_type, :object_owner, :object_name);
    dbms_output.get_lines(o, c);
    EXECUTE IMMEDIATE 'alter session set nls_date_format=''YYYY-MM-DD HH24:MI:SS''';

    OPEN :cur FOR
        SELECT /*+no_merge(o)*/
                 r "#",
                 object_name,
                 object_type,
                 0+regexp_substr(info, '[^/]+', 1, 1) OBJECT_ID,
                 nullif(0+regexp_substr(info, '[^/]+', 1, 2),0) DATA_OBJECT_ID,
                 regexp_substr(info, '[^/]+', 1, 6) STATUS,
                 TO_DATE(regexp_substr(info, '[^/]+', 1, 3)) CREATED,
                 TO_DATE(regexp_substr(info, '[^/]+', 1, 4)) LAST_DDL_TIME,
                 TO_DATE(regexp_substr(info, '[^/]+', 1, 5)) TIMESTAMP,
                 regexp_substr(info, '[^/]+', 1, 7) TEMPORARY
        FROM   (SELECT r,object_name,regexp_substr(obj, '[^\.]+', 1, 3) object_type,
                        (SELECT OBJECT_ID || '/' || nvl(DATA_OBJECT_ID,0) || '/' || CREATED || '/' ||
                                LAST_DDL_TIME || '/' || TIMESTAMP || '/' || STATUS || '/' || TEMPORARY
                          FROM   &check_access_obj
                          WHERE  owner = regexp_substr(obj, '[^\.]+', 1, 1)
                          AND    object_name = regexp_substr(obj, '[^\.]+', 1, 2)
                          AND    object_type = regexp_substr(obj, '[^\.]+', 1, 3)) info
                 FROM   (SELECT rownum r,
                                regexp_replace(COLUMN_VALUE, '([\* ]+)(.*) ([^ \(]+).*','\1\3') object_name,
                                regexp_replace(COLUMN_VALUE, '([\* ]+)(.*) ([^ \(]+).*', '\3.\2') obj
                         FROM   TABLE(o)
                         WHERE  COLUMN_VALUE LIKE '*%')) o
        ORDER BY r;
END;
/
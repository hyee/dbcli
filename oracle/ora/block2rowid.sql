/*[[Convert block number into ROWID, usage: @@NAME <object_id> <file#,block#|file# block#>]]*/
SET FEED OFF
VAR CUR1 REFCURSOR
VAR CUR2 REFCURSOR

DECLARE
    SRID ROWID;
    ERID ROWID;
    FNO  VARCHAR2(128) := :V2;
    BLK  INT := :V3;
    OBJ  VARCHAR2(128);
    SOBJ VARCHAR2(128);
    TYP  VARCHAR2(128);
    ID   int;
BEGIN
    IF BLK IS NULL AND INSTR(FNO, ',') > 0 THEN
        BLK := REGEXP_SUBSTR(FNO, '\d+', 1, 2);
        FNO := REGEXP_SUBSTR(FNO, '\d+');
    END IF;

    SELECT MAX(owner || '.' || object_name),max(object_id),MAX(SUBOBJECT_NAME),MAX(OBJECT_TYPE)
    INTO OBJ,ID,SOBJ,TYP
    FROM ALL_OBJECTS
    WHERE OBJECT_ID = REGEXP_SUBSTR(:V1, '\d+')+0;

    IF BLK IS NOT NULL AND OBJ IS NOT NULL THEN
        SRID := dbms_rowid.rowid_create(rowid_type    => 1,
                                        object_number => ID,
                                        relative_fno  => FNO,
                                        block_number  => BLK,
                                        row_number    => 1);
        ERID := dbms_rowid.rowid_create(rowid_type    => 1,
                                        object_number => ID,
                                        relative_fno  => FNO,
                                        block_number  => BLK,
                                        row_number    => 9999);
        BEGIN
            EXECUTE IMMEDIATE 'SELECT 1 FROM '||OBJ||' WHERE ROWNUM <2';
            OPEN :cur1 FOR 'SELECT /*+ROWID(A)*/ dbms_rowid.ROWID_ROW_NUMBER(ROWID) "ROW#",A.* FROM '||OBJ||' A WHERE ROWID BETWEEN :1 AND :2 ORDER BY ROWID'
                USING SRID,ERID;
        EXCEPTION WHEN OTHERS THEN
            OPEN :cur1 FOR SELECT 'Cannot query '||obj||' with current login.' Warning from dual;
        END;
        OPEN :cur2 FOR 'SELECT :0 OBJ_NAME,:4 SUB_NAME,:5 OBJ_TYPE,:1 BEGIN_ROWID, :2 END_ROWID FROM DUAL'  USING OBJ,SOBJ,TYP,SRID,ERID;
    END IF;
END;
/
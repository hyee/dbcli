/*[[Show object info for the input block in bh. Usage: @@NAME {<file#> <block#>} | <data block address>
	Sample Output:
	==============
    SQL> @@NAME 1 241
    DBA: 4194545(0x004000f1)    FILE#: 1    BLOCK#: 241
    =============================================================
    OWNER OBJECT_NAME SUBOBJECT_NAME OBJECT_ID DATA_OBJECT_ID OBJECT_TYPE       CREATED          LAST_DDL_TIME         TIMESTAMP      STATUS TEMPORARY GENERATED SECONDARY NAMESPACE EDITION_NAME
    ----- ----------- -------------- --------- -------------- ----------- ------------------- ------------------- ------------------- ------ --------- --------- --------- --------- ------------
    SYS   OBJ$                              18             18 TABLE       2011-08-28 22:10:48 2013-12-20 15:27:09 2011-08-28:22:10:48 VALID  N         N         N                 1

    ROWID INFO:
    ===========
    OBJ_NAME SUB_NAME OBJ_TYPE    BEGIN_ROWID         END_ROWID
    -------- -------- -------- ------------------ ------------------
    SYS.OBJ$          TABLE    AAAAASAABAAAADxAAB AAAAASAABAAAADxCcP

    DATA WITHIN SPECIC ROWID RANGE:
    ===============================
    ROW# OBJ# DATAOBJ# OWNER#         NAME         NAMESPACE SUBNAME TYPE#        CTIME               MTIME               STIME        STATUS REMOTEOWNER LINKNAME FLAGS OID$ SPARE1 SPARE2 SPARE3
    ---- ---- -------- ------ -------------------- --------- ------- ----- ------------------- ------------------- ------------------- ------ ----------- -------- ----- ---- ------ ------ ------
       1   46       46      0 I_USER1                      4             1 2011-08-28 22:10:48 2011-08-28 22:10:48 2011-08-28 22:10:48      1                          0           0  65535      0
       2   28       28      0 CON$                         1             2 2011-08-28 22:10:48 2011-08-28 22:18:15 2011-08-28 22:10:48      1                          0           0      1      0
       3   15       15      0 UNDO$                        1             2 2011-08-28 22:10:48 2011-08-28 22:10:48 2011-08-28 22:10:48      1                          0           0      1      0
       4   29       29      0 C_COBJ#                      5             3 2011-08-28 22:10:48 2011-08-28 22:10:48 2011-08-28 22:10:48      1                          0           0  65535      0
       5    3        3      0 I_OBJ#                       4             1 2011-08-28 22:10:48 2011-08-28 22:10:48 2011-08-28 22:10:48      1                          0           0  65535      0

    --[[
        @CHECK_ACCESS_SEG: {
            sys.seg$={select HWMINCR objd,file# from sys.seg$ where file#=&file and &block between block# and block#-1+blocks}
            X$BH={select * from table(gv$(cursor(select OBJ objd,file# from x$bh where file#=&file and DBABLK=&block)))}
            default={select * from table(gv$(cursor(select objd,file# from v$bh where file#=&file and block#=&block)))}
        }    
        @CHECK_ACCESS_OBJ: dba_objects={dba_objects}, default={all_objects}
        @ARGS: 1
    --]]
]]*/
set feed off verify off
var file number;
var block number;

DECLARE
	file  varchar2(100):=:v1;
	block int:=:v2;
	dba   int;
	SRID  ROWID;
    ERID  ROWID;
BEGIN
	IF block is null then
		IF substr(lower(file),1,2)='0x' THEN
			dba:=to_number(substr(lower(file),3),'xxxxxxxx');
		ELSIF regexp_like(file,'^\d+$') THEN
			dba:=file;
		ELSE
			raise_application_error(-20001,'Invalid data block address: '||file);
		END IF;

        IF dba < 4194305 THEN
            raise_application_error(-20001,'Usage: ora block {<file#> <block#>} | <data block address>');
        END IF;

		file := DBMS_UTILITY.DATA_BLOCK_ADDRESS_FILE(dba);
		block:= DBMS_UTILITY.DATA_BLOCK_ADDRESS_BLOCK(dba);
	ELSIF regexp_like(file,'^\d+$') THEN
		dba := DBMS_UTILITY.MAKE_DATA_BLOCK_ADDRESS(file,block);
	ELSE
		raise_application_error(-20001,'Invalid file#: '||file);
	END IF;
	dbms_output.put_line(utl_lms.format_message('DBA: %s(%s)    FILE#: %s    BLOCK#: %s',''||dba,'0x'||substr(to_char(dba,'fm0xxxxxxxx'),2),file,''||block));
	:file := file;
	:block:= block;
END;
/
PRO =============================================================
col OBJECT_ID new_value OBJECT_ID

SELECT b.*
FROM   (&CHECK_ACCESS_SEG) a, &CHECK_ACCESS_OBJ b
WHERE  rownum < 2
AND    objd = data_object_id;

set printsize 50
ora block2rowid "&OBJECT_ID" "&file" "&block"
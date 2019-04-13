/*[[List the available event number that used by 'alter session set events' statement. Usage: @@NAME [filter] 

Sample Output:
==============
ORCL> ora events hash
    ORA-10092: CBO Disable hash join
    ORA-10093: CBO Enable force hash joins
    ORA-10103: CBO Disable hash join swapping
    ORA-10104: dump hash join statistics to trace file
    ORA-10118: CBO Enable hash join costing
    ORA-10172: CBO force hash join back
    ORA-10178: CBO turn off hash cluster filtering through memcmp
    ORA-10344: reserved for simulating object hash reorganization
    ORA-10386: parallel SQL hash and range statistics
    ORA-10874: Change max logfiles in hashtable in krfbVerifyRedoAvailable
    ORA-10986: donot use HASH_AJ in refresh
    ORA-13837: invalid HASH_VALUE
    ORA-13839: V$SQL row doesn't exist with given HASH_VALUE and ADDRESS.
    ORA-13847: The plan with plan hash value %s does not exist
    ORA-14176: this attribute may not be specified for a hash partition
    ORA-14177: STORE-IN (Tablespace list) can only be specified for a LOCAL index on a Hash or Composite Range Hash table
    ORA-14178: STORE IN (DEFAULT) clause is not supported for hash partitioned global indexes
    ORA-14192: cannot modify physical index attributes of a Hash index partition
    ORA-14242: table is not partitioned by System, or Hash method
    ORA-14243: table is not partitioned by Range, System, List, or Hash method
    ORA-14252: invalid ALTER TABLE MODIFY PARTITION option for a Hash partition
    ORA-14257: cannot move partition other than a Range, List, System, or Hash partition
    ORA-14259: table is not partitioned by Hash method
    ORA-14261: partition bound may not be specified when adding this Hash partition
    ORA-14269: cannot exchange partition other than a Range,List,System, or Hash partition
    ORA-14270: table is not partitioned by Range, System, Hash or List method
   --[[
        @ALIAS: err
   --]]
]]*/
set feed off
DECLARE
    err_msg  VARCHAR2(2000);
    filter varchar2(300):= LOWER(:V1);
    rtn      PLS_INTEGER;
    cnt      PLS_INTEGER:=0;
    mx       PLS_INTEGER:=65535;
    facility varchar2(30);
    strip    varchar2(30):='['||chr(10)||chr(13)||chr(9)||']+';
    function msg(code PLS_INTEGER) return varchar2 IS
    BEGIN
        rtn:=utl_lms.get_message(abs(code),'rdbms',nvl(facility,'ora'),'us',err_msg);
        return regexp_replace(err_msg,strip,' ');
    END;
BEGIN
    IF filter IS NULL THEN
        filter:='%';
        mx:=10999;
    ELSE
        IF regexp_like(filter,'\d+$') THEN
            facility := nvl(regexp_substr(filter,'^[a-zA-Z]+'),'ora');
            dbms_output.put_line(upper(facility)||'-'||regexp_substr(filter,'\d+$')||': '||msg(regexp_substr(filter,'\d+$')));
            RETURN;
        END IF;
        filter:='%'||lower(filter)||'%';
    END IF;
    dbms_output.enable(null);
    FOR err_num IN 10000 .. mx LOOP
        err_msg := msg(err_num);
        IF err_msg NOT LIKE '%Message ' || err_num || ' not found%' AND lower(err_msg) LIKE filter THEN
            dbms_output.put_line('ORA-'||err_num||': ' ||err_msg);
            cnt := cnt +1;
        END IF;
    END LOOP;
    dbms_output.put_line(chr(10)||cnt||' events matched.');
END;
/


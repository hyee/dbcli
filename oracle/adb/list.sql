/*[[List files in cloud object store or Oracle directory. Usage: @@NAME {<directory>|{[<credential>] <URL>}} [<REGEXP_LIKE pattern>|<keyword>|-f"<filter>"] 
    --[[
        @ARGS: 1
        @CHECK_ACCESS_CLOUD: DBMS_CLOUD={}
        &filter: {default={regexp_like(object_name,keyword,'i')} 
                  f={}
                 }
        &op    : default={list} delete={delete} copy={copy} move={move}
        &ops   : default={} delete={to be deleted} copy={to be copied} move={to be moved}
    --]]
]]*/

var c refcursor "List of recent 100 matched objects&ops"
col bytes for tmb
set feed off
DECLARE
    C          SYS_REFCURSOR;
    op         VARCHAR2(10)   := :op;
    keyword    VARCHAR2(1000) := COALESCE(:V4,:V3,:V2);
    dest       VARCHAR2(1000);
    target     VARCHAR2(1000) := CASE WHEN :V2=keyword THEN :V1 ELSE NVL(:V2,:V1) END;
    credential VARCHAR2(1000) := CASE WHEN :V1=target THEN :credential ELSE :V1 END;
    is_url     BOOLEAN := FALSE;
    xml        XMLTYPE;
    ctx        NUMBER;
    PROCEDURE asser_credential IS
        cre VARCHAR2(1000);
    BEGIN
        SELECT MAX('"'||credential_name||'"')
        INTO   cre
        FROM   user_credentials
        WHERE  upper(credential_name)=upper(credential);

        IF cre IS NULL THEN
            raise_application_error(-20001,'Credential "'||credential||'" is not found in user_credentials.');
        END IF;
        credential := cre;
    END;

    FUNCTION asser_directory(dir VARCHAR2) RETURN VARCHAR2 IS
        d VARCHAR2(1000);
    BEGIN
        SELECT MAX('"'||directory_name||'"')
        INTO   d
        FROM   all_directories
        WHERE  upper(directory_name)=upper(dir);

        IF d IS NULL THEN
            raise_application_error(-20001,'Credential "'||dir||'" is not found in all_directories.');
        END IF;
        return d;
    END;
BEGIN
    IF op in('copy','move') THEN
        IF :V4 IS NOT NULL THEN
            dest   := :v3;
            target := :v2;
            credential := :V1;
        ELSIF :V3 IS NOT NULL THEN
            dest   := :v2;
            target := :v1;
            credential := :credential;
        ELSE
            raise_application_error(-20001,'Arguments: [<credential>] <source> <destination> {<keyword>|<REGEXP_LIKE pattern>}');
        END IF;

        IF target NOT like '%:%' AND dest NOT like '%:%' THEN
            raise_application_error(-20001,'one of source/destination must be an Object Storage URL.');
        ELSIF target like '%:%' AND dest like '%:%' THEN
            raise_application_error(-20001,'one of source/destination must be an Oracle directory.');
        END if;
    END IF;

    keyword := replace(replace(keyword,'%','.*'),'_','.');
    IF op!='list' AND keyword IS NULL THEN
        raise_application_error(-20001,'Please specify the regexp_like string as the file filter.');
    ELSIF keyword IS NOT NULL THEN
        BEGIN
            EXECUTE IMMEDIATE 'SELECT 1 FROM DUAL WHERE REGEXP_LIKE(:1,:2)'
            USING 'XXX',keyword;
        EXCEPTION WHEN OTHERS THEN 
            raise_application_error(-20001,'Unexpected REGEXP_LIKE pattern: '||keyword);
        END;
    ELSE
        keyword := '.';
    END IF;
    
    IF target like '%:%' THEN
        is_url := TRUE;
    END IF;

    IF is_url THEN
        asser_credential;
        OPEN C FOR
            SELECT * FROM DBMS_CLOUD.LIST_OBJECTS(credential,target) 
            WHERE  &filter 
            ORDER BY LAST_MODIFIED DESC
            FETCH FIRST 100 ROWS ONLY;
    ELSE
        target := asser_directory(target);
        OPEN C FOR
            SELECT * FROM DBMS_CLOUD.LIST_FILES(target) 
            WHERE &filter 
            ORDER BY LAST_MODIFIED DESC
            FETCH FIRST 100 ROWS ONLY;
    END IF;

    ctx := dbms_xmlgen.newcontext(c);
    xml := dbms_xmlgen.getxmltype(ctx);
    dbms_xmlgen.closecontext(ctx);

    
    IF op in('copy','move') THEN
        IF is_url THEN
            dest := asser_directory(dest);
            DBMS_CLOUD.BULK_DOWNLOAD (
                 credential_name => credential,
                 location_uri    => target,
                 directory_name  => dest,
                 regex_filter    => keyword);
            IF op = 'move' THEN
                DBMS_CLOUD.BULK_DELETE(credential,target,keyword);
            END IF;
        ELSE
            asser_credential;
            DBMS_CLOUD.BULK_UPLOAD(
                 credential_name => credential,
                 location_uri    => dest,
                 directory_name  => target,
                 regex_filter    => keyword);
        END IF;
    END IF;

    IF op in('delete','move') THEN
        IF is_url THEN
            DBMS_CLOUD.BULK_DELETE(credential,target,keyword);
        ELSE
            FOR R IN(SELECT * FROM DBMS_CLOUD.LIST_FILES(target) WHERE &filter) LOOP
                DBMS_CLOUD.DELETE_FILE(target,r.object_name);
            END LOOP;
        END IF;
    END IF;

    OPEN :c FOR
        SELECT * 
        FROM   XMLTABLE('/ROWSET/ROW' PASSING xml COLUMNS
                       OBJECT_NAME VARCHAR2(256),
                       BYTES INT,
                       CHECKSUM VARCHAR2(64),
                       CREATED VARCHAR2(40),
                       LAST_MODIFIED VARCHAR2(40));
END;
/

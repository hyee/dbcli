/*[Get the column info of target file in Object Storage. Usage: @@NAME [<credential>] <file_URI> [csv|json|xml|parquet|orc|avro]
    --[[
        @ARGS: 2
        @CHECK_ACCESS_DESC: SYS.KUBSD$DESC_INT={}
    --]]
]*/
set feed off
DECLARE
    typ               VARCHAR2(30)  := nvl(:V3,:V2);
    uri               VARCHAR2(1000):= CASE WHEN :V2=typ THEN :V1 ELSE NVL(:V2,:V1) END;
    credential        VARCHAR2(1000) := CASE WHEN :V1=uri THEN :credential ELSE :V1 END;
    column_clause     CLOB;
    return_code       BINARY_INTEGER := 0;
    stmt              VARCHAR2(32767);
    FUNCTION assert_url(url VARCHAR2) RETURN VARCHAR2 IS
        d VARCHAR2(1000) := url;
    BEGIN
        IF instr(d, '/') > 0 AND instr(d,'https://')=0 THEN
            IF :objbucket IS NULL THEN
                raise_application_error(-20001, 'Please define the default bucket by "set bucket" when the URL is a relative path.');
            END IF;
            d := trim(trailing '/' from :objbucket)||'/'|| trim(leading '/'  from d);
        END IF;
        IF instr(nvl(d, 'x'), 'http') != 1 THEN
            raise_application_error(-20001, 'Invalid Object Storage URL: ' || d);
        END IF;
        RETURN d;
    END;
BEGIN
    uri := assert_url(uri);
    stmt := q'~BEGIN
                 SYS.KUBSD$DESC_INT.KUBSDESC(
                          file_uri_list      => :1 ,
                          credential_name    => NVL(:2, '') , 
                          credential_schema  => :3 ,
                          type               => :4 ,
                          action             => :5 ,
                          delimiter          => ',',
                          maxvarchar         => 32767,
                          retcode            => :6,
                          doc                => :7 );
              END;~';
     EXECUTE IMMEDIATE stmt USING IN '["' || uri || '"]',
                                     IN trim('"' from credential),
                                     IN user,
                                     IN upper(typ),
                                     IN 'first',
                                     IN OUT return_code,
                                     IN OUT column_clause;
    dbms_output.enable(null);
    dbms_output.put_line('Target File  : '||uri);
    dbms_output.put_line('Return Code  : '||return_code);
    dbms_output.put_line('Return Clause: '||column_clause);
END;
/

/*[Compare fix controls and parameters between different optimizer_features_enable. Usage: @@NAME <OFE1> <OFE2> [<keyword>]
    [[
        @ARGS:2
    ]]

]*/
SET FEED OFF PRINTSIZE 10000
VAR cf REFCURSOR
DECLARE
    p1   CLOB;
    p2   CLOB;
    v3   VARCHAR2(128) := '%' || TRIM(lower(:v3)) || '%';
    curr VARCHAR2(30);
    PROCEDURE get_params(ofe VARCHAR2, v OUT CLOB) IS
    BEGIN
        EXECUTE IMMEDIATE 'alter session set optimizer_features_enable=''' || ofe || '''';
        SELECT JSON_ARRAYAGG(JSON_ARRAY(typ, NAME, val) RETURNING CLOB)
        INTO   v
        FROM   (SELECT 'Parameter' typ, n.ksppinm NAME, TRIM(c.ksppstvl) val
                FROM   sys.x$ksppi n, sys.x$ksppcv c
                WHERE  n.indx = c.indx
                AND    nvl(length(c.ksppstvl), 0) < 64
                AND    (v3 = '%%' OR lower(ksppinm || ',' || KSPPDESC) LIKE v3)
                UNION ALL
                SELECT '_fix_control', to_char(bugno), to_char(VALUE)
                FROM   v$session_fix_control
                WHERE  session_id = userenv('sid')
                AND    (v3 = '%%' OR lower(sql_feature || ',' || description) LIKE v3));
    EXCEPTION WHEN OTHERS THEN
        IF curr != :V2 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_features_enable=''' || curr || '''';
        END IF;
        RAISE; 
    END;
BEGIN
    SELECT VALUE INTO curr FROM v$parameter WHERE NAME = 'optimizer_features_enable';
    get_params(:V1, p1);
    get_params(:V2, p2);
    IF curr != :V2 THEN
        EXECUTE IMMEDIATE 'alter session set optimizer_features_enable=''' || curr || '''';
    END IF;

    OPEN :cf FOR
        SELECT /*+outline_leaf opt_estimate(table p1 rows=100000) opt_estimate(table p2 rows=100000) use_hash(p1 p2)*/
               typ, NAME, p1.v1 "&V1", p2.v2 "&V2", nvl(p.KSPPDESC, f.description) description
        FROM   JSON_TABLE(p1,'$[*]' COLUMNS 
                    typ VARCHAR2(30)   PATH '$[0]',
                    name VARCHAR2(200) PATH '$[1]',
                    v1  VARCHAR2(200)  PATH '$[2]') p1
        JOIN   JSON_TABLE(p2,'$[*]' COLUMNS 
                    typ VARCHAR2(30)   PATH '$[0]',
                    name VARCHAR2(200) PATH '$[1]',
                    v2  VARCHAR2(200)  PATH '$[2]') p2
        USING  (typ, NAME)
        LEFT   JOIN sys.x$ksppi p
        ON     typ = 'Parameter'
        AND    NAME = p.ksppinm
        LEFT   JOIN v$system_fix_control f
        ON     typ = '_fix_control'
        AND    NAME = '' || f.bugno
        WHERE  NVL(p1.v1, ' ') != nvl(p2.v2, ' ')
        ORDER  BY typ, NAME;
END;
/
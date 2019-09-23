/*[[List all memory info. Usage: @@NAME [SGA|PGA|UGA|<X table name>] ]]*/
var c refcursor;
set printsize 10000
DECLARE
    tabs  ODCIVARCHAR2LIST := ODCIVARCHAR2LIST();
    addrs ODCIRAWLIST := ODCIRAWLIST();
    addr  RAW(32);
    c     PLS_INTEGER := 0;
    cur   SYS_REFCURSOR;
BEGIN
    FOR r IN (SELECT kqftanam t, c.kqfconam c
              FROM   x$kqfta t, x$kqfco c
              WHERE  c.kqfcotab = t.indx
              AND    lower(kqftanam) NOT IN ('x$ksmsp')
              AND    INSTR(kqfconam, ' ') = 0
              AND    kqfcodty = 23
              AND    c.kqfcosiz IN (8)
              AND    nvl(upper(:V1),'SGA') IN('SGA','UGA','PGA',kqftanam)) LOOP
        addr := NULL;
        BEGIN
            EXECUTE IMMEDIATE 'select ' || r.c || ' from ' || r.t || ' where rownum<2 and ' || r.c ||
                              '!=hextoraw(''00'')'
                INTO addr;
        EXCEPTION
            WHEN OTHERS THEN
                null;
        END;
        IF addr IS NOT NULL THEN
            c := c + 1;
            tabs.extend;
            addrs.extend;
            tabs(c) := r.t || ' ' || r.c;
            addrs(c) := addr;
        END IF;
    END LOOP;
    OPEN :c FOR
        WITH src AS
         (SELECT /*+materialize OPT_ESTIMATE(query_block, rows=2048)*/ substr(addr,1,8) r,src,addr
          FROM   (SELECT ROWNUM r, COLUMN_VALUE src FROM TABLE(tabs)) 
          JOIN   (SELECT ROWNUM r, COLUMN_VALUE addr FROM TABLE(addrs))
          USING  (r)
          ORDER  by addr),
        ksm AS
         (SELECT /*+materialize OPT_ESTIMATE(query_block, rows=20480000)*/substr(KSMCHPTR,1,8) r,a.*
          FROM   (SELECT 'SGA' LOC,
                         KSMCHPTR,
                         KSMCHIDX,
                         KSMCHDUR,
                         KSMCHCOM,
                         KSMCHSIZ,
                         KSMCHCLS,
                         KSMCHTYP,
                         KSMCHPAR,
                         HEXTORAW(to_char(to_number(ksmchptr, 'XXXXXXXXXXXXXXXX') + ksmchsiz - 1, 'FM0XXXXXXXXXXXXXXX')) KSMCHPTRN
                  FROM   x$ksmsp
                  WHERE  nvl(upper(:V1),'SGA') NOT IN('UGA','PGA')
                  UNION ALL
                  SELECT 'UGA',
                         KSMCHPTR,
                         NULL,
                         NULL,
                         KSMCHCOM,
                         KSMCHSIZ,
                         KSMCHCLS,
                         KSMCHTYP,
                         KSMCHPAR,
                         HEXTORAW(to_char(to_number(ksmchptr, 'XXXXXXXXXXXXXXXX') + ksmchsiz - 1, 'FM0XXXXXXXXXXXXXXX'))
                  FROM   x$ksmup
                  WHERE  nvl(upper(:V1),'SGA') NOT IN('SGA','PGA')
                  UNION ALL
                  SELECT 'PGA',
                         KSMCHPTR,
                         NULL,
                         NULL,
                         KSMCHCOM,
                         KSMCHSIZ,
                         KSMCHCLS,
                         KSMCHTYP,
                         KSMCHPAR,
                         HEXTORAW(to_char(to_number(ksmchptr, 'XXXXXXXXXXXXXXXX') + ksmchsiz - 1, 'FM0XXXXXXXXXXXXXXX'))
                  FROM   x$ksmpp
                  WHERE  nvl(upper(:V1),'SGA') NOT IN('SGA','UGA')) a
          ORDER BY KSMCHPTR,KSMCHPTRN)
        SELECT /*+leading(a) use_hash(a b)*/
               regexp_substr(a.src,'\S+',1,1) xtable,
               regexp_substr(a.src,'\S+',1,2) col,
               a.addr sample_addr, LOC, KSMCHPAR,KSMCHPTR, KSMCHIDX, KSMCHDUR, KSMCHCOM, KSMCHSIZ, KSMCHCLS, KSMCHTYP
        FROM   src a, ksm b
        WHERE  a.addr BETWEEN KSMCHPTR AND KSMCHPTRN
        AND    a.r=b.r
        ORDER  BY 1,2;
END;
/
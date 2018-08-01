/*[[Describe X$ tables, column offsets and report indexed fixed table. Usage: @@NAME <x$table name>
Author:      Tanel Poder
]]*/
SELECT t.kqftanam TABLE_NAME, c.KQFCOCNO COL#, c.kqfconam COLUMN_NAME,
       decode(kqfcodty,
               1,'VARCHAR2',
               2,'NUMBER',
               8,'LONG',
               9,'VARCHAR',
               12,'DATE',
               23,'RAW',
               24,'LONG RAW',
               58,'CUSTOM OBJ',
               69,'ROWID',
               96,'CHAR',
               100,'BINARY_FLOAT',
               101,'BINARY_DOUBLE',
               105,'MLSLABEL',
               106,'MLSLABEL',
               111,'REF',
               112,'CLOB',
               113,'BLOB',
               114,'BFILE',
               115,'CFILE',
               121,'CUSTOM OBJ',
               122,'CUSTOM OBJ',
               123,'CUSTOM OBJ',
               178,'TIME',
               179,'TIME WITH TIME ZONE',
               180,'TIMESTAMP',
               181,'TIMESTAMP WITH TIME ZONE',
               231,'TIMESTAMP WITH LOCAL TIME ZONE',
               182,'INTERVAL YEAR TO MONTH',
               183,'INTERVAL DAY TO SECOND',
               208,'UROWID',
               'UNKNOWN') || '(' || to_char(c.kqfcosiz) || ')' DATA_TYPE, 
       c.kqfcooff offset, lpad('0x' || TRIM(to_char(c.kqfcooff, 'XXXXXX')), 8) offset_hex,
       decode(c.kqfcoidx, 0,'','Yes('||c.kqfcoidx||')') "Indexed?"
FROM   x$kqfta t, x$kqfco c
WHERE  c.kqfcotab = t.indx
and    c.inst_id = t.inst_id
AND    trim(:V1) is not null
AND   (upper(t.kqftanam) LIKE upper(:V1) or t.kqftanam=(SELECT KQFDTEQU FROM x$kqfdt WHERE KQFDTNAM=upper(:V1)))
ORDER  BY 1,2;

/*[[Show main cursor data block heap sizes and their contents. Usage: @@NAME <sql_id>
    Author:      Tanel Poder(curheaps.sql)
    --[[
      @ALIAS: curheaps
    --]]
]]*/

SET FEED OFF

SELECT kglobt09 CHILD#, KGLHDADR, KGLOBHD0 heap0, KGLOBHS0 size0, KGLOBHD1 heap1, KGLOBHS1 size1,
       KGLOBHD2 heap2, KGLOBHS2 size2, KGLOBHD3 heap3, KGLOBHS3 size3, KGLOBHD4 heap4,
       KGLOBHS4 size4, KGLOBHD5 heap5, KGLOBHS5 size5, KGLOBHD6 heap6, KGLOBHS6 size6,
       KGLOBHD7 heap7, KGLOBHS7 size7, KGLOBSTA STATUS
FROM   sys.X$KGLOB l
WHERE  kglobt03 = :V1;

PRO Memory Heap:
PRO ==========
SELECT /*+use_nl(l hp) ordered*/
       DECODE(KSMCHDS,KGLOBHD0,'HEAP0',KGLOBHD1,'HEAP1',KGLOBHD3,'HEAP2',KGLOBHD3,'HEAP3',KGLOBHD4,'HEAP4',KGLOBHD5,'HEAP5',KGLOBHD6,'HEAP6','HEAP7')  heap#, 
       ksmchcls CLASS, ksmchcom alloc_comment, SUM(ksmchsiz) bytes,
       COUNT(*) chunks
FROM   sys.X$KGLOB l, sys.x$ksmhp hp
WHERE  kglobt03 = :V1
AND    KSMCHDS !=hextoraw('00')
AND    KSMCHDS IN (KGLOBHD0, KGLOBHD1, KGLOBHD2, KGLOBHD3, KGLOBHD4, KGLOBHD5, KGLOBHD6)
GROUP  BY DECODE(KSMCHDS,KGLOBHD0,'HEAP0',KGLOBHD1,'HEAP1',KGLOBHD3,'HEAP2',KGLOBHD3,'HEAP3',KGLOBHD4,'HEAP4',KGLOBHD5,'HEAP5',KGLOBHD6,'HEAP6','HEAP7') , ksmchcls, ksmchcom;

PRO PGA Heap:
PRO ==========
SELECT /*+use_nl(l hp) ordered*/
       DECODE(ksmchpar ,KGLOBHD0,'HEAP0',KGLOBHD1,'HEAP1',KGLOBHD3,'HEAP2',KGLOBHD3,'HEAP3',KGLOBHD4,'HEAP4',KGLOBHD5,'HEAP5',KGLOBHD6,'HEAP6','HEAP7')  heap#, 
       ksmchcls CLASS, ksmchcom alloc_comment, SUM(ksmchsiz) bytes,
       COUNT(*) chunks
FROM   sys.X$KGLOB l, sys.x$ksmpp hp
WHERE  kglobt03 = :V1
AND    ksmchpar  !=hextoraw('00')
AND    ksmchpar  IN (KGLOBHD0, KGLOBHD1, KGLOBHD2, KGLOBHD3, KGLOBHD4, KGLOBHD5, KGLOBHD6)
GROUP  BY DECODE(ksmchpar ,KGLOBHD0,'HEAP0',KGLOBHD1,'HEAP1',KGLOBHD3,'HEAP2',KGLOBHD3,'HEAP3',KGLOBHD4,'HEAP4',KGLOBHD5,'HEAP5',KGLOBHD6,'HEAP6','HEAP7') , ksmchcls, ksmchcom;

/*
PRO SGA Heap:
PRO ==========
SELECT --+use_nl(l hp) ordered
       DECODE(ksmchpar ,KGLOBHD0,'HEAP0',KGLOBHD1,'HEAP1',KGLOBHD3,'HEAP2',KGLOBHD3,'HEAP3',KGLOBHD4,'HEAP4',KGLOBHD5,'HEAP5',KGLOBHD6,'HEAP6','HEAP7')  heap#, 
       ksmchcls CLASS, ksmchcom alloc_comment, SUM(ksmchsiz) bytes,
       COUNT(*) chunks
FROM   sys.X$KGLOB l, sys.x$ksmsp hp
WHERE  kglobt03 = :V1
AND    ksmchpar  !=hextoraw('00')
AND    ksmchpar  IN (KGLOBHD0, KGLOBHD1, KGLOBHD2, KGLOBHD3, KGLOBHD4, KGLOBHD5, KGLOBHD6)
GROUP  BY DECODE(ksmchpar ,KGLOBHD0,'HEAP0',KGLOBHD1,'HEAP1',KGLOBHD3,'HEAP2',KGLOBHD3,'HEAP3',KGLOBHD4,'HEAP4',KGLOBHD5,'HEAP5',KGLOBHD6,'HEAP6','HEAP7') , ksmchcls, ksmchcom;
*/

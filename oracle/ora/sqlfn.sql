/*[[Search SQL functions]]*/

select a.*,(select listagg(datatype,',') within group(order by argnum) from  V$SQLFN_ARG_METADATA  where func_id=a.func_id) args
from V$SQLFN_METADATA  a
where rownum<=50
and   ((:V1 IS NULL AND OFFLOADABLE='YES')
   or  (:V1 IS NOT NULL AND  name||','||a.descr like upper('%&V1%')));
/*[[Show info in x$trace of a specific sid. Usage: xtrace <sid> [inst_id] ]]*/

select * from (select /*+no_expand*/ a.* from x$trace a where sid=:V1 and (:V2 is null or inst_id=:V2) order by a.time desc)
WHERE ROWNUM<=300 order by time;
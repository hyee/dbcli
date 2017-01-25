/*[[Show library cache objects over the average
    Refer to : http://www.ixora.com.au/scripts/
]]*/
select /*+ ordered */
   b.inst_id, l.child# latch#, o.kglnaobj object_name,l.sleeps
   from (select inst_id, count(*) latches, avg(sleeps) sleeps
          from gv$latch_children
         where name = 'library cache'
         group by inst_id) a,
       gv$latch_children l,
       (select s.inst_id,
               s.buckets *
               power(2, least(8, ceil(log(2, ceil(count(*) / s.buckets))))) buckets
          from (select y.inst_id,
                       decode(y.ksppstvl,
                              0,
                              509,
                              1,
                              1021,
                              2,
                              2039,
                              3,
                              4093,
                              4,
                              8191,
                              5,
                              16381,
                              6,
                              32749,
                              7,
                              65521,
                              8,
                              131071,
                              509) buckets
                  from x$ksppi x, x$ksppcv y
                 where x.inst_id = y.inst_id
                   and x.ksppinm = '_kgl_bucket_count'
                   and y.indx = x.indx) s,
               x$kglob c
         where c.kglhdadr = c.kglhdpar
           and c.inst_id = s.inst_id
         group by s.buckets, s.inst_id) b,
       x$kglob o
 where l.name = 'library cache'
   and l.sleeps > 2 * a.sleeps
   and mod(mod(o.kglnahsh, b.buckets), a.latches) + 1 = l.child#
   and o.inst_id = b.inst_id
   and l.inst_id = b.inst_id
   and a.inst_id = b.inst_id
   and o.kglhdadr = o.kglhdpar;

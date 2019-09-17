/*[[Show library cache objects over the average
    Refer to : http://www.ixora.com.au/scripts/
]]*/
SELECT * FROM TABLE(GV$(CURSOR(
    SELECT /*+ ordered */
           b.inst_id, l.child# latch#, o.kglnaobj object_name, l.sleeps
    FROM   (SELECT COUNT(*) latches, AVG(sleeps) sleeps FROM v$latch_children WHERE NAME = 'library cache') a,
           v$latch_children l,
           (SELECT s.inst_id, s.buckets * power(2, least(8, ceil(log(2, ceil(COUNT(*) / s.buckets))))) buckets
            FROM   (SELECT y.inst_id, decode(y.ksppstvl, 0, 509, 1, 1021, 2, 2039, 3, 4093, 4, 8191, 5, 16381, 6, 32749, 7, 65521, 8, 131071, 509) buckets
                    FROM   x$ksppi x, x$ksppcv y
                    WHERE  x.inst_id = y.inst_id
                    AND    x.ksppinm = '_kgl_bucket_count'
                    AND    y.indx = x.indx) s,
                   x$kglob c
            WHERE  c.kglhdadr = c.kglhdpar
            GROUP  BY s.buckets, s.inst_id) b, 
           x$kglob o
    WHERE  l.name = 'library cache'
    AND    l.sleeps > 2 * a.sleeps
    AND    MOD(MOD(o.kglnahsh, b.buckets), a.latches) + 1 = l.child#
    AND    o.kglhdadr = o.kglhdpar)));
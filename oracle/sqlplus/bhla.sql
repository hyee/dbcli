
/*[[Report which blocks are in buffer cache, protected by a cache buffers chains child latch. Usage: bhla <child latch address>
-- Author:      Tanel Poder
-- Copyright:   (c) http://www.tanelpoder.com
--
-- Usage:       @bhla <child latch address>
--              @bhla 27E5A780
--
--
-- Other:       This script reports all buffers "under" the given cache buffers
--              chains child latch, their corresponding segment names and
--              touch counts (TCH).
--
]]*/

col bhla_object head object for a40 truncate
col bhla_DBA head DBA for a20

select  /*+ ORDERED */
    trim(to_char(bh.flag, 'XXXXXXXX'))    ||':'||
    trim(to_char(bh.lru_flag, 'XXXXXXXX'))     flg_lruflg,
    bh.obj,
    o.object_type,
    o.owner||'.'||o.object_name        bhla_object,
    bh.tch,
    file# ||' '||dbablk            bhla_DBA,
    bh.class,
    bh.state,
    bh.mode_held,
    bh.dirty_queue                DQ
from
    sys.x$bh       bh,
    dba_objects    o
where
    bh.obj = o.data_object_id
and    hladdr = hextoraw(lpad('&1', vsize(hladdr)*2 , '0'))
order by
    tch asc
/

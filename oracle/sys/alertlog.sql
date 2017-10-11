/*[[Show top 300 alert logs of current instance. Usage: @@NAME {[yymmddhh24miss] [yymmddhh24miss]}
    --[[
        @check_version: 11.0={}
    ]]--
]]*/
select * from (
    select inst_id,to_char(originating_timestamp,'yyyy-mm-dd hh24:mi:ss') timestamp, message_text 
    FROM TABLE(gv$(CURSOR(
        SELECT * from x$dbgalertext
        where originating_timestamp+0 between nvl(to_date(:V1,'yymmddhh24miss'),sysdate-7) and nvl(to_date(:V2,'yymmddhh24miss'),sysdate)
    )))
    order by originating_timestamp desc)
where rownum<=300;
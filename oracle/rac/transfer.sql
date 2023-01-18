/*[[
    Sample gv$instance_cache_transfer within specific seconds and generate the gc block transfer result between instances. Usage: @@NAME <secs>
    Sample Output:
    ==============
    +----------------------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+
    | Inst->Inst class     | CR blk Tx |CR blk tm  | CR blkav  | CR 2hop   | CR2hop tm | CR 2hop   | CR 3hop   |CR 3hop tm |CR 3hop av |
    +----------------------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+
    | 2->12nd level bmb    |         18|       1383|        .07|         18|       1383|        .07|          0|          0|          0|
    | 2->1undo header      |         24|       1294|        .05|         24|       1294|        .05|          0|          0|          0|
    | 1->21st level bmb    |          2|        146|        .07|          2|        146|        .07|          0|          0|          0|
    | 1->22nd level bmb    |          4|        333|        .08|          4|        333|        .08|          0|          0|          0|
    | 1->2undo header      |         20|       1350|        .06|         20|       1350|        .06|          0|          0|          0|
    +----------------------------------------------------------------------------------------------------------------------------------+

    +----------------------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+
    | Inst->Inst class     | CUR blk Tx|CUR blk tm | CUR blkav | CUR 2hop  | CUR2hop tm| CUR 2hop  | CUR 3hop  |CUR 3hop tm|CUR 3hop av|
    +----------------------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+
    | 2->12nd level bmb    |          7|       1444|         .2|          7|       1444|         .2|          0|          0|          0|
    | 1->22nd level bmb    |          2|        181|        .09|          2|        181|        .09|          0|          0|          0|
    +----------------------------------------------------------------------------------------------------------------------------------+

    +----------------------+-----------+-----------+-----------+-----------+-----------+-----------+
    | Inst->Inst class     | CRbsy     | CRbsy tm  | CRbsy %   | CRcongest | CRcngst tm| CRcng %   |
    |----------------------+-----------+-----------+-----------+-----------+-----------+-----------+
    | 2->12nd level bmb    |          0|          0|          0|          0|          0|          0|
    | 2->1undo header      |          3|        757|       58.5|          0|          0|          0|
    | 1->21st level bmb    |          0|          0|          0|          0|          0|          0|
    | 1->22nd level bmb    |          0|          0|          0|          0|          0|          0|
    | 1->2undo header      |          7|       1662|     123.11|          0|          0|          0|
    +----------------------+-----------+-----------+-----------+-----------+-----------+-----------+

    +----------------------------------------------------------------------------------------------+
    | Inst->Inst class     | CURbsy    | CURbsy tm | CURbsy %  | CURcongest|CURcngst tm| CURcng %  |
    +----------------------+-----------+-----------+-----------+-----------+-----------+-----------+
    | 2->12nd level bmb    |          0|          0|          0|          0|          0|          0|
    | 1->22nd level bmb    |          0|          0|          0|          0|          0|          0|
    |----------------------------------------------------------------------------------------------+
    --[[
        @ARGS: 1
        &V1: default={30}
    --]]
]]*/
/*
REM --------------------------------------------------------------------------------------------------
REM Author: Riyaj Shamsudeen @OraInternals, LLC
REM www.orainternals.com
REM
REM Functionality: This script is to print GC processing timing for the past N seconds
or so
REM **************
REM
REM Source : gv$sysstat
REM
REM Note : 1. Keep window 160 columns for better visibility.
REM
REM Exectution type: Execute from sqlplus or any other tool. Modify sleep as needed. Default is 60 seconds
REM
REM Parameters:
REM No implied or explicit warranty
REM
REM Please send me an email to rshamsud@orainternals.com for any question..
REM NOTE 1. Querying gv$ tables when there is a GC performance issue is not exactly nice. So, don't run this too often.
REM      2. Until 11g, gv statistics did not include PQ traffic.
REM      3. Of course, this does not tell any thing about root cause :-)
REM @copyright : OraInternals, LLC. www.orainternals.com
REM Version Change
REM ---------- --------------------
REM --------------------------------------------------------------------------------------------------
*/

SET verify off feed off
Define sleep=&v1
PROMPT
PROMPT
PROMPT gc_instance_cache.sql v1.10 by Riyaj Shamsudeen @orainternals.com
PROMPT
PROMPT ...Prints various timing related information for the past N seconds
PROMPT ...Please wait for at least &sleep seconds...
PROMPT
PROMPT Column name key:
PROMPT   Inst -> Inst class : source and target instance and class of the block transfer
PROMPT   CR blk TX  : CR blocks transmitted
PROMPT   CR blk tm  : CR blocks time taken
PROMPT   CR blk av  : Average time taken for CR block
PROMPT   CR bsy     : Count of blocks suffered from "busy" events
PROMPT   CR bsy tm  : Amount of time taken due to "busy" waits
PROMPT   CR bsy %   : Percentage of CR busy time to CR time
PROMPT   CR congest : Count of blocks suffered from "congestion" events
PROMPT   CR cngsttm : Amount of time taken due to "congestion" waits
PROMPT   CR cng %   : Percentage of CR congestion time to CR time

DECLARE
    TYPE t_number_table IS TABLE OF NUMBER INDEX BY VARCHAR2(32);
    TYPE t_varchar2_table IS TABLE OF VARCHAR2(32) INDEX BY VARCHAR2(32);
    TYPE t_key_table IS TABLE OF VARCHAR2(32) INDEX BY BINARY_INTEGER;
    key_table                t_key_table;
    b_inst_id                t_number_table;
    b_instance               t_number_table;
    b_class                  t_varchar2_table;
    b_lost                   t_number_table;
    b_lost_time              t_number_table;
    b_CR_BLOCK               t_number_table;
    b_CR_BLOCK_TIME          t_number_table;
    b_CR_2HOP                t_number_table;
    b_CR_2HOP_TIME           t_number_table;
    b_CR_3HOP                t_number_table;
    b_CR_3HOP_TIME           t_number_table;
    b_CR_BUSY                t_number_table;
    b_CR_BUSY_TIME           t_number_table;
    b_CR_CONGESTED           t_number_table;
    b_CR_CONGESTED_TIME      t_number_table;
    b_CURRENT_BLOCK          t_number_table;
    b_CURRENT_BLOCK_TIME     t_number_table;
    b_CURRENT_2HOP           t_number_table;
    b_CURRENT_2HOP_TIME      t_number_table;
    b_CURRENT_3HOP           t_number_table;
    b_CURRENT_3HOP_TIME      t_number_table;
    b_CURRENT_BUSY           t_number_table;
    b_CURRENT_BUSY_TIME      t_number_table;
    b_CURRENT_CONGESTED      t_number_table;
    b_CURRENT_CONGESTED_TIME t_number_table;
    e_inst_id                t_number_table;
    e_instance               t_number_table;
    e_class                  t_varchar2_table;
    e_lost                   t_number_table;
    e_lost_time              t_number_table;
    e_CR_BLOCK               t_number_table;
    e_CR_BLOCK_TIME          t_number_table;
    e_CR_2HOP                t_number_table;
    e_CR_2HOP_TIME           t_number_table;
    e_CR_3HOP                t_number_table;
    e_CR_3HOP_TIME           t_number_table;
    e_CR_BUSY                t_number_table;
    e_CR_BUSY_TIME           t_number_table;
    e_CR_CONGESTED           t_number_table;
    e_CR_CONGESTED_TIME      t_number_table;
    e_CURRENT_BLOCK          t_number_table;
    e_CURRENT_BLOCK_TIME     t_number_table;
    e_CURRENT_2HOP           t_number_table;
    e_CURRENT_2HOP_TIME      t_number_table;
    e_CURRENT_3HOP           t_number_table;
    e_CURRENT_3HOP_TIME      t_number_table;
    e_CURRENT_BUSY           t_number_table;
    e_CURRENT_BUSY_TIME      t_number_table;
    e_CURRENT_CONGESTED      t_number_table;
    e_CURRENT_CONGESTED_TIME t_number_table;
    v_ver                    NUMBER;
    l_sleep                  NUMBER := 60;
    l_cr_blks_served         NUMBER := 0;
    l_cur_blks_served        NUMBER := 0;
    i                        NUMBER := 1;
    ind                      VARCHAR2(32);
    CURSOR cur_1 IS
        SELECT instance || ',' || inst_id || ',' || CLASS indx, ic.*
        FROM   gv$instance_cache_transfer ic
        WHERE  cr_block > 0;
    c1  cur_1%rowtype;
    tim number;
BEGIN
    l_sleep:=upper(nvl('&sleep', 60));

    OPEN cur_1;

    tim := dbms_utility.get_time;
    LOOP
        FETCH cur_1 INTO c1;
        EXIT WHEN cur_1%NOTFOUND;
        key_table(i) := c1.indx;
        b_inst_id(c1.indx) := c1.inst_id;
        b_instance(c1.indx) := c1.instance;
        b_class(c1.indx) := c1.class;
        b_lost(c1.indx) := c1.lost;
        b_lost_time(c1.indx) := c1.lost_time;
        b_CR_BLOCK(c1.indx) := c1.cr_block;
        b_CR_BLOCK_TIME(c1.indx) := c1.cr_block_time;
        b_CR_2HOP(c1.indx) := c1.cr_2hop;
        b_CR_2HOP_TIME(c1.indx) := c1.cr_2hop_time;
        b_CR_3HOP(c1.indx) := c1.cr_3hop;
        b_CR_3HOP_TIME(c1.indx) := c1.cr_3hop_time;
        b_CR_BUSY(c1.indx) := c1.cr_busy;
        b_CR_BUSY_TIME(c1.indx) := c1.cr_busy_time;
        b_CR_CONGESTED(c1.indx) := c1.cr_congested;
        b_CR_CONGESTED_TIME(c1.indx) := c1.cr_congested_time;
        b_CURRENT_BLOCK(c1.indx) := c1.current_block;
        b_CURRENT_BLOCK_TIME(c1.indx) := c1.current_block_time;
        b_CURRENT_2HOP(c1.indx) := c1.current_2hop;
        b_CURRENT_2HOP_TIME(c1.indx) := c1.current_2hop_time;
        b_CURRENT_3HOP(c1.indx) := c1.current_3hop;
        b_CURRENT_3HOP_TIME(c1.indx) := c1.current_3hop_time;
        b_CURRENT_BUSY(c1.indx) := c1.current_busy;
        b_CURRENT_BUSY_TIME(c1.indx) := c1.current_busy_time;
        b_CURRENT_CONGESTED(c1.indx) := c1.current_congested;
        b_CURRENT_CONGESTED_TIME(c1.indx) := c1.current_congested_time;
        i := i + 1;
    END LOOP;
    CLOSE CUR_1;

    dbms_lock.sleep(l_sleep+tim-dbms_utility.get_time);
    OPEN cur_1;
    LOOP
        FETCH cur_1 INTO c1;
        EXIT WHEN cur_1%NOTFOUND;
        e_inst_id(c1.indx) := c1.inst_id;
        e_instance(c1.indx) := c1.instance;
        e_class(c1.indx) := c1.class;
        e_lost(c1.indx) := c1.lost;
        e_lost_time(c1.indx) := c1.lost_time;
        e_CR_BLOCK(c1.indx) := c1.cr_block;
        e_CR_BLOCK_TIME(c1.indx) := c1.cr_block_time;
        e_CR_2HOP(c1.indx) := c1.cr_2hop;
        e_CR_2HOP_TIME(c1.indx) := c1.cr_2hop_time;
        e_CR_3HOP(c1.indx) := c1.cr_3hop;
        e_CR_3HOP_TIME(c1.indx) := c1.cr_3hop_time;
        e_CR_BUSY(c1.indx) := c1.cr_busy;
        e_CR_BUSY_TIME(c1.indx) := c1.cr_busy_time;
        e_CR_CONGESTED(c1.indx) := c1.cr_congested;
        e_CR_CONGESTED_TIME(c1.indx) := c1.cr_congested_time;
        e_CURRENT_BLOCK(c1.indx) := c1.current_block;
        e_CURRENT_BLOCK_TIME(c1.indx) := c1.current_block_time;
        e_CURRENT_2HOP(c1.indx) := c1.current_2hop;
        e_CURRENT_2HOP_TIME(c1.indx) := c1.current_2hop_time;
        e_CURRENT_3HOP(c1.indx) := c1.current_3hop;
        e_CURRENT_3HOP_TIME(c1.indx) := c1.current_3hop_time;
        e_CURRENT_BUSY(c1.indx) := c1.current_busy;
        e_CURRENT_BUSY_TIME(c1.indx) := c1.current_busy_time;
        e_CURRENT_CONGESTED(c1.indx) := c1.current_congested;
        e_CURRENT_CONGESTED_TIME(c1.indx) := c1.current_congested_time;
    END LOOP;
    CLOSE CUR_1;

    dbms_output.put_line('+----------------------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+');
    dbms_output.put_line('| Inst->Inst class     | CR blk Tx |CR blk tm  | CR blkav  | CR 2hop   | CR2hop tm | CR 2hop   | CR 3hop   |CR 3hop tm |CR 3hop av |');
    dbms_output.put_line('+----------------------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+');
    FOR i IN key_table.first .. key_table.last LOOP
        ind := key_table(i);
        IF (e_cr_block(ind) - b_cr_block(ind) > 0) THEN
            dbms_output.put_line('| '||rpad(e_instance(ind) || '->' || e_inst_id(ind) || '' || e_class(ind),21) || '|' || 
                                 lpad(to_char(e_cr_block(ind) - b_cr_block(ind)), 11) || '|' ||
                                 lpad(to_char(e_cr_block_time(ind) - b_cr_block_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_cr_block(ind) - b_cr_block(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc((e_cr_block_time(ind) - b_cr_block_time(ind)) / (e_cr_block(ind) - b_cr_block(ind)) / 1000, 2)
                                              END),11) || '|' || 
                                 lpad(to_char(e_cr_2hop(ind) - b_cr_2hop(ind)), 11) || '|' ||
                                 lpad(to_char(e_cr_2hop_time(ind) - b_cr_2hop_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_cr_2hop(ind) - b_cr_2hop(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc((e_cr_2hop_time(ind) - b_cr_2hop_time(ind)) / (e_cr_2hop(ind) - b_cr_2hop(ind)) / 1000, 2)
                                              END),11) || '|' || 
                                 lpad(to_char(e_current_3hop(ind) - b_current_3hop(ind)), 11) || '|' ||
                                 lpad(to_char(e_current_3hop_time(ind) - b_current_3hop_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_current_3hop(ind) - b_current_3hop(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc((e_current_3hop_time(ind) - b_current_3hop_time(ind)) / (e_current_3hop(ind) - b_current_3hop(ind)) / 1000,
                                                         2)
                                              END),11) || '|');
        END IF;
    END LOOP;
    dbms_output.put_line('+----------------------------------------------------------------------------------------------------------------------------------+');
    dbms_output.put_line(' ');
    dbms_output.put_line('+----------------------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+');
    dbms_output.put_line('| Inst->Inst class     | CUR blk Tx|CUR blk tm | CUR blkav | CUR 2hop  | CUR2hop tm| CUR 2hop  | CUR 3hop  |CUR 3hop tm|CUR 3hop av|');
    dbms_output.put_line('+----------------------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+');
    FOR i IN key_table.first .. key_table.last LOOP
        ind := key_table(i);
        IF (e_current_block(ind) - b_current_block(ind) > 0) THEN
            dbms_output.put_line('| '||rpad(e_instance(ind) || '->' || e_inst_id(ind) || '' || e_class(ind),21) || '|' ||
                                 lpad(to_char(e_current_block(ind) - b_current_block(ind)), 11) || '|' ||
                                 lpad(to_char(e_current_block_time(ind) - b_current_block_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_current_block(ind) - b_current_block(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc((e_current_block_time(ind) - b_current_block_time(ind)) / (e_current_block(ind) - b_current_block(ind)) / 1000,2)
                                              END),11) || '|' ||
                                 lpad(to_char(e_current_2hop(ind) - b_current_2hop(ind)), 11) || '|' ||
                                 lpad(to_char(e_current_2hop_time(ind) - b_current_2hop_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_current_2hop(ind) - b_current_2hop(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc((e_current_2hop_time(ind) - b_current_2hop_time(ind)) / (e_current_2hop(ind) - b_current_2hop(ind)) / 1000,2)
                                              END),11) || '|' ||
                                 lpad(to_char(e_current_3hop(ind) - b_current_3hop(ind)), 11) || '|' ||
                                 lpad(to_char(e_current_3hop_time(ind) - b_current_3hop_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_current_3hop(ind) - b_current_3hop(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc((e_current_3hop_time(ind) - b_current_3hop_time(ind)) / (e_current_3hop(ind) - b_current_3hop(ind)) / 1000,2)
                                              END),11) || '|');
        END IF;
    END LOOP;
    dbms_output.put_line('+----------------------------------------------------------------------------------------------------------------------------------+');
    dbms_output.put_line(' ');
    dbms_output.put_line('+----------------------+-----------+-----------+-----------+-----------+-----------+-----------+');
    dbms_output.put_line('| Inst->Inst class     | CRbsy     | CRbsy tm  | CRbsy %   | CRcongest | CRcngst tm| CRcng %   |');
    dbms_output.put_line('|----------------------+-----------+-----------+-----------+-----------+-----------+-----------+');
    FOR i IN key_table.first .. key_table.last LOOP
        ind := key_table(i);
        IF (e_cr_block(ind) - b_cr_block(ind) > 0) THEN
            dbms_output.put_line('| '||rpad(e_instance(ind) || '->' || e_inst_id(ind) || '' || e_class(ind),21) || '|' || 
                                 lpad(to_char(e_cr_busy(ind) - b_cr_busy(ind)), 11) || '|' ||
                                 lpad(to_char(e_cr_busy_time(ind) - b_cr_busy_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_cr_block_time(ind) - b_cr_block_time(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc(100 * (e_cr_busy_time(ind) - b_cr_busy_time(ind)) / (e_cr_block_time(ind) - b_cr_block_time(ind)), 2)
                                              END),11) || '|' || 
                                 lpad(to_char(e_cr_congested(ind) - b_cr_congested(ind)), 11) || '|' ||
                                 lpad(to_char(e_cr_congested_time(ind) - b_cr_congested_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_cr_block_time(ind) - b_cr_block_time(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc(100 * (e_cr_congested_time(ind) - b_cr_congested_time(ind)) / (e_cr_block_time(ind) - b_cr_block_time(ind)),2)
                                              END),11) || '|');
        END IF;
    END LOOP;
    dbms_output.put_line('+----------------------+-----------+-----------+-----------+-----------+-----------+-----------+');
    dbms_output.put_line(' ');
    dbms_output.put_line('+----------------------------------------------------------------------------------------------+');
    dbms_output.put_line('| Inst->Inst class     | CURbsy    | CURbsy tm | CURbsy %  | CURcongest|CURcngst tm| CURcng %  |');
    dbms_output.put_line('+----------------------+-----------+-----------+-----------+-----------+-----------+-----------+');
    FOR i IN key_table.first .. key_table.last LOOP
        ind := key_table(i);
        IF (e_current_block(ind) - b_current_block(ind) > 0) THEN
            dbms_output.put_line('| '||rpad(e_instance(ind) || '->' || e_inst_id(ind) || '' || e_class(ind),21) || '|' || 
                                 lpad(to_char(e_current_busy(ind) - b_current_busy(ind)), 11) || '|' ||
                                 lpad(to_char(e_current_busy_time(ind) - b_current_busy_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_current_block_time(ind) - b_current_block_time(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc(100 * (e_current_busy_time(ind) - b_current_busy_time(ind)) /
                                                         (e_current_block_time(ind) - b_current_block_time(ind)),2)
                                              END),11) || '|' ||
                                 lpad(to_char(e_current_congested(ind) - b_current_congested(ind)), 11) || '|' ||
                                 lpad(to_char(e_current_congested_time(ind) - b_current_congested_time(ind)), 11) || '|' ||
                                 lpad(to_char(CASE
                                                  WHEN e_current_block_time(ind) - b_current_block_time(ind) = 0 THEN
                                                   0
                                                  ELSE
                                                   trunc(100 * (e_current_congested_time(ind) - b_current_congested_time(ind)) /
                                                         (e_current_block_time(ind) - b_current_block_time(ind)),2)
                                              END),11) || '|');
        END IF;
    END LOOP;
    dbms_output.put_line('|----------------------------------------------------------------------------------------------+');
END;
/
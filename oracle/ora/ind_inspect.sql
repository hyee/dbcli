CREATE TABLE index_log (
 owner          VARCHAR2(30),
 index_name     VARCHAR2(30),
 last_inspected DATE,
 leaf_blocks    NUMBER,    
 target_size    NUMBER,
 idx_layout     CLOB);

ALTER TABLE index_log ADD CONSTRAINT pk_index_log PRIMARY KEY (owner,index_name);

CREATE TABLE index_hist (
 owner          VARCHAR2(30),
 index_name     VARCHAR2(30),
 inspected_date DATE,
 leaf_blocks    NUMBER,    
 target_size    NUMBER,
 idx_layout     VARCHAR2(4000));

ALTER TABLE index_hist ADD CONSTRAINT pk_index_hist PRIMARY KEY  (owner,index_name,inspected_date);

--
-- Variables:
--  vMinBlks: Specifies the minimum number of leaf blocks for scanning the index
--            Indexes below this number will not be scanned/reported on
--  vScaleFactor: The scaling factor, defines the threshold of the estimated leaf block count 
--                to be smaller than the supplied fraction of the current size. 
--  vTargetUse : Supplied percentage utilisation. For example 90% equates to the default pctfree 10 
--  vHistRet : Defines the number of records to keep in the INDEX_HIST table for each index entry
--

CREATE OR REPLACE PACKAGE index_util AUTHID CURRENT_USER IS
vMinBlks     CONSTANT POSITIVE := 1000;
vScaleFactor CONSTANT NUMBER := 0.6;
vTargetUse   CONSTANT POSITIVE := 90;  -- equates to pctfree 10  
vHistRet     CONSTANT POSITIVE := 10;  -- (#) records to keep in index_hist
 procedure inspect_schema (aSchemaName IN VARCHAR2);
 procedure inspect_index (aIndexOwner IN VARCHAR2, aIndexName IN VARCHAR2, aTableOwner IN VARCHAR2, aTableName IN VARCHAR2, aLeafBlocks IN NUMBER);
END index_util; 
/

CREATE OR REPLACE PACKAGE BODY index_util IS
procedure inspect_schema (aSchemaName IN VARCHAR2) IS
 begin
 FOR r IN (select table_owner, table_name, owner index_owner, index_name, leaf_blocks 
           from dba_indexes  
           where owner = upper(aSchemaname)
             and index_type in ('NORMAL','NORMAL/REV','FUNCTION-BASED NORMAL')
             and partitioned = 'NO'  
             and temporary = 'N'  
             and dropped = 'NO'  
             and status = 'VALID'  
             and last_analyzed is not null  
           order by owner, table_name, index_name) LOOP

   IF r.leaf_blocks > vMinBlks THEN
   inspect_index (r.index_owner, r.index_name, r.table_owner, r.table_name, r.leaf_blocks);
   END IF;
  END LOOP;
 commit;
end inspect_schema;
procedure inspect_index (aIndexOwner IN VARCHAR2, aIndexName IN VARCHAR2, aTableOwner IN VARCHAR2, aTableName IN VARCHAR2, aLeafBlocks IN NUMBER) IS
 vLeafEstimate number;  
 vBlockSize    number;
 vOverhead     number := 192; -- leaf block "lost" space in index_stats 
 vIdxObjID     number;
 vSqlStr       VARCHAR2(4000);
 vIndxLyt      CLOB;
 vCnt          number := 0;
  TYPE IdxRec IS RECORD (rows_per_block number, cnt_blocks number);
  TYPE IdxTab IS TABLE OF IdxRec;
  l_data IdxTab;
begin  
  select a.block_size into vBlockSize from dba_tablespaces a,dba_indexes b where b.index_name=aIndexName and b.owner=aIndexOwner and a.tablespacE_name=b.tablespace_name;
 select round (100 / vTargetUse *       -- assumed packing efficiency
              (ind.num_rows * (tab.rowid_length + ind.uniq_ind + 4) + sum((tc.avg_col_len) * (tab.num_rows) )  -- column data bytes  
              ) / (vBlockSize - vOverhead)  
              ) index_leaf_estimate  
   into vLeafEstimate  
 from (select  /*+ no_merge */ table_name, num_rows, decode(partitioned,'YES',10,6) rowid_length  
       from dba_tables
       where table_name  = aTableName  
         and owner       = aTableOwner) tab,  
      (select  /*+ no_merge */ index_name, index_type, num_rows, decode(uniqueness,'UNIQUE',0,1) uniq_ind  
       from dba_indexes  
       where table_owner = aTableOwner  
         and table_name  = aTableName  
         and owner       = aIndexOwner  
         and index_name  = aIndexName) ind,  
      (select  /*+ no_merge */ column_name  
       from dba_ind_columns  
       where table_owner = aTableOwner  
         and table_name  = aTableName 
         and index_owner = aIndexOwner   
         and index_name  = aIndexName) ic,  
      (select  /*+ no_merge */ column_name, avg_col_len  
       from dba_tab_cols  
       where owner = aTableOwner  
         and table_name  = aTableName) tc  
 where tc.column_name = ic.column_name  
 group by ind.num_rows, ind.uniq_ind, tab.rowid_length; 

 IF vLeafEstimate < vScaleFactor * aLeafBlocks THEN
  select object_id into vIdxObjID
  from dba_objects  
  where owner = aIndexOwner
    and object_name = aIndexName;
   vSqlStr := 'SELECT rows_per_block, count(*) blocks FROM (SELECT /*+ cursor_sharing_exact ' ||
             'dynamic_sampling(0) no_monitoring no_expand index_ffs(' || aTableName || 
             ',' || aIndexName || ') noparallel_index(' || aTableName || 
             ',' || aIndexName || ') */ sys_op_lbid(' || vIdxObjID || 
             ', ''L'', ' || aTableName || '.rowid) block_id, ' || 
             'COUNT(*) rows_per_block FROM ' || aTableOwner || '.' || aTableName || ' GROUP BY sys_op_lbid(' || 
             vIdxObjID || ', ''L'', ' || aTableName || '.rowid)) group by rows_per_block order by rows_per_block';
   execute immediate vSqlStr BULK COLLECT INTO l_data;
  vIndxLyt := '';

   FOR i IN l_data.FIRST..l_data.LAST LOOP
    vIndxLyt := vIndxLyt || l_data(i).rows_per_block || ' - ' || l_data(i).cnt_blocks || chr(10);
   END LOOP;

   select count(*) into vCnt from index_log where owner = aIndexOwner and index_name = aIndexName;

   IF vCnt = 0   
    THEN insert into index_log values (aIndexOwner, aIndexName, sysdate, aLeafBlocks, round(vLeafEstimate,2), vIndxLyt);
    ELSE vCnt := 0;

         select count(*) into vCnt from index_hist where owner = aIndexOwner and index_name = aIndexName;

         IF vCnt >= vHistRet THEN
           delete from index_hist
           where owner = aIndexOwner 
             and index_name = aIndexName 
             and inspected_date = (select MIN(inspected_date) 
                                   from index_hist
                                   where owner = aIndexOwner 
                                     and index_name = aIndexName);
         END IF;

          insert into index_hist select * from index_log where owner = aIndexOwner and index_name = aIndexName;

         update index_log  
         set last_inspected = sysdate,
             leaf_blocks = aLeafBlocks, 
             target_size = round(vLeafEstimate,2),
             idx_layout = vIndxLyt
        where owner = aIndexOwner and index_name = aIndexName;

   END IF;
  END IF;
 END inspect_index;
END index_util;
/
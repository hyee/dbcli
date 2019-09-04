/*[[
	Find matched tables/views/procedures whose columns/parameters+source match the specific keyword. Usage: @@NAME <keyword>
	
	Example:
	========
	SQL> @@NAME bucket%X$
    OWNER    OBJECT_NAME        COLUMN_NAME      DATA_TYPE SOURCE
    ----- ----------------- -------------------- --------- -------
    SYS   X$KDKVIMHASHINDEX BITS_FOR_BUCKETINDEX NUMBER(2) x$kqfco
    SYS   X$KDKVIMHASHINDEX BUCKETS_PER_SEGMENT  NUMBER(4) x$kqfco
    SYS   X$KDKVIMHASHINDEX HASHBUCKETS          NUMBER(4) x$kqfco
    SYS   X$KDKVIMHASHINDEX HASHBUCKETSLOTS      NUMBER(4) x$kqfco
    SYS   X$KDKVIMHASHINDEX HASHBUCKETSLOT_SIZE  NUMBER(1) x$kqfco
    SYS   X$KDKVIMHASHINDEX HASHBUCKET_SIZE      NUMBER(1) x$kqfco
    SYS   X$KDKVIMHASHINDEX MASK_FOR_BUCKETINDEX NUMBER(8) x$kqfco
    SYS   X$KDKVIMHASHINDEX SLOTS_PER_BUCKET     NUMBER(4) x$kqfco
    SYS   X$KFCCE           BUCKET               NUMBER(4) x$kqfco
    SYS   X$KFCCE           FX_BUCKET            NUMBER(4) x$kqfco
    SYS   X$KFCLLE          BUCKET               NUMBER(4) x$kqfco
    SYS   X$KFCSGA          NUMBUCKETS           NUMBER(4) x$kqfco
    SYS   X$KJRTBCFP        BUCKETIDX            NUMBER(4) x$kqfco
    SYS   X$KKOCS_HISTOGRAM BUCKETID_KKOCS       NUMBER(1) x$kqfco
    SYS   X$KXTTSTECS       BUCKET_CNT_KXTTST_CS NUMBER(4) x$kqfco
    SYS   X$KXTTSTEHS       BUCKET_KXTTST_HS     NUMBER(4) x$kqfco
	--[[
		@ARGS: 1
		@check_user_dba: {
			SYSDBA={
			    UNION ALL
			    SELECT 'SYS',t.kqftanam TABLE_NAME, c.kqfconam COLUMN_NAME,
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
				               'UNKNOWN') || '(' || to_char(c.kqfcosiz) || ')' DATA_TYPE,'x$kqfco'
				FROM   x$kqfta t, x$kqfco c
				WHERE  c.kqfcotab = t.indx
				AND    c.inst_id = t.inst_id
				AND    upper(c.kqfconam||',x$kqfco') like upper('%&V1%')} default={}
		}
		@check_access_arg: DBA_ARGUMENTS={DBA_} default={ALL_}
	--]]
]]*/
set printsize 1000
SELECT a.OWNER, a.TABLE_NAME OBJECT_NAME, COLUMN_NAME, DATA_TYPE, '&check_access_arg.TAB_COLS' SOURCE
FROM   &check_access_arg.tab_cols a
WHERE  upper(COLUMN_NAME || ',&check_access_arg.TAB_COLS') LIKE upper('%&V1%')
UNION ALL
SELECT a.OWNER, TRIM('.' FROM PACKAGE_NAME || '.' || a.OBJECT_NAME), ARGUMENT_NAME, DATA_TYPE, '&check_access_arg.ARGUMENTS'
FROM   &check_access_arg.arguments a
WHERE  upper(ARGUMENT_NAME || ',&check_access_arg.ARGUMENTS') LIKE upper('%&V1%')
&check_user_dba
ORDER BY 1 DESC,2,3;
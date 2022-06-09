/*[[Show instance parameters, including hidden parameters, pls use 'set instance' to show the specific instance. Usage: @@NAME [<keyword1>[ <keyword2>...]] [-v] [-f"<filter>"]
   -v: show available values
   --[[
      @ctn: 12={decode(bitand(ksppiflg, 4), 4, 'FALSE', decode(bitand(ksppiflg / 65536, 3), 0, 'FALSE', 'TRUE')) PDB_MDF,}, default={}
      @def: 12={} default={--}
      @g11: 11={)))} default={)}
      @GV: 11.1={TABLE(GV$(CURSOR(} default={(}
      &df: {
        default={&def KSPPSTDFL default_value}
        v={(select listagg(decode(ISDEFAULT_KSPVLD_VALUES,'TRUE','*',' ')||VALUE_KSPVLD_VALUES,','||chr(10)) within group(order by ISDEFAULT_KSPVLD_VALUES desc) from sys.X$KSPVLD_VALUES o where NAME_KSPVLD_VALUES=ksppinm and o.inst_id=y.inst_id) avail_values}
      }
      &f1: default={ksppstdf='FALSE' or nvl(upper(ksppstdvl),' ')!=nvl(upper(sysval),' ')} f={1=1}
      &f2: default={1=1} f={}
      @con: 12={,con_id} default={}
   --]]
]]*/

SELECT * FROM &GV
        SELECT x.inst_id inst,ksppinm NAME, ksppity TYPE, 
               case when length(ksppstdvl)>80 then regexp_replace(ksppstdvl,', *',','||chr(10)) else ksppstdvl end SESS_VALUE, 
               decode(upper(ksppstdvl),upper(sysval),'<SAME>',case when length(sysval)>80 then regexp_replace(sysval,', *',','||chr(10))  else sysval end) SYS_VALUE,
               &df,
               &def decode(upper(KSPPSTVL),upper(KSPPSTDFL),'TRUE','FALSE') "DEFAULT",
               nvl2(z.flag,'TRUE','FALSE') OPT_ENV,
               decode(bitand(ksppiflg / 256, 1), 1, 'TRUE', 'FALSE') SES_Mdf,
               decode(bitand(ksppiflg / 65536, 3), 1, 'IMMEDIATE', 2, 'DEFERRED', 3, 'IMMEDIATE', 'FALSE') SYS_MDF,
               decode(bitand(ksppiflg, 4),4,'FALSE',decode(bitand(ksppiflg / 65536, 3), 0, 'FALSE', 'TRUE')) INST_MDF,
               &ctn
               decode(bitand(ksppiflg, 7),1,'TRUE',2,'ADJUSTED',4,'SYSTEM','FALSE') MODIFIED,
               decode(bitand(ksppstvf, 2), 2, 'TRUE', 'FALSE') "DEPRECATED",ksppdesc DESCRIPTION
        FROM   sys.x$ksppcv y 
        JOIN   sys.x$ksppi x USING(indx)
        JOIN   (select indx,ksppstdvl sysval,row_number() over(partition by indx order by indx &con) seq_ from sys.x$ksppsv) s USING(indx)
        LEFT   JOIN (select PNAME_QKSCESYROW ksppinm, 1 flag &con FROM sys.X$QKSCESYS) z USING(ksppinm)
        WHERE  seq_=1 
        AND   ((:V1 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V1||'%') escape '\' or
                :V2 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V2||'%') or
                :V3 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V3||'%') or
                :V4 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V4||'%') or
                :V5 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V5||'%'))
            OR (:V1 is null and (&f1)))
&g11
where inst=nvl('&instance',userenv('instance'))
and   (&f2)
ORDER BY 1,NAME;
/*[[Show instance parameters, including hidden parameters, pls use 'set instance' to show the specific instance. Usage: @@NAME [<keyword1>[,<keyword2>...]] [-v]
   -v: show available values
   --[[
      @ctn: 12={decode(bitand(ksppiflg, 4), 4, 'FALSE', decode(bitand(ksppiflg / 65536, 3), 0, 'FALSE', 'TRUE')) ISPDB_MDF,}, default={}
      @def: 12={} default={--}
      @g11: 11={)))} default={)}
      @GV: 11.1={TABLE(GV$(CURSOR(} default={(}
      &df: {
        default={&def KSPPSTDFL default_value}
        v={(select listagg(decode(ISDEFAULT_KSPVLD_VALUES,'TRUE','*',' ')||VALUE_KSPVLD_VALUES,','||chr(10)) within group(order by ISDEFAULT_KSPVLD_VALUES desc) from X$KSPVLD_VALUES o where NAME_KSPVLD_VALUES=ksppinm and o.inst_id=y.inst_id) avail_values}
      }
      &f1: default={ksppstdf='FALSE' or nvl(upper(ksppstdvl),' ')!=nvl(upper(sysval),' ')} f={1=1}
      &f2: default={1=1} f={}
   --]]
]]*/

SELECT * FROM &GV
        SELECT x.inst_id,ksppinm NAME, ksppity TYPE, 
               case when length(ksppstdvl)>80 then regexp_replace(ksppstdvl,', *',','||chr(10)) else ksppstdvl end SESS_VALUE, 
               decode(upper(ksppstdvl),upper(sysval),'<SAME>',case when length(sysval)>80 then regexp_replace(sysval,', *',','||chr(10))  else sysval end) SYS_VALUE,
               &df,
               &def decode(upper(KSPPSTVL),upper(KSPPSTDFL),'TRUE','FALSE') ISDEFAULT,
               nvl2(z.PNAME_QKSCESYROW,'TRUE','FALSE') ISOPT_ENV,
               decode(bitand(ksppiflg / 256, 1), 1, 'TRUE', 'FALSE') ISSES_Mdf,
               decode(bitand(ksppiflg / 65536, 3), 1, 'IMMEDIATE', 2, 'DEFERRED', 3, 'IMMEDIATE', 'FALSE') ISSYS_MDF,
               decode(bitand(ksppiflg, 4),4,'FALSE',decode(bitand(ksppiflg / 65536, 3), 0, 'FALSE', 'TRUE')) ISINST_MDF,
               &ctn
               decode(bitand(ksppstvf, 2), 2, 'TRUE', 'FALSE') ISDEPRECATED,ksppdesc DESCRIPTION
        FROM   x$ksppcv y,x$ksppi x, (select indx,ksppstdvl sysval from x$ksppsv) s,X$QKSCESYS z
        WHERE  (x.indx = y.indx and x.indx = s.indx) 
        AND    x.ksppinm=z.PNAME_QKSCESYROW(+)
        AND   ((:V1 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V1||'%') or
                :V2 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V2||'%') or
                :V3 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V3||'%') or
                :V4 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V4||'%') or
                :V5 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V5||'%'))
            OR (:V1 is null and (&f1)))
&g11
where inst_id=nvl('&instance',userenv('instance'))
and   (&f2)
ORDER BY 1,NAME;
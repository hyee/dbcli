/*[[Show instance parameters, including hidden parameters, pls use 'set instance' to show the specific instance. Usage: @@NAME [<keyword1>[,<keyword2>...]] [-v]
   -v: show available values
   --[[
      @ctn: 12={decode(bitand(ksppiflg, 4), 4, 'FALSE', decode(bitand(ksppiflg / 65536, 3), 0, 'FALSE', 'TRUE')) ISPDB_MDF,}, default={}
      @def: 12={} default={--}
      @g11: 11={} default={--}
      &df: {
        default={KSPPSTDFL default_value}
        v={(select listagg(decode(ISDEFAULT_KSPVLD_VALUES,'TRUE','*',' ')||VALUE_KSPVLD_VALUES,','||chr(10)) within group(order by ISDEFAULT_KSPVLD_VALUES desc) from X$KSPVLD_VALUES o
           where NAME_KSPVLD_VALUES=ksppinm and o.inst_id=y.inst_id) avail_values}
      }
   --]]
]]*/

&g11 SELECT * FROM TABLE(GV$(CURSOR(
        SELECT x.inst_id,ksppinm NAME, ksppity TYPE, substr(ksppstdvl,1,200) DISPLAY_VALUE, 
               &def &df,
               &def decode(upper(KSPPSTVL),upper(KSPPSTDFL),'TRUE','FALSE') ISDEFAULT,
               decode(bitand(ksppiflg / 256, 1), 1, 'TRUE', 'FALSE') ISSES_Mdf,
               decode(bitand(ksppiflg / 65536, 3), 1, 'IMMEDIATE', 2, 'DEFERRED', 3, 'IMMEDIATE', 'FALSE') ISSYS_MDF,
               decode(bitand(ksppiflg, 4),4,'FALSE',decode(bitand(ksppiflg / 65536, 3), 0, 'FALSE', 'TRUE')) ISINST_MDF,
               &ctn
               decode(bitand(ksppstvf, 2), 2, 'TRUE', 'FALSE') ISDEPRECATED,ksppdesc DESCRIPTION
        FROM   x$ksppi x, x$ksppcv y
        WHERE  (x.indx = y.indx) 
        AND   ((:V1 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V1||'%') or
                :V2 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V2||'%') or
                :V3 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V3||'%') or
                :V4 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V4||'%') or
                :V5 is not null and lower(ksppinm||' '||ksppdesc) LIKE LOWER('%'||:V5||'%'))
            OR (:V1 is null and ksppstdf='FALSE') 
           &def and  decode(upper(KSPPSTVL),upper(KSPPSTDFL),'TRUE','FALSE')='FALSE'
          )
&g11 ))) where inst_id=nvl('&instance',userenv('instance')) ORDER BY 1,NAME;
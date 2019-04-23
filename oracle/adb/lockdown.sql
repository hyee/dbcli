/*[[Show lockdown profile in current PDB. Usage: @@NAME [<keyword>] ]]*/

select * 
from v$lockdown_rules
where :V1 is null or lower(rule_type||','||RULE||','||clause||','||CLAUSE_OPTION||','||STATUS) like lower('%&v1%')
order by 1,2,3,4,5;
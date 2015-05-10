SPO &&edb360_main_report..html APP;
@@edb360_0e_html_footer.sql
SPO OFF;

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- turing trace off
ALTER SESSION SET SQL_TRACE = FALSE;
@@&&edb360_0g.tkprof.sql

PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- readme
SPO 00000_readme_first.txt
PRO 1. Unzip &&edb360_main_filename._&&edb360_file_time..zip into a directory
PRO 2. Review &&edb360_main_report..html
SPO OFF;

-- cleanup
SET HEA ON; 
SET LIN 80; 
SET NEWP 1; 
SET PAGES 14; 
SET LONG 80; 
SET LONGC 80; 
SET WRA ON; 
SET TRIMS OFF; 
SET TRIM OFF; 
SET TI OFF; 
SET TIMI OFF; 
SET ARRAY 15; 
SET NUM 10; 
SET NUMF ""; 
SET SQLBL OFF; 
SET BLO ON; 
SET RECSEP WR;
UNDEF 1

-- alert log (3 methods)
COL db_name_upper NEW_V db_name_upper;
COL db_name_lower NEW_V db_name_lower;
COL background_dump_dest NEW_V background_dump_dest;
SELECT UPPER(SYS_CONTEXT('USERENV', 'DB_NAME')) db_name_upper FROM DUAL;
SELECT LOWER(SYS_CONTEXT('USERENV', 'DB_NAME')) db_name_lower FROM DUAL;
SELECT value background_dump_dest FROM v$parameter WHERE name = 'background_dump_dest';
HOS cp &&background_dump_dest./alert_&&db_name_upper.*.log . >> &&edb360_log3..txt
HOS cp &&background_dump_dest./alert_&&db_name_lower.*.log . >> &&edb360_log3..txt
HOS cp &&background_dump_dest./alert_&&_connect_identifier..log . >> &&edb360_log3..txt
HOS rename alert_ 00006_&&common_edb360_prefix._alert_ alert_*.log >> &&edb360_log3..txt

-- zip 
HOS zip -m &&edb360_main_filename._&&edb360_file_time. &&common_edb360_prefix._query.sql >> &&edb360_log3..txt
HOS zip -d &&edb360_main_filename._&&edb360_file_time. &&common_edb360_prefix._query.sql >> &&edb360_log3..txt
HOS zip -m &&edb360_main_filename._&&edb360_file_time. 00006_&&common_edb360_prefix._alert_*.log >> &&edb360_log3..txt
HOS zip -j 00007_&&common_edb360_prefix._opatch $ORACLE_HOME/cfgtoollogs/opatch/opatch* >> &&edb360_log3..txt
HOS zip -m &&edb360_main_filename._&&edb360_file_time. 00007_&&common_edb360_prefix._opatch.zip >> &&edb360_log3..txt
HOS zip -m &&edb360_main_filename._&&edb360_file_time. &&edb360_log2..txt >> &&edb360_log3..txt
HOS zip -m &&edb360_main_filename._&&edb360_file_time. &&edb360_tkprof._sort.txt >> &&edb360_log3..txt
HOS zip -m &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt >> &&edb360_log3..txt
HOS zip -m &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html >> &&edb360_log3..txt
HOS zip -m &&edb360_main_filename._&&edb360_file_time. 00000_readme_first.txt >> &&edb360_log3..txt
HOS unzip -l &&edb360_main_filename._&&edb360_file_time. >> &&edb360_log3..txt
HOS zip -m &&edb360_main_filename._&&edb360_file_time. &&edb360_log3..txt
SET TERM ON;

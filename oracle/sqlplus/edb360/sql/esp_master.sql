----------------------------------------------------------------------------------------
--
-- File name:   esp_master.sql
--
-- Purpose:     Collect Database Requirements (CPU, Memory, Disk and IO Perf)
--
-- Author:      Carlos Sierra, Rodrigo Righetti
--
-- Version:     v1504 (2015/04/02)
--
-- Usage:       Collects Requirements from AWR and ASH views on databases with the 
--				Oracle Diagnostics Pack license, it also collect from Statspack starting
--				9i databases up to 12c. 				 
--				 
--              The output of this script can be used to feed a Sizing and Provisioning
--              application.
--
-- Example:     # cd esp_collect
--              # sqlplus / as sysdba
--              SQL> START sql/esp_master.sql
--
--  Notes:      Developed and tested on 12.1.0.2, 12.1.0.1, 11.2.0.4, 11.2.0.3, 
--				10.2.0.4, 9.2.0.8, 9.2.0.1
--             
---------------------------------------------------------------------------------------
--
SET TERM OFF ECHO OFF FEED OFF VER OFF HEA OFF PAGES 0 COLSEP ', ' LIN 32767 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 100 NUM 20 SQLBL ON BLO . RECSEP OFF;

DEF skip_awr = '';
COL skip_awr NEW_V skip_awr;

DEF skip_statspack = '';
COL skip_statspack NEW_V skip_statspack;

VARIABLE vskip_awr varchar2(2)
VARIABLE vskip_statspack varchar2(2)

-- IF AWR has snapshots for the last 2 hours use it and skip Statspack scripts
-- IF BOTH AWR AND SNAPSHOT HAVE NO DATA IN THE LAST 2 HOURS, IT WILL RUN BOTH.
BEGIN

	BEGIN
		EXECUTE IMMEDIATE 'SELECT ''--''  FROM DBA_HIST_SNAPSHOT WHERE begin_interval_time >= systimestamp-2/24 AND rownum < 2'
		INTO :vskip_statspack;
	EXCEPTION 
		WHEN OTHERS THEN 
 		NULL;
	END; 

	IF :vskip_statspack IS NULL THEN

	BEGIN
		EXECUTE IMMEDIATE 'SELECT ''--'' FROM perfstat.stats$snapshot WHERE snap_time >= sysdate-2/24 AND rownum < 2'
		INTO :vskip_awr ;
	EXCEPTION 
		WHEN OTHERS THEN 
 		NULL;
	END; 
	
	END IF;

END;
/

SELECT :vskip_statspack skip_statspack FROM dual;
SELECT :vskip_awr skip_awr FROM dual;

-- AWR collector
@@&&skip_awr.sql/esp_collect_requirements_awr.sql
@@&&skip_awr.sql/resources_requirements_awr.sql

-- STATSPACK collector
@@&&skip_statspack.sql/esp_collect_requirements_statspack.sql
@@&&skip_statspack.sql/resources_requirements_statspack.sql

SET TERM ON ECHO OFF FEED ON VER ON HEA ON PAGES 14 COLSEP ' ' LIN 80 TRIMS OFF TRIM ON TI OFF TIMI OFF ARRAY 15 NUM 10 SQLBL OFF BLO ON RECSEP WR;

EDB360 v1515 (2015-05-06) by Carlos Sierra

EDB360 is a "free to use" tool to perform an initial assessment of a remote system. 
It gives a glance of a database state. It also helps to document any findings.
EDB360 installs nothing. For better results execute connected as SYS or DBA.
It takes around one hour to execute. Output ZIP file can be large (several MBs), so
you may want to execute EDB360 from a system directory with at least 1 GB of free 
space. Best time to execute EDB360 is close to the end of a working day.

Steps
~~~~~
1. Unzip edb360.zip, navigate to the root edb360 directory, and connect as SYS, 
   DBA, or any User with Data Dictionary access:

   $ unzip edb360.zip
   $ cd edb360
   $ sqlplus / as sysdba

2. Execute edb360.sql indicating if your database is licensed for the Oracle Tuning Pack, 
   the Diagnostics Pack or None [ T | D | N ]. Example below specifies Tuning Pack.

   SQL> @edb360.sql T
   
3. Unzip output edb360_<dbname>_<host>_YYYYMMDD_HH24MI.zip into a directory on your PC

4. Review main html file 00001_edb360_<dbname>_index.html

****************************************************************************************

Notes
~~~~~
1. If you need to execute edb360 against all databases in host use then run_db360.sh:

   $ unzip edb360.zip
   $ cd edb360
   $ sh run_db360.sh

   note: this method requires Oracle Tuning pack license in all databases in such host.

2. If you need to execute only a portion of edb360 (i.e. a column, section or range) use 
   these commands. Notice hidden parameter _o_release can be set to one section (i.e. 3b),
   one column (i.e. 3), a range of sections (i.e. 5c-6b) or range of columns (i.e. 5-7):

   SQL> DEF _o_release = '3b';
   SQL> @edb360.sql T
   
   note: valid column range for hidden parameter _o_release is 1 to 7. 

3. If you need to generate edb360 for a range of dates other than last 31 days; or change
   default "working hours" between 7:30AM and 7:30PM; or suppress an output format such as
   text or csv; modify then file edb360_00_config.sql (back it up first).

****************************************************************************************

Troubleshooting
~~~~~~~~~~~~~~~
edb360 takes a few hours to execute on a large database. On smaller ones or on Exadata it
takes less than 1hr. In rare cases it may take 12 hours or even more. 
If you think edb360 takes too long on your database, the first suspect is usually the 
state of the CBO stats on Tables behind AWR. 
Troubleshooting steps below are for improving performance of edb360 based on known issues.

Steps:

1. Review files 00002_edb360_dbname_log.txt, 00003_edb360_dbname_log2.txt, 
   00004_edb360_dbname_log3.txt and 00005_edb360_dbname_tkprof_sort.txt. 
   First log shows the state of the statistics for AWR Tables. If stats are old then 
   gather them fresh with script edb360/sql/gather_stats_wr_sys.sql
   
2. If number of rows on WRH$_ACTIVE_SESSION_HISTORY as per 00002_edb360_dbname_log.txt is
   several millions, then you may not be purging data periodically. 
   There are some known bugs and some blog posts on this regard. 
   Execute query below to validate ASH age:

       SELECT TRUNC(sample_time, 'MM'), COUNT(*)
         FROM dba_hist_active_sess_history
        GROUP BY TRUNC(sample_time, 'MM')
        ORDER BY TRUNC(sample_time, 'MM')
       /

3. If edb360 version (first line on this readme) is older than 1 month, download and use
   latest version: https://github.com/carlos-sierra/edb360/archive/master.zip

4. Consider suppressing text and or csv reports. Each for an estimated gain of about 20%.
   Keep in mind that when suppressing reports, you start loosing some functionality. 
   To suppress lets say text and csv reports, place the following two commands at the end 
   of script edb360/sql/edb360_00_config.sql

       DEF edb360_conf_incl_text = 'N';
       DEF edb360_conf_incl_csv = 'N';

5. If after going through steps 1-4 above, edb360 still takes longer than a few hours, 
   feel free to email author carlos.sierra.usa@gmail.com and provide 4 files from step 1.

****************************************************************************************
   
    EDB360 - Enkitec's Oracle Database 360-degree View
    Copyright (C) 2014  Carlos Sierra

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

****************************************************************************************

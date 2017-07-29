![](https://github.com/dbsid/moats_rac/blob/master/moats_rac.gif)

# Mother Of All Tuning Scripts (MOATS) README

## Copyright Information
MOATS v1.06, April 2011
(c) Adrian Billington www.oracle-developer.net
(c) Tanel Poder       www.e2sn.com

MOATS v2.0.6, Jan 2015
(c) Sidney Chen www.dbsid.com

## Contents
1. Introduction
2. Supported Versions
3. Installation & Removal
  1. Prerequisites
    1. System Privileges
    2. Object Privileges
  2. Installation
  3. Removal
4. Usage
  1. SQL*Plus Setup
    1. Window Size
    2 .SQL*Plus Settings
  2. MOATS TOP Usage
    1. Using MOATS.TOP directly
    2. Using the TOP view
  3. Other MOATS APIs
5. Roadmap
6. Disclaimer
7. Acknowledgements

 
## 1.0 Introduction
MOATS is a simple tuning tool that samples active sessions and reports top database activity in regular screen refreshes at specified intervals (similar to the TOP utility for UNIX). MOATS is designed to run in sqlplus only and has recommended display settings to enable screen refreshes.

In V2.0, MOATS is extended as a RAC Dashbooard, it's now capable of monitoring the ASH and Activity Stats on all the instances. Just for fun, MOATS RAC can display the colourful Active Session Graph for both xterm and xterm-256color.

Examples of how this application might be used:
```
   -- To report top session and instance activity at 5 second intervals...
   -- The default window size is 40 * 175, the arraysize should be set to 80 = 40 * 2
   -- --------------------------------------------------------------------------------

   SQL> set arrays 80 lines 175 head off tab off pages 0

   SQL> SELECT * FROM TABLE(moats.top(5));


   -- Sample output...
   -- --------------------------------------------------------------------

+ Database: ORA12C   | Activity Statistics Per Second  | Interval: 5s    | Screen size = 40 * 175   | Ash Height = 13 | SQL Height = 8  | Arraysize should be 80   +--------+
|Inst|CPU: idle%--usr%--sys%|  Logons|   Execs|   Calls| Commits|  sParse|  hParse|  ccHits| LIOs(K)|   PhyRD|   PhyWR| READ MB|Write MB| Redo MB|Offload%| ExSI MB|ExFCHits|
|   1|      94.8   3.7   1.5|       2|       3|       9|       0|       2|       0|       1|       0|    1676|       1|      92|       0|       0|      .0|       0|    1676|
|   2|      96.2   3.3    .5|       2|       3|      10|       0|       2|       0|       1|       0|    1745|       1|      95|       0|       0|      .0|       0|    1744|
|   3|      96.3   3.2    .4|       2|       2|      10|       0|       2|       0|       0|       0|    1691|       1|      92|       0|       0|      .0|       0|    1692|
|   4|      95.8   3.7    .5|       2|       2|       9|       0|       2|       0|       0|       0|    1641|       1|      90|       0|       0|      .0|       0|    1641|
|   5|      95.0   4.4    .6|       2|       6|       9|       0|       2|       0|       4|       0|    1659|       1|      91|       0|       0|      .0|       0|    1659|
|   6|      96.5   3.1    .4|       2|       5|       9|       0|       2|       0|       3|       0|    1710|       2|      93|       0|       0|      .0|       0|    1709|
|   7|      95.1   4.0    .9|       2|       5|       9|       0|       2|       0|       3|       0|    1710|       1|      93|       0|       0|      .0|       0|    1710|
|   8|      96.2   3.3    .5|       2|       5|       9|       0|       2|       0|       3|       0|    1689|       1|      92|       0|       0|      .0|       0|    1688|
+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
                      Total :      14;      32;      74;       0;      16;       0;      16;       0;   13520;       9;     738;       0;       0;        ;       0;   13519;
                                                                       _______                                Active Session Graph                                    _______
+   AAS| TOP|Instance| Top Events------------------+ WAIT CLASS -+        18 | CPU:+  IO:*  Others:@                                                                  | 18
|   1.8| 11%| inst(4)| ON CPU                      | ON CPU      |        17 |                                                                                * **    | 17
|   1.4|  9%| inst(3)| ON CPU                      | ON CPU      |        16 |                                                                             *+++****** | 16
|   1.4|  9%| inst(8)| ON CPU                      | ON CPU      |        14 |                                                                             *++++++*** | 14
|   1.2|  8%| inst(6)| ON CPU                      | ON CPU      |        13 |                                                                             ++++++++** | 13
|   1.2|  8%| inst(5)| ON CPU                      | ON CPU      |        12 |                                                                             ++++++++** | 12
|   1.2|  8%| inst(2)| ON CPU                      | ON CPU      |        10 |                                                                             ++++++++++ | 10
|   1.0|  6%| inst(7)| direct path read temp       | User I/O    |         9 |                                                                             ++++++++++ | 9
|   1.0|  6%| inst(1)| ON CPU                      | ON CPU      |         8 |                                                                             ++++++++++ | 8
|   1.0|  6%| inst(7)| ON CPU                      | ON CPU      |         7 |                                                                             ++++++++++ | 7
|   1.0|  6%| inst(1)| direct path read temp       | User I/O    |         5 |                                                                             ++++++++++ | 5
|   0.8|  5%| inst(2)| direct path read temp       | User I/O    |         4 |                                                  *                          ++++++++++ | 4
|   0.8|  5%| inst(6)| direct path read temp       | User I/O    |         3 |                                                 ++++++ + +++++++++      +  *++++++++++ | 3
|   0.8|  5%| inst(5)| direct path read temp       | User I/O    |         1 |                                                 +++++++++++++++++++     +  *++++++++++ | 1
+----------------------------------------------------------------+         0 +----------------------------------------------------------------------------------------+ 0
                                                                               ^ 06:25:45                       06:29:20 ^                                 06:32:55 ^
+   AAS| TOP| SQL_ID -------+ 1st TOP Event(%) ------------------+ 2nd TOP Event(%) ------------------+ Inst_Cnt + TOP SESSIONS (sid@inst_id) ------------------------------+
|  16.0|100%| 539d8b7druy5x | ON CPU (64%)                       | direct path read temp (36%)        |        8 | 800@7,895@1,233@4,238@4,664@5,699@3,728@5,729@6          |
+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
+ TOP SQL_ID ----+ PLAN_HASH_VALUE + SQL TEXT ------------------------------------------------------------------------------------------------------------------------------+
| 539d8b7druy5x  | 1547908977      | select /*+ parallel(16)*/ count(*) from t, t                                                                                           |
+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
```
   
## 2.0 Supported Versions
MOATS V2.0 supports all Oracle versions of 11g Release 1 and above. 


## 3.0 Installation & Removal
MOATS requires several database objects to be created. The privileges, installation and removal steps are described below.

### 3.1 Prerequisites
It is recommended that this application is installed in a "TOOLS" schema, but whichever schema is used requires the following privileges. Note that any or all of these grants can be assigned to either the MOATS target schema itself or a role that is granted to the MOATS target schema.

#### 3.1.1 System Privileges
-----------------------   
```
   * CREATE TYPE
   * CREATE TABLE
   * CREATE VIEW
   * CREATE PROCEDURE
```

#### 3.1.2 Object Privileges
-----------------------
```
   * EXECUTE ON DBMS_LOCK
   * SELECT ON V_$DATABASE    ***
   * SELECT ON GV_$SESSION    ***
   * SELECT ON GV_$STATNAME   ***
   * SELECT ON GV_$SYSSTAT    ***
   * SELECT ON GV_$OSSTAT     ***
   * SELECT ON GV_$LATCH      ***
   * SELECT ON GV_$TIMER      ***
   * SELECT ON GV_$SQL        ***
```

  *** Note: 
  1. SELECT ANY DICTIONARY can be granted in place of the specific V$ view grants above
  2. Supplied scripts will grant/revoke all of the above to/from the MOATS target schema/role.

### 3.2 Installation
----------------
MOATS can be installed using sqlplus or any tools that fully support sqlplus commands. To install MOATS:

1. Ensure that the MOATS owner schema has the required privileges described in Section 3.1 above. A script named moats_privs_grant.sql is supplied if required (this will need to be run as a user with admin grant rights on SYS objects. This script will prompt for the name of the target MOATS schema).

2. To install MOATS, login as the target schema and run the moats_install.sql script. A warning will prompt for a continue/cancel option.

### 3.3 Removal
-----------
To remove MOATS, login as the MOATS owner schema and run the moats_remove.sql script. A warning will prompt for a continue/cancel option.

To revoke all related privileges from the MOATS owner schema, a script named moats_privs_revoke.sql is supplied if required (this will need to be run as a user with admin grant rights on SYS objects. This script will prompt for the name of the target MOATS schema).

## 4.0 Usage
MOATS is simple to use. It is designed for sqlplus only and makes use of sqlplus and PL/SQL functionality to provide real-time screen refreshes. To make the most of MOATS v2.0, follow the steps below.

### 4.1 SQL*Plus Setup
------------------
MOATS TOP output is of a fixed size so needs some specific settings.

#### 4.1.1 Window Size
-----------------------
By default, the window size is 40 * 175, the ASH height is 13, The sql height is 8. You can customize the Windows size by the arguments p_screen_size, p_ash_height and p_sql_height, when invoking the moats.top functio to start the monitoring. 
```
   function top (
            p_refresh_rate    in integer default null,
            p_screen_size     in integer default null,
            p_ash_height      in integer default null,
            p_sql_height      in integer default null,
            p_ash_window_size in integer default null
            ) return moats_output_ntt pipelined;
```

#### 4.1.2 SQL*Plus Settings
-----------------------
Although the number of charaters on each line is no more than 175, the linesize setting should be at least 2000, since the output contains lots of invisible charaters to draw the color active session graph. The arraysize should be exactly double of the screen size, by default, the screen size is 40, arraysize is 80. If you customize the screen size to 60, then the arraysize should be set to 120.
MOATS comes with a moats_settings.sql file that does the following: 
```
   * set arrays 80
   * set lines 2000
   * set trims on
   * set head off
   * set tab off
   * set pages 0
   * set serveroutput on format wrapped
```

These are default sqlplus settings for the MOATS TOP utility and need to be set before running it (see Usage below).

### 4.2 MOATS TOP Usage
-------------------
MOATS.TOP is a pipelined function that outputs instance performance statistics at a given refresh interval. Before running TOP, the moats_settings.sql script (or equivalent) should be run in the sqlplus session, or you can call q.sql directly. The following example refreshes the instance statistics at the default 10 seconds:

#### 4.2.1 Using MOATS.TOP directly
------------------------------
```
   +-------------------------------------+
   | SQL> @q                             |
   +-------------------------------------+
```

```
   +-------------------------------------+
   | SQL> @moats_settings.sql            |
   |                                     |
   | SQL> SELECT *                       |
   |  2   FROM   TABLE(moats.top);       |
   +-------------------------------------+
```

To use a non-default refresh rate, supply it as follows:

```
   +-------------------------------------+
   | SQL> SELECT *                       |
   |  2   FROM   TABLE(moats.top(5));    |
   +-------------------------------------+
```

To display with a bigger screen size, make sure the arraysize is set to double fo screen size=120.
```
   +----------------------------------------------------+
   | SQL> set arraysize 120                             |
   | SQL> SELECT *                                      |
   |  2   FROM   TABLE(moats.top(p_screen_size->60));   |
   +----------------------------------------------------+
```

To display with a bigger screen size, with customized ash height and sql height, make sure the arraysize is set to double fo screen size.
```
   +----------------------------------------------------+
   | SQL> set arraysize 120                             |
   | SQL> SELECT *                                      |
   |  2   FROM   TABLE(moats.top( p_screen_size->60,    |
   |                              p_ash_height=>20,     |
   |                              p_sql_height=>15));   |
   +----------------------------------------------------+
```

To use a non-default screen size

To stop MOATS.TOP refreshes, use a Ctrl-C interrupt.

#### 4.2.2 Using the TOP view
------------------------
A view named TOP is included with MOATS for convenience.
```
   +-------------------------------------+
   | SQL> @moats_settings.sql            |
   |                                     |
   | SQL> SELECT * FROM top;             |
   +-------------------------------------+
```
To set a non-default value for refresh rate, set the MOATS refresh rate parameter, as follows.
```
   +--------------------------------------------------------------+
   | SQL> @moats_settings.sql                                     |
   |                                                              |
   | SQL> exec moats.set_parameter(moats.gc_top_refresh_rate, 3); |
   |                                                              |
   | SQL> SELECT * FROM top;                                      |
   +--------------------------------------------------------------+
```
This example uses a 3 second refresh rate.

### 4.3 Other MOATS APIs
--------------------
MOATS contains several other public APIs that are currently for internal use only. These will be fully described and "released" with future MOATS versions but are currently only supported for use by MOATS.TOP. They include pipelined functions to query the active session data that MOATS gathers. 

## 5.0 Roadmap
===========
There is no fixed roadmap at the time of writing. Features that Tanel and Adrian would like to add (but are not limited to) the following:

   * formally expose the active session query functions for custom-reporting
   * add drill-down functionality for SQL statements of interest in the TOP output

## 6.0 Disclaimer
==============
This software is supplied in good faith and is free for download, but any subsequent use is entirely at the end-users' risk. Adrian Billington(www.oracle-developer.net), Tanel Poder(www.e2sn.com), Sidney Chen(www.dbsid.com) do not accept any responsibility for problems arising as a result of using MOATS. All users are strongly advised to read the installation and removal scripts prior to running them and test the application in an appropriate environment.

## 7.0 Acknowledgements
====================
Many thanks to Randolf Geist for his contributions to MOATS, including several bug-fixes to the original alpha version.

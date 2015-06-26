-- sqld360 configuration file. for those cases where you must change sqld360 functionality

/*************************** ok to modify (if really needed) ****************************/

-- history days (default 31)
DEF sqld360_conf_days = '31';

/**************************** not recommended to modify *********************************/

-- excluding report types reduce usability while providing marginal performance gain
DEF sqld360_conf_incl_html = 'Y';
DEF sqld360_conf_incl_text = 'Y';
DEF sqld360_conf_incl_csv  = 'Y';
DEF sqld360_conf_incl_line = 'Y';
DEF sqld360_conf_incl_pie  = 'Y';
DEF sqld360_conf_incl_bar  = 'Y';
DEF sqld360_conf_incl_tree = 'Y';

-- include/exclude SQL Monitor reports
DEF sqld360_conf_incl_sqlmon = 'Y';

-- include/exclude DBA_HIST_ASH (always on by default, turned off only by eDB180) 
DEF sqld360_conf_incl_ash_hist = 'Y';

-- include/exclude ASH SQL Reports (always off by default, very expensive and little benefit) 
DEF sqld360_conf_incl_ashrpt = 'N';

-- include/exclude eAdam (only for standalone execs, always skipped for eDB360 execs) 
DEF sqld360_conf_incl_eadam = 'Y';

-- include/exclude raw ASH data sample (only for standalone execs, always skipped for eDB360 execs) 
DEF sqld360_conf_incl_rawash = 'Y';

-- include/exclude stats history (always on by default, turned off only by eDB180) 
DEF sqld360_conf_incl_stats_h = 'Y';

-- include/exclude Testcase Builder (only for standalone execs, always skipped for eDB360 execs) 
DEF sqld360_conf_incl_tcb = 'Y';

-- include/exclude translate min/max/histograms endpoint values
DEF sqld360_conf_translate_lowhigh = 'Y';

-- number of partitions to consider for column stats gathering (first 100, last 100)
DEF sqld360_conf_first_part = '100';
DEF sqld360_conf_last_part = '100';

/**************************** enter your modifications here *****************************/

--DEF sqld360_conf_incl_text = 'N';
--DEF sqld360_conf_incl_csv = 'N';


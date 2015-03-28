-- tkprof for trace from execution of tool in case someone reports slow performance in tool
HOS tkprof &&edb360_udump_path.*ora_&&edb360_spid._&&edb360_tracefile_identifier..trc &&edb360_tkprof._sort.txt sort=prsela exeela fchela
HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_tkprof._sort.txt

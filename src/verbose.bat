SET OTHER_LIB=; -verbose:class -XX:-TraceClassUnloading  -Xshare:off
"%~dp0\..\dbcli.bat"|tee ..\cache\verbose.log
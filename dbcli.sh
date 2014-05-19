
cd $(dirname "$0")
export JRE_HOME="/C/Program Files (x86)/Java/jdk7/jre/bin;"
export TNS_ADM="/C/Oracle/product/11.2.0/client_1/network/admin"

export PATH=$JRE_HOME:$PATH
java -Xmx64M -cp ./lib/.:./lib/jnlua-0.9.6.jar \
               -Djava.library.path=./lib/ \
               -Doracle.net.tns_admin="$TNS_ADM" \
               Loader ^
               $*

package org.dbcli;

//copy from ojdbc8:oracle.net.resolver.EZConnectResolver

import java.util.*;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class OracleEZConnectResolver {
    private static final String DESCRIPTION_FORMAT = "(DESCRIPTION=%s%s%s%s)";
    private static final String ADDRESS_LIST_FORMAT = "(ADDRESS_LIST=(LOAD_BALANCE=%s)%s)";
    private static final String ADDRESS_FORMAT = "(ADDRESS=(PROTOCOL=%s)(HOST=%s)(PORT=%s)%s)";
    private static final String HTTPS_PROXY_FORMAT = "(HTTPS_PROXY=%s)";
    private static final String HTTPS_PROXY_PORT_FORMAT = "(HTTPS_PROXY_PORT=%s)";
    private static final String CONNECT_DATA_FORMAT = "(CONNECT_DATA=%s%s%s)";
    private static final String SERVICE_NAME_FORMAT = "(SERVICE_NAME=%s)";
    private static final String SERVER_MODE_FORMAT = "(SERVER=%s)";
    private static final String INSTANCE_NAME_FORMAT = "(INSTANCE_NAME=%s)";
    private static final String SECURITY_FORMAT = "(SECURITY=(SSL_SERVER_DN_MATCH=%s)%s%s)";
    private static final String SERVER_DN_FORMAT = "(SSL_SERVER_CERT_DN=%s)";
    private static final String MY_WALLET_DIR_FORMAT = "(MY_WALLET_DIRECTORY=%s)";
    private static final String EMPTY_STRING = "";
    private static final String KEY_VALUE_FORMAT = "(%s=%s)";
    private static final Pattern HOST_INFO_PATTERN = Pattern.compile("(?<hostnames>([A-z0-9][A-z0-9._-]+,?)+)(:(?<port>\\d+))?");
    private static final Pattern EZ_URL_PATTERN;
    private static final String EXT_TNS_ADMIN_KEYWORD = "TNS_ADMIN";
    private static final char EXT_DOUBLE_QT = '"';
    private static final char EXT_KEY_VAL_SEP = '=';
    private static final char EXT_PARAM_SEP = '&';
    private static final char EXT_ESCAPE_CHAR = '\\';
    private static final Map<String, String> URL_PROPS_ALIAS;
    private static final Map<String, String> CONNECTION_PROPS_ALIAS;
    private static final List<String> DESCRIPTION_PARAMS;
    private final String url;
    private String resolvedUrl;
    private final Properties connectionProps = new Properties();
    private final Properties urlProps = new Properties();
    private final String urlPrefix;

    String service;
    String protocol;
    String instance;
    String hosts;
    String serverMode;
    int port;


    private OracleEZConnectResolver(String var1) {
        int var2 = var1.indexOf(64);
        if (var2 != -1) {
            this.url = var1.substring(var2 + 1);
            this.urlPrefix = var1.substring(0, var2 + 1);
        } else {
            this.url = var1;
            this.urlPrefix = "";
        }

        this.parse();
    }

    public static OracleEZConnectResolver newInstance(String var0) {
        return new OracleEZConnectResolver(var0);
    }

    public String getResolvedUrl() {
        return this.resolvedUrl;
    }

    public Properties getProperties() {
        return this.connectionProps;
    }

    private void parse() {
        String var1 = this.parseExtendedSettings(this.url);
        if (this.connectionProps.isEmpty() && this.urlProps.isEmpty()) {
            var1 = this.url;
        }

        if (var1.startsWith("(")) {
            this.resolvedUrl = this.urlPrefix + var1;
        } else {
            this.resolvedUrl = this.urlPrefix + this.resolveToLongURLFormat(var1);
        }

    }

    private String resolveToLongURLFormat(String var1) {
        String var2 = var1.replaceAll("\\s+", "");
        Matcher var3 = EZ_URL_PATTERN.matcher(var2);
        if (!var3.matches()) {
            return var1;
        } else {
            protocol = var3.group("protocol");
            hosts = var3.group("hostinfo");
            service = var3.group("servicename");
            serverMode = var3.group("servermode");
            instance = var3.group("instance");
            if (hosts == null) {
                return var1;
            } else if (protocol == null && service == null && serverMode == null && instance == null) {
                return var1;
            } else {
                String var9 = this.urlProps.getProperty("HTTPS_PROXY");
                String var10 = this.urlProps.getProperty("HTTPS_PROXY_PORT");
                String var11 = this.buildAddressList(hosts, protocol, var9, var10);
                return var11 == null ? var1 : String.format(DESCRIPTION_FORMAT, this.buildDescriptionParams(), var11, this.buildConnectData(service, serverMode, instance), this.buildSecurityInfo(protocol));
            }
        }
    }

    private String buildConnectData(String var1, String var2, String var3) {
        return String.format(CONNECT_DATA_FORMAT, String.format(SERVICE_NAME_FORMAT, var1 == null ? "" : var1), var2 == null ? "" : String.format(SERVER_MODE_FORMAT, var2), var3 == null ? "" : String.format(INSTANCE_NAME_FORMAT, var3));
    }

    private String buildAddressList(String var1, String var2, String var3, String var4) {
        Matcher var5 = HOST_INFO_PATTERN.matcher(var1);
        StringBuilder var6 = new StringBuilder();
        String var7 = "";
        if (var3 != null && var4 != null) {
            var7 = String.format(HTTPS_PROXY_FORMAT, var3) + String.format(HTTPS_PROXY_PORT_FORMAT, var4);
        }

        if (var2 == null) {
            var2 = "TCP";
        }

        int var8 = 0;

        while (var5.find()) {
            String[] var9 = var5.group("hostnames").split(",");
            String var10 = var5.group("port");
            if (var10 == null) {
                var10 = "1521";
            }

            String[] var11 = var9;
            int var12 = var9.length;

            for (int var13 = 0; var13 < var12; ++var13) {
                String var14 = var11[var13];
                var14 = var14.trim();
                if (var14.length() != 0) {
                    var6.append(String.format(ADDRESS_FORMAT, var2, var14, var10, var7));
                    ++var8;
                }
            }
        }

        if (var8 == 1) {
            return var6.toString();
        } else if (var8 > 1) {
            return String.format(ADDRESS_LIST_FORMAT, this.urlProps.getProperty("LOAD_BALANCE", "ON"), var6);
        } else {
            return null;
        }
    }

    private String buildDescriptionParams() {
        if (this.urlProps.isEmpty()) {
            return "";
        } else {
            StringBuilder var1 = new StringBuilder();
            this.urlProps.forEach((var1x, var2) -> {
                if (DESCRIPTION_PARAMS.contains(var1x)) {
                    var1.append(String.format("(%s=%s)", var1x, var2));
                }

            });
            return var1.toString();
        }
    }

    private String buildSecurityInfo(String var1) {
        String var2 = this.connectionProps.getProperty("oracle.net.ssl_server_dn_match");
        if (var2 == null && var1 != null && var1.equalsIgnoreCase("tcps")) {
            var2 = "TRUE";
            this.connectionProps.setProperty("oracle.net.ssl_server_dn_match", "true");
        }

        String var3 = this.urlProps.getProperty("SSL_SERVER_CERT_DN");
        String var4 = this.urlProps.getProperty("MY_WALLET_DIRECTORY");
        return var2 == null && var3 == null && var4 == null ? "" : String.format(SECURITY_FORMAT, var2, var3 == null ? "" : String.format(SERVER_DN_FORMAT, var3), var4 == null ? "" : String.format(MY_WALLET_DIR_FORMAT, var4));
    }

    private String parseExtendedSettings(String var1) {
        char[] var2 = var1.trim().toCharArray();
        int var3 = this.findExtendedSettingPosition(var2);
        if (var3 == -1) {
            return var1;
        } else {
            this.parseExtendedProperties(var2, var3 + 1);
            return var1.substring(0, var3);
        }
    }

    private void parseExtendedProperties(char[] var1, int var2) {
        try {
            String var3 = null;
            String var4 = null;
            char[] var5 = new char[var1.length];
            int var6 = 0;
            int var7 = var2;

            while (true) {
                if (var7 >= var1.length) {
                    if (var3 != null) {
                        var4 = (new String(var5, 0, var6)).trim();
                        this.addParam(var3, var4);
                    }
                    break;
                }

                if (!Character.isWhitespace(var1[var7])) {
                    String var9;
                    switch (var1[var7]) {
                        case '"':
                            int[] var8 = this.parseQuotedString(var7, var1, var6, var5);
                            var6 = var8[1];
                            var7 = var8[0];
                            break;
                        case '&':
                            if (var3 == null) {
                                var9 = "Unable to parse url \"" + new String(var5, 0, var6) + "\"";
                                throw new RuntimeException(var9);
                            }

                            var4 = (new String(var5, 0, var6)).trim();
                            this.addParam(var3, var4);
                            var3 = null;
                            var4 = null;
                            var6 = 0;
                            break;
                        case '=':
                            if (var3 != null) {
                                var9 = "Unable to parse url \"" + new String(var5, 0, var6) + "\"";
                                throw new RuntimeException(var9);
                            }

                            var3 = (new String(var5, 0, var6)).trim();
                            var6 = 0;
                            break;
                        case '\\':
                            if (var7 + 1 >= var1.length || !this.isValidEscapeChar(var1[var7 + 1])) {
                                throw new RuntimeException("Invalid character at " + var7 + " : " + var1[var7]);
                            }

                            int var10001 = var6++;
                            ++var7;
                            var5[var10001] = var1[var7];
                            break;
                        default:
                            var5[var6++] = var1[var7];
                    }
                }

                ++var7;
            }
        } catch (Exception var10) {
            Logger.getLogger("oracle.jdbc.driver").log(Level.SEVERE, "Extended settings parsing failed.", var10);
        }

    }

    private int[] parseQuotedString(int var1, char[] var2, int var3, char[] var4) {
        for (int var5 = var1 + 1; var5 < var2.length; ++var5) {
            char var6 = var2[var5];
            if (var6 == '\\') {
                if (var5 + 1 >= var2.length || !this.isValidEscapeChar(var2[var5 + 1])) {
                    throw new RuntimeException("Invalid character at " + var5 + " : " + var2[var5]);
                }

                int var10001 = var3++;
                ++var5;
                var4[var10001] = var2[var5];
            } else {
                if (var6 == '"') {
                    return new int[]{var5, var3};
                }

                var4[var3++] = var6;
            }
        }

        throw new RuntimeException("Quote at " + var1 + " not closed.");
    }

    private boolean isValidEscapeChar(char var1) {
        return var1 == '\\' || var1 == '"';
    }

    private void addParam(String var1, String var2) {
        if (var1.equalsIgnoreCase("TNS_ADMIN")) {
            this.addTNSAdmin(var2);
        } else {
            String var3 = URL_PROPS_ALIAS.get(var1);
            if (var3 != null) {
                this.urlProps.put(var3, var2);
            } else {
                var3 = CONNECTION_PROPS_ALIAS.getOrDefault(var1, var1);
                this.connectionProps.put(var3, var2);
            }
        }

    }

    private void addTNSAdmin(String var1) {
        this.connectionProps.put("oracle.net.tns_admin", var1);
    }

    private int findExtendedSettingPosition(char[] var1) {
        int var2 = 0;

        for (int var3 = 0; var3 < var1.length; ++var3) {
            if (var1[var3] == '(') {
                ++var2;
            } else if (var1[var3] == ')') {
                --var2;
            } else if (var1[var3] == '?' && var2 == 0) {
                return var3;
            }
        }

        return -1;
    }

    private static final Map<String, String> initializeUrlAlias() {
        HashMap var0 = new HashMap();
        var0.put("enable", "ENABLE");
        var0.put("failover", "FAILOVER");
        var0.put("load_balance", "LOAD_BALANCE");
        var0.put("recv_buf_size", "RECV_BUF_SIZE");
        var0.put("send_buf_size", "SEND_BUF_SIZE");
        var0.put("sdu", "SDU");
        var0.put("source_route", "SOURCE_ROUTE");
        var0.put("retry_count", "RETRY_COUNT");
        var0.put("retry_delay", "RETRY_DELAY");
        var0.put("https_proxy", "HTTPS_PROXY");
        var0.put("https_proxy_port", "HTTPS_PROXY_PORT");
        var0.put("connect_timeout", "CONNECT_TIMEOUT");
        var0.put("transport_connect_timeout", "TRANSPORT_CONNECT_TIMEOUT");
        var0.put("ssl_server_cert_dn", "SSL_SERVER_CERT_DN");
        var0.put("wallet_location", "MY_WALLET_DIRECTORY");
        return var0;
    }

    private static final Map<String, String> initializeConnectionPropertiesAlias() {
        HashMap var0 = new HashMap();
        var0.put("keystore_type", "javax.net.ssl.keyStoreType");
        var0.put("keystore_password", "javax.net.ssl.keyStorePassword");
        var0.put("keystore", "javax.net.ssl.keyStore");
        var0.put("truststore_type", "javax.net.ssl.trustStoreType");
        var0.put("truststore_password", "javax.net.ssl.trustStorePassword");
        var0.put("truststore", "javax.net.ssl.trustStore");
        var0.put("ssl_version", "oracle.net.ssl_version");
        var0.put("ssl_ciphers", "oracle.net.ssl_cipher_suites");
        var0.put("ssl_server_dn_match", "oracle.net.ssl_server_dn_match");
        return var0;
    }

    static {
        EZ_URL_PATTERN = Pattern.compile("((?<protocol>tcp|tcps):)?(//)?(?<hostinfo>(" + HOST_INFO_PATTERN.pattern() + ")+)(/(?<servicename>[A-z][A-z0-9,-.]+))?(:(?<servermode>dedicated|shared|pooled))?(/(?<instance>[A-z][A-z0-9]+))?", 2);
        URL_PROPS_ALIAS = initializeUrlAlias();
        CONNECTION_PROPS_ALIAS = initializeConnectionPropertiesAlias();
        DESCRIPTION_PARAMS = Collections.unmodifiableList(Arrays.asList("ENABLE", "FAILOVER", "LOAD_BALANCE", "RECV_BUF_SIZE", "SEND_BUF_SIZE", "SDU", "SOURCE_ROUTE", "RETRY_COUNT", "RETRY_DELAY", "CONNECT_TIMEOUT", "TRANSPORT_CONNECT_TIMEOUT"));
    }
}

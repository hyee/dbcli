package org.dbcli;

import java.security.Permission;

public class SystemExitControl {
    public static void forbidSystemExitCall() {
        final SecurityManager securityManager = new MySecurityManager(System.getSecurityManager());
        System.setSecurityManager(securityManager);
    }

    public static void enableSystemExitCall() {
        System.setSecurityManager(null);
    }

    static class MySecurityManager extends SecurityManager {
        private final SecurityManager baseSecurityManager;

        public MySecurityManager(SecurityManager baseSecurityManager) {
            this.baseSecurityManager = baseSecurityManager;
        }

        @Override
        public void checkPermission(Permission permission) {
            if (permission.getName().startsWith("exitVM")) {
                throw new SecurityException("System exit not allowed");
            }
            if (baseSecurityManager != null) {
                baseSecurityManager.checkPermission(permission);
            } else {
                return;
            }
        }

    }
}

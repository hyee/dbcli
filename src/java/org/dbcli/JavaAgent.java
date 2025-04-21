package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import jdk.internal.org.objectweb.asm.ClassReader;

import java.io.*;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Method;
import java.net.URISyntaxException;
import java.net.URL;
import java.net.URLClassLoader;
import java.security.CodeSource;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.jar.JarFile;
import java.util.jar.JarOutputStream;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;

public class JavaAgent implements ClassFileTransformer {
    static String destFolder;
    static Instrumentation inst;
    static Pattern re;
    static String separator = File.separator;
    static String libPath = null;
    private static final Pattern re1 = Pattern.compile("^\\[+L(.+);?$");
    private static final int dumpLevel = System.getProperty("java.version").startsWith("1.8") ? 1 : 0;

    static {
        try {
            re = Pattern.compile("(.*?)/([^/]+?)\\.(jar|zip)");
            File f = new File(JavaAgent.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            destFolder = f.getParentFile().getParent() + separator + "dump" + separator;
            libPath = f.getParentFile().getPath().replaceAll("([\\\\/])", "/");
        } catch (URISyntaxException localURISyntaxException) {
        }
    }

    public static void premain(String agentArgs, Instrumentation inst) {
        try {
            JarLoader.loadedViaPreMain = true;
            if (JavaAgent.inst == null) JavaAgent.inst = inst;
            if (dumpLevel == 0) return;
            inst.addTransformer(new JavaAgent());
            dumpAllClasses();
            ArrayList<Class<?>> classes = new ArrayList<Class<?>>();
            for (Class<?> c : inst.getAllLoadedClasses()) {
                if (inst.isModifiableClass(c)) {
                    classes.add(c);
                }
            }
            inst.retransformClasses(classes.toArray(new Class<?>[classes.size()]));
        } catch (Exception e) {
            Loader.getRootCause(e).printStackTrace();
        }
    }

    public static void agentmain(String agentArgs, Instrumentation inst) {
        premain(agentArgs, inst);
    }

    private static String getCandidate(String className) {
        if (className.charAt(0) == '[') {
            Matcher mt = re1.matcher(className);
            if (mt.find()) className = mt.group(1).replace('.', '/');
            else return null;
            if (className.indexOf("/") == -1) return null;
        }
        return className;
    }

    public static URL getClassLocation(Class<?> cls) {
        if (cls == null) {
            throw new IllegalArgumentException("null input: cls");
        }
        URL result = null;
        String clsAsResource = cls.getName().replace('.', '/').concat(".class");

        ProtectionDomain pd = cls.getProtectionDomain();
        if (pd != null) {
            CodeSource cs = pd.getCodeSource();
            if (cs != null) {
                result = cs.getLocation();
            }
        }
        if (result == null) {
            ClassLoader clsLoader = cls.getClassLoader();
            if (clsLoader != null) result = clsLoader.getResource(clsAsResource);
            if (result == null) result = ClassLoader.getSystemResource(clsAsResource);
        }
        return result;
    }

    public static URL getClassURL(String className, ProtectionDomain domain) throws Exception {
        String source = className;
        URL location = null;
        if (className == null) return null;
        final String tmp = className.replace("/", ".");
        if (tmp.startsWith(ClassAccess.ACCESS_CLASS_PREFIX) || tmp.contains("$$Lambda$")) return null;
        try {
            source = "/" + className.replace(".", "/") + ".class";
            if (domain != null) {
                CodeSource c = domain.getCodeSource();
                if (c != null) location = c.getLocation();
            }
            if (location == null) location = JavaAgent.class.getResource(source);
        } catch (Exception e1) {
        }
        if (location == null) return null;

        try {
            if ((location.toExternalForm().endsWith(".jar")) || (location.toExternalForm().endsWith(".zip"))) {
                location = new URL("jar:".concat(location.toExternalForm()).concat("!/").concat(source));
            } else if (new File(location.getFile()).isDirectory()) {
                location = new URL(location, source);
            }
            return location;
        } catch (Exception e1) {
            Loader.getRootCause(e1).printStackTrace();
            throw e1;
        }
    }

    public static String resolveDest(ProtectionDomain domain, Object clz) throws Exception {
        String jar = null;
        String source;
        Matcher mt;
        URL location = (clz instanceof Class) ? getClassLocation((Class) clz) : getClassURL((String) clz, domain);
        if (location == null) return null;
        source = location.toString();
        mt = re.matcher(source);
        if (mt.find()) {
            source = mt.group(1);
            if (source.contains(libPath)) return null;
            jar = mt.group(2);
        }
        return jar;
    }

    public static void copyFile(ProtectionDomain domain, Object clz, byte[] bytes) throws Exception {
        String jar = "";
        String className = (clz instanceof Class) ? ((Class) clz).getName() : (String) clz;
        if (className.startsWith("[")) {
            className = getCandidate(className);
            while ((clz instanceof Class) && ((Class) clz).isArray()) clz = ((Class) clz).getComponentType();
        }
        if (className == null) {
            System.out.println("Cannot resolve class:" + clz);
            return;
        }
        className = className.replace(";", "");
        jar = resolveDest(domain, clz);
        if (jar == null) jar = "temp";
        File destFile = new File(destFolder + jar + separator + className.replace(".", separator).replace("/", separator) + ".class");
        if (destFile.exists()) return;

        destFile.getParentFile().mkdirs();
        byte[] classFileBuffer;
        if (bytes == null) {
            classFileBuffer = getClassBuffer(clz, domain);
            if (classFileBuffer == null) {
                System.out.println("Cannot load file: " + className);
                return;
            }
        } else classFileBuffer = bytes;
        if (classFileBuffer != null) {
            if (!jar.equals("temp")) System.out.println("Folder: " + jar + "     Class: " + className);
            FileOutputStream destStream = new FileOutputStream(destFile);
            destStream.write(classFileBuffer, 0, classFileBuffer.length);
            destStream.close();
            //System.out.println("Folder: " + jar + "     Class: " + className);
            ClassReader cr = new ClassReader(classFileBuffer);
            String superClassName;
            try {
                superClassName = cr.getSuperName();
            } catch (Exception e) {
                return;
            }
            String[] interfaces = cr.getInterfaces();
            if (superClassName != null && !superClassName.replace(".", "/").equals(className.replace(".", "/")))
                copyFile(null, superClassName, null);
            if (interfaces != null && interfaces.length > 0) {
                for (int k = 0; k < interfaces.length; k++)
                    copyFile(null, interfaces[k], null);
            }
        } else {
            System.out.println("Cannot load file: " + className);
        }
    }

    public static void createJar(String[] classes, String location, String source) throws Exception {
        try (FileOutputStream fout = new FileOutputStream(location);
             JarOutputStream jarOut = new JarOutputStream(fout)) {
            System.out.println("================================================================================");
            HashMap<String, Boolean> map = new HashMap<>();
            int counter = 0;
            String suffix;
            for (String clz : classes) {
                String cl = clz;
                if (cl.endsWith(".class")) cl = cl.substring(0, cl.lastIndexOf(".class"));
                cl = cl.replace(".", "/").replace("\\", "");
                byte[] classFileBuffer = getClassBuffer(cl, null);
                suffix = ".class";
                if (classFileBuffer == null) {
                    byte[] buffer = new byte[16384];
                    int c;
                    int idx = clz.lastIndexOf(".");
                    if (idx == -1) suffix = "";
                    else {
                        suffix = clz.substring(idx);
                        cl = clz.substring(0, idx);
                    }
                    if (!clz.endsWith(".class")) {
                        try (InputStream in = JavaAgent.class.getResourceAsStream("/" + clz); ByteArrayOutputStream bos = new ByteArrayOutputStream()) {
                            while ((c = in.read(buffer)) > 0) bos.write(buffer, 0, c);
                            classFileBuffer = bos.toByteArray();
                        } catch (Exception e1) {
                            System.out.println("Cannot load " + clz);
                        }
                    }
                    if (classFileBuffer == null) {
                        URL url = new URL(("jar:file:" + source + "!/" + clz).replace("//", "/"));
                        try (InputStream in = url.openStream(); ByteArrayOutputStream bos = new ByteArrayOutputStream()) {
                            while ((c = in.read(buffer)) > 0) bos.write(buffer, 0, c);
                            classFileBuffer = bos.toByteArray();
                        } catch (Exception e1) {
                            System.out.println("Cannot load file " + clz);
                            continue;
                        }
                    }
                }
                String dir = cl.substring(0, cl.lastIndexOf('/') + 1);
                if (map.get(dir) == null) {
                    jarOut.putNextEntry(new ZipEntry(dir));
                    map.put(dir, true);
                }
                jarOut.putNextEntry(new ZipEntry(cl + suffix));
                jarOut.write(classFileBuffer);
                jarOut.flush();
                jarOut.closeEntry();
                ++counter;
            }
            jarOut.finish();
            System.out.println(location + " is generated with " + counter + " classes.");
        } catch (Exception e) {
            System.out.println(location + ":" + e.getMessage());
        }
    }

    public static byte[] getClassBuffer(Object clz, ProtectionDomain domain) throws Exception {
        URL classLocation = (clz instanceof String) ? getClassURL((String) clz, domain) : getClassLocation((Class) clz);
        if (classLocation == null) {
            return null;
        }
        InputStream srcStream = classLocation.openStream();
        ByteArrayOutputStream outStream = new ByteArrayOutputStream();
        int count = -1;
        byte[] buf = new byte[4096];
        while ((count = srcStream.read(buf)) != -1) outStream.write(buf, 0, count);
        return outStream.toByteArray();
    }

    public static void dumpAllClasses() throws Exception {
        ArrayList<Class> ary = new ArrayList();
        ary.addAll(Arrays.asList(inst.getAllLoadedClasses()));
        ClassLoader[] loaders = new ClassLoader[]{Thread.currentThread().getContextClassLoader(), JavaAgent.class.getClassLoader(), ClassLoader.getSystemClassLoader()};
        for (ClassLoader loader : loaders) {
            while (loader != null) {
                ary.addAll(Arrays.asList(inst.getInitiatedClasses(loader)));
                loader = loader.getParent();
            }
        }
        for (Class c : ary) {
            String className = getCandidate(c.getName());
            if (className != null) {
                copyFile(c.getProtectionDomain(), c, null);
            } //else System.out.println("Cannot dump " + c.getName());
        }
    }

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined, ProtectionDomain domain, byte[] classFileBuffer) {
        try {
            ClassReader cr = new ClassReader(classFileBuffer);
            if (className == null) className = cr.getClassName();
            if (className != null) copyFile(domain, className, classFileBuffer);
            //System.out.println(className);
        } catch (Exception e) {
            //System.out.println("Failed" + className);
            //Loader.getRootCause(e).printStackTrace();
        }
        return classFileBuffer;
    }

    /**
     * Adds JAR files to the class path dynamically. Uses an officially supported
     * API where possible. To ensure use of the official method and compatibility
     * with Java 9+, your app must be started with
     * {@code -javaagent:path/to/jar-loader.jar}.
     *
     * @author Chris Jennings <https://cgjennings.ca/contact.html>
     */
    static class JarLoader {
        /**
         * Adds a JAR file to the list of JAR files searched by the system class
         * loader. This effectively adds a new JAR to the class path.
         *
         * @param jarFile the JAR file to add
         * @throws IOException if there is an error accessing the JAR file
         */
        public static synchronized void addToClassPath(File jarFile) throws IOException {
            if (jarFile == null) {
                throw new NullPointerException();
            }
            // do our best to ensure consistent behaviour across methods
            if (!jarFile.exists()) {
                throw new FileNotFoundException(jarFile.getAbsolutePath());
            }
            if (!jarFile.canRead()) {
                throw new IOException("can't read jar: " + jarFile.getAbsolutePath());
            }
            if (jarFile.isDirectory()) {
                throw new IOException("not a jar: " + jarFile.getAbsolutePath());
            }

            // add the jar using instrumentation, or fall back to reflection
            if (inst != null) {
                inst.appendToSystemClassLoaderSearch(new JarFile(jarFile));
                return;
            }
            try {
                getAddUrlMethod().invoke(addUrlThis, jarFile.toURI().toURL());
            } catch (SecurityException iae) {
                throw new RuntimeException("security model prevents access to method", iae);
            } catch (Throwable t) {
                throw new AssertionError("internal error", t);
            }
        }

        /**
         * Returns whether the extending the class path is supported on the host
         * JRE. If this returns false, the most likely causes are:
         * <ul>
         * <li> the manifest is not configured to load the agent or the
         * {@code -javaagent:jarpath} argument was not specified (Java 9+);
         * <li> security restrictions are preventing reflective access to the class
         * loader (Java &le; 8);
         * <li> the underlying VM neither supports agents nor uses URLClassLoader as
         * its system class loader (extremely unlikely from Java 1.6+).
         * </ul>
         *
         * @return true if the Jar loader is supported on the Java runtime
         */
        public static synchronized boolean isSupported() {
            try {
                return inst != null || getAddUrlMethod() != null;
            } catch (Throwable t) {
            }
            return false;
        }

        /**
         * Returns a string that describes the strategy being used to add JAR files
         * to the class path. This is meant mainly to assist with debugging and
         * diagnosing client issues.
         *
         * @return returns {@code "none"} if no strategy was found, otherwise a
         * short describing the method used; the value {@code "reflection"}
         * indicates that a fallback not compatible with Java 9+ is being used
         */
        public static synchronized String getStrategy() {
            String strat = "none";
            if (inst != null) {
                strat = loadedViaPreMain ? "agent" : "agent (main)";
            } else {
                try {
                    if (isSupported()) {
                        strat = "reflection";
                    }
                } catch (Throwable t) {
                }
            }
            return strat;
        }

        private static Method getAddUrlMethod() {
            if (addUrlMethod == null) {
                addUrlThis = ClassLoader.getSystemClassLoader();
                if (addUrlThis instanceof URLClassLoader) {
                    try {
                        final Method method = URLClassLoader.class.getDeclaredMethod("addURL", URL.class);
                        method.setAccessible(true);
                        addUrlMethod = method;
                    } catch (NoSuchMethodException nsm) {
                        throw new AssertionError(); // violates URLClassLoader API!
                    }
                } else {
                    throw new UnsupportedOperationException("did you forget -javaagent:<jarpath>?");
                }
            }
            return addUrlMethod;
        }

        private static ClassLoader addUrlThis;
        private static Method addUrlMethod;
        static boolean loadedViaPreMain = false;
    }
}
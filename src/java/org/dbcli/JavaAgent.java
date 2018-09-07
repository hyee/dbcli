package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import jdk.internal.org.objectweb.asm.ClassReader;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.net.URISyntaxException;
import java.net.URL;
import java.security.CodeSource;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class JavaAgent implements ClassFileTransformer {
    static String destFolder;
    static Instrumentation in;
    static Pattern re;
    static String separator = File.separator;
    static Field classFinder = null;
    static String libPath = null;
    private static Pattern re1 = Pattern.compile("^\\[+L(.+);?$");

    static {
        try {
            re = Pattern.compile("(.*?)/([^/]+?)\\.(jar|zip)");
            File f = new File(JavaAgent.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            destFolder = f.getParentFile().getParent() + separator + "dump" + separator;
            libPath = f.getParentFile().getPath().replaceAll("([\\\\/])", "/");
            classFinder = ClassLoader.class.getDeclaredField("classes");
            classFinder.setAccessible(true);
        } catch (URISyntaxException localURISyntaxException) {
        } catch (NoSuchFieldException ex) {
            ex.printStackTrace();
        }
    }

    public static void premain(String agentArgs, Instrumentation inst) {
        try {
            in = inst;
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
            //System.out.println("superClassName :"+superClassName);
        } else {
            System.out.println("Cannot load file: " + className);
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
        ary.addAll(Arrays.asList(in.getAllLoadedClasses()));
        ClassLoader[] loaders = new ClassLoader[]{Thread.currentThread().getContextClassLoader(), JavaAgent.class.getClassLoader(), ClassLoader.getSystemClassLoader()};
        for (ClassLoader loader : loaders) {
            while (loader != null) {
                ary.addAll(Arrays.asList(in.getInitiatedClasses(loader)));
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

    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined, ProtectionDomain domain, byte[] classFileBuffer) {
        try {
            ClassReader cr = new ClassReader(classFileBuffer);
            if (className == null) className = cr.getClassName();
            if (className != null) copyFile(domain, className, classFileBuffer);
        } catch (Exception e) {
            Loader.getRootCause(e).printStackTrace();
        }
        return classFileBuffer;
    }
}
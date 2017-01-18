package org.dbcli;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.net.MalformedURLException;
import java.net.URISyntaxException;
import java.net.URL;
import java.security.CodeSource;
import java.security.ProtectionDomain;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class JavaAgent implements ClassFileTransformer {
    static String destFolder;
    static Instrumentation in;
    static Pattern re;
    static String separator = File.separator;

    static {
        try {
            re = Pattern.compile("/([^/]+?)\\.(jar|zip)");
            File f = new File(JavaAgent.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            destFolder = f.getParentFile().getParent() + separator + "dump" + separator;
        } catch (URISyntaxException localURISyntaxException) {
        }
    }

    public static void premain(String agentArgs, Instrumentation inst) {
        try {
            in = inst;
            inst.addTransformer(new JavaAgent());
            dumpAllClasses();
        } catch (Exception e) {
            Loader.getRootCause(e).printStackTrace();
        }
    }

    public static void agentmain(String agentArgs, Instrumentation inst) {
        premain(agentArgs, inst);
    }

    private static String isCandidate(String className) {
        if (className.charAt(0) == '[') {
            //Matcher mt = re1.matcher(className);
            //if (mt.find()) return mt.group(1).replace('.', '/');
            return null;
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
            if (result != null) {
                if ("file".equals(result.getProtocol())) {
                    try {
                        if ((result.toExternalForm().endsWith(".jar")) || (result.toExternalForm().endsWith(".zip"))) {
                            result = new URL("jar:".concat(result.toExternalForm()).concat("!/").concat(clsAsResource));
                        } else if (new File(result.getFile()).isDirectory()) {
                            result = new URL(result, clsAsResource);
                        }
                    } catch (MalformedURLException localMalformedURLException) {
                    }
                }
            }
        }
        if (result == null) {
            ClassLoader clsLoader = cls.getClassLoader();

            result = clsLoader != null ? clsLoader.getResource(clsAsResource) : ClassLoader.getSystemResource(clsAsResource);
        }
        return result;
    }

    public static URL getClassURL(String className, ProtectionDomain domain) throws Exception {
        String source = className;
        URL location;
        if (className == null) return null;
        try {
            source = "/" + className.replace(".", "/") + ".class";
            location = JavaAgent.class.getResource(source);
        } catch (Exception e1) {
            location = null;
            System.out.println("Error on loading Source: " + source);
            //e1.printStackTrace();
        }
        Exception e = new Exception();
        if (location == null) {
            CodeSource c;
            try {
                c = (domain == null ? Class.forName(className.replace("/", ".")).getProtectionDomain() : domain).getCodeSource();
                if (c == null) throw e;
            } catch (Exception e1) {
                if (className != null && !className.startsWith("sun/reflect") && !className.startsWith("com/sun/proxy"))
                    System.out.println("Cannot find class " + className);
                return null;
            }
            location = c.getLocation();
        }

        try {
            if ((location.toExternalForm().endsWith(".jar")) || (location.toExternalForm().endsWith(".zip"))) {
                location = new URL("jar:".concat(location.toExternalForm()).concat("!/").concat(source));
            } else if (new File(location.getFile()).isDirectory()) {
                location = new URL(location, source);
            }
            return location;
        } catch (MalformedURLException e1) {
            Loader.getRootCause(e1).printStackTrace();
            throw e1;
        }
    }

    public static String resolveDest(ProtectionDomain domain, String className) throws Exception {
        String jar = null;
        String source;
        Matcher mt;
        URL location = getClassURL(className, domain);
        if (location == null) return null;
        source = location.toString();
        mt = re.matcher(source);
        if (mt.find()) jar = mt.group(1);
        return jar;
    }

    public static void copyFile(ProtectionDomain domain, String className) throws Exception {
        String jar = resolveDest(domain, className);
        if (jar == null) return;
        File destFile = new File(destFolder + jar + separator + className.replace(".", separator).replace("/", separator) + ".class");
        if (destFile.exists()) return;
        System.out.println("Folder: " + jar + "     Class: " + className);
        destFile.getParentFile().mkdirs();
        byte[] classFileBuffer = getClassBuffer(className, domain);
        FileOutputStream destStream = new FileOutputStream(destFile);
        destStream.write(classFileBuffer, 0, classFileBuffer.length);
        destStream.close();
    }

    public static byte[] getClassBuffer(String className, ProtectionDomain domain) throws Exception {
        URL classLocation = getClassURL(className, domain);
        InputStream srcStream = classLocation.openStream();
        ByteArrayOutputStream outStream = new ByteArrayOutputStream();
        int count = -1;
        byte[] buf = new byte[4096];
        while ((count = srcStream.read(buf)) != -1) outStream.write(buf, 0, count);
        buf = null;
        return outStream.toByteArray();
    }

    public static void dumpAllClasses() throws Exception {
        Class[] classes = in.getAllLoadedClasses();
        Class[] arrayOfClass1 = classes;
        int j = classes.length;
        for (int i = 0; i < j; i++) {
            Class c = arrayOfClass1[i];
            String className = isCandidate(c.getName());
            if (className != null) {
                copyFile(c.getProtectionDomain(), className);
            } //else System.out.println("Cannot dump " + c.getName());
        }
    }

    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined, ProtectionDomain domain, byte[] classFileBuffer) {
        try {
            copyFile(domain, className);
        } catch (Exception e) {
            Loader.getRootCause(e).printStackTrace();
        }
        return classFileBuffer;
    }

/*
    public static void addFilesToExistingJar(File zipFile, File[] files) throws IOException {
        // get a temp file
        File tempFile = File.createTempFile(zipFile.getName(), null);
        // delete it, otherwise you cannot rename your existing zip to it.
        tempFile.delete();
        boolean renameOk=zipFile.renameTo(tempFile);
        if (!renameOk)
        {
            throw new RuntimeException("could not rename the file "+zipFile.getAbsolutePath()+" to "+tempFile.getAbsolutePath());
        }
        byte[] buf = new byte[1024];
        JarInputStream zin = new JarInputStream(new FileInputStream(tempFile));
        JarOutputStream out = new JarOutputStream(new FileOutputStream(zipFile));
        JarEntry entry = zin.getNextJarEntry();
        while (entry != null) {
            String name = entry.getName();
            boolean notInFiles = true;
            for (File f : files) {
                if (f.getName().equals(name)) {
                    notInFiles = false;
                    break;
                }
            }
            if (notInFiles) {
                // Add ZIP entry to output stream.
                out.putNextEntry(new JarEntry(name));
                // Transfer bytes from the ZIP file to the output file
                int len;
                while ((len = zin.read(buf)) > 0) {
                    out.write(buf, 0, len);
                }
            }
            entry = zin.getNextJarEntry();
        }
        // Close the streams
        zin.close();
        // Compress the files
        for (int i = 0; i < files.length; i++) {
            InputStream in = new FileInputStream(files[i]);
            // Add ZIP entry to output stream.
            out.putNextEntry(new JarEntry(files[i].getName()));
            // Transfer bytes from the file to the ZIP file
            int len;
            while ((len = in.read(buf)) > 0) {
                out.write(buf, 0, len);
            }
            // Complete the entry
            out.closeEntry();
            in.close();
        }
        // Complete the ZIP file
        out.close();
        tempFile.delete();
    }
 */
}
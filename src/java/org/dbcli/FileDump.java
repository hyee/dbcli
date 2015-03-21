package org.dbcli;

import sun.jvm.hotspot.debugger.AddressException;
import sun.jvm.hotspot.memory.SystemDictionary;
import sun.jvm.hotspot.oops.InstanceKlass;
import sun.jvm.hotspot.oops.Klass;
import sun.jvm.hotspot.runtime.VM;
import sun.jvm.hotspot.tools.jcore.ClassDump;
import sun.jvm.hotspot.tools.jcore.ClassFilter;
import sun.jvm.hotspot.tools.jcore.ClassWriter;
import sun.jvm.hotspot.tools.Tool;

import java.io.*;
import java.lang.reflect.Method;

public class FileDump extends ClassDump {
    private String outputDirectory;
    private SystemDictionary ioe;

    public static void main(String[] args) {
        ClassFilter classFilter = null;
        System.out.print("Starting to dump...");
        String outputDirectory = System.getProperty("sun.jvm.hotspot.tools.jcore.outputDir");
        if (outputDirectory == null) {
            outputDirectory = ".";
        }
        FileDump cd = new FileDump();
        cd.setClassFilter(classFilter);
        cd.setOutputDirectory(outputDirectory);

        try {
            Method method;
            try {
                method = Tool.class.getDeclaredMethod("execute", new Class[]{String[].class});
            } catch (Exception e1) {
                method = Tool.class.getDeclaredMethod("start", new Class[]{String[].class});
            }
            method.invoke((Tool)cd, new Object[]{args});
        } catch (Exception e) {
            e.printStackTrace();
            return;
        }
        //cd.start(args);
        cd.stop();
    }

    @Override
    public void setOutputDirectory(String od) {
        this.outputDirectory = od;
        super.setOutputDirectory(od);
    }

    @Override
    public void run() {
        try {
            ioe = VM.getVM().getSystemDictionary();
            ioe.classesDo(new SystemDictionary.ClassVisitor() {
                public void visit(Klass k) {
                    if (k instanceof InstanceKlass) {
                        try {
                            FileDump.this.dumpKlass((InstanceKlass) k);
                        } catch (Exception var3) {
                            System.out.println(k.getName().asString());
                            var3.printStackTrace();
                        }
                    }

                }
            });
        } catch (AddressException var3) {
            System.err.println("Error accessing address 0x" + Long.toHexString(var3.getAddress()));
            var3.printStackTrace();
        }

    }

    private void dumpKlass(InstanceKlass kls) throws Exception {
        String klassName = kls.getName().asString();
        String jar = JavaAgent.resolveDest(null, klassName);
        if (jar == null) return;
        klassName = klassName.replace('/', File.separatorChar);
        try {
            OutputStream os = null;
            int index = klassName.lastIndexOf(File.separatorChar);
            File dir = null;
            if (index != -1) {
                String dirName = klassName.substring(0, index);
                dir = new File(this.outputDirectory + File.separator + jar, dirName);
            } else {
                dir = new File(this.outputDirectory + File.separator + jar);
            }
            dir.mkdirs();
            File f = new File(dir, klassName.substring(index + 1) + ".class");
            f.createNewFile();
            os = new BufferedOutputStream(new FileOutputStream(f));
            try {
                ClassWriter cw = new ClassWriter(kls, os);
                cw.write();
                os.close();
            } finally {
                os.close();
            }
        } catch (IOException exp) {
            exp.printStackTrace();
        }
    }

}

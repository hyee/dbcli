package org.dbcli;

import com.naef.jnlua.LuaState;
import jline.console.ConsoleReader;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;


public class Loader {
    public static LuaState lua;
    public static PrintWriter printer;
    public static ConsoleReader reader;
    public static Boolean ReloadNextTime = true;
    public static String root="";
    private class KeyListner implements ActionListener {
        @Override
        public void actionPerformed(ActionEvent e) {
            lua.getGlobal("TRIGGER_ABORT");
            lua.call(0, 0);
            //System.exit(0);
        }

    }

    public Loader() {
        try {
            reader = new ConsoleReader();
            Class clz = reader.getClass();
            printer = new PrintWriter((Writer) reader.getOutput());
            // reader.setCompletionHandler(null);
            reader.setHandleUserInterrupt(false);
            ActionListener al = new KeyListner();
            //Ctrl+D
            reader.getKeys().bind("\004", al);
            //Ctrl+Z
            reader.getKeys().bind("\026", al);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public void addPath(String file) throws Exception {
        URLClassLoader classLoader = (URLClassLoader) lua.getClassLoader();
        Class<URLClassLoader> clazz = URLClassLoader.class;
        URL url = new URL("file:" + file);
        // Use reflection
        Method method = clazz.getDeclaredMethod("addURL", new Class[]{URL.class});
        method.setAccessible(true);
        method.invoke(classLoader, new Object[]{url});
        System.setProperty("java.class.path",System.getProperty("java.class.path")
                +(System.getProperty("sun.desktop").equals("windows")?";":":")+file.replace(root,"."));
    }

    public void copyClass(String className) throws Exception{
        JavaAgent.copyFile(null, className.replace("\\.","/"));
    }


    public String dumpClass(String folder) throws Exception{
        String cp=System.getProperty("java.class.path");
        String stack = java.lang.management.ManagementFactory.getRuntimeMXBean().getName();
        String packageName = Loader.class.getPackage().getName()+".FileDump";
        String sep=File.separator;
        stack= stack.split("@")[0];
        stack=String.format("java -cp \"%s%slib%ssa-jdi.jar;%s\" -Dsun.jvm.hotspot.tools.jcore.outputDir=%s %s %s",
                System.getProperty("java.home"),sep,sep,cp,folder,packageName,stack);
        //System.out.println("Command: "+stack);
        return stack;
    }

    public static void loadLua(Loader l, String args[]) throws Exception {
        lua = new LuaState();
        lua.openLibs();
        lua.pushJavaObject(l);
        lua.setGlobal("loader");
        if (printer != null) {
            lua.pushJavaObject(reader);
            lua.setGlobal("reader");
            lua.pushJavaObject(printer);
            lua.setGlobal("writer");
        }
        String separator = File.separator;

        File f = new File(Loader.class.getProtectionDomain().getCodeSource().getLocation().toURI());
        root= f.getParentFile().getParent();
        String input = root + separator + "lua" + separator + "input.lua";
        StringBuilder sb = new StringBuilder();
        String readline = "";
        BufferedReader br = new BufferedReader(new FileReader(new File(input)));
        while (br.ready()) {
            readline = br.readLine();
            sb.append(readline + "\n");
        }
        br.close();
        //System.out.println(sb.toString());
        lua.load(sb.toString(), input);
        for (int i = 0; i < args.length; i++) lua.pushString(args[i]);
        ReloadNextTime = false;
        lua.call(args.length, 0);
        lua.close();
        lua = null;
        System.gc();
    }

    public static void main(String args[]) throws Exception {
        System.loadLibrary("lua5.1");
        Loader l = new Loader();
        while (ReloadNextTime) loadLua(l, args);
    }
}
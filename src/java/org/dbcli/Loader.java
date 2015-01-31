package org.dbcli;

import com.naef.jnlua.LuaState;
import jline.console.ConsoleReader;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.lang.reflect.Field;
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
            File f = new File(Loader.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            root= f.getParentFile().getParent();
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
                +File.pathSeparator+file.replace(root,"."));
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

    public static void setLibrary(String path) throws Exception {
        System.setProperty("java.library.path", path);
        Field fieldSysPath = ClassLoader.class.getDeclaredField( "sys_paths" );
        fieldSysPath.setAccessible( true );
        fieldSysPath.set( null, null);

    }

    public static void addLibrary(String s,Boolean isReplace) throws IOException {
        try {
            Field field = ClassLoader.class.getDeclaredField("usr_paths");
            field.setAccessible(true);
            if(!isReplace) {
                String path="";
                String[] paths = (String[]) field.get(null);
                for (int i = 0; i < paths.length; i++) {
                    if (s.equals(paths[i])) return;
                    path=path+paths[i]+File.pathSeparator;
                }
                String[] tmp = new String[paths.length + 1];
                System.arraycopy(paths, 0, tmp, 0, paths.length);
                tmp[paths.length] = s;
                field.set(null, tmp);
                path=path+s;
                System.setProperty("java.library.path", path);
            } else {
                field.set(null, new String[]{s});
                System.setProperty("java.library.path", s);
            }
        } catch (IllegalAccessException e) {
            throw new IOException("Failed to get permissions to set library path");
        } catch (NoSuchFieldException e) {
            throw new IOException("Failed to get field handle to set library path");
        }
    }


    public static void main(String args[]) throws Exception {
        Loader l = new Loader();
        String path=root+File.separator+"lib";
        if(System.getProperty("sun.arch.data.model").equals("64"))
            setLibrary(path + File.separator + "x64");
        else
            setLibrary(path);
        System.loadLibrary("lua5.1");
        while (ReloadNextTime) loadLua(l, args);
    }
}
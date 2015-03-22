package org.dbcli;

import com.naef.jnlua.LuaState;
import com.opencsv.CSVWriter;
import com.opencsv.SQLWriter;
import jline.console.ConsoleReader;
import jline.console.completer.Completer;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.sql.CallableStatement;
import java.sql.ResultSet;
import java.util.Iterator;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;


public class Loader {
    public static Boolean ReloadNextTime = true;
    static LuaState lua;
    static PrintWriter printer;
    static ConsoleReader reader;
    static String root = "";
    ExecutorService executor = Executors.newFixedThreadPool(1);

    public Loader() {
        try {
            File f = new File(Loader.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            root = f.getParentFile().getParent();
            reader = new ConsoleReader(System.in, System.out);
            printer = new PrintWriter((Writer) reader.getOutput());
            Iterator<Completer> iterator = reader.getCompleters().iterator();
            while (iterator.hasNext()) reader.removeCompleter(iterator.next());
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
        //lua.getTop();
        for (int i = 0; i < args.length; i++) lua.pushString(args[i]);
        ReloadNextTime = false;
        lua.call(args.length, 0);
        lua.close();
        lua = null;
        System.gc();
    }

    public static void addLibrary(String s, Boolean isReplace) throws IOException {
        try {
            Field field = ClassLoader.class.getDeclaredField("usr_paths");
            field.setAccessible(true);
            if (!isReplace) {
                String path = "s";
                String[] paths = (String[]) field.get(null);
                for (int i = 0; i < paths.length; i++) {
                    if (s.equals(paths[i])) return;
                    path = path + File.pathSeparator + paths[i];
                }
                String[] tmp = new String[paths.length + 1];
                System.arraycopy(paths, 0, tmp, 0, paths.length);
                tmp[paths.length] = s;
                field.set(null, tmp);
                System.setProperty("java.library.path", path);
            } else {
                System.setProperty("java.library.path", s);
                //set sys_paths to null so that java.library.path will be reevalueted next time it is needed
                final Field sysPathsField = ClassLoader.class.getDeclaredField("sys_paths");
                sysPathsField.setAccessible(true);
                sysPathsField.set(null, null);
            }
        } catch (IllegalAccessException e) {
            throw new IOException("Failed to get permissions to set library path");
        } catch (NoSuchFieldException e) {
            throw new IOException("Failed to get field handle to set library path");
        }
    }

    public static void main(String args[]) throws Exception {
        Loader l = new Loader();
        String path = root + File.separator + "lib" + File.separator;
        if (System.getProperty("sun.arch.data.model").equals("64")) addLibrary(path + "x64", true);
        else addLibrary(path + "x86", true);
        System.loadLibrary("lua5.1");
        while (ReloadNextTime) loadLua(l, args);
    }

    public void addPath(String file) throws Exception {
        URLClassLoader classLoader = (URLClassLoader) lua.getClassLoader();
        Class<URLClassLoader> clazz = URLClassLoader.class;
        URL url = new URL("file:" + file);
        // Use reflection
        Method method = clazz.getDeclaredMethod("addURL", new Class[]{URL.class});
        method.setAccessible(true);
        method.invoke(classLoader, new Object[]{url});
        System.setProperty("java.class.path", System.getProperty("java.class.path") + File.pathSeparator + file.replace(root, "."));
    }

    public void copyClass(String className) throws Exception {
        JavaAgent.copyFile(null, className.replace("\\.", "/"));
    }

    public String dumpClass(String folder) throws Exception {
        String cp = System.getProperty("java.class.path");
        String stack = java.lang.management.ManagementFactory.getRuntimeMXBean().getName();
        String packageName = Loader.class.getPackage().getName() + ".FileDump";
        String sep = File.separator;
        stack = stack.split("@")[0];
        stack = String.format("java -cp \"%s%slib%ssa-jdi.jar;%s\" -Dsun.jvm.hotspot.tools.jcore.outputDir=%s %s %s", System.getProperty("java.home"), sep, sep, cp, folder, packageName, stack);
        //System.out.println("Command: "+stack);
        return stack;
    }

    public void dbCall(final CallableStatement p) throws InterruptedException {
        executor.execute(new DbExecutor(p, new DbCallback() {
            @Override
            public void complete(String result) {
                System.out.println("Callback1 ..." + " " + result);
                lua.getGlobal("ON_ASYNC_STATEMENT_COMPLETE");
                lua.pushString(result);
                lua.pushJavaObject(p);
                System.out.println("Callback2 ...");
                lua.call(2, 0);
                System.out.println("Callback3 ...");
            }
        }));
    }

    public int ResultSet2CSV(ResultSet rs, String fileName, String header) throws Exception {
        try {
            CSVWriter writer = new CSVWriter(fileName);
            int result = writer.writeAll(rs, true);
            rs.close();
            writer.close();
            return result;
        } catch (Exception e) {
            e.printStackTrace();
            throw e;
        }
    }

    public int ResultSet2SQL(ResultSet rs, String fileName, String header) throws Exception {
        try {
            SQLWriter writer = new SQLWriter(fileName);
            writer.setFileHead(header);
            int result = writer.writeAll2SQL(rs, "", 1500);
            rs.close();
            return result;
        } catch (Exception e) {
            e.printStackTrace();
            throw e;
        }
    }

    public int CSV2SQL(String CSVfileName, String SQLFileName, String header, ResultSet rs) throws Exception {
        try {
            SQLWriter writer = new SQLWriter(SQLFileName);
            writer.setFileHead(header);
            if (rs != null) writer.setCSVDataTypes(rs);
            writer.setMaxLineWidth(1500);
            return writer.writeAll2SQL(CSVfileName);
        } catch (Exception e) {
            e.printStackTrace();
            throw e;
        }
    }

    private class KeyListner implements ActionListener {
        @Override
        public void actionPerformed(ActionEvent e) {
            lua.getGlobal("TRIGGER_ABORT");
            lua.call(0, 0);
            //System.exit(0);
        }
    }
}
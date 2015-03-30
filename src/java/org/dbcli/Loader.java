package org.dbcli;

import com.naef.jnlua.LuaState;
import com.opencsv.CSVWriter;
import com.opencsv.SQLWriter;
import jline.console.KeyMap;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.sql.CallableStatement;
import java.sql.ResultSet;
import java.util.concurrent.Future;


public class Loader {
    public static Boolean ReloadNextTime = true;
    static LuaState lua;
    static PrintWriter printer;
    static Console console;
    static String root = "";
    static String libPath;
    KeyMap keyMap;
    KeyListner q;
    private CallableStatement stmt = null;
    private Future sleeper;
    private Sleeper runner = new Sleeper();

    public Loader() {
        try {
            File f = new File(Loader.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            root = f.getParentFile().getParent();
            libPath = root + File.separator + "lib" + File.separator;
            String bit = System.getProperty("sun.arch.data.model");
            if (bit == null) bit = System.getProperty("com.ibm.vm.bitmode");
            libPath += (bit.equals("64") ? "x64" : "x86");
            addLibrary(libPath, true);
            System.setProperty("library.jansi.path", libPath);
            console = new Console();
            printer = new PrintWriter(console.getOutput());
            //Ctrl+D
            keyMap = console.getKeys();
            keyMap.bind(String.valueOf(KeyMap.CTRL_D), new KeyListner(KeyMap.CTRL_D));
            q = new KeyListner('q');

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
            lua.pushJavaObject(console);
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

    public static void addLibrary(String s, Boolean isReplace) throws Exception {
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
            System.setProperty("java.library.path", s);
            //throw new IOException("Failed to get field handle to set library path");
        }
    }

    public static void main(String args[]) throws Exception {
        Loader l = new Loader();
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

    public synchronized boolean setStatement(CallableStatement p) throws Exception {
        try {
            this.stmt = p;
            console.setEvents(p == null ? null : q, new char[]{'q', KeyMap.CTRL_D});
            return this.stmt == null ? false : this.stmt.execute();
        } catch (Exception e) {
            throw e;
        } finally {
            this.stmt = null;
            console.setEvents(null, null);
        }
    }

    public synchronized void sleep(int millSeconds) throws Exception {
        try {
            runner.setSleep(millSeconds);
            sleeper = console.threadPool.submit(runner);
            console.setEvents(q, new char[]{'q', KeyMap.CTRL_D});
            sleeper.get();
        } catch (Exception e) {
            throw new IOException("Statement is aborted.");
        } finally {
            sleeper = null;
            console.setEvents(null, null);
        }
    }

    private class KeyListner implements ActionListener {
        int key;

        public KeyListner(int k) {
            this.key = k;
        }

        @Override
        public void actionPerformed(ActionEvent e) {
            try {
                if (e != null) key = e.getActionCommand().charAt(0);
                if (!console.isRunning() && key != 'q') {
                    lua.getGlobal("TRIGGER_ABORT");
                    lua.call(0, 0);
                } else if (stmt != null) {
                    if (stmt != null && !stmt.isClosed()) stmt.cancel();
                }
                if (sleeper != null) synchronized (sleeper) {
                    sleeper.cancel(true);
                }
            } catch (Exception err) {
                //err.printStackTrace();
            }
        }
    }

    private class Sleeper implements Runnable {
        private int timer = 0;

        public void setSleep(int t) {
            timer = t;
        }

        public void run() {
            try {
                synchronized (this) {
                    Thread.sleep(timer);
                }
            } catch (InterruptedException e) {

            }
        }
    }
}

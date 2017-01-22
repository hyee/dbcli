package org.dbcli;

import com.naef.jnlua.LuaState;
import com.opencsv.CSVReader;
import com.opencsv.CSVWriter;
import com.opencsv.ResultSetHelperService;
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
import java.util.ArrayList;
import java.util.concurrent.Callable;
import java.util.concurrent.CancellationException;
import java.util.concurrent.Future;
import java.util.regex.Pattern;
import java.util.zip.InflaterInputStream;

public class Loader {
    public static String ReloadNextTime = "_init_";
    static LuaState lua;
    static Console console;
    static String root = "";
    static String libPath;
    KeyMap keyMap;
    KeyListner q;
    Future sleeper;
    private CallableStatement stmt = null;
    private Sleeper runner = new Sleeper();
    private ResultSet rs;
    private IOException CancelError = new IOException("Statement is aborted.");

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
            //Ctrl+D
            keyMap = console.getKeys();
            keyMap.bind(String.valueOf(KeyMap.CTRL_D), new KeyListner(KeyMap.CTRL_D));
            q = new KeyListner('q');
            Interrupter.listen("loader", new EventCallback() {
                @Override
                public void interrupt(Object... e) throws Exception {
                    q.actionPerformed((ActionEvent) e[0]);
                }
            });
        } catch (Exception e) {
            getRootCause(e).printStackTrace();
        }
    }

    public static Exception getRootCause(Exception e) {
        Throwable t = e.getCause();
        while (t != null && t.getCause() != null) t = t.getCause();
        return t == null ? e : new Exception(t);
    }

    public static void loadLua(Loader loader, String args[]) throws Exception {
        lua = new LuaState();
        lua.openLibs();
        lua.pushJavaObject(loader);
        lua.setGlobal("loader");
        console.lua = lua;
        if (console.writer != null) {
            lua.pushJavaObject(console);
            lua.setGlobal("reader");
            lua.pushJavaObject(console.writer);
            lua.setGlobal("writer");
            lua.pushJavaObject(console.getTerminal());
            lua.setGlobal("terminal");
            lua.pushJavaObject(new PrintWriter(console.getOutput()));
            lua.setGlobal("jwriter");
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
        if (ReloadNextTime != null && ReloadNextTime.equals("_init_")) ReloadNextTime = null;
        //lua.getTop();
        for (int i = 0; i < args.length; i++) {
            if (args[i].toLowerCase().contains("database ") && ReloadNextTime != null) {
                args[i] = "set database " + ReloadNextTime;
                ReloadNextTime = null;
            }
            lua.pushString(args[i]);
        }
        if (ReloadNextTime != null) {
            lua.pushString("set database " + ReloadNextTime);
            ReloadNextTime = null;
            lua.call(args.length + 1, 0);
        } else lua.call(args.length, 0);
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
        while (ReloadNextTime != null) loadLua(l, args);
        //console.threadPool.shutdown();
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
        //packageName="sun.jvm.hotspot.tools.jcore.ClassDump";
        String sep = File.separator;
        stack = stack.split("@")[0];
        Pattern p = Pattern.compile("[\\\\/]jre.*", Pattern.CASE_INSENSITIVE);
        String java_home = p.matcher(System.getProperty("java.home")).replaceAll("");
        stack = String.format("java -cp \"%s%slib%s*;%s\" -Dsun.jvm.hotspot.tools.jcore.outputDir=%s %s %s", java_home, sep, sep, cp, folder, packageName, stack);
        //System.out.println("Command: "+stack);
        return stack;
    }

    public void setCurrentResultSet(ResultSet res) {
        this.rs = res;
    }

    private void setExclusiveAndRemap(CSVWriter writer, String excludes, String[] remaps) {
        if (excludes != null && !excludes.trim().equals("")) {
            String ary[] = excludes.split(",");
            for (String column : ary) writer.setExclude(column, true);
        }
        if (remaps != null) {
            for (String column : remaps) {
                if (column == null || column.trim().equals("")) continue;
                String[] o = column.split("=", 2);
                System.out.println(o[0]);
                writer.setRemap(o[0], o.length < 2 ? null : o[1]);
            }
        }
    }

    public int ResultSet2CSV(final ResultSet rs, final String fileName, final String header, final boolean aync, final String excludes, final String[] remaps) throws Exception {
        setCurrentResultSet(rs);
        return (int) asyncCall(new Callable() {
            @Override
            public Integer call() throws Exception {
                try (CSVWriter writer = new CSVWriter(fileName)) {
                    writer.setAsyncMode(aync);
                    setExclusiveAndRemap(writer, excludes, remaps);
                    int result = writer.writeAll(rs, true);
                    return result - 1;
                }
            }
        });
    }

    public int ResultSet2SQL(final ResultSet rs, final String fileName, final String header, final boolean aync, final String excludes, final String[] remaps) throws Exception {
        setCurrentResultSet(rs);
        return (int) asyncCall(new Callable() {
            @Override
            public Integer call() throws Exception {
                try (SQLWriter writer = new SQLWriter(fileName)) {
                    writer.setAsyncMode(aync);
                    writer.setFileHead(header);
                    setExclusiveAndRemap(writer, excludes, remaps);
                    int count = writer.writeAll2SQL(rs, "", 1500);
                    return count;
                }
            }
        });
    }

    public int CSV2SQL(final ResultSet rs, final String SQLFileName, final String CSVfileName, final String header, final String excludes, final String[] remaps) throws Exception {
        setCurrentResultSet(rs);
        return (int) asyncCall(new Callable() {
            @Override
            public Integer call() throws Exception {
                try (SQLWriter writer = new SQLWriter(SQLFileName)) {
                    writer.setFileHead(header);
                    setExclusiveAndRemap(writer, excludes, remaps);
                    return writer.writeAll2SQL(CSVfileName, rs);
                }
            }
        });
    }

    public Object[][] fetchResult(final ResultSet rs, final int rows) throws Exception {
        if (rs.getStatement().isClosed() || rs.isClosed()) throw CancelError;
        setCurrentResultSet(rs);
        return (Object[][]) asyncCall(new Callable() {
            @Override
            public Object call() throws Exception {
                try(ResultSetHelperService helper = new ResultSetHelperService(rs)) {
                return (rows >= 0 && rows <= 10000) ? helper.fetchRows(rows) : helper.fetchRowsAsync(rows);
                }
            }
        });
    }

    public String[][] fetchCSV(final String CSVFileSource, final int rows) throws Exception {
        ArrayList<String[]> list = (ArrayList<String[]>) asyncCall(new Callable() {
            @Override
            public ArrayList<String[]> call() throws Exception {
                ArrayList<String[]> ary = new ArrayList();
                String[] line;
                int size = 0;
                try (CSVReader reader = new CSVReader(new FileReader(CSVFileSource))) {
                    while ((line = reader.readNext()) != null) {
                        ++size;
                        if (rows > -1 && size > rows) break;
                        ary.add(line);
                    }
                }
                return ary;
            }
        });
        return list.toArray(new String[][]{});
    }

    public String inflate(byte[] data) throws Exception {
        try (ByteArrayInputStream bis = new ByteArrayInputStream(data); InflaterInputStream iis = new InflaterInputStream(bis);) {

            StringBuffer sb = new StringBuffer();
            int i = 0;
            for (int c = iis.read(); c != -1; c = iis.read()) {
                sb.append((char) c);
            }
            return sb.toString();
        }
    }

    public synchronized boolean setStatement(CallableStatement p) throws Exception {
        try {
            this.stmt = p;
            console.setEvents(p == null ? null : q, new char[]{'q', 'Q', KeyMap.CTRL_D});
            if (p == null) return false;
            boolean result = p.execute();
            if (p.isClosed()) throw CancelError;
            return result;
        } catch (Exception e) {
            throw e;
        } finally {
            this.stmt = null;
            console.setEvents(null, null);
        }
    }

    public Object asyncCall(Callable<Object> c) throws Exception {
        try {
            this.sleeper = console.threadPool.submit(c);
            console.setEvents(q, new char[]{'q', KeyMap.CTRL_D});
            return sleeper.get();
        } catch (CancellationException | InterruptedException e) {
            throw CancelError;
        } catch (Exception e) {
            e = getRootCause(e);
            //e.printStackTrace();
            throw e;
        } finally {
            if (rs != null && !rs.isClosed()) rs.close();
            sleeper = null;
            rs = null;
            console.setEvents(null, null);
        }
    }

    public synchronized Object asyncCall(final Object o, final String func, final Object... args) throws Exception {
        return asyncCall(new Callable() {
            @Override
            public Object call() throws Exception {
                int len = args.length;
                Object[] params = new Object[len];
                Class[] clazz = new Class[len];
                for (int i = 0; i < len; i++) {
                    params[i] = args[i];
                    clazz[i] = args[i].getClass();
                    if (clazz[i] == Double.class) {
                        clazz[i] = int.class;
                        params[i] = (int) Math.round((Double) params[i]);
                    }
                }
                if (!(o instanceof Class)) {
                    Method m = o.getClass().getDeclaredMethod(func, clazz);
                    return m.invoke(o, params);
                } else {
                    Method m = ((Class) o).getDeclaredMethod(func, clazz);
                    return m.invoke(null, params);
                }
            }
        });
    }

    public synchronized void sleep(int millSeconds) throws Exception {
        try {
            runner.setSleep(millSeconds);
            sleeper = console.threadPool.submit(runner);
            console.setEvents(q, new char[]{'q', KeyMap.CTRL_D});
            sleeper.get();
        } catch (Exception e) {
            throw CancelError;
        } finally {
            sleeper = null;
            console.setEvents(null, null);
        }
    }

    /*
        public Commander newExtProcess(String cmd) {
            return new Commander(printer,cmd,console);
        }
    */
    private class KeyListner implements ActionListener {
        int key;

        public KeyListner(int k) {
            this.key = k;
        }

        @Override
        public void actionPerformed(ActionEvent e) {
            try {
                if (e != null) key = Character.codePointAt(e.getActionCommand(), 0);
                if (sleeper != null) {
                    sleeper.cancel(true);
                }
                if (console.isRunning() && stmt != null && !stmt.isClosed()) {
                    stmt.cancel();
                }

                if (rs != null && !rs.isClosed()) rs.close();
            } catch (Exception err) {
                //getRootCause(err).printStackTrace();
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
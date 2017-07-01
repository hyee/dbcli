package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.LuaTable;
import com.opencsv.CSVReader;
import com.opencsv.CSVWriter;
import com.opencsv.ResultSetHelperService;
import com.opencsv.SQLWriter;
import org.jline.keymap.KeyMap;
import org.jline.reader.LineReaderBuilder;

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
import java.util.Arrays;
import java.util.Base64;
import java.util.concurrent.*;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;
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
    private volatile CallableStatement stmt = null;
    private Sleeper runner = new Sleeper();
    private volatile ResultSet rs;
    private IOException CancelError = new IOException("Statement is aborted.");


    public Loader() throws ExecutionException, InterruptedException {
        Future<Console> t1 = Console.threadPool.schedule(new Callable<Console>() {
            @Override
            public Console call() {
                try {
                    Console console = new Console(LineReaderBuilder.builder()
                            .terminal(Console.terminal)
                            .build());
                    //Ctrl+D
                    keyMap = console.reader.getKeys();
                    //keyMap.bind(String.valueOf(KeyMap.CTRL_D), new KeyListner(KeyMap.CTRL_D));
                    q = new KeyListner('q');
                    Interrupter.listen("loader", new EventCallback() {
                        @Override
                        public void call(Object... e) {
                            q.actionPerformed((ActionEvent) e[0]);
                        }
                    });
                    return console;
                } catch (Exception e) {
                    e.printStackTrace();
                    System.exit(0);
                }
                return null;
            }
        }, 0, TimeUnit.MILLISECONDS);
        Future<LuaState> t2 = Console.threadPool.schedule(new Callable<LuaState>() {
            @Override
            public LuaState call() {
                try {
                    File f = new File(Loader.class.getProtectionDomain().getCodeSource().getLocation().toURI());
                    root = f.getParentFile().getParent();
                    libPath = root + File.separator + "lib" + File.separator;
                    String bit = System.getProperty("sun.arch.data.model");
                    if (bit == null) bit = System.getProperty("com.ibm.vm.bitmode");
                    libPath += (bit.equals("64") ? "x64" : "x86");
                    addLibrary(libPath, true);
                    System.setProperty("library.jansi.path", libPath);

                } catch (Exception e) {
                    e.printStackTrace();
                    System.exit(0);
                }
                return new LuaState();
            }
        }, 0, TimeUnit.MILLISECONDS);
        console=t1.get();
        lua=t2.get();
        console.threadID=Thread.currentThread().getId();
    }

    public static Exception getRootCause(Exception e) {
        Throwable t = e.getCause();
        while (t != null && t.getCause() != null) t = t.getCause();
        return t == null ? e : new Exception(t);
    }

    public static void loadLua(Loader loader, String args[]) throws Exception {
        if(lua==null) lua = new LuaState();
        lua.pushGlobal("loader", loader);
        console.setLua(lua);
        if (console.writer != null) {
            lua.pushGlobal("reader", console.reader);
            lua.pushGlobal("writer", console.writer);
            lua.pushGlobal("terminal", console.terminal);
            lua.pushGlobal("console", console);
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
        ArrayList<String> list = new ArrayList<>(args.length);
        if (ReloadNextTime != null) list.add("set database " + ReloadNextTime);
        for (int i = 0; i < args.length; i++) {
            if (ReloadNextTime != null && (args[i].toLowerCase().contains(" database ") || args[i].toLowerCase().contains(" platform ")))
                continue;
            list.add(args[i]);
        }
        ReloadNextTime = null;
        lua.call(list.toArray());
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
        JavaAgent.copyFile(null, className.replace("\\.", "/"), null);
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
                writer.setRemap(o[0], o.length < 2 ? null : o[1]);
            }
        }
    }

    public int ResultSet2CSV(final ResultSet rs, final String fileName, final String header, final boolean aync, final String excludes, final String[] remaps) throws Exception {
        setCurrentResultSet(rs);
        return (int) asyncCall(() -> {
            try (CSVWriter writer = new CSVWriter(fileName)) {
                writer.setAsyncMode(aync);
                setExclusiveAndRemap(writer, excludes, remaps);
                int result = writer.writeAll(rs, true);
                return result - 1;
            }
        });
    }

    public int ResultSet2SQL(final ResultSet rs, final String fileName, final String header, final boolean aync, final String excludes, final String[] remaps) throws Exception {
        setCurrentResultSet(rs);
        return (int) asyncCall(() -> {
            try (SQLWriter writer = new SQLWriter(fileName)) {
                writer.setAsyncMode(aync);
                writer.setFileHead(header);
                setExclusiveAndRemap(writer, excludes, remaps);
                int count = writer.writeAll2SQL(rs, "", 1500);
                return count;
            }
        });
    }

    Pattern pbase = Pattern.compile("(\\S{64,64}[\n\r])%1+");

    public static byte[] hexStringToByteArray(String s) {
        int len = s.length();
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(s.charAt(i), 16) << 4)
                    + Character.digit(s.charAt(i + 1), 16));
        }
        return data;
    }

    public String Base64ZlibToText(String[] pieces) throws Exception {
        byte[] buff = new byte[]{};
        for (String piece : pieces) {
            if (piece == null) continue;
            byte[] tmp = Base64.getDecoder().decode(piece.replaceAll("\\s+", ""));
            byte[] joinedArray = Arrays.copyOf(buff, buff.length + tmp.length);
            System.arraycopy(tmp, 0, joinedArray, buff.length, tmp.length);
            buff = joinedArray;
        }
        if (buff.length == 0) return "";
        return inflate(buff);
    }

    public int CSV2SQL(final ResultSet rs, final String SQLFileName, final String CSVfileName, final String header, final String excludes, final String[] remaps) throws Exception {
        setCurrentResultSet(rs);
        return (int) asyncCall(() -> {
            try (SQLWriter writer = new SQLWriter(SQLFileName)) {
                writer.setFileHead(header);
                setExclusiveAndRemap(writer, excludes, remaps);
                return writer.writeAll2SQL(CSVfileName, rs);
            }
        });
    }

    public LuaTable fetchResult(final ResultSet rs, final int rows) throws Exception {
        if (rs.getStatement().isClosed() || rs.isClosed()) throw CancelError;
        setCurrentResultSet(rs);
        return new LuaTable((Object[]) asyncCall(new Callable() {
            @Override
            public Object[] call() throws Exception {
                try (ResultSetHelperService helper = new ResultSetHelperService(rs)) {
                    helper.IS_TRIM = false;
                    return (rows >= 0 && rows <= 10000) ? helper.fetchRows(rows) : helper.fetchRowsAsync(rows);
                }
            }
        }));
    }

    public LuaTable fetchCSV(final String CSVFileSource, final int rows) throws Exception {
        ArrayList<String[]> list = (ArrayList<String[]>) asyncCall(() -> {
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
        });
        return new LuaTable(list.toArray());
    }

    public String inflate(byte[] data) throws Exception {
        ByteArrayInputStream bis = new ByteArrayInputStream(data);
        InflaterInputStream iis;
        try {
            iis = new InflaterInputStream(bis);
        } catch (Exception e1) {
            try {
                iis = new GZIPInputStream(bis);
            } catch (Exception e2) {
                throw e1;
            }
        }

        try (Closeable c2 = iis) {
            StringBuffer sb = new StringBuffer();
            int i = 0;
            for (int c = iis.read(); c != -1; c = iis.read()) {
                sb.append((char) c);
            }
            return sb.toString();
        }
    }

    public synchronized boolean setStatement(CallableStatement p) throws Exception {
        try (Closeable clo = console::setEvents) {
            this.stmt = p;
            console.setEvents(p == null ? null : q, new char[]{'q', 'Q'});
            if (p == null) return false;
            boolean result = p.execute();
            if (p.isClosed()) throw CancelError;
            return result;
        } catch (Exception e) {
            throw e;
        } finally {
            this.stmt = null;
        }
    }

    public Object asyncCall(Callable<Object> c) throws Exception {
        try {
            this.sleeper = console.threadPool.submit(c);
            console.setEvents(q, new char[]{'q', 'Q'});
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
        return asyncCall(() -> {
            ClassAccess access = ClassAccess.access(lua.toClass(o));
            return access.invoke(o, func, args);
        });
    }

    public synchronized void sleep(int millSeconds) throws Exception {
        try (Closeable clo = console::setEvents) {
            runner.setSleep(millSeconds);
            sleeper = console.threadPool.submit(runner);
            console.setEvents(q, new char[]{'q'});
            sleeper.get();
        } catch (Exception e) {
            throw CancelError;
        } finally {
            sleeper = null;
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
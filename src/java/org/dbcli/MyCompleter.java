package org.dbcli;

import org.jline.reader.Candidate;
import org.jline.reader.LineReader;
import org.jline.reader.ParsedLine;
import org.jline.reader.impl.completer.StringsCompleter;

import java.util.*;
import java.util.concurrent.TimeUnit;

import static org.jline.builtins.Completers.TreeCompleter;
import static org.jline.builtins.Completers.TreeCompleter.Node;
import static org.jline.builtins.Completers.TreeCompleter.node;

public class MyCompleter implements org.jline.reader.Completer {

    StringsCompleter keysWordCompeleter = new StringsCompleter();
    StringsCompleter dotCompeleter = new StringsCompleter();
    TreeCompleter commandCompleter = new TreeCompleter();
    HashMap<String, Object> keywords = new HashMap<>();
    HashMap<String, HashMap<String, Boolean>> commands = new HashMap<>();
    HashMap<String, StringsCompleter> commandSet = new HashMap<>();

    Console console;


    public void reset() {
        keysWordCompeleter = new StringsCompleter();
        dotCompeleter = new StringsCompleter();
        commandCompleter = new TreeCompleter();
        keywords.clear();
        commands.clear();
    }

    public MyCompleter(Console console) {
        this.console = console;
    }

    public void loadKeyWords(final Map<String, ?> keywords, long delay) {
        console.threadPool.schedule(() -> setKeysWords(keywords), delay, TimeUnit.MILLISECONDS);
    }

    public void loadCommands(final Map<String, ?> keywords, long delay) {
        console.threadPool.schedule(() -> setCommands(keywords), delay, TimeUnit.MILLISECONDS);
    }

    HashMap<String, HashMap> values = new HashMap();

    void putKey(String key, String value) {
        Object o = values.get(key);
        if (o == null) {
            o = Boolean.TRUE;
        } else {
            o = ((HashMap) o).get(key);
            if (o instanceof Boolean) {
                o = new HashMap<String, Object>();
            }
        }
        keywords.put(key, o);
        values.put(key, keywords);
        if (value != null && o instanceof HashMap) {
            HashMap m = (HashMap<String, Object>) o;
            o = values.get(value);
            if (o == null) o = Boolean.TRUE;
            else o = ((HashMap) o).get(value);
            m.put(value, o);
            values.put(value, m);
        }
    }

    final String dot = ".";

    synchronized void setKeysWords(Map<String, ?> keywords) {
        try {
            this.keywords.clear();
            for (Map.Entry<String, ?> entry : keywords.entrySet()) {
                String key = entry.getKey().toLowerCase();
                String sub = null;
                Object value = entry.getValue();
                int pos = key.indexOf('.');
                if (pos > 0) {
                    sub = key.substring(pos + 1);
                    key = key.substring(0, pos);
                }
                if (value instanceof String) {
                    putKey(((String) value).toLowerCase(), key);
                }
                putKey(key, sub);
            }
            values.clear();
            String[] ary;
            ary = this.keywords.keySet().toArray(new String[0]);
            Arrays.sort(ary);
            Candidate[] candidates = new Candidate[ary.length];
            for (int i = 0, n = ary.length; i < n; i++) {
                Candidate c;
                if (this.keywords.get(ary[i]) instanceof HashMap)
                    c = new Candidate(ary[i], ary[i], null, null, dot, null, false);
                else
                    c = new Candidate(ary[i], ary[i], null, null, null, null, true);
                candidates[i] = c;
            }
            keysWordCompeleter = new StringsCompleter(candidates);
            keywords.clear();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    synchronized void setCommands(Map<String, ?> keywords) {
        for (Map.Entry<String, ?> entry : keywords.entrySet()) {
            String key = entry.getKey().toUpperCase();
            Object value = entry.getValue();
            HashMap<String, Boolean> map = commands.get(key);
            if (map == null) map = new HashMap<>();
            if (value instanceof Map) {
                Set<String> keys = ((Map) value).keySet();
                for (String key1 : keys) map.put(key1.toUpperCase(), true);
            }
            commands.put(key, map);
        }
        ArrayList<Node> nodes = new ArrayList<>(commands.size() + keywords.size());
        String[] list = commands.keySet().toArray(new String[0]);
        Arrays.sort(list);
        for (String e : list) {
            String key = e.toUpperCase();
            HashMap<String, Boolean> map = commands.get(e);
            if (map.size() > 0) {
                Object[] objs = new Object[map.size() + 1];
                String[] keys = map.keySet().toArray(new String[0]);
                Arrays.sort(keys);
                objs[0] = key;
                for (int i = 0; i < keys.length; i++) objs[i + 1] = node(keys[i]);
                nodes.add(node(objs));
                objs[0] = key.toLowerCase();
                nodes.add(node(objs));
                commandSet.put(key, new StringsCompleter(keys));
            } else nodes.add(node(key));
        }
        commandCompleter = new TreeCompleter(nodes.toArray(new Node[0]));
        keywords.clear();
    }

    @Override
    public void complete(LineReader lineReader, ParsedLine parsedLine, List<Candidate> list) {
        int index = parsedLine.wordIndex();
        final int prev = Math.max(0, index - 1);
        final List<String> words = parsedLine.words().subList(prev, index + 1);
        final String key = words.get(0).toUpperCase();
        index += console.parser.lines * 10;
        StringsCompleter subs;

        if ((subs = commandSet.get(key)) != null)
            subs.complete(lineReader, parsedLine, list);
        else if (index > 0) {
            Object keys;
            String k = words.get(words.size() - 1);
            if (k.equals("")) return;
            final int pos = k.lastIndexOf(dot);
            if (pos == k.length() - 1) k = k.substring(0, pos);
            String[] ary = k.split("\\.");
            int len = ary.length - 1;
            String prefix = "";
            HashMap<String, Object> map = keywords;
            for (int i = 0; i <= len; i++) {
                keys = map.get(ary[i].toLowerCase());
                if (!(keys instanceof HashMap)) break;
                map = (HashMap) keys;
                prefix += prefix.equals("") ? ary[i] : (dot + ary[i]);
                String next = i + 1 <= len ? ary[i + 1].toLowerCase() : null;
                if (next != null) {
                    if (map.get(next) instanceof HashMap) continue;
                }
                final boolean isUpper = ary[i].equals(ary[i].toUpperCase());
                for (Map.Entry<String, Object> entry : map.entrySet()) {
                    String can = entry.getKey();
                    if (isUpper) can = can.toUpperCase();
                    if (entry.getValue() instanceof HashMap) {
                        list.add(new Candidate(prefix + dot + can, dot + can, null, null, dot, null, false));
                    } else
                        list.add(new Candidate(prefix + dot + can, dot + can, null, null, null, null, true));
                }
                return;
            }
            if (pos > 0) return;
            String key1 = k.toUpperCase();
            if ((subs = commandSet.get(key1)) != null) subs.complete(lineReader, parsedLine, list);
            else keysWordCompeleter.complete(lineReader, parsedLine, list);
        } else
            commandCompleter.complete(lineReader, parsedLine, list);
    }
}

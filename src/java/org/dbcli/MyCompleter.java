package org.dbcli;

import com.naef.jnlua.util.AbstractTableMap;
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
    TreeCompleter commandCompleter = new TreeCompleter();
    HashMap<String, Object> keywords = new HashMap<>(1024);
    HashMap<String, String> groups = new HashMap<>(256);
    HashMap<String, Object> commandSet = new HashMap<>(128);
    HashMap<String, HashMap<String, Boolean>> commands = new HashMap<>();
    Console console;
    String defaultSchema = null;
    String quote = "\"";
    Candidate[] candidates;

    public void reset() {
        synchronized (this.commands) {
            commandCompleter = new TreeCompleter();
            commands.clear();
        }
        resetKeywords();
    }

    public void resetKeywords() {
        synchronized (this.keywords) {
            keysWordCompeleter = new StringsCompleter();
            keywords.clear();
            groups.clear();
            values.clear();
            defaultSchema = null;
            quote = "\"";
            candidates = null;
        }
    }

    public MyCompleter(Console console) {
        this.console = console;
    }

    public void loadKeyWords(final Map<String, ?> keywords, long delay) {
        Console.threadPool.schedule(() -> setKeysWords(keywords), delay, TimeUnit.MILLISECONDS);
    }

    public void loadCommands(final Map<String, ?> keywords, long delay) {
        Console.threadPool.schedule(() -> setCommands(keywords), delay, TimeUnit.MILLISECONDS);
    }

    public void renameCommands(String[] oldNames, String[] newNames) {

    }

    //command is used to complete the leading words of a command line
    void setCommands(Map<String, ?> keywords) {
        synchronized (this.commands) {
            try {
                for (Map.Entry<String, ?> entry : keywords.entrySet()) {
                    String key = entry.getKey().toUpperCase();
                    if (key.contains(" ")) continue;
                    Object value = entry.getValue();
                    HashMap<String, Boolean> map = commands.get(key);
                    if (map == null) map = new HashMap<>();
                    if (value instanceof Map) {
                        Set<String> keys = ((Map) value).keySet();
                        for (String key1 : keys) {
                            map.put(key1.toUpperCase(), true);
                        }
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
                        commandSet.put(key, 1);
                        Object[] objs = new Object[map.size() + 1];
                        String[] keys = map.keySet().toArray(new String[0]);
                        Arrays.sort(keys);
                        objs[0] = key;
                        for (int i = 0; i < keys.length; i++) objs[i + 1] = node(keys[i]);
                        nodes.add(node(objs));
                    } else nodes.add(node(key));
                }
                commandCompleter = new TreeCompleter(nodes.toArray(new Node[0]));
                keywords.clear();
            } catch (Exception e) {
                e.printStackTrace();
            }

            if (keywords instanceof AbstractTableMap)
                ((AbstractTableMap) keywords).unRef();
        }
    }


    //keyword completer is triggered since the 2nd word of a command line, such as object name and function name
    final String dot = ".";
    final String re = "\\" + dot;
    HashMap<String, HashMap> values = new HashMap();

    void putKey(String key, String value) {
        Object o = values.get(key);
        if (o == null && (o = keywords.get(key)) == null) {
            o = value;
        } else {
            if (o.equals(value)) return;
            if (o instanceof HashMap)
                o = ((HashMap) o).get(key);
            if (o instanceof String && !value.equals("\1")) {
                o = new HashMap<String, Object>();
            }
        }
        keywords.put(key, o);
        values.put(key, keywords);
        if (!value.equals("\1") && o instanceof HashMap) {
            HashMap m = (HashMap<String, Object>) o;
            o = values.get(value);
            if (o == null) o = value;
            else o = ((HashMap) o).get(value);
            m.put(value, o);
            values.put(value, m);
        }
    }

    void setKeysWords(Map<String, ?> keywords) {
        synchronized (this.keywords) {
            try {
                for (Map.Entry<String, ?> entry : keywords.entrySet()) {
                    String key = entry.getKey();
                    if (key.length() < 3 || key.contains(" ")) continue;
                    Object value = entry.getValue();
                    String[] ary = key.toLowerCase().split(re);
                    if (value instanceof String)
                        putKey(((String) value).toLowerCase(), ary[0]);
                    for (int i = 0, n = ary.length - 1, m = n - (n > 0 ? 1 : 0); i <= m; i++)
                        putKey(ary[i], i == n ? "\1" : ary[i + 1]);
                }
                //values.clear();
                keywords.clear();
                groups.clear();
                candidates = new Candidate[this.keywords.size()];
                int seq = 0;
                for (Map.Entry<String, Object> entry : this.keywords.entrySet()) {
                    final String key = entry.getKey();
                    final Object value = entry.getValue();
                    if (value instanceof HashMap) {
                        candidates[seq] = new Candidate(key, key, null, null, null, null, false);
                        String[] keys = ((HashMap<String, Object>) value).keySet().toArray(new String[0]);
                        Arrays.sort(keys);
                        String prev = null;
                        for (int j = 0, m = keys.length; j < m; j++) {
                            //if the sibling key contains prev key, then cheat prev key as possible multiple candidates
                            if (prev != null && keys[j].startsWith(prev) && this.keywords.get(key) != null)
                                groups.put(prev, keys[j]);
                            prev = keys[j];
                        }
                    } else {
                        candidates[seq] = new Candidate(key, key, null, null, null, null, true);
                    }
                    ++seq;
                }
                keysWordCompeleter = new StringsCompleter(candidates);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    @Override
    public void complete(LineReader lineReader, ParsedLine parsedLine, List<Candidate> list) {
        int index = parsedLine.wordIndex();
        final int prev = Math.max(0, index - 1);
        final List<String> words = parsedLine.words().subList(prev, index + 1);
        final String key = words.get(0).toUpperCase();

        index += console.parser.lines * 10;
        if (index == 1 && commandSet.get(key) != null) {
            commandCompleter.complete(lineReader, parsedLine, list);
        } else if (index > 0) {
            String k = words.get(words.size() - 1);
            if (k.equals("")) return;
            int pos = k.lastIndexOf(dot);
            boolean doted = false;
            if (pos == k.length() - 1) {
                k = k.substring(0, pos);
                doted = true;
            } else if (pos < 0 && groups.get(k.toLowerCase()) != null) {
                keysWordCompeleter.complete(lineReader, parsedLine, list);
                return;
            }

            String[] ary = k.split(re);
            int len = ary.length - 1;
            String prefix = "";
            String next;
            Object keys;
            HashMap<String, Object> map = keywords;
            String sep;
            boolean usedefaultSchema = false;
            for (int i = 0; i <= len; i++) {
                if (ary[i].startsWith(quote) && ary[i].endsWith(quote))
                    ary[i] = ary[i].substring(1, ary[i].length() - 1);
                keys = map.get(ary[i].toLowerCase());
                sep = dot;
                if (!(keys instanceof HashMap)) {
                    if (i == 0 && pos == -1 && defaultSchema != null && !defaultSchema.equals("")) {
                        keys = map.get(defaultSchema.toLowerCase());
                        if (keys instanceof HashMap) {
                            k = defaultSchema + "." + k;
                            ary = k.split(re);
                            ++len;
                            ++pos;
                            sep = "";
                            usedefaultSchema = true;
                        } else break;
                    } else break;
                } else {
                    usedefaultSchema = false;
                    prefix += (prefix.equals("") ? ary[i] : (dot + ary[i]));
                }
                map = (HashMap) keys;
                next = i + 1 <= len ? ary[i + 1].toLowerCase() : null;
                if (next != null && map.get(next) instanceof HashMap) {
                    if (!doted && i + 1 == len && groups.containsKey(next)) {
                        //skip if there are similar matches
                    } else continue;
                }
                final boolean isUpper = ary[i].equals(ary[i].toUpperCase());
                for (Map.Entry<String, Object> entry : map.entrySet()) {
                    String can = entry.getKey();
                    if (isUpper) can = can.toUpperCase();
                    if (entry.getValue() instanceof HashMap) {
                        list.add(new Candidate(prefix + sep + can, sep + can, null, null, sep, null, false));
                    } else
                        list.add(new Candidate(prefix + sep + can, sep + can, null, null, null, null, true));
                }
                if (!usedefaultSchema) return;
            }
            if (pos > 0) return;
            keysWordCompeleter.complete(lineReader, parsedLine, list);
        } else {
            commandCompleter.complete(lineReader, parsedLine, list);
        }
    }
}

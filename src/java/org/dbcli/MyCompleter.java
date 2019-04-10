package org.dbcli;

import org.jline.reader.Candidate;
import org.jline.reader.LineReader;
import org.jline.reader.ParsedLine;
import org.jline.reader.impl.completer.StringsCompleter;

import java.util.*;

import static org.jline.builtins.Completers.TreeCompleter;
import static org.jline.builtins.Completers.TreeCompleter.Node;
import static org.jline.builtins.Completers.TreeCompleter.node;

public class MyCompleter implements org.jline.reader.Completer {

    StringsCompleter keysWordCompeleter = new StringsCompleter();
    TreeCompleter commandCompleter = new TreeCompleter();
    HashMap<String, Boolean> keywords = new HashMap<>();
    HashMap<String, HashMap<String, Boolean>> commands = new HashMap<>();
    HashMap<String, StringsCompleter> commandSet = new HashMap<>();

    Console console;

    public MyCompleter(Console console) {
        this.console = console;
    }

    void setKeysWords(Map<String, ?> keywords) {
        this.keywords = new HashMap<>();
        Set<String> keys = keywords.keySet();
        for (String key : keys) {
            this.keywords.put(key.toLowerCase(), true);
            if (key.contains(".")) {
                String[] piece = key.toLowerCase().split("\\.");
                if (piece.length > 1) {
                    this.keywords.put(piece[1], true);
                }
            }
        }
        String[] ary = this.keywords.keySet().toArray(new String[0]);
        Arrays.sort(ary);
        keysWordCompeleter = new StringsCompleter(ary);
    }

    void setCommands(Map<String, ?> keywords) {
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
    }

    @Override
    public void complete(LineReader lineReader, ParsedLine parsedLine, List<Candidate> list) {
        int index = parsedLine.wordIndex();
        final int prev = Math.max(0, index - 1);
        final List<String> words = parsedLine.words().subList(prev, index + 1);
        final String key = words.get(0).toUpperCase();
        index += console.parser.lines * 10;
        StringsCompleter subs;
        //System.out.println(key+","+words.get(words.size() - 1).toUpperCase());
        if ((subs = commandSet.get(key)) != null)
            subs.complete(lineReader, parsedLine, list);
        else if (index > 0) {
            final String key1 = words.get(words.size() - 1).toUpperCase();
            if (key1.equals("")) return;
            if ((subs = commandSet.get(key1)) != null) subs.complete(lineReader, parsedLine, list);
            else keysWordCompeleter.complete(lineReader, parsedLine, list);
        } else
            commandCompleter.complete(lineReader, parsedLine, list);
    }
}

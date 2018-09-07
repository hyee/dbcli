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
    HashMap<String, TreeCompleter> trees = new HashMap<>();
    HashMap<String, Boolean> keywords = new HashMap<>();
    HashMap<String, HashMap<String, Boolean>> commands = new HashMap<>();

    void setKeysWords(Map<String, ?> keywords) {
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
        keysWordCompeleter = new StringsCompleter(this.keywords.keySet());
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
        for (Map.Entry<String, HashMap<String, Boolean>> e : commands.entrySet()) {
            String key = e.getKey().toUpperCase();
            HashMap<String, Boolean> map = e.getValue();
            if (map.size() > 0) {
                Object[] objs = new Object[map.size() + 1];
                String[] keys = map.keySet().toArray(new String[0]);
                objs[0] = key;
                for (int i = 0; i < keys.length; i++) objs[i + 1] = node(keys[i]);
                nodes.add(node(objs));
                objs[0] = key.toLowerCase();
                nodes.add(node(objs));
            } else nodes.add(node(key));
        }
        commandCompleter = new TreeCompleter(nodes.toArray(new Node[0]));
    }

    @Override
    public void complete(LineReader lineReader, ParsedLine parsedLine, List<Candidate> list) {
        final int index = parsedLine.wordIndex();
        final int prev = Math.max(0, index - 1);
        final List<String> words = parsedLine.words().subList(prev, index + 1);
        final String key = words.get(0).toUpperCase();
        if (index == 1 && commands.get(key) != null && commands.get(key).size() > 0)
            commandCompleter.complete(lineReader, parsedLine, list);
        else if (index > 0) {
            if (words.get(index).equals("")) return;
            keysWordCompeleter.complete(lineReader, parsedLine, list);
        } else
            commandCompleter.complete(lineReader, parsedLine, list);
         /*
         ArrayList<Candidate> cans=new ArrayList<>();
         if(cans.size()<=100) {
             Collections.copy(list,cans);
         } else {

             for(int i=0;i<=100;i++) list.add(cans.get(i));
             list.add(new Candidate(words[words.length - 1].trim() + "|..."));
         }*/
    }
}

package org.dbcli;
import org.jline.builtins.Completers;
import org.jline.reader.Candidate;
import org.jline.reader.LineReader;
import org.jline.reader.ParsedLine;
import org.jline.reader.impl.completer.StringsCompleter;
import static org.jline.builtins.Completers.TreeCompleter.node;
import static org.jline.builtins.Completers.TreeCompleter.Node;

import java.util.*;

public class MyCompleter  implements org.jline.reader.Completer {
    StringsCompleter keysWordCompeleter=new StringsCompleter();
    Completers.TreeCompleter commandCompleter=new Completers.TreeCompleter();
    HashMap<String,Boolean> keywords=new HashMap<>();
    HashMap<String,HashMap<String,Boolean>> commands=new HashMap<>();
    void setKeysWords(Map<String, ?> keywords) {
        Set<String> keys=keywords.keySet();
        for(String key:keys) {
            this.keywords.put(key.toLowerCase(),true);
            if(key.contains(".")) {
                String[] piece=key.toLowerCase().split("\\.");
                if(piece.length>1) {
                    this.keywords.put(piece[1],true);
                }
            }
        }
        keysWordCompeleter=new StringsCompleter(this.keywords.keySet());
    }

    void setCommands(Map<String, ?> keywords) {
        for (Map.Entry<String, ?> entry : keywords.entrySet()) {
            String key=entry.getKey();
            Object value = entry.getValue();
            HashMap<String,Boolean> map=commands.get(key);
            if(map==null)  map=new HashMap<>();
            if(value instanceof Map) {
                Set<String> keys=((Map) value).keySet();
                for(String key1:keys) {
                    map.put(key1,true);
                }
            }
            commands.put(key,map);
        }
        ArrayList<Node> nodes=new ArrayList<>(commands.size()+keywords.size());
        for(Map.Entry<String,HashMap<String,Boolean>> e:commands.entrySet()) {
            String key=e.getKey();
            HashMap<String,Boolean> map=e.getValue();
            if(map.size()==0) nodes.add(node(key));
            else {
                for(String key1:map.keySet()) {
                    nodes.add(node(key+" "+key1));
                }
            }
        }
        commandCompleter=new Completers.TreeCompleter(nodes.toArray(new Node[nodes.size()]));
    }

    @Override
    public void complete(LineReader lineReader, ParsedLine parsedLine, List<Candidate> list) {
        int index = parsedLine.wordIndex();
        int prev = Math.max(0, index - 1);
        ArrayList<Candidate> cans=new ArrayList<>();
        if (index > 0)
            keysWordCompeleter.complete(lineReader,parsedLine,list);
         else
            commandCompleter.complete(lineReader,parsedLine,list);
         /*
         if(cans.size()<=100) {
             Collections.copy(list,cans);
         } else {
             String[] words = parsedLine.words().subList(prev, index + 1).toArray(new String[0]);
             for(int i=0;i<=100;i++) list.add(cans.get(i));
             list.add(new Candidate(words[words.length - 1].trim() + "|..."));
         }*/
    }
}

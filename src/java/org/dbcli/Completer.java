package org.dbcli;

import org.jline.reader.Candidate;
import org.jline.reader.LineReader;
import org.jline.reader.ParsedLine;

import java.util.List;
import java.util.SortedMap;
import java.util.SortedSet;
import java.util.TreeMap;

public class Completer implements org.jline.reader.Completer {
    public TreeMap<String, Candidate[]> candidates = new TreeMap();

    @Override
    public void complete(LineReader lineReader, ParsedLine parsedLine, List<Candidate> list) {
        int index = parsedLine.wordIndex();
        int prev = Math.max(0, index - 1);
        SortedSet set = candidates.navigableKeySet();
        SortedMap<String, Candidate[]> result = null;
        String[] words = parsedLine.words().subList(prev, index + 1).toArray(new String[0]);
        String k1 = words[0].toUpperCase().trim();
        String k2 = index == 0 ? k1 : words[1].toUpperCase().trim();
        if (index > 0) {
            String key = k1 + " " + k2;
            result = candidates.subMap(key, key + "ZZZZ");
            if (result.size() == 0) {
                if (candidates.subMap(k1 + " ", k1 + " ZZZZ").size() > 0) return;
            }
        }

        if (result == null || result.size() == 0) result = candidates.subMap(k2, k2 + "ZZZZ");
        boolean isUpper = k2 == words[words.length - 1].trim();
        if (k2 != k1 && k2.equals("")) isUpper = k1 == words[0].trim();

        int counter = 0;
        for (Candidate[] c : result.values()) {
            if (index == 0 && c[2] != null || index > 0) {
                list.add(isUpper ? c[0] : c[1]);
                ++counter;
            }
            if (counter >= 100) {
                list.add(new Candidate(words[words.length - 1].trim() + "|..."));
                break;
            }
        }
    }
}

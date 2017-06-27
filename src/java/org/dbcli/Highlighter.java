/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */
package org.dbcli;

import org.apache.felix.gogo.runtime.EOFError;
import org.apache.felix.gogo.runtime.Parser.Program;
import org.apache.felix.gogo.runtime.Parser.Statement;
import org.apache.felix.gogo.runtime.SyntaxError;
import org.apache.felix.gogo.runtime.Token;
import org.jline.reader.LineReader;
import org.jline.reader.LineReader.RegionType;
import org.jline.reader.impl.DefaultHighlighter;
import org.jline.utils.AttributedString;
import org.jline.utils.AttributedStringBuilder;
import org.jline.utils.AttributedStyle;
import org.jline.utils.WCWidth;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

public class Highlighter extends DefaultHighlighter {
    public static final String DEFAULT_HIGHLIGHTER_COLORS = "rs=1:st=2:nu=3:co=4:va=5:vn=6:fu=7:bf=8:re=9";
    public String ansi=null;
    public String buffer=null;
    int adj=0;
    public static final Pattern numPattern=Pattern.compile("^^-?\\d+([,\\.]\\d+)?([eE]-?\\d+)?$$");
    public static Map<String, String> colors = Arrays.stream(DEFAULT_HIGHLIGHTER_COLORS.split(":"))
            .collect(Collectors.toMap(s -> s.substring(0, s.indexOf('=')),
                    s -> s.substring(s.indexOf('=') + 1)));
    public Map<String,Integer> keywords=new HashMap();
    public Map<String,Map> commands=new HashMap();
    boolean enabled=true;

    public void setAnsi(String ansi) {
        if(ansi.equals(this.ansi)) return;
        this.ansi=ansi;
        enabled=!ansi.equals("\33[0m");
        for(String key:colors.keySet()) {
            String value;
            switch (key) {
                case "bf": value="\33[91m";break;
                case "fu": value=ansi; break;
                case "rs": value="\33[95m"; break;
                default: value=ansi; break;
            }
            colors.put(key,value);
        }
    }

    public Highlighter() {
        setAnsi("\033[0m");
    }
    Pattern p= Pattern.compile("(\\S+)(.*)");

    public AttributedString highlight(LineReader reader, String buffer) {
        AttributedStringBuilder sb = new AttributedStringBuilder();
        Matcher m=p.matcher(buffer);
        if(enabled&&m.find()) {
            if(!commands.containsKey(m.group(1).toUpperCase())) {
                sb.appendAnsi("\33[91m");
                sb.append(m.group(1));
                sb.appendAnsi(ansi);
                sb.append(m.group(2));
            } else {
                sb.appendAnsi(ansi);
                sb.append(buffer);
            }
        } else sb.append(buffer);
        return sb.toAttributedString();
    }

    private void applyStyle(AttributedStringBuilder sb, Map<String, String> colors, Type type) {
        String col = colors.get(type.color);
        if (col != null && !col.isEmpty()) {
            sb.appendAnsi(col);
        } else sb.appendAnsi(ansi);
    }

    enum Type {
        Reserved("rs"),
        String("st"),
        Number("nu"),
        Variable("va"),
        VariableName("vn"),
        Function("fu"),
        BadFunction("bf"),
        Constant("co"),
        Unknown("un"),
        Repair("re");

        private final String color;

        Type(String color) {
            this.color = color;
        }
    }

}

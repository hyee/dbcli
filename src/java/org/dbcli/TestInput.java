package org.dbcli;

import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
public class TestInput {
    public static void main(String[] args) throws Exception {
        Terminal terminal=TerminalBuilder.builder().system(true).exec(true).jansi(true).build();
        boolean exit=false;
        while (!exit) {
            System.out.write("Input: ".getBytes());
            while(true) {
                int c = System.in.read(); //Don't use JLine3 as reader
                if(c==10) break;
                if((char)c=='q') {
                    exit=true;
                    break;
                }
            }
        }
    }
}

package org.dbcli;

import org.jline.reader.LineReaderBuilder;
import org.jline.reader.impl.LineReaderImpl;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.jline.utils.AttributedStringBuilder;

/**
 * Created by Will on 2017/6/25.
 */
public class TestAnsi {
    public static void main(String[] args) throws Exception {
        //Prompt color:  High Intensity Foreground Color: Yellow
        String HIY = "\33[33;1m";
        //Command color: High Intensity Foreground Color: Cyan
        String HIC = "\33[36;1m";
        //reset colors
        String NOR = "\33[0m";


        Terminal terminal = TerminalBuilder.builder().system(true).nativeSignals(true).signalHandler(Terminal.SignalHandler.SIG_IGN).exec(true).jansi(true).build();
        LineReaderImpl reader = (LineReaderImpl) LineReaderBuilder.builder().terminal(terminal).build();
        reader.setHighlighter((reader1, buffer) -> {
            AttributedStringBuilder sb = new AttributedStringBuilder();
            sb.appendAnsi(HIC);
            sb.append(buffer);
            //sb.append(NOR);
            return sb.toAttributedString();
        });

        //Terminal output
        terminal.writer().println(String.format("%s  prompt>%s %sthis is terminal output line%s\n", HIY, NOR, HIC, NOR));
        terminal.writer().flush();

        reader.readLine(String.format("%s  prompt>%s ", HIY, NOR));

        /* // Same to above line
        String prompt = new AttributedStringBuilder()
                .style(AttributedStyle.DEFAULT.foreground(AttributedStyle.YELLOW))
                .style(AttributedStyle.BOLD)
                .append("  prompt>")
                .style(AttributedStyle.DEFAULT)
                .append("  ").toAnsi();
        reader.readLine(prompt);
        */
    }
}

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Pattern;

import org.jline.utils.Curses;
import org.jline.utils.InfoCmp;
import org.jline.utils.InfoCmp.Capability;

public class CapsDump
{
  static final String E = "\u001b";

  static int fails;

  static final List<String> LABELS = new ArrayList<>();

  static final Set<String> DECLARED = new TreeSet<>();

  static final String INPUT_LEG =
      "input leg: those bytes come from a console record matched against a KeyMap prefix, never from a caps "
      + "lookup (DESIGN section 4 rules the whole family not this library's surface)";
  static final String NO_STRING =
      "number or boolean: there is no string for tputs to decode, and the value is asserted where it is used";
  static final String SIBLING =
      "single-arm string this leg only ever reaches inside a sibling expectation (sgr, or the cursor family), "
      + "so its bytes are pinned indirectly and not by name";

  static final Map<String, String> NO_EXPECTATION = new LinkedHashMap<>();

  static void silent( String reason, String... names )
  {
    for ( String n : names )
      NO_EXPECTATION.put( n, reason );
  }

  static
  {
    silent( NO_STRING, "colors", "cols", "it", "lines", "msgr" );
    silent( INPUT_LEG, "kcub1", "kcud1", "kcuf1", "kcuu1", "kdch1", "kich1", "kend", "khome", "knp", "kpp",
            "kf1", "kf2", "kf3", "kf4", "kf5", "kf6", "kf7", "kf8", "kf9", "kf10", "kf11", "kf12" );
    silent( SIBLING, "bold", "rev", "smso", "smul", "cvvis", "home",
            "cub", "cub1", "cuf", "cuf1", "cuu", "cuu1", "il1", "dl1" );
  }

  static String show( String s )
  {
    if ( s == null )
      return "null";
    StringBuilder b = new StringBuilder( s.length() + 8 );
    for ( int i = 0; i < s.length(); i++ )
    {
      char c = s.charAt( i );
      if ( c == 27 )
        b.append( "<e>" );
      else if ( c == '\n' )
        b.append( "<n>" );
      else if ( c == '\r' )
        b.append( "<r>" );
      else if ( c == '\t' )
        b.append( "<t>" );
      else if ( c == 8 )
        b.append( "<b>" );
      else if ( c == 7 )
        b.append( "<g>" );
      else
        b.append( c );
    }
    return b.toString();
  }

  static void expect( String what, Object got, Object want )
  {
    LABELS.add( what );
    boolean ok = want == null ? got == null : want.equals( got );
    if ( !ok )
      fails++;
    System.out.printf( "%-4s %-44s got=%-40s want=%s%n", ok ? "ok" : "FAIL", what, show( "" + got ), show( "" + want ) );
  }

  static String raw( Map<Capability, String> strs, Capability c )
  {
    return strs.get( c );
  }

  public static void main( String[] args ) throws Exception
  {
    String text = new String( Files.readAllBytes( Paths.get( args[0] ) ), StandardCharsets.UTF_8 );
    Set<Capability> bools = EnumSet.noneOf( Capability.class );
    Map<Capability, Integer> ints = new EnumMap<>( Capability.class );
    Map<Capability, String> strs = new EnumMap<>( Capability.class );
    InfoCmp.parseInfoCmp( text, bools, ints, strs );

    System.out.println( "--- parsed (file spelling, nothing decoded) ---" );
    System.out.println( "bools : " + new TreeSet<>( bools ) );
    System.out.println( "ints  : " + ints );
    for ( Capability c : new TreeSet<>( strs.keySet() ) )
      System.out.println( "  " + c + " = " + show( strs.get( c ) ) );

    System.out.println( "--- keys the parser could not resolve (must be empty) ---" );
    Map<String, Capability> byName = InfoCmp.getCapabilitiesByName();
    int from = text.indexOf( '\n' ) + 1;
    for ( String line : text.substring( from ).split( "\n" ) )
      for ( String tok : line.split( "," ) )
      {
        String k = tok.trim();
        int i = k.indexOf( '=' );
        int h = k.indexOf( '#' );
        if ( i >= 0 )
          k = k.substring( 0, i ).trim();
        else if ( h >= 0 )
          k = k.substring( 0, h ).trim();
        if ( !k.matches( "[a-z_0-9]+" ) )
          continue;
        DECLARED.add( k );
        if ( !byName.containsKey( k ) )
          System.out.println( "  UNRESOLVED: " + k );
      }

    System.out.println( "--- assertions on the file spelling ---" );
    expect( "csr (Status gate: must exist)", raw( strs, Capability.change_scroll_region ), "\\E[%i%p1%d;%p2%dr" );
    expect( "sc (Status gate)", raw( strs, Capability.save_cursor ), "\\E7" );
    expect( "rc (Status gate)", raw( strs, Capability.restore_cursor ), "\\E8" );
    expect( "cup (Status gate)", raw( strs, Capability.cursor_address ), "\\E[%i%p1%d;%p2%dH" );
    expect( "Status.isSupported needs all four", raw( strs, Capability.change_scroll_region ) != null
                                                && raw( strs, Capability.save_cursor ) != null
                                                && raw( strs, Capability.restore_cursor ) != null
                                                && raw( strs, Capability.cursor_address ) != null, true );
    expect( "am advertised", bools.contains( Capability.auto_right_margin ), true );
    expect( "xenl NOT advertised (wrap is immediate)", bools.contains( Capability.eat_newline_glitch ), false );
    expect( "bce advertised", bools.contains( Capability.back_color_erase ), true );
    expect( "mir NOT advertised (IRM has no body)", bools.contains( Capability.move_insert_mode ), false );
    expect( "in NOT advertised", bools.contains( Capability.insert_null_glitch ), false );
    expect( "mc5i NOT advertised", bools.contains( Capability.prtr_silent ), false );
    expect( "ncv NOT advertised", ints.get( Capability.no_color_video ), null );
    expect( "max_colors", ints.get( Capability.max_colors ), 256 );
    expect( "init_tabs", ints.get( Capability.init_tabs ), 8 );
    expect( "cbt advertised (the Shift-Tab name a reader binds)", raw( strs, Capability.back_tab ), "\\E[Z" );
    expect( "hts NOT advertised (no reader; CEAnsi drops ESC H)", raw( strs, Capability.set_tab ), null );
    expect( "tbc NOT advertised (no reader; CEAnsi drops CSI 3g)", raw( strs, Capability.clear_all_tabs ), null );
    expect( "smacs", raw( strs, Capability.enter_alt_charset_mode ), "\\E(0" );
    expect( "rmacs", raw( strs, Capability.exit_alt_charset_mode ), "\\E(B" );
    expect( "acsc pairs (xterm's identity map)", raw( strs, Capability.acs_chars ).length() / 2, 26 );
    expect( "smcup", raw( strs, Capability.enter_ca_mode ), "\\E[?1049h\\E[22;0;0t" );
    expect( "rmcup", raw( strs, Capability.exit_ca_mode ), "\\E[?1049l\\E[23;0;0t" );
    expect( "cnorm (no ?12 noise)", raw( strs, Capability.cursor_normal ), "\\E[?25h" );
    expect( "civis", raw( strs, Capability.cursor_invisible ), "\\E[?25l" );
    expect( "smkx NOT advertised (input is console records)", raw( strs, Capability.keypad_xmit ), null );
    expect( "rmkx NOT advertised", raw( strs, Capability.keypad_local ), null );
    expect( "flash NOT advertised (reads fall back to bel)", raw( strs, Capability.flash_screen ), null );
    expect( "u6 (the answer's shape, with %i)", raw( strs, Capability.user6 ), "\\E[%i%d;%dR" );
    expect( "u7 (the query)", raw( strs, Capability.user7 ), "\\E[6n" );
    expect( "kmous (the X10 prefix the default family sends; xterm-256color declares \\E[<, the SGR prefix -- a deliberate divergence)", raw( strs, Capability.key_mouse ), "\\E[M" );
    expect( "initc NOT advertised", raw( strs, Capability.initialize_color ), null );
    expect( "ccc NOT advertised", bools.contains( Capability.can_change ), false );
    expect( "smam NOT advertised", raw( strs, Capability.enter_am_mode ), null );
    expect( "rmam NOT advertised", raw( strs, Capability.exit_am_mode ), null );
    expect( "ich1 (Display line editing)", raw( strs, Capability.insert_character ), "\\E[@" );
    expect( "dch1 (Display line editing)", raw( strs, Capability.delete_character ), "\\E[P" );
    expect( "parm_ich", raw( strs, Capability.parm_ich ), "\\E[%p1%d@" );
    expect( "parm_dch", raw( strs, Capability.parm_dch ), "\\E[%p1%dP" );
    expect( "ech", raw( strs, Capability.erase_chars ), "\\E[%p1%dX" );
    expect( "rep", raw( strs, Capability.repeat_char ), "%p1%c\\E[%p2%{1}%-%db" );
    expect( "indn", raw( strs, Capability.parm_index ), "\\E[%p1%dS" );
    expect( "rin", raw( strs, Capability.parm_rindex ), "\\E[%p1%dT" );
    expect( "ri", raw( strs, Capability.scroll_reverse ), "\\EM" );
    expect( "nel", raw( strs, Capability.newline ), "\\EE" );
    expect( "vpa", raw( strs, Capability.row_address ), "\\E[%i%p1%dd" );
    expect( "hpa", raw( strs, Capability.column_address ), "\\E[%i%p1%dG" );
    expect( "el1", raw( strs, Capability.clr_bol ), "\\E[1K" );
    expect( "clear", raw( strs, Capability.clear_screen ), "\\E[H\\E[2J" );
    expect( "ed", raw( strs, Capability.clr_eos ), "\\E[J" );
    expect( "el", raw( strs, Capability.clr_eol ), "\\E[K" );
    expect( "rmso turns reverse off", raw( strs, Capability.exit_standout_mode ), "\\E[27m" );
    expect( "rmul turns underline off", raw( strs, Capability.exit_underline_mode ), "\\E[24m" );
    expect( "setaf (xterm 3-tier)", raw( strs, Capability.set_a_foreground ), "\\E[%?%p1%{8}%<%t3%p1%d%e%p1%{16}%<%t9%p1%{8}%-%d%e38;5;%p1%d%;m" );
    expect( "setab (xterm 3-tier)", raw( strs, Capability.set_a_background ), "\\E[%?%p1%{8}%<%t4%p1%d%e%p1%{16}%<%t10%p1%{8}%-%d%e48;5;%p1%d%;m" );
    expect( "op", raw( strs, Capability.orig_pair ), "\\E[39;49m" );
    expect( "sgr0", raw( strs, Capability.exit_attribute_mode ), "\\E(B\\E[m" );
    expect( "blink NOT advertised", raw( strs, Capability.enter_blink_mode ), null );
    expect( "invis NOT advertised", raw( strs, Capability.enter_secure_mode ), null );
    expect( "rmpch NOT advertised", raw( strs, Capability.exit_pc_charset_mode ), null );
    expect( "sgr drops blink/invis/font", raw( strs, Capability.set_attributes ),
           "\\E[0%?%p6%t;1%;%?%p2%t;4%;%?%p1%p3%|%t;7%;m" );
    expect( "il", raw( strs, Capability.parm_insert_line ), "\\E[%p1%dL" );
    expect( "dl", raw( strs, Capability.parm_delete_line ), "\\E[%p1%dM" );
    expect( "cud1 is a CSI, not a newline (owner ruling 2026-10-05: back from the xterm alignment)", raw( strs, Capability.cursor_down ), "\\E[B" );

    System.out.println( "--- what reaches the terminal ---" );
    expect( "csr(0,23) whole page", Curses.tputs( raw( strs, Capability.change_scroll_region ), 0, 23 ), E + "[1;24r" );
    expect( "csr(0,22) one status line", Curses.tputs( raw( strs, Capability.change_scroll_region ), 0, 22 ), E + "[1;23r" );
    expect( "csr(0,0) Status.reset()", Curses.tputs( raw( strs, Capability.change_scroll_region ), 0, 0 ), E + "[1;1r" );
    expect( "cup(5,10)", Curses.tputs( raw( strs, Capability.cursor_address ), 5, 10 ), E + "[6;11H" );
    /* The wire layer is the layer that decides behaviour, and for this pair it is the only one that matters:
       Status.update()'s grow branch emits cursor_down while standing on the last row, so a cud1 that decodes
       to LF scrolls the viewport there and a CSI does not. The file-spelling leg above cannot tell those two
       apart -- that is exactly the difference this entry went through on 2026-10-05 and no gate saw. */
    expect( "cud1 bytes are a CSI, so a down-move at the bottom does not scroll",
            Curses.tputs( raw( strs, Capability.cursor_down ) ), E + "[B" );
    expect( "cud(2) bytes", Curses.tputs( raw( strs, Capability.parm_down_cursor ), 2 ), E + "[2B" );
    expect( "hpa(0) is 1-based after %i", Curses.tputs( raw( strs, Capability.column_address ), 0 ), E + "[1G" );
    expect( "vpa(3)", Curses.tputs( raw( strs, Capability.row_address ), 3 ), E + "[4d" );
    expect( "ich(1)", Curses.tputs( raw( strs, Capability.parm_ich ), 1 ), E + "[1@" );
    expect( "dch(2)", Curses.tputs( raw( strs, Capability.parm_dch ), 2 ), E + "[2P" );
    expect( "ich1()", Curses.tputs( raw( strs, Capability.insert_character ) ), E + "[@" );
    expect( "setaf(3) first arm", Curses.tputs( raw( strs, Capability.set_a_foreground ), 3 ), E + "[33m" );
    expect( "setaf(9) second arm", Curses.tputs( raw( strs, Capability.set_a_foreground ), 9 ), E + "[91m" );
    expect( "setaf(196) third arm", Curses.tputs( raw( strs, Capability.set_a_foreground ), 196 ), E + "[38;5;196m" );
    expect( "setab(1) first arm", Curses.tputs( raw( strs, Capability.set_a_background ), 1 ), E + "[41m" );
    expect( "smacs bytes", Curses.tputs( raw( strs, Capability.enter_alt_charset_mode ) ), E + "(0" );
    expect( "rmacs bytes", Curses.tputs( raw( strs, Capability.exit_alt_charset_mode ) ), E + "(B" );
    expect( "ind bytes", Curses.tputs( raw( strs, Capability.scroll_forward ) ), "\n" );
    expect( "cr bytes", Curses.tputs( raw( strs, Capability.carriage_return ) ), "\r" );
    expect( "ht bytes", Curses.tputs( raw( strs, Capability.tab ) ), "\t" );
    expect( "kbs bytes", Curses.tputs( raw( strs, Capability.key_backspace ) ), "\b" );
    expect( "cbt bytes are the bytes the key leg sends", Curses.tputs( raw( strs, Capability.back_tab ) ),
            E + "[Z" );
    expect( "kcbt bytes are the same three bytes", Curses.tputs( raw( strs, Capability.key_btab ) ), E + "[Z" );
    expect( "rep(0x78,4) writes x then three repeats", Curses.tputs( raw( strs, Capability.repeat_char ), 0x78, 4 ),
            "x" + E + "[3b" );
    expect( "rep(0x79,1) owes no repeat at all", Curses.tputs( raw( strs, Capability.repeat_char ), 0x79, 1 ),
            "y" + E + "[0b" );
    try {
      Curses.tputs( raw( strs, Capability.repeat_char ), 'x', 4 );
      expect( "a Character parameter is a NumberFormatException", "returned", "threw" );
    } catch ( java.io.IOError ok ) {
      System.out.println( "ok   a Character parameter throws, as toInteger parses \"x\" (by design, pinned)" );
    }
    System.out.println( "sgr(all attrs on) -> " + show( Curses.tputs( raw( strs, Capability.set_attributes ),
                                                                    1, 1, 1, 1, 1, 1, 1, 1, 1 ) ) );
    System.out.println( "sgr(bold+ul+rev)  -> " + show( Curses.tputs( raw( strs, Capability.set_attributes ),
                                                                    0, 1, 1, 0, 0, 1, 0, 0, 0 ) ) );
    System.out.println( "sgr(nothing)      -> " + show( Curses.tputs( raw( strs, Capability.set_attributes ),
                                                                    0, 0, 0, 0, 0, 0, 0, 0, 0 ) ) );

    System.out.println( "--- what the reader on this classpath binds ---" );
    try {
      org.jline.terminal.Terminal t = new org.jline.terminal.impl.LineDisciplineTerminal(
          "capsdump", "windows-conemu", new java.io.ByteArrayOutputStream(), StandardCharsets.UTF_8 );
      String loaded = InfoCmp.getLoadedInfoCmp( "windows-conemu" );
      String resource = InfoCmp.getDefaultInfoCmp( "windows-conemu" );
      System.out.println( "     the text this JVM read: loaded=" + ( loaded == null ? "null" : "" + loaded.length() )
                          + " bytes, bundled resource="
                          + ( resource == null ? "null" : "" + resource.length() )
                          + " bytes, terminal type " + t.getType() );
      String cbt = org.jline.keymap.KeyMap.key( t, Capability.back_tab );
      expect( "the shipped entry gives back_tab a value", cbt, E + "[Z" );
      org.jline.keymap.KeyMap<org.jline.reader.Binding> menu =
          new org.jline.reader.impl.LineReaderImpl( t ).getKeyMaps().get( org.jline.reader.LineReader.MENU );
      String got;
      if ( menu == null )
        got = "no menu keymap at all";
      else if ( cbt == null )
        got = "no cbt to look up";
      else
        {
          org.jline.reader.Binding b = menu.getBound( cbt );
          got = b instanceof org.jline.reader.Reference ? ( (org.jline.reader.Reference) b ).name()
                                                       : ( "bound to " + b + ", not a widget reference" );
        }
      expect( "menu binds Shift-Tab to reverse-menu-complete", got,
              org.jline.reader.LineReader.REVERSE_MENU_COMPLETE );
    } catch ( Exception e ) {
      expect( "the reader leg ran without an exception", e.getClass().getName(), "none" );
    }

    System.out.println( "--- coverage census ---" );
    Set<String> asserted = new TreeSet<>();
    for ( String name : DECLARED )
    {
      Pattern p = Pattern.compile( "\\b" + name + "\\b" );
      for ( String label : LABELS )
        if ( p.matcher( label ).find() )
        {
          asserted.add( name );
          break;
        }
    }
    Set<String> quiet = new TreeSet<>( DECLARED );
    quiet.removeAll( asserted );
    int unexplained = 0;
    for ( String n : quiet )
      if ( !NO_EXPECTATION.containsKey( n ) )
      {
        System.out.println( "  NOT ASSERTED AND NOT EXPLAINED: " + n );
        unexplained++;
      }
    for ( String n : NO_EXPECTATION.keySet() )
      if ( !DECLARED.contains( n ) )
      {
        System.out.println( "  THE SILENCE TABLE CARRIES A NAME THE ENTRY NO LONGER DECLARES: " + n );
        unexplained++;
      }
    Map<String, List<String>> byReason = new LinkedHashMap<>();
    for ( Map.Entry<String, String> e : NO_EXPECTATION.entrySet() )
      if ( quiet.contains( e.getKey() ) )
      {
        List<String> group = byReason.get( e.getValue() );
        if ( group == null )
          byReason.put( e.getValue(), group = new ArrayList<>() );
        group.add( e.getKey() );
      }
    for ( Map.Entry<String, List<String>> e : byReason.entrySet() )
      System.out.println( "  " + e.getValue() + "  <<  " + e.getKey() );
    System.out.printf( "census expectations=%d declared=%d asserted=%d unasserted=%d unexplained=%d%n",
                       LABELS.size(), DECLARED.size(), asserted.size(), quiet.size(), unexplained );
    if ( unexplained != 0 )
      fails++;

    System.out.println( fails == 0 ? "CAPS CHECK: ok" : ( "CAPS CHECK: " + fails + " FAILED" ) );
    if ( fails != 0 )
      System.exit( 1 );
  }
}

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import org.jline.utils.Curses;
import org.jline.utils.InfoCmp;
import org.jline.utils.InfoCmp.Capability;

/**
 * Reads a .caps file through the parser jline uses at runtime and asserts what the terminal will see.
 *
 * Two layers, and mixing them up is the trap this harness exists to avoid:
 *  - InfoCmp.parseInfoCmp (InfoCmp.java:644) keeps each value EXACTLY as the file spells it ("\\E[1m", "^I")
 *    and skips line 0 entirely (its loop starts at i = 1), so the description line is rationale for humans
 *    and nothing else; an unresolvable key name is dropped without a word (:669-684).
 *  - Curses.doTputs (Curses.java:92) is where "\\E", "^X", "\:", "\n" and octal "\ddd" become bytes, at
 *    output time. So a raw comparison uses the file spelling; a wire comparison goes through tputs.
 */
public class CapsDump
{
  /** A real escape byte, for the wire-layer expectations. */
  static final String E = "\u001b";

  static int fails;

  /** Make every control byte visible, or the console eats the evidence. */
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
    boolean ok = want == null ? got == null : want.equals( got );
    if ( !ok )
      fails++;
    System.out.printf( "%-4s %-44s got=%-40s want=%s%n", ok ? "ok" : "FAIL", what, show( "" + got ), show( "" + want ) );
  }

  /** The file spelling of a string capability, with the ESC still written as backslash-E. */
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
    expect( "cbt NOT advertised (no tab stops exist)", raw( strs, Capability.back_tab ), null );
    expect( "hts NOT advertised", raw( strs, Capability.set_tab ), null );
    expect( "tbc NOT advertised", raw( strs, Capability.clear_all_tabs ), null );
    expect( "smacs", raw( strs, Capability.enter_alt_charset_mode ), "\\E(0" );
    expect( "rmacs", raw( strs, Capability.exit_alt_charset_mode ), "\\E(B" );
    expect( "acsc pairs (xterm's identity map)", raw( strs, Capability.acs_chars ).length() / 2, 26 );
    expect( "smcup", raw( strs, Capability.enter_ca_mode ), "\\E[?1049h" );
    expect( "rmcup", raw( strs, Capability.exit_ca_mode ), "\\E[?1049l" );
    expect( "cnorm (no ?12 noise)", raw( strs, Capability.cursor_normal ), "\\E[?25h" );
    expect( "civis", raw( strs, Capability.cursor_invisible ), "\\E[?25l" );
    expect( "smkx NOT advertised (input is console records)", raw( strs, Capability.keypad_xmit ), null );
    expect( "rmkx NOT advertised", raw( strs, Capability.keypad_local ), null );
    expect( "flash NOT advertised (reads fall back to bel)", raw( strs, Capability.flash_screen ), null );
    /* Advertised since the reply leg landed (DESIGN I29, §4): CSI 6n is answered onto CONIN$, and u6 is the
       pattern a reader compiles to parse that answer -- spelled one-based with %i, which is what turns it
       back into the zero-based cursor jline hands back. u7 is the query itself. Both were "NOT advertised"
       here before the leg existed; the entry and this expectation had to move together. */
    expect( "u6 (the answer's shape, with %i)", raw( strs, Capability.user6 ), "\\E[%i%d;%dR" );
    expect( "u7 (the query)", raw( strs, Capability.user7 ), "\\E[6n" );
    expect( "initc NOT advertised", raw( strs, Capability.initialize_color ), null );
    expect( "ccc NOT advertised", bools.contains( Capability.can_change ), false );
    expect( "smam NOT advertised", raw( strs, Capability.enter_am_mode ), null );
    expect( "rmam NOT advertised", raw( strs, Capability.exit_am_mode ), null );
    expect( "ich1 (Display line editing)", raw( strs, Capability.insert_character ), "\\E[@" );
    expect( "dch1 (Display line editing)", raw( strs, Capability.delete_character ), "\\E[P" );
    expect( "parm_ich", raw( strs, Capability.parm_ich ), "\\E[%p1%d@" );
    expect( "parm_dch", raw( strs, Capability.parm_dch ), "\\E[%p1%dP" );
    expect( "ech", raw( strs, Capability.erase_chars ), "\\E[%p1%dX" );
    /* rep is here because the file's own test admits it and the old asymmetry did not: CEAnsi has a case for
       `CSI Ps b` (Ansi.cpp:3070-3087) and render.dll models it, which is the same two-clause test that put
       `ech` in. No jline code reads Capability.repeat_char, exactly as none reads erase_chars, so "nothing in
       this stack asks for it" was never the reason it was missing. The value is xterm's canonical one: write
       the character, then repeat it n-1 times, because both legs count the repeats and not the total. */
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
    expect( "setaf", raw( strs, Capability.set_a_foreground ), "\\E[38;5;%p1%dm" );
    expect( "setab", raw( strs, Capability.set_a_background ), "\\E[48;5;%p1%dm" );
    expect( "op", raw( strs, Capability.orig_pair ), "\\E[39;49m" );
    expect( "sgr0", raw( strs, Capability.exit_attribute_mode ), "\\E(B\\E[0m" );
    expect( "blink NOT advertised", raw( strs, Capability.enter_blink_mode ), null );
    expect( "invis NOT advertised", raw( strs, Capability.enter_secure_mode ), null );
    expect( "rmpch NOT advertised", raw( strs, Capability.exit_pc_charset_mode ), null );
    expect( "sgr drops blink/invis/font", raw( strs, Capability.set_attributes ),
           "\\E[0%?%p6%t;1%;%?%p2%t;4%;%?%p1%p3%|%t;7%;m" );
    expect( "il", raw( strs, Capability.parm_insert_line ), "\\E[%p1%dL" );
    expect( "dl", raw( strs, Capability.parm_delete_line ), "\\E[%p1%dM" );
    expect( "cud1 is a CSI, not a newline", raw( strs, Capability.cursor_down ), "\\E[B" );

    System.out.println( "--- what reaches the terminal ---" );
    expect( "csr(0,23) whole page", Curses.tputs( raw( strs, Capability.change_scroll_region ), 0, 23 ), E + "[1;24r" );
    expect( "csr(0,22) one status line", Curses.tputs( raw( strs, Capability.change_scroll_region ), 0, 22 ), E + "[1;23r" );
    expect( "csr(0,0) Status.reset()", Curses.tputs( raw( strs, Capability.change_scroll_region ), 0, 0 ), E + "[1;1r" );
    expect( "cup(5,10)", Curses.tputs( raw( strs, Capability.cursor_address ), 5, 10 ), E + "[6;11H" );
    expect( "hpa(0) is 1-based after %i", Curses.tputs( raw( strs, Capability.column_address ), 0 ), E + "[1G" );
    expect( "vpa(3)", Curses.tputs( raw( strs, Capability.row_address ), 3 ), E + "[4d" );
    expect( "ich(1)", Curses.tputs( raw( strs, Capability.parm_ich ), 1 ), E + "[1@" );
    expect( "dch(2)", Curses.tputs( raw( strs, Capability.parm_dch ), 2 ), E + "[2P" );
    expect( "ich1()", Curses.tputs( raw( strs, Capability.insert_character ) ), E + "[@" );
    expect( "setaf(9)", Curses.tputs( raw( strs, Capability.set_a_foreground ), 9 ), E + "[38;5;9m" );
    expect( "smacs bytes", Curses.tputs( raw( strs, Capability.enter_alt_charset_mode ) ), E + "(0" );
    expect( "rmacs bytes", Curses.tputs( raw( strs, Capability.exit_alt_charset_mode ) ), E + "(B" );
    expect( "ind bytes", Curses.tputs( raw( strs, Capability.scroll_forward ) ), "\n" );
    expect( "cr bytes", Curses.tputs( raw( strs, Capability.carriage_return ) ), "\r" );
    expect( "ht bytes", Curses.tputs( raw( strs, Capability.tab ) ), "\t" );
    expect( "kbs bytes", Curses.tputs( raw( strs, Capability.key_backspace ) ), "\b" );
    /* The one arm of `%c` and of the `%{1}%-` arithmetic in this file, and the only place either is checked:
       doTputs accepts a conversion only out of "cdoxXs" (Curses.java:425), so `rep` is the sole capability
       here that reaches it. A `rep` that expands to `x\E[3b` is also the proof that the two legs agree on
       what the number means -- repeats, not total. The parameter is an int and not a char, which is the
       spelling below it proves is the only one that works. */
    expect( "rep(0x78,4) writes x then three repeats", Curses.tputs( raw( strs, Capability.repeat_char ), 0x78, 4 ),
            "x" + E + "[3b" );
    expect( "rep(0x79,1) owes no repeat at all", Curses.tputs( raw( strs, Capability.repeat_char ), 0x79, 1 ),
            "y" + E + "[0b" );
    /* The trap in the same capability, pinned rather than fixed: `%c` pops into toInteger
       (Curses.java:502-510), which takes a Number or else Integer.parseInt(toString) -- so a Character
       argument is parseInt("x") and dies inside the IOError wrapper tputs puts around it (:88). Not this
       entry's invention: xterm's own `rep` has the same requirement, and nothing in jline calls it. It is
       recorded here because `tputs(rep, 'x', 4)` looks like the obvious way to write the line above. */
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

    System.out.println( fails == 0 ? "CAPS CHECK: ok" : ( "CAPS CHECK: " + fails + " FAILED" ) );
    if ( fails != 0 )
      System.exit( 1 );
  }
}

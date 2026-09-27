import io, subprocess, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

C = r"D:\dbcli\cache\audit90\teethlab\src\c\conemu"
RC = C + "\\RenderCheck.cpp"
RN = C + "\\Render.cpp"
LEG = r"D:\dbcli\cache\audit90\leg_teeth.c.txt"
BUILD = ["wsl.exe", "-e", "bash", "-lc",
         "cd /mnt/d/dbcli/cache/audit90/teethlab/src/c/conemu && ./build.sh"]

BS, Q = chr(92), chr(39)
HEAD = "  int r, c;\n  msg[0] = " + Q + BS + "0" + Q + ";\n"
BLIND = HEAD + "  return 0;   /* MUTANT: the oracle reports every grid clean */\n"
FNA = "static void geo_decrpm_silence()"
CALL = "  geo_decrpm_silence();"


def rd(p): return open(p, encoding="utf-8", errors="replace").read()
def wr(p, t): open(p, "w", encoding="utf-8", newline="").write(t)


def build(tag):
    p = subprocess.run(BUILD, capture_output=True, text=True, timeout=1800)
    out = (p.stdout or "") + (p.stderr or "")
    L = out.splitlines()
    chk = [l.strip() for l in L if "checks=" in l and "fails=" in l]
    ver = [l.strip() for l in L if "RENDERCHECK:" in l]
    fl = [l.strip() for l in L if l.strip().startswith("FAIL")]
    er = [l.strip() for l in L if "error:" in l]
    print("---- " + tag)
    print("     " + ((chk or ["NO checks= LINE (gate did not run!)"])[0]))
    print("     " + ((ver or ["NO VERDICT LINE"])[0]))
    for e in er[:3]: print("     build " + e[:130])
    for f in fl[:8]: print("     " + f[:132])
    if len(fl) > 8: print("     ... +%d more FAIL lines" % (len(fl) - 8))


rc, rn, leg = rd(RC), rd(RN), rd(LEG)
for name, cnt in (("function anchor", rc.count(FNA)), ("call anchor", rc.count(CALL)),
                  ("oracle head", rn.count(HEAD))):
    if cnt != 1:
        print("ABORT: %s matched %d times" % (name, cnt)); sys.exit(1)

wr(RC, rc.replace(FNA, leg + FNA, 1).replace(CALL, CALL + "\n  geo_oracle_teeth();", 1))
build("A  trunk bytes + the new teeth leg  (want: ok, checks above trunk's own count)")

wr(RN, rn.replace(HEAD, BLIND, 1))
build("B  same leg, oracle blinded (M4)   (want: FAILED, naming the teeth arms)")

wr(RN, rn); wr(RC, rc)
print("---- reverted; lab back to trunk bytes")
for f in (RN, RC):
    print("     " + f.split("\\")[-1] + " " + rd(f)[:0] if False else
          "     " + f.split("\\")[-1] + " md5 " +
          subprocess.run(["certutil", "-hashfile", f, "MD5"], capture_output=True, text=True).stdout.split()[-2])
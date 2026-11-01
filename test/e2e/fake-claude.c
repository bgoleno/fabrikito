#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <sys/ioctl.h>
static char buf[65536], hist[65536], head[4096], mode[64], name[256];
static size_t blen, hlen, pstart;
static int npaste;
static const char *base;
static volatile sig_atomic_t winch;
static void onwinch(int s) { (void)s; winch = 1; }
static void cat(const char *what) {
  char path[4096]; snprintf(path, sizeof path, "%s-%s.txt", base, what);
  FILE *f = fopen(path, "r"); int c; if (!f) return;
  while ((c = fgetc(f)) != EOF) { if (c == '\n') putchar('\r'); putchar(c); }
  fclose(f);
}
static int has(const char *what) {
  char path[4096]; snprintf(path, sizeof path, "%s-%s.txt", base, what);
  return access(path, R_OK) == 0;
}
static char RULE[4096];   /* the box's plain rule, as wide as the pane (draw() fills it), as Claude Code draws it */
/* Claude Code 2.1.316's @-mention list, captured on 2026-10-30: drawn above the box's top rule,
   each row indented two spaces in colour 246; a row picked with the arrow keys gets a ❯ in colour
   153, and only then does Enter complete the mention instead of submitting. */
static int mention_open(void) {
  size_t i = blen;
  if (strcmp(mode, "mention") && strcmp(mode, "mentionsel")) return 0;
  while (i > 0 && buf[i - 1] != ' ' && buf[i - 1] != '\n') i--;
  return i < blen && buf[i] == '@';
}
static void mention_list(void) {
  const char *rows[] = { "+ src/", "+ src/beta.txt", "+ src/alpha.txt", "\xe2\x97\x87 example:skill:\xe2\x80\xa6 \xe2\x80\x93 requirements.txt" };
  for (int i = 0; i < 4; i++)
    if (i == 0 && !strcmp(mode, "mentionsel")) printf("  \033[38;5;153m\xe2\x9d\xaf %s\033[39m\r\n", rows[i]);
    else printf("  \033[38;5;246m  %s\033[39m\r\n", rows[i]);
}
/* mode tall*: the input box as Claude Code 2.1.316 draws long text. Rows wrap at word boundaries
   with a 2-space indent; the box shows at most max(3, (terminal rows - 10) / 2) rows and scrolls to
   keep the end in view, with the prompt on the first VISIBLE row and no scroll marker. tall-dim
   adds a dim suggestion after the text, tall-short shows one row fewer than a full box. */
static void tall(void) {
  struct winsize ws; int cols = 220, rows = 50, w, v, nr = 0; static size_t rs[8192], rl[8192];
  if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col && ws.ws_row) { cols = ws.ws_col; rows = ws.ws_row; }
  w = cols - 4 < 20 ? 20 : cols - 4; v = (rows - 10) / 2; if (v < 3) v = 3;
  if (!strcmp(mode, "tall-short")) v--;
  for (size_t i = 0; i <= blen && nr < 8192;) {          /* split into logical lines, then wrap each */
    size_t e = i; while (e < blen && buf[e] != '\n') e++;
    size_t a = i;
    do {
      size_t len = e - a, cut = len;
      if (len > (size_t)w) { cut = (size_t)w; while (cut > 0 && buf[a + cut] != ' ') cut--; if (cut == 0) cut = (size_t)w; }
      rs[nr] = a; rl[nr] = cut; nr++;
      a += cut; if (a < e && buf[a] == ' ') a++;
    } while (a < e && nr < 8192);
    i = e + 1;
  }
  int first = nr > v ? nr - v : 0;
  for (int r = first; r < nr; r++) {
    if (r > first) printf("\r\n  ");                     /* draw() has printed the prompt */
    fwrite(buf + rs[r], 1, rl[r], stdout);
  }
  if (blen == 0) printf("\033[2mTry \"something\"\033[0m");
  else if (!strcmp(mode, "tall-dim")) printf(" \033[2mrun the tests\033[0m");
}
static void draw(void) {
  struct winsize ws; int cols = 220, rows = 50;
  if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col && ws.ws_row) { cols = ws.ws_col; rows = ws.ws_row; }
  int small = !strncmp(mode, "small", 5), notice = !strcmp(mode, "small") && cols < 110;
  { size_t o = 0; for (int i = 0; i < cols && o + 4 < sizeof RULE; i++) o += (size_t)snprintf(RULE + o, sizeof RULE - o, "\xe2\x94\x80"); }
  printf("\033[H\033[2J%s\r\n", head);
  fwrite(hist, 1, hlen, stdout);
  if (has("prompt")) { cat("prompt"); fflush(stdout); return; }
  if (!small || notice) cat("output");
  if (mention_open()) mention_list();
  if (name[0]) printf("────────────────────────────────────────── %s ──\r\n\xe2\x9d\xaf\xc2\xa0", name);
  else printf("%s\r\n\xe2\x9d\xaf\xc2\xa0", RULE);
  if (!strncmp(mode, "tall", 4) || small) {
    tall();
    if ((notice && rows <= 13) || (small && blen && rows < 12)) { fflush(stdout); return; }
    printf("\r\n%s\r\n  SL line one\r\n  \xe2\x8f\xb5\xe2\x8f\xb5 bypass permissions on (shift+tab to cycle)\r\n", RULE);
    fflush(stdout); return;
  }
  int sticky = !strcmp(mode, "sticky") || !strcmp(mode, "mixed");
  if (blen == 0) printf(sticky || !strcmp(mode, "suggest") ? "\033[2mrun the tests\033[0m" : "\033[2mTry \"something\"\033[0m");
  for (size_t i = 0; i < blen; i++) { if (buf[i] == '\n') printf("\r\n  "); else putchar(buf[i]); }
  if (blen && sticky) printf(" \033[2mrun the tests\033[0m");
  if (!strcmp(mode, "cut")) { fflush(stdout); return; }
  printf("\r\n%s\r\n", RULE);
  if (!strcmp(mode, "below")) printf("  \xe2\x9d\xaf suggestion one\r\n    suggestion two\r\n");
  printf("  SL line one\r\n  \xe2\x8f\xb5\xe2\x8f\xb5 bypass permissions on (shift+tab to cycle)\r\n");
  fflush(stdout);
}
/* At the end of a paste, Claude Code 2.1.316 shows a paste of more than 800 characters, or of 4 or
   more lines, as a placeholder (measured 2026-10-30). tall-typed and small-typed: text typed right
   after the paste. */
static void endpaste(void) {
  if (strncmp(mode, "tall", 4) && strncmp(mode, "small", 5)) return;
  size_t len = blen - pstart; int nl = 0;
  for (size_t i = pstart; i < blen; i++) if (buf[i] == '\n') nl++;
  if (len > 800 || nl >= 3) {
    npaste++;
    blen = pstart + (size_t)(nl ? snprintf(buf + pstart, sizeof buf - pstart, "[Pasted text #%d +%d lines]", npaste, nl)
                                : snprintf(buf + pstart, sizeof buf - pstart, "[Pasted text #%d]", npaste));
  }
  if (!strcmp(mode, "tall-typed") || !strcmp(mode, "small-typed")) blen += (size_t)snprintf(buf + blen, sizeof buf - blen, " typed after");
}
int main(int n, char **v) {
  if (n == 2 && !strcmp(v[1], "--version")) { char *fv = getenv("FAKE_VERSION"); printf("%s (Claude Code)\n", fv ? fv : "9.9.9"); return 0; }
  struct termios t; char *k = getenv("FAKE_KEYLOG"); FILE *kl = k ? fopen(k, "a") : 0, *mf;
  base = getenv("FAKE_FILES"); if (!base) base = "/nonexistent";
  char path[4096]; snprintf(path, sizeof path, "%s-mode.txt", base);
  if ((mf = fopen(path, "r"))) { if (fscanf(mf, "%63s", mode) != 1) mode[0] = 0; fclose(mf); }
  if (!strcmp(mode, "prefill")) blen = (size_t)snprintf(buf, sizeof buf, "leftover draft text");
  if (!strcmp(mode, "mixed")) blen = (size_t)snprintf(buf, sizeof buf, "typed text");
  if (!strcmp(mode, "mentionsel")) blen = (size_t)snprintf(buf, sizeof buf, "sel @sr");
  size_t h = (size_t)snprintf(head, sizeof head, "FAKE-CLAUDE");
  for (int i = 1; i < n && h < sizeof head - 60; i++) h += (size_t)snprintf(head + h, sizeof head - h, " [%.50s]", v[i]);
  for (int i = 1; i + 1 < n; i++) if (!strcmp(v[i], "-n")) snprintf(name, sizeof name, "%s", v[i + 1]);
  signal(SIGCHLD, SIG_IGN);                      /* ! commands are not waited for; no zombies */
  tcgetattr(0, &t); cfmakeraw(&t); tcsetattr(0, TCSANOW, &t);
  struct sigaction sw; memset(&sw, 0, sizeof sw); sw.sa_handler = onwinch; sigaction(SIGWINCH, &sw, 0);  /* no SA_RESTART */
  printf("\033[?2004h"); draw();
  int c, esc = 0, paste = 0; char seq[8]; int sl = 0;
  for (;;) {
    ssize_t got = read(0, &c, 1);
    if (got < 0 && errno == EINTR) {               /* small-slow: a busy seat, slow to redraw */
      if (winch) { winch = 0; if (!strcmp(mode, "small-slow")) usleep(1500000); if (!paste) draw(); }
      continue;
    }
    if (got != 1) break;
    unsigned char b = (unsigned char)c;
    if (kl) { fputc(b, kl); fflush(kl); }
    if (esc) {                                   /* ESC [ 2 0 0 ~ and ESC [ 2 0 1 ~ mark a paste */
      seq[sl++] = (char)b;
      if (b == '~' || sl >= 7) { seq[sl] = 0; if (!strcmp(seq, "[200~")) { paste = 1; pstart = blen; } if (!strcmp(seq, "[201~")) { paste = 0; endpaste(); } esc = 0; draw(); }
      continue;
    }
    if (b == 27) { esc = 1; sl = 0; continue; }
    if (!strcmp(mode, "swallow")) continue;
    if (b == '\r' || b == '\n') {
      if (paste) { if (blen < sizeof buf - 1) buf[blen++] = '\n'; }
      else if (!strcmp(mode, "mentionsel") && mention_open()) {   /* Enter picks the highlighted row */
        while (blen > 0 && buf[blen - 1] != '@') blen--;
        blen += (size_t)snprintf(buf + blen, sizeof buf - blen, "src/");
      }
      else {                                      /* submit: the transcript echoes it, the box empties */
        if (blen && buf[0] == '!' && fork() == 0) {
          int fd = open("/dev/null", O_RDWR);
          setsid(); signal(SIGCHLD, SIG_DFL); dup2(fd, 0); dup2(fd, 1); dup2(fd, 2); buf[blen] = 0;
          execl("/bin/sh", "sh", "-c", buf + 1, (char *)0); _exit(127);
        }
        hlen += (size_t)snprintf(hist + hlen, sizeof hist - hlen, "\xe2\x9d\xaf %.*s\r\n", (int)blen, buf);
        if (hlen > sizeof hist - 8192) hlen = 0;
        blen = 0;
      }
    } else if (b == 21) blen = 0;                 /* ctrl-u clears the box */
    else if (b == 12) ;                           /* ctrl-l redraws (after a resize) */
    else if (blen < sizeof buf - 1) buf[blen++] = (char)b;
    /* Not while a paste is coming in: a redraw per pasted byte (800 for a tall message) can still
       be running at say's check after the paste on a loaded machine. ESC [ 201 ~ draws once. */
    if (!paste) draw();
  }
  return 0;
}

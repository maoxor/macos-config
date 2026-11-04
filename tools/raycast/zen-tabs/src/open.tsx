// "o <text>" in Raycast: jump straight to the open Zen tab whose title or address matches, in one Enter.
// Every word must appear in the title or the address (case and accents ignored). Best match: words found in the
// title first, then a title starting with the text, then the most recently used tab. No match: the tab list opens
// with the text already typed (the "Onglets Zen" command), so nothing is lost.
import { LaunchProps, LaunchType, closeMainWindow, launchCommand, showToast, Toast } from "@raycast/api";
import { execFile } from "child_process";
import { promisify } from "util";

const run = promisify(execFile);
const MOZEIDON = "/opt/homebrew/bin/mozeidon";
const ZEN = "app.zen-browser.zen";

type MozTab = { id: number; windowId: number; url: string; title: string; active: boolean; lastAccessed: number };

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

function score(t: MozTab, words: string[], whole: string): number | null {
  const title = fold(t.title || "");
  const url = fold(t.url || "");
  if (!words.every((w) => title.includes(w) || url.includes(w))) return null;
  let s = 0;
  s += words.filter((w) => title.includes(w)).length * 100;
  if (title.startsWith(whole)) s += 50;
  if (title.split(/\W+/).some((part) => part === whole)) s += 25;
  return s;
}

export default async function Command(props: LaunchProps<{ arguments: { query: string } }>) {
  const whole = fold(props.arguments.query.trim());
  if (!whole) return;
  const words = whole.split(/\s+/);
  try {
    const { stdout } = await run(MOZEIDON, ["tabs", "get"], { timeout: 3000 });
    const tabs = ((JSON.parse(stdout).data ?? []) as MozTab[]).filter((t) => t.url && t.url !== "about:blank");
    const ranked = tabs
      .map((t) => ({ t, s: score(t, words, whole) }))
      .filter((x): x is { t: MozTab; s: number } => x.s !== null)
      .sort((a, b) => b.s - a.s || b.t.lastAccessed - a.t.lastAccessed);
    if (!ranked.length) {
      await launchCommand({ name: "index", type: LaunchType.UserInitiated, fallbackText: props.arguments.query });
      return;
    }
    await closeMainWindow({ clearRootSearch: true });
    const best = ranked[0].t;
    await run(MOZEIDON, ["tabs", "switch", `${best.windowId}:${best.id}`], { timeout: 3000 });
    await run("/usr/bin/open", ["-b", ZEN]);
  } catch (err) {
    showToast({ style: Toast.Style.Failure, title: "Onglet Zen introuvable", message: String(err) });
  }
}

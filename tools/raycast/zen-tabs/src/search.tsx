// "z hello world" in Raycast: search with Zen's own engine in a new tab and land on that tab.
// Zen keeps two synced windows here: `mozeidon tabs new` loads the search in one and leaves its twin (about:blank)
// in the other, and Zen could come to the front on that twin. So: find the new tab that got the search URL, switch
// to it explicitly (Mozeidon focuses its window), then bring Zen to the front. Never close the twin: Zen closes the
// real tab with it (seen 2026-11-04). Fallback without Mozeidon: a Google
// URL opened in Zen.
import { LaunchProps, closeMainWindow, showToast, Toast } from "@raycast/api";
import { execFile } from "child_process";
import { existsSync } from "fs";
import { promisify } from "util";

const run = promisify(execFile);
const MOZEIDON = "/opt/homebrew/bin/mozeidon";
const ZEN = "app.zen-browser.zen";

type MozTab = { id: number; windowId: number; url: string; active: boolean };
const ref = (t: MozTab) => `${t.windowId}:${t.id}`;

async function tabs(): Promise<MozTab[]> {
  const { stdout } = await run(MOZEIDON, ["tabs", "get"], { timeout: 3000 });
  return (JSON.parse(stdout).data ?? []) as MozTab[];
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const blank = (u: string) => !u || u === "about:blank" || u.startsWith("about:newtab");

export default async function Command(props: LaunchProps<{ arguments: { query: string } }>) {
  const query = props.arguments.query.trim();
  if (!query) return;
  await closeMainWindow({ clearRootSearch: true });
  if (!existsSync(MOZEIDON)) {
    await run("/usr/bin/open", ["-b", ZEN, `https://www.google.com/search?q=${encodeURIComponent(query)}`]);
    return;
  }
  try {
    const before = new Set((await tabs()).map(ref));
    await run(MOZEIDON, ["tabs", "new", ...query.split(/\s+/)], { timeout: 3000 });
    // The search tab gets its URL a moment after it opens.
    let target: MozTab | undefined;
    let fresh: MozTab[] = [];
    for (let i = 0; i < 15 && !target; i++) {
      await sleep(80);
      fresh = (await tabs()).filter((t) => !before.has(ref(t)));
      target = fresh.find((t) => !blank(t.url));
    }
    if (target) await run(MOZEIDON, ["tabs", "switch", ref(target)], { timeout: 3000 });
    await run("/usr/bin/open", ["-b", ZEN]);
  } catch (err) {
    showToast({ style: Toast.Style.Failure, title: "Recherche Zen impossible", message: String(err) });
  }
}

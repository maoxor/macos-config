// "z hello world" in Raycast: search with Zen's own engine in a new tab of the open Zen window (Mozeidon's
// `tabs new` with keywords), then bring Zen to the front. Without Mozeidon: open a Google search URL in Zen, which
// also lands in a tab of the existing window (Firefox's default for links from other apps).
import { LaunchProps, closeMainWindow, showToast, Toast } from "@raycast/api";
import { execFile } from "child_process";
import { existsSync } from "fs";

const MOZEIDON = "/opt/homebrew/bin/mozeidon";
const ZEN = "app.zen-browser.zen";

export default async function Command(props: LaunchProps<{ arguments: { query: string } }>) {
  const query = props.arguments.query.trim();
  if (!query) return;
  await closeMainWindow({ clearRootSearch: true });
  const front = () => execFile("/usr/bin/open", ["-b", ZEN]);
  if (existsSync(MOZEIDON)) {
    execFile(MOZEIDON, ["tabs", "new", ...query.split(/\s+/)], { timeout: 3000 }, (err) => {
      if (err) {
        showToast({ style: Toast.Style.Failure, title: "Mozeidon ne répond pas", message: err.message });
        return;
      }
      front();
    });
    return;
  }
  execFile("/usr/bin/open", ["-b", ZEN, `https://www.google.com/search?q=${encodeURIComponent(query)}`]);
}

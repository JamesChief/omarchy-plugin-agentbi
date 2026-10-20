# AgentBI — Omarchy bar widget

Your own site's agent-readiness score in the bar: the AgentBI icon, a dot
coloured by band, and the score. **Hover the mark for the panel** — your site's
name, the score, and what was actually measured.

<!-- screenshot: drop agentbi-bar.png back in once the new widget is on screen -->

## Install

    omarchy plugin add https://github.com/JamesChief/omarchy-plugin-agentbi --enable

Or clone it into `~/.config/omarchy/plugins/agentbi/` and
`omarchy plugin enable agentbi`.

## Configure

Copy the sample and put your site in it:

    mkdir -p ~/.config/agentbi
    cp widget.conf.example ~/.config/agentbi/widget.conf
    $EDITOR ~/.config/agentbi/widget.conf

    url = https://your-store.com
    name = My Store
    lang = en          # or zh — the measured lines come back in that language

Three keys, one per line. Saving the file reloads it and triggers a fresh scan;
the widget also rescans every 30 minutes, which is the server's cache window.

You can also set them from the widget: hover the mark, click **Edit site**. The
panel then switches to a form (that mode takes keyboard focus, which a hover
panel cannot), and Save writes the same file back. Editing the file by hand
still works — the file is the one source of truth.

## Reading the mark

| Dot | Meaning |
| --- | --- |
| green | 80–100 |
| amber | 50–79 |
| red | 0–49 |
| grey | not measured yet, or the scan failed (the panel says which) |

- Left click opens <https://agentbi.tech>, middle click rescans now.
- The panel lists the five dimensions the score is made of: agent fetch,
  product data, UCP, llms.txt, robots.txt.

## Where the numbers come from

One GET per scan to <https://agentbi.tech/api/check?url=…>, the same endpoint
the website's own form calls — a real scan from a single vantage, cached for
30 minutes. The daily census of 225 storefronts is a different thing and lives
at <https://agentbi.tech/batch.json>.

## Privacy

No accounts, no telemetry. The only outbound request is the check above, and it
carries the URL you configured — nothing else leaves the machine.

# Web — read-only bounty board

The Live Demo Link. A read-only page showing the bounty board on Arc Testnet,
the break an agent already performed, and the boundary value list it used.

No wallet connection, no writes, no way to trigger the agent from here.

## Run locally

```bash
npm install
npm run build && npm run start
```

Optional environment: `REGISTRY` and `ARC_RPC_URL` override the defaults (used
by the local test harness to point the page at anvil).

## The three constraints that shaped it

**Chain reads happen on the server, cached.** `src/lib/chain.ts` starts with
`import "server-only"` — if a client component ever imports it the build fails,
so "no RPC from the browser" is enforced by the compiler rather than by
discipline. Measured: a cold first load costs 13 RPC calls, and five more
visitors after it cost **zero**. Arc's public endpoint is throttled and the agent
shares that budget; a page that read from the browser would multiply load by the
number of viewers, and if that happened mid-recording the agent is what would get
throttled.

**Nothing polls.** There is no interval, no revalidate-on-focus, no timer. The
board is read once when the cache is cold and again only when somebody clicks
refresh. Verified by instrumenting `setInterval`/`setTimeout`/`fetch` in the
browser and leaving the page idle: zero of each.

**Provenance is labelled, not blended.** Three badges appear throughout:
*live from chain*, *from run log*, *source code*. The bounty statuses are read
from the Registry. "It broke on the 6th probe" is not something any contract
records — it is what the agent printed — so it is labelled as such and the
transaction hash is there for the parts that can be checked. Mixing the two
unlabelled is the one thing this page must not do.

## The boundary list is generated, not copied

`src/data/boundaries.json` is generated from `agent/src/boundaries.ts` by
`scripts/sync-boundaries.mjs`, because Vercel deploys with `web/` as the root and
cannot reach into `agent/`. The build runs the generator in `--check` mode first
and fails if the two have drifted, so a stale copy cannot ship silently.

## Deploying

Vercel project with **root directory `web/`**. The build command in
`vercel.json` runs the drift check before `next build`.

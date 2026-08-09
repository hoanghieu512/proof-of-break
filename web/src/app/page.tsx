import { getBoard } from "@/lib/board";
import { EXPLORER, REGISTRY_ADDRESS } from "@/lib/chain";
import { RUN_LOG } from "@/lib/runlog";
import boundaries from "@/data/boundaries.json";
import { RefreshButton } from "./RefreshButton";

// Rendered per request on the server. The cache in board.ts is what stops that
// meaning one RPC read per visitor.
export const dynamic = "force-dynamic";

const short = (s: string) => `${s.slice(0, 10)}…${s.slice(-8)}`;

function Chain() {
  return <span className="provenance chain">live from chain</span>;
}
function Log() {
  return <span className="provenance log">from run log</span>;
}
function Static() {
  return <span className="provenance static">source code</span>;
}

export default async function Page() {
  const board = await getBoard();

  return (
    <main>
      <h1>Proof of Break</h1>
      <p className="tagline">
        Autonomous agents get paid in USDC for breaking smart contracts. This page
        is read-only: no wallet, no writes, nothing to sign.
      </p>

      <p className="provenance-note">
        Three kinds of information appear below, and each is labelled.{" "}
        <Chain /> is read from Arc Testnet when the page loads.{" "}
        <Log /> is what the agent printed during its run — the chain does not
        record it, so anything checkable carries a transaction hash.{" "}
        <Static /> is committed source. Nothing here is estimated.
      </p>

      {/* ---------------------------------------------------------------- */}
      <section className="section">
        <div className="section-head">
          <h2>1. The bounty board <Chain /></h2>
          <RefreshButton />
        </div>
        <p className="provenance-note">
          Read from the Registry at{" "}
          <a href={`${EXPLORER}/address/${REGISTRY_ADDRESS}`} target="_blank" rel="noreferrer">
            <code>{REGISTRY_ADDRESS}</code>
          </a>
          . Reads happen on the server and are cached, so a hundred people
          opening this page cost one set of RPC calls, not a hundred. There is no
          auto-refresh — the button above is the only thing that re-reads.
        </p>

        {!board.ok ? (
          <div className="error">
            <h3>The RPC did not answer</h3>
            <p>
              The page is fine; Arc&apos;s public endpoint did not respond. Try the
              refresh button, or read the board directly on{" "}
              <a href={`${EXPLORER}/address/${REGISTRY_ADDRESS}`} target="_blank" rel="noreferrer">
                Arcscan
              </a>
              .
            </p>
            <p className="mono">{board.message}</p>
          </div>
        ) : (
          <>
            <div className="summary-row">
              <span>
                <b>{board.bounties.length}</b> bounties opened
              </span>
              <span>
                <b>{board.claimableCount}</b> still claimable
              </span>
              <span>
                <b>{board.totalEscrowed} USDC</b> escrowed in total
              </span>
              <span>read at {new Date(board.readAt).toUTCString()}</span>
            </div>

            {board.bounties.map((b) => {
              const dead = !b.paid && b.invariantHolds === false;
              const cls = b.paid ? "card claimed" : dead ? "card dead" : "card";
              const isTheClaimedOne = b.paid && b.id === RUN_LOG.chosenBountyId;
              return (
                <div className={cls} key={b.id}>
                  <div className="bounty-head">
                    <span className="bid">#{b.id}</span>
                    <span className="reward">{b.reward} USDC</span>
                    {b.paid ? (
                      <span className="status claimed">claimed by an agent</span>
                    ) : dead ? (
                      <span className="status dead">invariant already broken — unclaimable</span>
                    ) : (
                      <span className="status open">open</span>
                    )}
                  </div>
                  <dl className="kv">
                    <dt>target</dt>
                    <dd>
                      <a className="mono" href={`${EXPLORER}/address/${b.target}`} target="_blank" rel="noreferrer">
                        {b.target}
                      </a>
                    </dd>
                    <dt>checker</dt>
                    <dd>
                      <a className="mono" href={`${EXPLORER}/address/${b.checker}`} target="_blank" rel="noreferrer">
                        {b.checker}
                      </a>
                    </dd>
                    <dt>callable function</dt>
                    <dd>
                      <code>{b.functionSignature}</code> <span style={{ color: "var(--muted)" }}>selector <code>{b.selector}</code></span>
                    </dd>
                    {isTheClaimedOne && (
                      <>
                        <dt>winning tx</dt>
                        <dd>
                          <a className="mono" href={`${EXPLORER}/tx/${RUN_LOG.txHash}`} target="_blank" rel="noreferrer">
                            {short(RUN_LOG.txHash)}
                          </a>{" "}
                          <Log />
                        </dd>
                      </>
                    )}
                  </dl>
                </div>
              );
            })}
          </>
        )}
      </section>

      {/* ---------------------------------------------------------------- */}
      <section className="section">
        <h2>2. The break <Log /></h2>
        <p className="provenance-note">
          Everything in this section is what the agent printed on{" "}
          {RUN_LOG.when}. The chain does not record &ldquo;it broke on the 6th
          probe&rdquo; — only that one transaction claimed the bounty. That
          transaction is linked, so the parts that can be checked, can be.
        </p>

        <div className="card claimed">
          <p>
            The agent scanned the board and chose <b>bounty #{RUN_LOG.chosenBountyId}</b>{" "}
            ({RUN_LOG.chosenReward} USDC) because {RUN_LOG.whyChosen}. It then
            generated inputs <b>{RUN_LOG.strategy}</b> and broke the invariant on{" "}
            <b>probe {RUN_LOG.winningProbe}</b>.
          </p>

          <dl className="kv">
            <dt>winning value</dt>
            <dd>
              <code>{RUN_LOG.winningValue}</code> — {RUN_LOG.winningValueLabel}
            </dd>
            <dt>transaction</dt>
            <dd>
              <a className="mono" href={`${EXPLORER}/tx/${RUN_LOG.txHash}`} target="_blank" rel="noreferrer">
                {RUN_LOG.txHash}
              </a>
            </dd>
            <dt>agent wallet</dt>
            <dd>
              <a className="mono" href={`${EXPLORER}/address/${RUN_LOG.agentAddress}`} target="_blank" rel="noreferrer">
                {RUN_LOG.agentAddress}
              </a>
            </dd>
            <dt>balance</dt>
            <dd>
              {RUN_LOG.balanceBefore} → {RUN_LOG.balanceAfter} USDC ({RUN_LOG.netChange} after gas)
            </dd>
            {RUN_LOG.rpcCalls !== undefined && (
              <>
                <dt>rpc cost</dt>
                <dd>
                  {RUN_LOG.rpcCalls} calls, {RUN_LOG.elapsedSeconds}s,{" "}
                  {RUN_LOG.throttled} throttled, {RUN_LOG.realErrors} real errors
                </dd>
              </>
            )}
          </dl>
        </div>

        <h3 style={{ marginTop: 20 }}>What it tried before it landed <Log /></h3>
        <table>
          <thead>
            <tr>
              <th>probe</th>
              <th>value</th>
              <th>result</th>
            </tr>
          </thead>
          <tbody>
            {RUN_LOG.probesBefore.map((p) => (
              <tr key={p.probe}>
                <td>{p.probe}</td>
                <td><code>{p.value}</code></td>
                <td>{p.outcome}</td>
              </tr>
            ))}
            <tr className="hit">
              <td>{RUN_LOG.winningProbe}</td>
              <td><code>{RUN_LOG.winningValue}</code></td>
              <td className="bv-label">broke the invariant — bounty paid</td>
            </tr>
          </tbody>
        </table>
      </section>

      {/* ---------------------------------------------------------------- */}
      <section className="section">
        <h2>3. The boundary value list <Static /></h2>
        <p className="provenance-note">
          Generated from <code>{boundaries.generatedFrom}</code>, the file the
          agent actually reads. This is the answer to the obvious question: the
          same person wrote the target and the agent, so how do you know the
          agent was not simply told where the bug is?
        </p>
        <p>
          Read the list. It contains no threshold from the target and nothing
          specific to it — these are the values a tester tries against{" "}
          <em>any</em> function taking a <code>uint256</code> amount, before
          knowing anything about the contract. The planted bug happens to sit at{" "}
          <code>1e18</code>. That value is on the list because &ldquo;one whole
          unit at 18 decimals&rdquo; is the most common amount in DeFi and the
          first round number anyone tries — not because the agent knew. That is
          why it is 6th and not 1st.
        </p>
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>value</th>
              <th>why a tester tries it</th>
            </tr>
          </thead>
          <tbody>
            {boundaries.entries.map((b, i) => {
              const isWinner = b.value === RUN_LOG.winningValue;
              return (
                <tr key={b.value} className={isWinner ? "hit" : undefined}>
                  <td>{i + 1}</td>
                  <td>
                    <div className="bv-label">{b.label}</div>
                    <code>{b.expression}</code>
                  </td>
                  <td>
                    {b.why}
                    {isWinner && (
                      <>
                        {" "}
                        <b>← this is the one that broke the target.</b>
                      </>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </section>

      <footer>
        <p>
          Read-only. No wallet connection, no writes, no way to trigger the agent
          from this page. Chain reads happen on the server and are cached; open
          your browser&apos;s network tab and you will see no RPC traffic.
        </p>
        <p>
          Source:{" "}
          <a href="https://github.com/hoanghieu512/proof-of-break" target="_blank" rel="noreferrer">
            github.com/hoanghieu512/proof-of-break
          </a>{" "}
          · Registry on{" "}
          <a href={`${EXPLORER}/address/${REGISTRY_ADDRESS}`} target="_blank" rel="noreferrer">
            Arcscan
          </a>
        </p>
      </footer>
    </main>
  );
}

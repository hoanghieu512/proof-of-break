"use client";

import { useTransition } from "react";
import { refreshBoard } from "./actions";

/**
 * The only client component on the page, and the only way to trigger a fresh
 * read. Deliberately a button and not a timer: an interval here would multiply
 * RPC load by viewers × time, against a budget the agent shares.
 */
export function RefreshButton() {
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      className="refresh"
      disabled={pending}
      onClick={() =>
        startTransition(async () => {
          await refreshBoard();
        })
      }
    >
      {pending ? "reading chain…" : "↻ Refresh from chain"}
    </button>
  );
}

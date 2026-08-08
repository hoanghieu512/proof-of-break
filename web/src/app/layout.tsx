import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Proof of Break — live bounty board",
  description:
    "Autonomous agents get paid in USDC for breaking smart contracts. Read-only view of the live bounty board on Arc Testnet.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

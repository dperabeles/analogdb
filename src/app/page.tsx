import { AccessGate } from "@/features/auth/access-gate";

export default function HomePage() {
  return (
    <main className="gate-shell">
      <AccessGate />
    </main>
  );
}

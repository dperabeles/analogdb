import Link from "next/link";
import { STATUS_LABELS, type RollListItem } from "@/features/rolls/roll-types";

type DashboardOverviewProps = {
  rolls: RollListItem[];
};

const FORMAT_OPTIONS = [
  { key: "35mm", label: "35", color: "#d97150" },
  { key: "120", label: "120", color: "#5a8aad" },
  { key: "Super8", label: "S8", color: "#c8a048" },
  { key: "110", label: "110", color: "#b85c00" },
  { key: "16mm", label: "16", color: "#2a7a4a" },
  { key: "Large Format", label: "LF", color: "#7c5cbf" }
];

const WORKFLOW_STATUSES = [
  { key: "In Camera", title: "En cámara", num: "I", className: "s-incamera" },
  { key: "To Develop", title: "Por revelar", num: "II", className: "s-todevelop" },
  { key: "In Development", title: "En revelado", num: "III", className: "s-indevelopment" }
];

function formatKey(value: string | null) {
  return String(value || "").trim().toLowerCase().replace(/\s+/g, "");
}

function countFormat(rolls: RollListItem[], key: string) {
  const target = formatKey(key);
  return rolls.filter((roll) => formatKey(roll.format) === target).length;
}

function stockColor(stock: string) {
  const value = stock.toLowerCase();
  if (value.includes("portra") || value.includes("ektar")) return "#c8785a";
  if (value.includes("gold") || value.includes("ultramax")) return "#d4a050";
  if (value.includes("hp5") || value.includes("delta") || value.includes("fp4")) return "#6a6a6a";
  if (value.includes("velvia") || value.includes("provia") || value.includes("fuji")) return "#5a8a6a";
  if (value.includes("tmax") || value.includes("tri-x") || value.includes("400tx")) return "#505050";
  if (value.includes("cinestill")) return "#c84848";
  return "#9c9284";
}

function topStocks(rolls: RollListItem[]) {
  const counts = new Map<string, number>();
  rolls.forEach((roll) => {
    if (!roll.filmStock) return;
    counts.set(roll.filmStock, (counts.get(roll.filmStock) || 0) + 1);
  });
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6);
}

function oldestRollYear(rolls: RollListItem[]) {
  const years = rolls
    .map((roll) => roll.started)
    .filter((value): value is string => Boolean(value))
    .map((value) => new Date(`${value}T12:00:00`).getFullYear())
    .filter(Number.isFinite);
  return years.length ? Math.min(...years) : new Date().getFullYear();
}

function formatDate(value: string | null) {
  if (!value) return "—";
  return new Date(`${value}T12:00:00`).toLocaleDateString("es-MX", {
    day: "2-digit",
    month: "short",
    year: "numeric"
  });
}

function workflowRolls(rolls: RollListItem[], status: string) {
  return rolls
    .filter((roll) => roll.status === status)
    .sort((a, b) => String(b.started || "").localeCompare(String(a.started || "")));
}

function RollWorkflowCard({ roll, className }: { roll: RollListItem; className: string }) {
  const format = roll.format || "—";
  const freshLabel = roll.expFresh === "FRESH" ? "Fresh" : roll.expFresh || "—";
  const dateLabel = roll.status === "In Camera"
    ? `Iniciado: ${formatDate(roll.started)}`
    : `${formatDate(roll.started)}${roll.finished ? ` -> ${formatDate(roll.finished)}` : ""}`;

  return (
    <Link className={`roll-card ${className}`} href={`/rolls/${encodeURIComponent(roll.code)}`}>
      <div className="roll-card-header">
        <div>
          <div className="roll-card-name">{roll.filmStock || "—"}</div>
          <div className="roll-card-maker">{roll.manufacturer || ""}</div>
        </div>
        <span className={`roll-card-status ${className}`}>{STATUS_LABELS[roll.status] || roll.status}</span>
      </div>
      <div className="roll-card-body">
        <div className="roll-card-chips">
          <span className="roll-card-chip">{freshLabel}</span>
          <span className="roll-card-chip">{format}</span>
          {roll.iso ? <span className="roll-card-chip">ISO {roll.iso}</span> : null}
          {roll.frameSettings ? <span className="roll-card-chip settings">Settings {roll.frameSettings}</span> : null}
        </div>
        <div className="roll-card-meta">
          {roll.modelName ? (
            <div className="roll-card-meta-row">
              <span>{roll.modelName}</span>
              {roll.maker ? ` · ${roll.maker}` : ""}
            </div>
          ) : null}
          {roll.locations ? (
            <div className="roll-card-meta-row">
              <span>{roll.locations}</span>
            </div>
          ) : null}
          {roll.status === "In Development" && roll.dev ? (
            <div className="roll-card-meta-row">
              <span>{roll.dev}</span>
            </div>
          ) : null}
          <div className="roll-card-meta-row">
            <span>{dateLabel}</span>
          </div>
        </div>
      </div>
    </Link>
  );
}

export function DashboardOverview({ rolls }: DashboardOverviewProps) {
  const total = rolls.length;
  const stocks = topStocks(rolls);
  const maxStock = stocks[0]?.[1] || 1;

  return (
    <>
      <section className="dashboard-section">
        <div className="ed-section-head">
          <div className="ed-section-num">I.</div>
          <div>
            <h2 className="ed-section-title">Tu film, <em>de un vistazo</em></h2>
            <div className="ed-section-sub">Inventario general del archivo</div>
          </div>
        </div>

        <div className="ed-index-grid">
          <div>
            <div className="ed-index-kicker">EN NÚMEROS</div>
            <div className="ed-number-block">
              <div className="ed-big-num">{total}</div>
              <div className="ed-number-copy">rollos desde {oldestRollYear(rolls)}</div>
            </div>
            <div className="ed-format-boxes">
              {FORMAT_OPTIONS.map((format) => {
                const count = countFormat(rolls, format.key);
                return (
                  <div className="ed-format-box" key={format.key} style={{ borderTopColor: format.color }}>
                    <div className="ed-format-box-label" style={{ color: format.color }}>
                      {format.label.toUpperCase()}
                    </div>
                    <div className="ed-format-num">{count}</div>
                    <div className="ed-format-pct">{total ? Math.round((count / total) * 100) : 0}% del archivo</div>
                  </div>
                );
              })}
            </div>
          </div>

          <div>
            <div className="ed-index-kicker">STOCKS FAVORITOS</div>
            <div className="ed-stock-list">
              {stocks.length ? stocks.map(([stock, count], index) => (
                <div className="ed-stock-row" key={stock}>
                  <span className="ed-stock-num">{String(index + 1).padStart(2, "0")}</span>
                  <span className="ed-stock-swatch" style={{ background: stockColor(stock) }} />
                  <span className="ed-stock-copy">
                    <span className="ed-stock-name">{stock}</span>
                    <span className="ed-stock-brand">{(stock.split(" ")[0] || "").toUpperCase()}</span>
                  </span>
                  <span className="ed-stock-bar-wrap">
                    <span className="ed-stock-bar" style={{ width: `${(count / maxStock) * 100}%` }} />
                  </span>
                  <span className="ed-stock-count">{count}</span>
                </div>
              )) : <div className="status-empty">Sin stocks registrados</div>}
            </div>
          </div>
        </div>
      </section>

      <section className="dashboard-section">
        <div className="ed-section-head">
          <div className="ed-section-num">II.</div>
          <div>
            <h2 className="ed-section-title">Tu film, <em>en curso</em></h2>
            <div className="ed-section-sub">Rollos activos, por etapa</div>
          </div>
        </div>

        <div className="ed-workflow">
          {WORKFLOW_STATUSES.map((status) => {
            const visible = workflowRolls(rolls, status.key);
            return (
              <div className="ed-workflow-col" key={status.key}>
                <div className="ed-workflow-head">
                  <div className="ed-workflow-title-wrap">
                    <span>{status.num}</span>
                    <span className="ed-workflow-title">{status.title}</span>
                  </div>
                  <span className={`ed-workflow-count${visible.length ? " live" : ""}`}>
                    {String(visible.length).padStart(2, "0")}
                  </span>
                </div>
                <div className="roll-cards">
                  {visible.length ? visible.map((roll) => (
                    <RollWorkflowCard className={status.className} key={roll.id} roll={roll} />
                  )) : (
                    <p className="status-empty">ninguno</p>
                  )}
                </div>
                {status.key === "In Camera" ? (
                  <Link className="ed-add-card" href="/rolls/new">
                    + Cargar rollo
                  </Link>
                ) : null}
              </div>
            );
          })}
        </div>
      </section>
    </>
  );
}

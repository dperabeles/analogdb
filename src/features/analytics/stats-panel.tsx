import type { AnalyticsOverview, Leader } from "@/features/analytics/queries";

type StatsPanelProps = {
  overview: AnalyticsOverview;
};

function percent(count: number, total: number) {
  if (!total) return 0;
  return Math.round((count / total) * 100);
}

function MetricGrid({ overview }: StatsPanelProps) {
  const color = overview.filmTypeCounts.find((item) => item.label === "COLOR")?.count || 0;
  const bw = overview.filmTypeCounts.find((item) => item.label === "B/W")?.count || 0;
  const push = overview.rolls.filter((roll) => roll.pushPull !== "0").length;

  return (
    <div className="status-grid">
      <div className="status-cell">
        <div className="status-label">Total</div>
        <div className="status-value">{overview.total}</div>
      </div>
      <div className="status-cell">
        <div className="status-label">Color</div>
        <div className="status-value">{color}</div>
      </div>
      <div className="status-cell">
        <div className="status-label">B/W</div>
        <div className="status-value">{bw}</div>
      </div>
      <div className="status-cell">
        <div className="status-label">Push/Pull</div>
        <div className="status-value">{push}</div>
      </div>
    </div>
  );
}

function Leaderboard({ title, subtitle, leaders, total }: { title: string; subtitle: string; leaders: Leader[]; total: number }) {
  const max = leaders[0]?.count || 1;
  return (
    <section className="analytics-section">
      <div className="analytics-section-head">
        <div>
          <h2>{title}</h2>
          <p>{subtitle}</p>
        </div>
      </div>
      <div className="analytics-list">
        {leaders.length ? (
          leaders.map((leader, index) => (
            <div className="analytics-row" key={leader.label}>
              <span className="analytics-rank">{String(index + 1).padStart(2, "0")}</span>
              <span className="analytics-name">{leader.label}</span>
              <span className="analytics-bar-wrap">
                <span className="analytics-bar" style={{ width: `${(leader.count / max) * 100}%` }} />
              </span>
              <span className="analytics-count">{leader.count}</span>
              <span className="analytics-percent">{percent(leader.count, total)}%</span>
            </div>
          ))
        ) : (
          <div className="empty-state">Sin datos suficientes.</div>
        )}
      </div>
    </section>
  );
}

export function StatsPanel({ overview }: StatsPanelProps) {
  return (
    <div className="analytics-panel">
      {overview.error ? <p className="auth-message auth-message-error">No se pudieron cargar stats: {overview.error}</p> : null}
      <MetricGrid overview={overview} />
      <Leaderboard title="Tipo de rollo" subtitle="Distribucion por emulsion" leaders={overview.filmTypeCounts} total={overview.total} />
      <Leaderboard title="Formatos" subtitle="Peliculas por tamano fisico" leaders={overview.formatCounts} total={overview.total} />
      <Leaderboard title="Stocks favoritos" subtitle="Top de peliculas mas usadas" leaders={overview.stockLeaders} total={overview.total} />
      <Leaderboard title="Laboratorios" subtitle="Revelado y escaneo" leaders={overview.labLeaders} total={overview.total} />
      <Leaderboard title="Camaras" subtitle="Equipo mas utilizado" leaders={overview.cameraLeaders} total={overview.total} />
      <Leaderboard title="Ubicaciones" subtitle="Lugares mas fotografiados" leaders={overview.locationLeaders} total={overview.total} />
      <Leaderboard title="Categorias" subtitle="Tipos de fotografia" leaders={overview.photoTypeLeaders} total={overview.total} />
      <Leaderboard title="Tags" subtitle="Etiquetas recurrentes" leaders={overview.tagLeaders} total={overview.total} />
    </div>
  );
}

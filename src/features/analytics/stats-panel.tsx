import type { AnalyticsOverview, Leader } from "@/features/analytics/queries";

type StatsPanelProps = {
  overview: AnalyticsOverview;
};

function percent(count: number, total: number) {
  if (!total) return 0;
  return Math.round((count / total) * 100);
}

function countFor(leaders: Leader[], label: string) {
  return leaders.find((item) => item.label.toUpperCase() === label.toUpperCase())?.count || 0;
}

function swatchColor(label: string) {
  const value = label.toLowerCase();
  if (value.includes("portra") || value.includes("ektar")) return "#c8785a";
  if (value.includes("gold") || value.includes("ultramax")) return "#d4a050";
  if (value.includes("hp5") || value.includes("delta") || value.includes("fp4")) return "#6a6a6a";
  if (value.includes("velvia") || value.includes("provia") || value.includes("fuji")) return "#5a8a6a";
  if (value.includes("tmax") || value.includes("tri-x") || value.includes("400tx")) return "#505050";
  if (value.includes("cinestill")) return "#c84848";
  return "#9c9284";
}

function formatColor(label: string) {
  const value = label.toLowerCase();
  if (value.includes("120")) return "#9b72cf";
  if (value.includes("110")) return "#5aaf7a";
  if (value.includes("instant") || value.includes("polaroid")) return "#d4a050";
  if (value.includes("sheet") || value.includes("4x5")) return "#5b9bd5";
  return "#d94a2a";
}

function SectionHead({ num, title, subtitle }: { num: string; title: string; subtitle: string }) {
  return (
    <div className="ed-section-head">
      <div className="ed-section-num">{num}.</div>
      <div className="ed-section-copy">
        <h2 className="ed-section-title">{title}</h2>
        <div className="ed-section-sub">{subtitle}</div>
      </div>
    </div>
  );
}

function FormatBox({ label, count, total, color }: { label: string; count: number; total: number; color: string }) {
  return (
    <div className="ed-format-box" style={{ borderTopColor: color }}>
      <div className="ed-format-box-label" style={{ color }}>
        {label}
      </div>
      <div className="ed-format-num">{count}</div>
      <div className="ed-format-pct">{percent(count, total)}% del archivo</div>
    </div>
  );
}

function Leaderboard({
  num,
  title,
  subtitle,
  leaders,
  total,
  barColor = "#d94a2a",
  swatch = swatchColor,
  sub
}: {
  num: string;
  title: string;
  subtitle: string;
  leaders: Leader[];
  total: number;
  barColor?: string;
  swatch?: (label: string) => string;
  sub?: (label: string) => string;
}) {
  const max = leaders[0]?.count || 1;
  return (
    <section className="analytics-section">
      <SectionHead num={num} title={title} subtitle={subtitle} />
      <div className="ed-stock-list">
        {leaders.length ? (
          leaders.map((leader, index) => (
            <div className="ed-stock-row" key={leader.label}>
              <span className="ed-stock-num">{String(index + 1).padStart(2, "0")}</span>
              <span className="ed-stock-swatch" style={{ background: swatch(leader.label) }} />
              <span className="ed-stock-copy">
                <span className="ed-stock-name">{leader.label}</span>
                <span className="ed-stock-brand">{sub?.(leader.label) || `${percent(leader.count, total)}% del archivo`}</span>
              </span>
              <span className="ed-stock-bar-wrap">
                <span className="ed-stock-bar" style={{ width: `${(leader.count / max) * 100}%`, background: barColor }} />
              </span>
              <span className="ed-stock-count">{leader.count}</span>
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
  const typeRows = [
    { label: "COLOR", count: countFor(overview.filmTypeCounts, "COLOR"), color: "#d94a2a" },
    { label: "B / W", count: countFor(overview.filmTypeCounts, "B/W"), color: "#9a9080" },
    { label: "SLIDE", count: countFor(overview.filmTypeCounts, "SLIDE"), color: "#6a9de0" }
  ];

  return (
    <div className="analytics-panel">
      {overview.error ? <p className="auth-message auth-message-error">No se pudieron cargar stats: {overview.error}</p> : null}
      <section className="analytics-section">
        <SectionHead num="I" title="Tipo de rollo" subtitle="Distribución por emulsión del archivo" />
        <div className="ed-format-boxes">
          {typeRows.map((row) => (
            <FormatBox key={row.label} label={row.label} count={row.count} total={overview.total} color={row.color} />
          ))}
        </div>
      </section>
      <section className="analytics-section">
        <SectionHead num="II" title="Formatos" subtitle="Películas por tamaño físico" />
        <div className="ed-format-boxes analytics-format-grid">
          {overview.formatCounts.length ? (
            overview.formatCounts.map((format) => (
              <FormatBox
                key={format.label}
                label={format.label.toUpperCase()}
                count={format.count}
                total={overview.total}
                color={formatColor(format.label)}
              />
            ))
          ) : (
            <div className="empty-state">Sin formatos registrados.</div>
          )}
        </div>
      </section>
      <Leaderboard
        num="III"
        title="Stocks favoritos"
        subtitle="Top 10 de películas más usadas"
        leaders={overview.stockLeaders}
        total={overview.total}
        sub={(label) => (label.split(" ")[0] || "").toUpperCase()}
      />
      <Leaderboard
        num="IV"
        title="Laboratorios"
        subtitle="Dónde se reveló cada rollo"
        leaders={overview.labLeaders}
        total={overview.total}
        barColor="#5b9bd5"
        swatch={() => "#5b9bd5"}
      />
      <Leaderboard
        num="V"
        title="Cámaras"
        subtitle="Equipo más utilizado"
        leaders={overview.cameraLeaders}
        total={overview.total}
        barColor="#9b72cf"
        swatch={() => "#9b72cf"}
      />
      <Leaderboard
        num="VI"
        title="Ubicaciones"
        subtitle="Lugares más fotografiados"
        leaders={overview.locationLeaders}
        total={overview.total}
        barColor="#5aaf7a"
        swatch={() => "#5aaf7a"}
      />
      <Leaderboard
        num="VII"
        title="Categorías"
        subtitle="Tipos de fotografía"
        leaders={overview.photoTypeLeaders}
        total={overview.total}
        barColor="#c07a30"
        swatch={() => "#c07a30"}
      />
      <Leaderboard
        num="VIII"
        title="Tags"
        subtitle="Etiquetas recurrentes"
        leaders={overview.tagLeaders}
        total={overview.total}
        barColor="#6a9de0"
        swatch={() => "#6a9de0"}
      />
    </div>
  );
}

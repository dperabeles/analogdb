import Link from "next/link";
import { STATUS_LABELS, type RollListItem } from "@/features/rolls/roll-types";
import type { AnalyticsOverview } from "@/features/analytics/queries";

type TimelinePanelProps = {
  overview: AnalyticsOverview;
};

function effectiveDate(roll: RollListItem) {
  return roll.finished || roll.started || "";
}

function dateLabel(value: string) {
  if (!value) return "Sin fecha";
  const date = new Date(`${value}T12:00:00`);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString("es-MX", { day: "2-digit", month: "short", year: "numeric" });
}

export function TimelinePanel({ overview }: TimelinePanelProps) {
  const { timelineGroups } = overview;
  return (
    <div className="timeline-panel">
      {overview.error ? <p className="auth-message auth-message-error">No se pudo cargar timeline: {overview.error}</p> : null}
      {timelineGroups.length ? (
        timelineGroups.map((group) => (
          <section className="timeline-month" key={group.key}>
            <div className="timeline-month-label">
              {group.year ? <span>{group.year}</span> : null}
              <h2>{group.month || "Sin fecha"}</h2>
            </div>
            <div className="timeline-month-body">
              <div className="timeline-month-count">
                {group.rolls.length} {group.rolls.length === 1 ? "rollo" : "rollos"}
              </div>
              <div className="timeline-rolls">
                {group.rolls.map((roll) => (
                  <Link className="timeline-row" href={`/rolls/${encodeURIComponent(roll.code)}`} key={roll.code}>
                    <span className="timeline-date">{dateLabel(effectiveDate(roll))}</span>
                    <span className="timeline-code">{roll.code}</span>
                    <span className="timeline-main">
                      <strong>{roll.filmStock || "-"}</strong>
                      <small>{roll.manufacturer || ""}</small>
                    </span>
                    <span className="timeline-badges">
                      <span>{roll.format || "-"}</span>
                      <span>{STATUS_LABELS[roll.status] || roll.status}</span>
                    </span>
                    <span className="timeline-main">
                      <strong>{roll.modelName || "-"}</strong>
                      <small>{roll.maker || ""}</small>
                    </span>
                  </Link>
                ))}
              </div>
            </div>
          </section>
        ))
      ) : (
        <div className="empty-state">Todavia no hay rollos fechados.</div>
      )}
    </div>
  );
}

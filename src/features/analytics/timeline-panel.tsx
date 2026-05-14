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
  if (!value) return "—";
  const date = new Date(`${value}T12:00:00`);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString("es-MX", { day: "2-digit", month: "short", year: "numeric" });
}

function badgeClass(value: string | null) {
  if (value === "COLOR") return "badge badge-color";
  if (value === "B/W") return "badge badge-bw";
  if (value === "SLIDE") return "badge badge-slide";
  return "badge";
}

export function TimelinePanel({ overview }: TimelinePanelProps) {
  const { timelineGroups } = overview;
  return (
    <div className="timeline-wrap">
      {overview.error ? <p className="auth-message auth-message-error">No se pudo cargar timeline: {overview.error}</p> : null}
      {timelineGroups.length ? (
        timelineGroups.map((group) => (
          <section className="tl-month" key={group.key}>
            <div className="tl-month-label">
              {group.year ? <div className="tl-month-year">{group.year}</div> : null}
              <div className="tl-month-name">{group.month || "Sin fecha"}</div>
            </div>
            <div className="tl-month-body">
              <div className="tl-month-head">
                <span className="tl-month-dot" />
                <span className="tl-month-count">
                  {group.rolls.length} {group.rolls.length === 1 ? "rollo" : "rollos"}
                </span>
              </div>
              <div className="tl-month-rolls">
                {group.rolls.map((roll) => (
                  <Link className="tl-row" href={`/rolls/${encodeURIComponent(roll.code)}`} key={roll.code}>
                    <span className="tl-date">{dateLabel(effectiveDate(roll))}</span>
                    <span className="tl-id">{roll.code}</span>
                    <span className="tl-stack tl-film">
                      <span className="tl-primary">{roll.filmStock || "—"}</span>
                      <span className="tl-secondary">{roll.manufacturer || ""}</span>
                    </span>
                    <span className="tl-badges">
                      {roll.filmType ? <span className={badgeClass(roll.filmType)}>{roll.filmType}</span> : null}
                      {roll.format ? <span className="badge">{roll.format}</span> : null}
                      <span className="badge">{STATUS_LABELS[roll.status] || roll.status}</span>
                    </span>
                    <span className="tl-stack tl-cam">
                      <span className="tl-primary">{roll.modelName || "—"}</span>
                      <span className="tl-secondary">{roll.maker || ""}</span>
                    </span>
                    <span className="tl-notes">{roll.notes || ""}</span>
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

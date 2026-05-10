import { getRolls } from "@/features/rolls/queries";
import type { RollListItem } from "@/features/rolls/roll-types";

export type Leader = {
  label: string;
  count: number;
};

export type TimelineGroup = {
  key: string;
  year: string;
  month: string;
  undated: boolean;
  rolls: RollListItem[];
};

export type AnalyticsOverview = {
  rolls: RollListItem[];
  total: number;
  filmTypeCounts: Leader[];
  formatCounts: Leader[];
  stockLeaders: Leader[];
  labLeaders: Leader[];
  cameraLeaders: Leader[];
  locationLeaders: Leader[];
  photoTypeLeaders: Leader[];
  tagLeaders: Leader[];
  timelineGroups: TimelineGroup[];
  error: string | null;
};

const MONTHS_ES = [
  "Enero",
  "Febrero",
  "Marzo",
  "Abril",
  "Mayo",
  "Junio",
  "Julio",
  "Agosto",
  "Septiembre",
  "Octubre",
  "Noviembre",
  "Diciembre"
];

function splitList(value: string | null) {
  if (!value) return [];
  return value
    .split(value.includes("|") ? "|" : /[,;]/)
    .map((item) => item.trim().replace(/^#/, ""))
    .filter(Boolean);
}

function countValues(values: (string | null | undefined)[]) {
  const counts = new Map<string, number>();
  for (const value of values) {
    const clean = String(value || "").trim();
    if (!clean) continue;
    counts.set(clean, (counts.get(clean) || 0) + 1);
  }
  return [...counts.entries()]
    .map(([label, count]) => ({ label, count }))
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}

function countExpanded(rolls: RollListItem[], field: keyof RollListItem) {
  return countValues(rolls.flatMap((roll) => splitList(String(roll[field] || ""))));
}

function effectiveDate(roll: RollListItem) {
  return roll.finished || roll.started || "";
}

function buildTimelineGroups(rolls: RollListItem[]) {
  const dated = rolls
    .filter((roll) => effectiveDate(roll))
    .sort((a, b) => effectiveDate(b).localeCompare(effectiveDate(a)) || b.id - a.id);
  const undated = rolls.filter((roll) => !effectiveDate(roll));
  const groups: TimelineGroup[] = [];

  for (const roll of dated) {
    const date = effectiveDate(roll);
    const key = date.slice(0, 7);
    let group = groups.find((item) => item.key === key);
    if (!group) {
      const [year, month] = key.split("-");
      group = {
        key,
        year: year || "",
        month: MONTHS_ES[(Number(month) || 1) - 1] || month || "",
        undated: false,
        rolls: []
      };
      groups.push(group);
    }
    group.rolls.push(roll);
  }

  if (undated.length) {
    groups.push({
      key: "undated",
      year: "",
      month: "Sin fecha",
      undated: true,
      rolls: undated.sort((a, b) => b.id - a.id)
    });
  }

  return groups;
}

export async function getAnalyticsOverview(): Promise<AnalyticsOverview> {
  const { rolls, error } = await getRolls();
  const labValues = rolls.flatMap((roll) => [roll.dev, roll.scan]).filter(Boolean) as string[];
  const cameraValues = rolls.map((roll) => [roll.maker, roll.modelName].filter(Boolean).join(" "));

  return {
    rolls,
    total: rolls.length,
    filmTypeCounts: countValues(rolls.map((roll) => roll.filmType)),
    formatCounts: countValues(rolls.map((roll) => roll.format)),
    stockLeaders: countValues(rolls.map((roll) => roll.filmStock)).slice(0, 10),
    labLeaders: countValues(labValues).slice(0, 8),
    cameraLeaders: countValues(cameraValues).slice(0, 8),
    locationLeaders: countExpanded(rolls, "locations").slice(0, 8),
    photoTypeLeaders: countExpanded(rolls, "photoType").slice(0, 8),
    tagLeaders: countExpanded(rolls, "tags").slice(0, 10),
    timelineGroups: buildTimelineGroups(rolls),
    error
  };
}

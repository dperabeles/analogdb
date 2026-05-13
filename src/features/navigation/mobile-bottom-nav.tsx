import Link from "next/link";

type MobileBottomNavProps = {
  active: "dashboard" | "new" | "stats" | "timeline" | "equipment" | "admin" | "detail" | "edit";
};

const ITEMS = [
  { key: "dashboard", href: "/dashboard", label: "Data" },
  { key: "new", href: "/rolls/new", label: "Nuevo" },
  { key: "stats", href: "/stats", label: "Stats" },
  { key: "timeline", href: "/timeline", label: "Timeline" },
  { key: "equipment", href: "/equipment", label: "Equipo" }
] as const;

export function MobileBottomNav({ active }: MobileBottomNavProps) {
  return (
    <nav className="mobile-bottom-nav" aria-label="Navegacion movil">
      {ITEMS.map((item) => (
        <Link
          aria-current={active === item.key ? "page" : undefined}
          className="mobile-bottom-nav-item"
          href={item.href}
          key={item.key}
        >
          {item.label}
        </Link>
      ))}
    </nav>
  );
}

import Link from "next/link";

type MobileBottomNavProps = {
  active: "dashboard" | "database" | "new" | "stats" | "timeline" | "equipment" | "account" | "admin" | "detail" | "edit";
};

const ITEMS = [
  { key: "dashboard", href: "/dashboard", label: "Dash" },
  { key: "database", href: "/database", label: "Data" },
  { key: "stats", href: "/stats", label: "Stats" },
  { key: "account", href: "/account", label: "Cuenta" }
] as const;

export function MobileBottomNav({ active }: MobileBottomNavProps) {
  return (
    <nav className="mobile-bottom-nav" aria-label="Navegacion movil">
      <Link
        aria-current={active === ITEMS[0].key ? "page" : undefined}
        className="mobile-bottom-nav-item"
        href={ITEMS[0].href}
      >
        {ITEMS[0].label}
      </Link>
      <Link
        aria-current={active === ITEMS[1].key ? "page" : undefined}
        className="mobile-bottom-nav-item"
        href={ITEMS[1].href}
      >
        {ITEMS[1].label}
      </Link>
      <Link
        aria-current={active === "new" ? "page" : undefined}
        className="mobile-bottom-nav-fab"
        href="/rolls/new"
        aria-label="Cargar rollo nuevo"
      >
        <span>+</span>
        Nuevo
      </Link>
      {ITEMS.slice(2).map((item) => (
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

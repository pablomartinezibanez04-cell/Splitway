// admin/components/shared/sidebar.tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Home, Map, Settings, Users } from "lucide-react";

const NAV_ITEMS = [
  { href: "/", label: "Inicio", icon: Home },
  { href: "/users", label: "Usuarios", icon: Users },
  { href: "/routes", label: "Rutas", icon: Map },
  { href: "/settings", label: "Configuración", icon: Settings },
] as const;

export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="hidden w-56 shrink-0 border-r bg-background md:flex md:flex-col">
      <div className="flex h-14 items-center border-b px-4 font-semibold">
        Splitway Admin
      </div>
      <nav className="flex-1 space-y-1 p-2 text-sm">
        {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
          const active =
            href === "/" ? pathname === "/" : pathname.startsWith(href);
          return (
            <Link
              key={href}
              href={href}
              className={
                "flex items-center gap-2 rounded-md px-3 py-2 transition-colors " +
                (active
                  ? "bg-accent text-accent-foreground"
                  : "text-muted-foreground hover:bg-accent hover:text-accent-foreground")
              }
            >
              <Icon className="h-4 w-4" />
              {label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}

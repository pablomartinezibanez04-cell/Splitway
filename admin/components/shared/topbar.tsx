// admin/components/shared/topbar.tsx
import { ThemeToggle } from "@/components/shared/theme-toggle";
import { Button } from "@/components/ui/button";
import { signOut } from "@/app/(dashboard)/actions";
import type { AdminProfile } from "@/lib/auth";

export function Topbar({ admin }: { admin: AdminProfile }) {
  return (
    <header className="flex h-14 items-center justify-between border-b px-4">
      <div className="text-sm text-muted-foreground">
        <span className="font-medium text-foreground">{admin.email}</span>
        <span className="ml-2 rounded-md bg-muted px-2 py-0.5 text-xs">
          {admin.role}
        </span>
      </div>
      <div className="flex items-center gap-2">
        <ThemeToggle />
        <form action={signOut}>
          <Button type="submit" variant="outline" size="sm">
            Cerrar sesión
          </Button>
        </form>
      </div>
    </header>
  );
}

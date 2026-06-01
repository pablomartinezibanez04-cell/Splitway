// admin/app/(dashboard)/users/[id]/page.tsx
import { notFound } from "next/navigation";
import Link from "next/link";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs";
import { ProfileTab } from "./profile-tab";
import { ActivityTab } from "./activity-tab";
import { GarageTab } from "./garage-tab";
import { RoutesTab } from "./routes-tab";
import { LogsTab } from "./logs-tab";
import { BanDialog } from "./ban-dialog";
import { ResetPasswordDialog } from "./reset-password-dialog";

export const dynamic = "force-dynamic";

export default async function UserDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const admin = await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  const { data: row } = await supabase
    .from("admin_users_view")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (!row || !row.id) notFound();

  const { data: profileRow } = await supabase
    .from("profiles")
    .select("bio")
    .eq("id", row.id)
    .maybeSingle();
  const initialBio = profileRow?.bio ?? "";

  const isBanned =
    !!row.banned_until && new Date(row.banned_until) > new Date();

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm">
        <Link href="/users">← Volver a usuarios</Link>
      </Button>

      <div className="flex items-start gap-4">
        <div className="h-16 w-16 overflow-hidden rounded-full bg-muted">
          {row.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={row.avatar_url}
              alt=""
              className="h-full w-full object-cover"
            />
          ) : null}
        </div>
        <div className="flex-1 space-y-1">
          <h1 className="text-2xl font-semibold">{row.nickname || "—"}</h1>
          <p className="text-sm text-muted-foreground">{row.email}</p>
          <div className="flex items-center gap-2">
            <Badge
              variant={
                row.role === "superadmin"
                  ? "default"
                  : row.role === "admin"
                    ? "secondary"
                    : "outline"
              }
            >
              {row.role ?? "user"}
            </Badge>
            <Badge variant={isBanned ? "destructive" : "outline"}>
              {isBanned ? "Baneado" : "Activo"}
            </Badge>
          </div>
        </div>
      </div>

      <Tabs defaultValue="profile" className="space-y-4">
        <TabsList>
          <TabsTrigger value="profile">Perfil</TabsTrigger>
          <TabsTrigger value="activity">Actividad</TabsTrigger>
          <TabsTrigger value="garage">Garaje</TabsTrigger>
          <TabsTrigger value="routes">Rutas</TabsTrigger>
          <TabsTrigger value="logs">Logs</TabsTrigger>
        </TabsList>

        <TabsContent value="profile">
          <ProfileTab
            userId={row.id}
            initialNickname={row.nickname ?? ""}
            initialBio={initialBio}
            currentRole={row.role ?? "user"}
            actorRole={admin.role}
          />
        </TabsContent>
        <TabsContent value="activity">
          <ActivityTab userId={row.id} />
        </TabsContent>
        <TabsContent value="garage">
          <GarageTab userId={row.id} />
        </TabsContent>
        <TabsContent value="routes">
          <RoutesTab userId={row.id} />
        </TabsContent>
        <TabsContent value="logs">
          <LogsTab userId={row.id} />
        </TabsContent>
      </Tabs>

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <div className="flex flex-wrap gap-2">
          <BanDialog
            userId={row.id}
            userEmail={row.email ?? ""}
            isBanned={isBanned}
            bannedUntil={row.banned_until}
          />
          <ResetPasswordDialog
            userId={row.id}
            userEmail={row.email ?? ""}
          />
        </div>
      </div>
    </div>
  );
}

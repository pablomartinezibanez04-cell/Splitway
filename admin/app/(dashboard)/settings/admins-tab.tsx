// admin/app/(dashboard)/settings/admins-tab.tsx
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { adminClient } from "@/lib/supabase/admin";
import type { AdminProfile } from "@/lib/auth";
import { PromoteForm } from "./promote-form";
import { DemoteButton } from "./demote-button";

export async function AdminsTab({
  currentAdmin,
}: {
  currentAdmin: AdminProfile;
}) {
  // Authorization invariant: this component relies on its caller having
  // already gated the route via requireAdmin(). The `currentAdmin` prop is
  // the proof. If reusing this component from a new entry point, ensure
  // the caller calls requireAdmin() first — otherwise adminClient() will
  // leak the full admin list and auth user emails.
  const supabase = adminClient();
  const { data: admins } = await supabase
    .from("profiles")
    .select("id, nickname, role")
    .in("role", ["admin", "superadmin"])
    .order("role", { ascending: true })
    .order("nickname", { ascending: true });

  // Pull emails via the auth admin API (profiles only stores ids).
  const { data: usersList } = await supabase.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  const emailById = new Map(
    usersList?.users.map((u) => [u.id, u.email ?? "—"]) ?? [],
  );

  const isSuperadmin = currentAdmin.role === "superadmin";

  return (
    <div className="space-y-6">
      {isSuperadmin ? (
        <Card>
          <CardHeader>
            <CardTitle>Promover a admin</CardTitle>
          </CardHeader>
          <CardContent>
            <PromoteForm />
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>Administradores actuales</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nickname</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Rol</TableHead>
                {isSuperadmin ? (
                  <TableHead className="w-24 text-right">Acciones</TableHead>
                ) : null}
              </TableRow>
            </TableHeader>
            <TableBody>
              {(admins ?? []).map((a) => (
                <TableRow key={a.id}>
                  <TableCell className="font-medium">
                    {a.nickname || "—"}
                  </TableCell>
                  <TableCell>{emailById.get(a.id) ?? "—"}</TableCell>
                  <TableCell>
                    <Badge variant={a.role === "superadmin" ? "default" : "secondary"}>
                      {a.role}
                    </Badge>
                  </TableCell>
                  {isSuperadmin ? (
                    <TableCell className="text-right">
                      {a.role === "admin" && a.id !== currentAdmin.id ? (
                        <DemoteButton userId={a.id} nickname={a.nickname} />
                      ) : null}
                    </TableCell>
                  ) : null}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}

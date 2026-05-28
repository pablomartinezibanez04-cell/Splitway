// admin/app/(dashboard)/page.tsx
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { requireAdmin } from "@/lib/auth";

export default async function DashboardHome() {
  const admin = await requireAdmin();

  return (
    <Card className="mx-auto max-w-2xl">
      <CardHeader>
        <CardTitle>Bienvenido</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <p className="text-sm text-muted-foreground">
          Sesión iniciada como{" "}
          <span className="font-medium">{admin.email}</span> (
          <span className="font-medium">{admin.role}</span>).
        </p>
        <p className="text-sm text-muted-foreground">
          El dashboard real con métricas se construye en la fase F7. Mientras
          tanto, usa <span className="font-medium">Configuración</span> en la
          barra lateral para gestionar administradores.
        </p>
      </CardContent>
    </Card>
  );
}

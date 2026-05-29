// admin/app/(dashboard)/settings/page.tsx
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { requireAdmin } from "@/lib/auth";
import { MyAccountForm } from "./my-account-form";
import { AdminsTab } from "./admins-tab";

export default async function SettingsPage() {
  const admin = await requireAdmin();

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Configuración</h1>
        <p className="text-sm text-muted-foreground">
          Gestiona tu cuenta y los administradores del panel.
        </p>
      </div>

      <Tabs defaultValue="account" className="space-y-4">
        <TabsList>
          <TabsTrigger value="account">Mi cuenta</TabsTrigger>
          <TabsTrigger value="admins">Administradores</TabsTrigger>
        </TabsList>

        <TabsContent value="account">
          <MyAccountForm />
        </TabsContent>

        <TabsContent value="admins">
          <AdminsTab currentAdmin={admin} />
        </TabsContent>
      </Tabs>
    </div>
  );
}

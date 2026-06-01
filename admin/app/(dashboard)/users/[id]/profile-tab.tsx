// admin/app/(dashboard)/users/[id]/profile-tab.tsx
"use client";

import { useActionState, useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { editUserProfile, type EditProfileState } from "./actions";

const initialState: EditProfileState = {};

export function ProfileTab({
  userId,
  initialNickname,
  currentRole,
  actorRole,
}: {
  userId: string;
  initialNickname: string;
  currentRole: string;
  actorRole: "admin" | "superadmin";
}) {
  const [state, formAction, isPending] = useActionState(
    editUserProfile,
    initialState,
  );
  const [bio, setBio] = useState<string>("");

  useEffect(() => {
    if (state.ok) toast.success("Perfil actualizado.");
  }, [state]);

  const isSuperadmin = actorRole === "superadmin";

  return (
    <Card>
      <CardHeader>
        <CardTitle>Perfil</CardTitle>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="space-y-4">
          <input type="hidden" name="userId" value={userId} />
          <div className="space-y-2">
            <Label htmlFor="nickname">Apodo</Label>
            <Input
              id="nickname"
              name="nickname"
              defaultValue={initialNickname}
              minLength={2}
              maxLength={24}
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="bio">Bio</Label>
            <textarea
              id="bio"
              name="bio"
              value={bio}
              onChange={(e) => setBio(e.target.value)}
              maxLength={500}
              className="flex min-h-[80px] w-full rounded-md border bg-transparent px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
          <div className="space-y-2">
            <Label>Rol</Label>
            {isSuperadmin ? (
              <p className="text-sm text-muted-foreground">
                Para cambiar el rol usa <strong>Configuración →
                Administradores</strong>. (Rol actual:{" "}
                <span className="font-medium">{currentRole}</span>.)
              </p>
            ) : (
              <p className="text-sm text-muted-foreground">
                Rol actual: <span className="font-medium">{currentRole}</span>.
                Solo los superadmins pueden cambiar roles.
              </p>
            )}
          </div>
          {state.error ? (
            <p
              role="alert"
              className="text-sm text-destructive"
              aria-live="polite"
            >
              {state.error}
            </p>
          ) : null}
          <Button type="submit" disabled={isPending}>
            {isPending ? "Guardando…" : "Guardar"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}

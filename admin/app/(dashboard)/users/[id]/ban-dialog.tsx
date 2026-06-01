// admin/app/(dashboard)/users/[id]/ban-dialog.tsx
"use client";

import { useActionState, useEffect, useState } from "react";
import { toast } from "sonner";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { banUser, unbanUser, type BanState } from "./actions";

const initialState: BanState = {};

// 100 years × 365 days × 24 hours ≈ practical "permanent".
const PERMANENT_HOURS = 100 * 365 * 24;

const DURATIONS: { label: string; hours: number }[] = [
  { label: "1 hora", hours: 1 },
  { label: "24 horas", hours: 24 },
  { label: "7 días", hours: 24 * 7 },
  { label: "30 días", hours: 24 * 30 },
  { label: "Permanente", hours: PERMANENT_HOURS },
];

export function BanDialog({
  userId,
  userEmail,
  isBanned,
  bannedUntil,
}: {
  userId: string;
  userEmail: string;
  isBanned: boolean;
  bannedUntil: string | null;
}) {
  if (isBanned) {
    return (
      <UnbanButton userId={userId} userEmail={userEmail} until={bannedUntil} />
    );
  }
  return <BanButton userId={userId} userEmail={userEmail} />;
}

function BanButton({
  userId,
  userEmail,
}: {
  userId: string;
  userEmail: string;
}) {
  const [state, formAction, isPending] = useActionState(banUser, initialState);
  const [hours, setHours] = useState<string>("24");

  useEffect(() => {
    if (state.ok) toast.success("Usuario baneado.");
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Banear</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Banear a {userEmail}</AlertDialogTitle>
          <AlertDialogDescription>
            Mientras dure el ban el usuario no podrá iniciar sesión. Esta
            acción queda registrada en el audit log.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction} className="space-y-3">
          <input type="hidden" name="userId" value={userId} />
          <input type="hidden" name="durationHours" value={hours} />
          <Select value={hours} onValueChange={setHours}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {DURATIONS.map((d) => (
                <SelectItem key={d.hours} value={String(d.hours)}>
                  {d.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Aplicando…" : "Banear"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function UnbanButton({
  userId,
  userEmail,
  until,
}: {
  userId: string;
  userEmail: string;
  until: string | null;
}) {
  const [state, formAction, isPending] = useActionState(
    unbanUser,
    initialState,
  );

  useEffect(() => {
    if (state.ok) toast.success("Ban levantado.");
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="outline">
          Quitar ban{until ? ` (hasta ${new Date(until).toLocaleDateString()})` : ""}
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Levantar ban de {userEmail}</AlertDialogTitle>
          <AlertDialogDescription>
            El usuario podrá iniciar sesión de nuevo inmediatamente.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="userId" value={userId} />
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Quitando…" : "Quitar ban"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}

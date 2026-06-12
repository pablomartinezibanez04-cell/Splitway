// admin/app/(dashboard)/users/[id]/reset-password-dialog.tsx
"use client";

import { useActionState, useEffect } from "react";
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
import { resetUserPassword, type ResetState } from "./actions";

const initialState: ResetState = {};

export function ResetPasswordDialog({
  userId,
  userEmail,
}: {
  userId: string;
  userEmail: string;
}) {
  const [state, formAction, isPending] = useActionState(
    resetUserPassword,
    initialState,
  );

  useEffect(() => {
    if (state.ok) toast.success("Email de reseteo enviado.");
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="outline">Resetear contraseña</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Resetear contraseña</AlertDialogTitle>
          <AlertDialogDescription>
            Se enviará un email a <strong>{userEmail}</strong> con un enlace
            para fijar una nueva contraseña.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="userId" value={userId} />
          {/* email is resolved server-side from userId — not trusted from
              the form (see actions.ts / audit SEC-5). */}
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Enviando…" : "Enviar"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}

// admin/app/(dashboard)/sessions/speed-sessions/[id]/delete-dialog.tsx
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
import { deleteSpeedSession, type DeleteState } from "./actions";

const initialState: DeleteState = {};

export function DeleteSpeedSessionDialog({
  speedSessionId,
}: {
  speedSessionId: string;
}) {
  const [state, formAction, isPending] = useActionState(
    deleteSpeedSession,
    initialState,
  );
  useEffect(() => {
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Eliminar sesión</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Eliminar sesión de velocidad</AlertDialogTitle>
          <AlertDialogDescription>
            La fila quedará marcada como borrada (<code className="rounded bg-muted px-1">deleted_at</code>) y dejará de aparecer en la lista. La cuenta del usuario y los datos crudos se preservan por si hubiera una disputa.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="speedSessionId" value={speedSessionId} />
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Eliminando…" : "Eliminar"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}

// admin/app/(dashboard)/sessions/free-rides/[id]/delete-dialog.tsx
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
import { deleteFreeRide, type DeleteState } from "./actions";

const initialState: DeleteState = {};

export function DeleteFreeRideDialog({ freeRideId }: { freeRideId: string }) {
  const [state, formAction, isPending] = useActionState(
    deleteFreeRide,
    initialState,
  );
  useEffect(() => {
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Eliminar salida</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Eliminar salida libre</AlertDialogTitle>
          <AlertDialogDescription>
            Se borrará la salida y todos sus puntos de telemetría
            (<code className="rounded bg-muted px-1">ON DELETE CASCADE</code>).
            No se puede deshacer.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="freeRideId" value={freeRideId} />
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

// admin/app/(dashboard)/routes/[id]/delete-dialog.tsx
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
import { deleteRoute, type DeleteRouteState } from "./actions";

const initialState: DeleteRouteState = {};

export function DeleteRouteDialog({
  routeId,
  routeName,
}: {
  routeId: string;
  routeName: string;
}) {
  const [state, formAction, isPending] = useActionState(
    deleteRoute,
    initialState,
  );

  useEffect(() => {
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Eliminar ruta</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Eliminar {routeName}</AlertDialogTitle>
          <AlertDialogDescription>
            Esta acción borrará la ruta y sus sectores. Las sesiones que
            apunten a ella quedarán huérfanas (route_id pasa a null). No se
            puede deshacer.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="routeId" value={routeId} />
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

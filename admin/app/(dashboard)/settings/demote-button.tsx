// admin/app/(dashboard)/settings/demote-button.tsx
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
import { demoteAdmin, type PromoteState } from "./actions";

const initialState: PromoteState = {};

export function DemoteButton({
  userId,
  nickname,
}: {
  userId: string;
  nickname: string;
}) {
  const [state, formAction, isPending] = useActionState(
    demoteAdmin,
    initialState,
  );

  useEffect(() => {
    if (state.ok) toast.success("Admin degradado a usuario.");
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="outline" size="sm">
          Degradar
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Degradar a {nickname || "usuario"}</AlertDialogTitle>
          <AlertDialogDescription>
            Perderá el acceso al panel de administración. Esta acción se puede
            revertir promoviéndolo de nuevo.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="userId" value={userId} />
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Degradando…" : "Degradar"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}

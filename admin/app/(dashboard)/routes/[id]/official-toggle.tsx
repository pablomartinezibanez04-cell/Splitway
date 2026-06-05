// admin/app/(dashboard)/routes/[id]/official-toggle.tsx
"use client";

import { useActionState, useEffect } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  toggleRouteOfficial,
  duplicateRouteAsOfficial,
  type ToggleOfficialState,
  type DuplicateState,
} from "./actions";

const initialToggle: ToggleOfficialState = {};
const initialDup: DuplicateState = {};

export function OfficialControls({
  routeId,
  isOfficial,
}: {
  routeId: string;
  isOfficial: boolean;
}) {
  const [toggleState, toggleAction, togglePending] = useActionState(
    toggleRouteOfficial,
    initialToggle,
  );
  const [dupState, dupAction, dupPending] = useActionState(
    duplicateRouteAsOfficial,
    initialDup,
  );

  useEffect(() => {
    if (toggleState.ok) {
      toast.success(
        isOfficial ? "Marca de oficial retirada." : "Ruta marcada como oficial.",
      );
    }
    if (toggleState.error) toast.error(toggleState.error);
  }, [toggleState, isOfficial]);

  useEffect(() => {
    if (dupState.error) toast.error(dupState.error);
  }, [dupState]);

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Badge variant={isOfficial ? "default" : "outline"}>
        {isOfficial ? "Oficial" : "Comunidad"}
      </Badge>
      <form action={toggleAction}>
        <input type="hidden" name="routeId" value={routeId} />
        <input
          type="hidden"
          name="isOfficial"
          value={isOfficial ? "false" : "true"}
        />
        <Button type="submit" variant="outline" size="sm" disabled={togglePending}>
          {togglePending
            ? "Aplicando…"
            : isOfficial
              ? "Quitar marca oficial"
              : "Marcar como oficial"}
        </Button>
      </form>
      <form action={dupAction}>
        <input type="hidden" name="routeId" value={routeId} />
        <Button type="submit" variant="outline" size="sm" disabled={dupPending}>
          {dupPending ? "Duplicando…" : "Duplicar como oficial"}
        </Button>
      </form>
    </div>
  );
}

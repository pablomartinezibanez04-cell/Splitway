// admin/app/(dashboard)/routes/[id]/metadata-form.tsx
"use client";

import { useActionState, useEffect } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { editRoute, type EditRouteState } from "./actions";

const initialState: EditRouteState = {};

export function MetadataForm({
  routeId,
  initialName,
  initialDescription,
  initialDifficulty,
  initialLocationLabel,
}: {
  routeId: string;
  initialName: string;
  initialDescription: string;
  initialDifficulty: string;
  initialLocationLabel: string;
}) {
  const [state, formAction, isPending] = useActionState(
    editRoute,
    initialState,
  );

  useEffect(() => {
    if (state.ok) toast.success("Ruta actualizada.");
  }, [state]);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Metadatos</CardTitle>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="space-y-4">
          <input type="hidden" name="routeId" value={routeId} />
          <div className="space-y-2">
            <Label htmlFor="name">Nombre</Label>
            <Input
              id="name"
              name="name"
              defaultValue={initialName}
              maxLength={120}
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="description">Descripción</Label>
            <textarea
              id="description"
              name="description"
              defaultValue={initialDescription}
              maxLength={2000}
              className="flex min-h-[80px] w-full rounded-md border bg-transparent px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="difficulty">Dificultad</Label>
            <select
              id="difficulty"
              name="difficulty"
              defaultValue={initialDifficulty}
              className="flex h-9 w-40 rounded-md border bg-transparent px-3 py-1 text-sm shadow-sm"
            >
              <option value="easy">easy</option>
              <option value="medium">medium</option>
              <option value="hard">hard</option>
              <option value="extreme">extreme</option>
            </select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="locationLabel">Ubicación</Label>
            <Input
              id="locationLabel"
              name="locationLabel"
              defaultValue={initialLocationLabel}
              maxLength={200}
            />
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

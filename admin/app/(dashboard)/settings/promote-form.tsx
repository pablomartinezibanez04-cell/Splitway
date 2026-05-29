// admin/app/(dashboard)/settings/promote-form.tsx
"use client";

import { useActionState, useEffect, useRef } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { promoteAdmin, type PromoteState } from "./actions";

const initialState: PromoteState = {};

export function PromoteForm() {
  const [state, formAction, isPending] = useActionState(
    promoteAdmin,
    initialState,
  );
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (state.ok) {
      toast.success("Usuario promovido a admin.");
      formRef.current?.reset();
    }
  }, [state]);

  return (
    <form ref={formRef} action={formAction} className="flex items-end gap-3">
      <div className="flex-1 space-y-2">
        <Label htmlFor="promote-email">Email del usuario</Label>
        <Input
          id="promote-email"
          name="email"
          type="email"
          autoComplete="off"
          required
        />
      </div>
      <Button type="submit" disabled={isPending}>
        {isPending ? "Promoviendo…" : "Promover"}
      </Button>
      {state.error ? (
        <p
          role="alert"
          className="ml-3 text-sm text-destructive"
          aria-live="polite"
        >
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

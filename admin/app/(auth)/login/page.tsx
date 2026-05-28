// admin/app/(auth)/login/page.tsx
"use client";

import { Suspense, useActionState } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { signIn, type SignInState } from "./actions";

const initialState: SignInState = {};

function ForbiddenBanner() {
  const searchParams = useSearchParams();
  const forbidden = searchParams.get("error") === "forbidden";

  if (!forbidden) return null;

  return (
    <p
      role="alert"
      className="mb-4 rounded-md border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive"
      aria-live="polite"
    >
      Tu cuenta no tiene acceso al panel de administración.
    </p>
  );
}

function LoginForm() {
  const [state, formAction, isPending] = useActionState(signIn, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="password">Contraseña</Label>
        <Input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
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
      <Button type="submit" className="w-full" disabled={isPending}>
        {isPending ? "Entrando…" : "Entrar"}
      </Button>
    </form>
  );
}

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-muted px-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Splitway Admin</CardTitle>
        </CardHeader>
        <CardContent>
          <Suspense>
            <ForbiddenBanner />
          </Suspense>
          <LoginForm />
        </CardContent>
      </Card>
    </main>
  );
}

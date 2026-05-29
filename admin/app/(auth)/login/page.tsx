// admin/app/(auth)/login/page.tsx
"use client";

import { Suspense, useActionState } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/browser";
import { signIn, type SignInState } from "./actions";

const initialState: SignInState = {};

function LoginBanner() {
  const searchParams = useSearchParams();
  const error = searchParams.get("error");

  if (error === "forbidden") {
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

  if (error === "oauth_failed") {
    return (
      <p
        role="alert"
        className="mb-4 rounded-md border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive"
        aria-live="polite"
      >
        No se pudo completar el inicio de sesión con Google. Inténtalo de nuevo.
      </p>
    );
  }

  return null;
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

function GoogleButton() {
  async function handleClick() {
    const supabase = createClient();
    await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${window.location.origin}/auth/callback`,
      },
    });
  }

  return (
    <Button
      type="button"
      variant="outline"
      className="w-full"
      onClick={handleClick}
    >
      Continuar con Google
    </Button>
  );
}

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-muted px-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Splitway Admin</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Suspense>
            <LoginBanner />
          </Suspense>
          <LoginForm />
          <div className="relative">
            <div className="absolute inset-0 flex items-center">
              <span className="w-full border-t" />
            </div>
            <div className="relative flex justify-center text-xs uppercase">
              <span className="bg-card px-2 text-muted-foreground">o</span>
            </div>
          </div>
          <GoogleButton />
        </CardContent>
      </Card>
    </main>
  );
}

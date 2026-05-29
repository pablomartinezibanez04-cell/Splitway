// admin/app/(onboarding)/layout.tsx
// Minimal layout used by onboarding screens. No sidebar / topbar so a
// signed-in admin with an incomplete profile is not tempted to navigate
// elsewhere — the middleware will bounce them back anyway, but giving
// them no navigation surface is the cleanest UX.
export default function OnboardingLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <main className="flex min-h-screen items-center justify-center bg-muted p-4">
      {children}
    </main>
  );
}

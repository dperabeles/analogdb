import type { AccessProfile, AccessState } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";

type AccessStatusProps = {
  state: Exclude<AccessState, "public" | "approved">;
  profile: AccessProfile | null;
};

const COPY = {
  pending: {
    eyebrow: "Pending",
    title: "Tu acceso está en revisión.",
    body: "Tu cuenta ya existe, pero el archivo seguirá bloqueado hasta que un admin la apruebe."
  },
  rejected: {
    eyebrow: "Access closed",
    title: "Tu solicitud fue rechazada.",
    body: "Esta cuenta no tiene acceso activo. Si fue un error, el ajuste debe hacerse desde administración."
  },
  invalid: {
    eyebrow: "Profile error",
    title: "La sesión no está lista.",
    body: "La cuenta existe en Auth, pero el perfil de aplicación está incompleto o inválido."
  }
};

export function AccessStatus({ state, profile }: AccessStatusProps) {
  const copy = COPY[state];

  return (
    <section className="auth-status">
      <div className="eyebrow">{copy.eyebrow}</div>
      <h1>{copy.title}</h1>
      <p className="lead">{copy.body}</p>
      {profile ? (
        <div className="status-grid compact">
          <div className="status-cell">
            <div className="status-label">Cuenta</div>
            <div className="status-note">{profile.email}</div>
          </div>
          <div className="status-cell">
            <div className="status-label">Display</div>
            <div className="status-note">{profile.displayName || "Sin nombre visible"}</div>
          </div>
        </div>
      ) : null}
      <div className="actions">
        <SignOutButton />
      </div>
    </section>
  );
}

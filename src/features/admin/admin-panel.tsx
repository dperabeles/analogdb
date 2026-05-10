import {
  requestAdminRoleChangeAction,
  setProfileStatusAction,
  voteAdminAction
} from "@/features/admin/actions";
import type { AdminAction, AdminOverview, AdminProfile, AdminRole } from "@/features/admin/queries";
import type { ReactNode } from "react";

type AdminPanelProps = {
  overview: AdminOverview;
};

function displayName(profile: AdminProfile) {
  return profile.display_name || "-";
}

function RolePill({ profile, roster }: { profile: AdminProfile; roster: AdminRole[] }) {
  const role = roster.find((item) => item.user_id === profile.user_id);
  if (role?.is_founder) return <span className="admin-pill accent">Founder</span>;
  if (role?.role === "admin") return <span className="admin-pill solid">Admin</span>;
  return <span className="admin-pill">User</span>;
}

function ProfileCard({
  profile,
  children,
  urgent = false
}: {
  profile: AdminProfile;
  children?: ReactNode;
  urgent?: boolean;
}) {
  return (
    <article className={`admin-card${urgent ? " urgent" : ""}`}>
      <div className="admin-card-main">
        <strong>{displayName(profile)}</strong>
        <span>{profile.email}</span>
        <small>{profile.status}</small>
      </div>
      {children ? <div className="admin-card-actions">{children}</div> : null}
    </article>
  );
}

function StatusButton({
  profile,
  status,
  children,
  tone = "secondary"
}: {
  profile: AdminProfile;
  status: AdminProfile["status"];
  children: ReactNode;
  tone?: "primary" | "secondary" | "danger";
}) {
  return (
    <form action={setProfileStatusAction}>
      <input type="hidden" name="targetUserId" value={profile.user_id} />
      <input type="hidden" name="status" value={status} />
      <button className={`${tone}-action`} type="submit">
        {children}
      </button>
    </form>
  );
}

function RoleActionButton({
  profile,
  actionType,
  children,
  tone = "secondary"
}: {
  profile: AdminProfile;
  actionType: AdminAction["action_type"];
  children: ReactNode;
  tone?: "secondary" | "danger";
}) {
  return (
    <form action={requestAdminRoleChangeAction}>
      <input type="hidden" name="targetUserId" value={profile.user_id} />
      <input type="hidden" name="actionType" value={actionType} />
      <button className={`${tone}-action`} type="submit">
        {children}
      </button>
    </form>
  );
}

function VoteButton({
  action,
  decision,
  children,
  tone
}: {
  action: AdminAction;
  decision: "approved" | "rejected";
  children: ReactNode;
  tone: "primary" | "secondary";
}) {
  return (
    <form action={voteAdminAction}>
      <input type="hidden" name="actionId" value={action.id} />
      <input type="hidden" name="decision" value={decision} />
      <button className={`${tone}-action`} type="submit">
        {children}
      </button>
    </form>
  );
}

function PendingUsers({ profiles }: { profiles: AdminProfile[] }) {
  if (!profiles.length) return <div className="empty-state">No hay usuarios pendientes.</div>;

  return profiles.map((profile) => (
    <ProfileCard key={profile.user_id} profile={profile} urgent>
      <StatusButton profile={profile} status="approved" tone="primary">
        Aprobar
      </StatusButton>
      <StatusButton profile={profile} status="rejected">
        Rechazar
      </StatusButton>
    </ProfileCard>
  ));
}

function ApprovedUsers({ profiles, roster }: { profiles: AdminProfile[]; roster: AdminRole[] }) {
  if (!profiles.length) return <div className="empty-state">No hay usuarios aprobados.</div>;

  const adminIds = new Set(roster.map((role) => role.user_id));
  const founderIds = new Set(roster.filter((role) => role.is_founder).map((role) => role.user_id));

  return profiles.map((profile) => {
    const isAdmin = adminIds.has(profile.user_id);
    const isFounder = founderIds.has(profile.user_id);
    return (
      <ProfileCard key={profile.user_id} profile={profile}>
        <RolePill profile={profile} roster={roster} />
        {!isAdmin ? (
          <RoleActionButton profile={profile} actionType="promote_to_admin">
            Solicitar admin
          </RoleActionButton>
        ) : null}
        {isAdmin && !isFounder ? (
          <RoleActionButton profile={profile} actionType="demote_from_admin" tone="danger">
            Solicitar downgrade
          </RoleActionButton>
        ) : null}
      </ProfileCard>
    );
  });
}

function RejectedUsers({ profiles }: { profiles: AdminProfile[] }) {
  if (!profiles.length) return <div className="empty-state">No hay usuarios rechazados.</div>;

  return profiles.map((profile) => (
    <ProfileCard key={profile.user_id} profile={profile}>
      <StatusButton profile={profile} status="pending" tone="primary">
        Reactivar
      </StatusButton>
    </ProfileCard>
  ));
}

function actionLabel(action: AdminAction) {
  if (action.action_type === "promote_to_admin") return "Promover a admin";
  if (action.action_type === "demote_from_admin") return "Quitar admin";
  return action.action_type;
}

function AdminActions({ actions }: { actions: AdminAction[] }) {
  if (!actions.length) return <div className="empty-state">No hay acciones sensibles registradas.</div>;

  return actions.map((action) => (
    <article className={`admin-card${action.status === "pending" ? " urgent" : ""}`} key={action.id}>
      <div className="admin-card-main">
        <strong>{actionLabel(action)}</strong>
        <span>Target: {action.target_user_id}</span>
        <small>{action.status}</small>
        {action.resolved_reason ? <span>{action.resolved_reason}</span> : null}
      </div>
      {action.status === "pending" ? (
        <div className="admin-card-actions">
          <VoteButton action={action} decision="approved" tone="primary">
            Aprobar
          </VoteButton>
          <VoteButton action={action} decision="rejected" tone="secondary">
            Rechazar
          </VoteButton>
        </div>
      ) : null}
    </article>
  ));
}

export function AdminPanel({ overview }: AdminPanelProps) {
  return (
    <div className="admin-panel">
      {overview.error ? <p className="auth-message auth-message-error">No se pudo cargar admin: {overview.error}</p> : null}
      <section className="admin-section">
        <div className="admin-section-head">
          <span>I.</span>
          <h2>Pending</h2>
          <strong>{overview.pending.length}</strong>
        </div>
        <PendingUsers profiles={overview.pending} />
      </section>
      <section className="admin-section">
        <div className="admin-section-head">
          <span>II.</span>
          <h2>Aprobados</h2>
          <strong>{overview.approved.length}</strong>
        </div>
        <ApprovedUsers profiles={overview.approved} roster={overview.roster} />
      </section>
      <section className="admin-section">
        <div className="admin-section-head">
          <span>III.</span>
          <h2>Usuarios rechazados</h2>
          <strong>{overview.rejected.length}</strong>
        </div>
        <RejectedUsers profiles={overview.rejected} />
      </section>
      <section className="admin-section">
        <div className="admin-section-head">
          <span>IV.</span>
          <h2>Acciones admin</h2>
          <strong>{overview.actions.filter((action) => action.status === "pending").length}</strong>
        </div>
        <AdminActions actions={overview.actions} />
      </section>
    </div>
  );
}

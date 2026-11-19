/// The web app is paused (Diego, 17-nov): until it is rebuilt like the app,
/// the web is only the home page. These pages send there; their code stays
/// so the web app can come back. The pages the e-mails open (/confirm,
/// /forgot-password, /reset-password) and the legal pages are not here.
export const PAUSED_WEBAPP_PATHS = [
  "/dashboard",
  "/rolls",
  "/stats",
  "/equipment",
  "/account",
  "/admin",
  "/timeline",
  "/database",
] as const;

/// The page itself or anything under it: /rolls and /rolls/12, not /rollsx.
export function isPausedWebappPath(pathname: string): boolean {
  return PAUSED_WEBAPP_PATHS.some((p) => pathname === p || pathname.startsWith(`${p}/`));
}

import { headers } from "next/headers";
import { type AccessLang, resolveAccessLang } from "./access-lang";

export type AccessPageProps = {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

/// For an access page: `?lang=` from the email link, then the request's
/// Accept-Language, then Spanish.
export async function accessLangFor(props: AccessPageProps): Promise<AccessLang> {
  const params = (await props.searchParams) ?? {};
  const accept = (await headers()).get("accept-language");
  return resolveAccessLang(params.lang, accept);
}

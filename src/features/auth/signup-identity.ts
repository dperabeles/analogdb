type SignupRequest = {
  email: string;
  password: string;
  options: { data: { display_name: string; username: string } };
};

type SignupResult = { ok: true; request: SignupRequest } | { ok: false; error: string };

export function buildSignupRequest(form: FormData): SignupResult {
  const displayName = String(form.get("displayName") || "").trim();
  if (displayName.length < 3 || displayName.length > 20) {
    return { ok: false, error: "El nombre debe tener entre 3 y 20 caracteres." };
  }

  // Only ASCII case normalization matches the server and keeps Unicode
  // lookalikes invalid. Remove one leading @, never all pasted @ characters.
  const username = String(form.get("username") || "")
    .trim()
    .replace(/^@/, "")
    .replace(/[A-Z]/g, (letter) => letter.toLowerCase());
  if (username.length < 3 || username.length > 24 || !/^[a-z0-9]+([._][a-z0-9]+)*$/.test(username)) {
    return {
      ok: false,
      error: "El nombre de usuario debe tener de 3 a 24 letras o números; usa punto o guion bajo sólo entre ellos."
    };
  }
  return {
    ok: true,
    request: {
      email: String(form.get("email") || "").trim(),
      password: String(form.get("password") || ""),
      options: { data: { display_name: displayName, username } }
    }
  };
}

#!/usr/bin/env python3
"""
Register the Scaleway SAML Service Provider in a fresh Authentik IdP via the
Authentik API (stdlib only): creates the SAML provider + "Scaleway"
application, then prints the IdP entity ID / SSO URL and signing cert for
bootstrap's `sso:` block.

Usage (run after `terraform apply`; needs the bootstrap token + SP metadata):
    python3 configure_scw_saml.py \
      --base-url   https://<idp-fqdn> \
      --bootstrap-token <AKADMIN_BOOTSTRAP_TOKEN> \
      --sp-entity-id <stage0 sp_entity_id> \
      --sp-acs-url  <stage0 acs_url> \
      --slug scaleway

Best-effort helper for Scaleway's "Set up SSO with Authentik" flow; adapt if
the Authentik API shape drifts. Does NOT touch the Scaleway side - bootstrap
still owns that config.
"""

import argparse
import base64
import json
import ssl
import sys
import urllib.error
import urllib.request

DEFAULT_SLUG = "scaleway"
NAME_ID_UNSPECIFIED = "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"


class ApiError(RuntimeError):
    pass


class Authentik:
    def __init__(self, base_url, insecure=False):
        self.base = base_url.rstrip("/")
        self.ctx = ssl.create_default_context()
        if insecure:
            self.ctx.check_hostname = False
            self.ctx.verify_mode = ssl.CERT_NONE

    def _call(self, method, path, payload=None, basic=None, bearer=None):
        url = self.base + path
        body = json.dumps(payload).encode() if payload is not None else None
        headers = {}
        if basic:
            token = base64.b64encode(b"akadmin:" + basic.encode()).decode()
            headers["Authorization"] = "Basic " + token
        elif bearer:
            headers["Authorization"] = "Bearer " + bearer
        if body is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, context=self.ctx) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:500]
            raise ApiError(f"HTTP {e.code} {e.reason} on {method} {path}: {detail}") from e
        except urllib.error.URLError as e:
            raise ApiError(f"Could not reach {url}: {e.reason}") from e

    # -- bootstrap auth ----------------------------------------------------
    def validate_bootstrap(self, token):
        return self._call("POST", "/api/v3/core/users/me/", basic=token)

    def create_api_token(self, token, identifier):
        resp = self._call(
            "POST", "/api/v3/core/tokens/", basic=token,
            payload={"identifier": identifier, "intent": "api", "expiring": False},
        )
        key = (resp or {}).get("key")
        if not key:
            raise ApiError("token creation returned no key")
        return key

    # -- flows -------------------------------------------------------------
    def authorization_flow(self, bearer):
        resp = self._call("GET", "/api/v3/flows/instances/?ordering=slug", bearer=bearer)
        for f in resp.get("results", []):
            if f.get("designation") == "authorization":
                return f["pk"]
        raise ApiError("no authorization flow found - create one in the Authentik UI first")

    # -- SAML provider + application --------------------------------------
    def create_saml_provider(self, bearer, flow_pk, name, issuer, acs_url):
        return self._call(
            "POST", "/api/v3/providers/saml/", bearer=bearer,
            payload={
                "name": name,
                "authorization_flow": flow_pk,
                "issuer": issuer,
                "acs_url": acs_url,
                "sp_binding": "redirect",
                "name_id_policy": NAME_ID_UNSPECIFIED,
            },
        )

    def create_application(self, bearer, slug, name, provider_pk, acs_url):
        return self._call(
            "POST", "/api/v3/core/applications/", bearer=bearer,
            payload={
                "name": name,
                "slug": slug,
                "provider": provider_pk,
                "launch_url": acs_url,
                "open_in_new_tab": True,
            },
        )

    def signing_cert(self, bearer, provider_pk):
        provider = self._call("GET", f"/api/v3/providers/saml/{provider_pk}/", bearer=bearer)
        kp = provider.get("signing_kp")
        if not kp:
            raise ApiError("provider has no signing keypair configured")
        cert = self._call("GET", f"/api/v3/crypto/certificatekeypairs/{kp}/", bearer=bearer)
        return cert.get("certificate_data")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base-url", required=True, help="Authentik URL, e.g. https://auth.example.com")
    ap.add_argument("--bootstrap-token", required=True, help="AKADMIN bootstrap token (output bootstrap_token)")
    ap.add_argument("--sp-entity-id", required=True, help="Scaleway SP entity ID (bootstrap sso output)")
    ap.add_argument("--sp-acs-url", required=True, help="Scaleway ACS URL (bootstrap sso output)")
    ap.add_argument("--slug", default=DEFAULT_SLUG)
    ap.add_argument("--name", default="Scaleway")
    ap.add_argument("--insecure", action="store_true",
                    help="allow self-signed HTTPS (Authentik's default on :443)")
    args = ap.parse_args()

    ak = Authentik(args.base_url, insecure=args.insecure)
    bearer = None
    try:
        me = ak.validate_bootstrap(args.bootstrap_token)
        username = (me or {}).get("username", "akadmin")
        print(f"bootstrap OK (user: {username})")
        bearer = ak.create_api_token(args.bootstrap_token, f"scw-sso-{args.slug}")

        flow = ak.authorization_flow(bearer)
        provider = ak.create_saml_provider(bearer, flow, args.name,
                                           args.sp_entity_id, args.sp_acs_url)
        pk = provider["pk"]
        ak.create_application(bearer, args.slug, args.name, pk, args.sp_acs_url)

        cert = ak.signing_cert(bearer, pk)
    except ApiError as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        sys.exit(1)

    entity_id = f"{ak.base}/application/o/{args.slug}/"
    print("\n=== IdP values for bootstrap `sso:` block ===")
    print(f"entity_id:          {entity_id}")
    print(f"single_sign_on_url: {entity_id}")
    if cert:
        print("\n=== IdP signing certificate (for sso.<key>.certs) ===")
        print(cert.rstrip())
    else:
        print("\n[WARN] no signing certificate retrieved - download it from the Authentik UI")
        print("       (Flows & Stages -> Providers -> <provider> -> Download signing certificate)")
    print("\nThen run the bootstrap apply to finish the handshake.")


if __name__ == "__main__":
    main()

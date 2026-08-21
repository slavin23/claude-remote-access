#!/usr/bin/env python3
"""
Provision UniFi networks and WLANs on a UDM Pro from site-config.json.

UniFi has no importable config file: .unf backups are opaque binaries and
config.gateway.json is USG-legacy. This drives the controller's REST API
instead, which is the closest equivalent.

Scope, deliberately:
  - creates VLANs / networks          (tedious, repetitive, safe to automate)
  - creates WLANs                     (best effort - payload shape varies by version)
  - does NOT touch firewall policy    (few objects, security-critical, eyeball them in the UI)

Never deletes or overwrites. An object whose name already exists is skipped.

Usage:
    export UNIFI_PASSWORD='...'
    export WIFI_STAFF_PSK='...' WIFI_BARPOS_PSK='...' WIFI_DISPPOS_PSK='...'

    # see what it would do - this is the default, nothing is written
    python3 provision_unifi.py --host 10.0.1.1 --username admin

    # actually create the networks
    python3 provision_unifi.py --host 10.0.1.1 --username admin --apply

    # networks and WLANs
    python3 provision_unifi.py --host 10.0.1.1 --username admin --apply --wlans
"""

import argparse
import getpass
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from http.cookiejar import CookieJar
from pathlib import Path

DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "config" / "site-config.json"

BAND_MAP = {"2g": "2g", "5g": "5g", "6g": "6g"}


class UniFi:
    """Thin client for the UniFi OS controller API on a UDM Pro."""

    def __init__(self, host, site="default", verify_tls=False):
        self.base = f"https://{host}"
        self.site = site
        self.csrf = None
        ctx = ssl.create_default_context()
        if not verify_tls:
            # A UDM Pro presents a self-signed certificate on its LAN address.
            # This is a local, on-site connection to the device being configured.
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPSHandler(context=ctx),
            urllib.request.HTTPCookieProcessor(CookieJar()),
        )

    def _request(self, method, path, body=None):
        url = self.base + path
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        if self.csrf:
            req.add_header("X-CSRF-Token", self.csrf)
        try:
            with self.opener.open(req, timeout=30) as resp:
                token = resp.headers.get("X-CSRF-Token")
                if token:
                    self.csrf = token
                raw = resp.read().decode() or "{}"
                return json.loads(raw)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:400]
            raise SystemExit(f"  ! {method} {path} -> HTTP {exc.code}\n    {detail}")
        except urllib.error.URLError as exc:
            raise SystemExit(f"  ! cannot reach {url}: {exc.reason}")

    def login(self, username, password):
        self._request("POST", "/api/auth/login",
                      {"username": username, "password": password, "rememberMe": False})

    def net(self, method, endpoint, body=None):
        return self._request(method, f"/proxy/network/api/s/{self.site}{endpoint}", body)

    def list_networks(self):
        return self.net("GET", "/rest/networkconf").get("data", [])

    def list_wlans(self):
        return self.net("GET", "/rest/wlanconf").get("data", [])

    def list_usergroups(self):
        return self.net("GET", "/rest/usergroup").get("data", [])

    def list_apgroups(self):
        return self._request(
            "GET", f"/proxy/network/v2/api/site/{self.site}/apgroups") or []


def network_payload(spec):
    dhcp = spec.get("dhcp", {})
    payload = {
        "name": spec["name"],
        "purpose": spec.get("purpose", "corporate"),
        "networkgroup": "LAN",
        "vlan_enabled": spec["vlan"] != 1,
        "ip_subnet": spec["subnet"],
        "dhcpd_enabled": bool(dhcp),
        "dhcpd_leasetime": dhcp.get("lease", 86400),
        "dhcpd_dns_enabled": False,
        "domain_name": "",
        "igmp_snooping": False,
        "is_nat": True,
        "enabled": True,
    }
    if spec["vlan"] != 1:
        payload["vlan"] = spec["vlan"]
    if dhcp:
        payload["dhcpd_start"] = dhcp["start"]
        payload["dhcpd_stop"] = dhcp["stop"]
    return payload


def wlan_payload(spec, network_id, usergroup_id, apgroup_ids):
    payload = {
        "name": spec["name"],
        "enabled": True,
        "networkconf_id": network_id,
        "usergroup_id": usergroup_id,
        "hide_ssid": spec.get("hide_ssid", False),
        "is_guest": spec.get("network") == "GUEST",
        "wlan_bands": [BAND_MAP[b] for b in spec.get("bands", ["2g", "5g"])],
        "security": spec["security"],
    }
    if apgroup_ids:
        payload["ap_group_ids"] = apgroup_ids
    if spec["security"] == "wpapsk":
        payload["wpa_mode"] = spec.get("wpa_mode", "wpa2")
        payload["wpa_enc"] = "ccmp"
        env = spec.get("passphrase_env")
        secret = os.environ.get(env) if env else None
        if not secret:
            return None, f"passphrase env var {env} is not set"
        payload["x_passphrase"] = secret
    return payload, None


def provision_networks(uni, specs, apply_changes):
    existing = {n["name"]: n for n in uni.list_networks()}
    created = {}
    for spec in specs:
        name = spec["name"]
        if spec.get("existing"):
            state = "present" if name in existing else "NOT FOUND"
            print(f"  · {name:<10} vlan {spec['vlan']:<3} — pre-existing network, {state}")
            print(f"      {spec['note']}")
            if name in existing:
                created[name] = existing[name]["_id"]
            continue
        if name in existing:
            print(f"  · {name:<10} vlan {spec['vlan']:<3} — already exists, skipping")
            created[name] = existing[name]["_id"]
            continue
        payload = network_payload(spec)
        if not apply_changes:
            print(f"  + {name:<10} vlan {spec['vlan']:<3} {spec['subnet']:<16} would create")
            continue
        result = uni.net("POST", "/rest/networkconf", payload)
        new_id = result["data"][0]["_id"]
        created[name] = new_id
        print(f"  + {name:<10} vlan {spec['vlan']:<3} {spec['subnet']:<16} created")
    return created


def provision_wlans(uni, specs, network_ids, apply_changes):
    existing = {w["name"] for w in uni.list_wlans()}

    groups = uni.list_usergroups()
    default_group = next((g["_id"] for g in groups if g.get("name") == "Default"), None)
    if not default_group and groups:
        default_group = groups[0]["_id"]

    apgroups = {g.get("name", "").lower(): g.get("_id") for g in uni.list_apgroups()}

    for spec in specs:
        name = spec["name"]
        if name in existing:
            print(f"  · {name:<14} already exists, skipping")
            continue

        net_id = network_ids.get(spec["network"])
        if not net_id:
            print(f"  ! {name:<14} skipped — network {spec['network']} not found")
            continue

        wanted = spec.get("ap_group", "all").lower()
        ids = []
        if wanted != "all":
            gid = apgroups.get(wanted)
            if not gid:
                print(f"  ! {name:<14} skipped — AP group '{wanted}' does not exist yet")
                print(f"      Create it in the UI first: {spec['note']}")
                continue
            ids = [gid]

        payload, err = wlan_payload(spec, net_id, default_group, ids)
        if err:
            print(f"  ! {name:<14} skipped — {err}")
            continue

        if not apply_changes:
            band = "/".join(spec.get("bands", []))
            print(f"  + {name:<14} vlan→{spec['network']:<9} {band:<8} would create")
            continue

        uni.net("POST", "/rest/wlanconf", payload)
        print(f"  + {name:<14} vlan→{spec['network']:<9} created")


def print_manual_work(cfg):
    print("\n" + "=" * 68)
    print("BUILD BY HAND IN THE UI — not scripted, on purpose")
    print("=" * 68)

    print("\nFirewall zones:")
    for zone, nets in cfg["firewall_zones"].items():
        print(f"  {zone:<12} {', '.join(nets)}")

    print("\nZone policies (default-deny between zones first):")
    for p in cfg["firewall_policies"]:
        verb = "BLOCK" if p["action"] == "block" else "allow"
        line = f"  {verb:<6} {p['from']:<12} -> {p['to']:<12}"
        print(f"{line}  {p['why']}" if p["why"] else line)

    print("\nRemaining steps:")
    for i, step in enumerate(cfg["manual_steps"], 1):
        print(f"  {i}. {step}")
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True, help="gateway address, e.g. 10.0.1.1")
    ap.add_argument("--username", required=True, help="local UniFi admin")
    ap.add_argument("--site", default=None, help="site name (default: from config)")
    ap.add_argument("--config", default=str(DEFAULT_CONFIG), type=Path)
    ap.add_argument("--apply", action="store_true",
                    help="actually write changes (default is a dry run)")
    ap.add_argument("--wlans", action="store_true", help="also create WLANs")
    ap.add_argument("--verify-tls", action="store_true",
                    help="verify the gateway certificate (off by default; a UDM Pro "
                         "presents a self-signed cert on its LAN address)")
    args = ap.parse_args()

    cfg = json.loads(args.config.read_text())
    site = args.site or cfg.get("site", "default")

    password = os.environ.get("UNIFI_PASSWORD") or getpass.getpass("UniFi password: ")

    mode = "APPLY — writing changes" if args.apply else "DRY RUN — nothing will be written"
    print(f"\n{mode}")
    print(f"Gateway {args.host}  ·  site {site}  ·  config {args.config.name}\n")

    uni = UniFi(args.host, site, verify_tls=args.verify_tls)
    uni.login(args.username, password)
    print("Authenticated.\n")

    print("Networks:")
    network_ids = provision_networks(uni, cfg["networks"], args.apply)

    if args.wlans:
        print("\nWLANs:")
        provision_wlans(uni, cfg["wlans"], network_ids, args.apply)
    else:
        print("\nWLANs: skipped (pass --wlans to include them)")

    print_manual_work(cfg)

    if not args.apply:
        print("Dry run complete. Re-run with --apply to write these changes.\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)

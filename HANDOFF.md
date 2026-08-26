# Handoff — Fields UniFi build (bar / dispensary)

Context primer for a fresh Claude Code session running **locally on the laptop that
goes to site**. Earlier sessions ran elsewhere — a cloud session that could not reach
the gateway, then a desktop at the shop. Claude Code transcripts do not sync between
machines, so this file is the only thing that crosses over. Keep it current.

## Start here

```bash
git clone https://github.com/slavin23/claude-remote-access.git fields-canary-network
cd fields-canary-network
git checkout claude/unifi-bar-dispensary-setup-bqharh
claude
```

Opening message to paste:

> Read HANDOFF.md, docs/unifi-bar-dispensary-design.md and docs/provisioning.md.
> I'm on site with the UDM Pro. Walk me through the setup wizard, then provision
> the VLANs.

---

## Before you leave the shop

Do these while you still have working internet. On site you are *building* the
internet — assume there is none until you have made one.

- [ ] **Clone this repo onto the laptop.** Not on site.
- [ ] **Install Python 3.** `provision_unifi.py` is stdlib-only but still needs an
      interpreter. There was none on the shop desktop, so do not assume the laptop
      has one. `python --version` must answer.
- [ ] **Install Git and Claude Code** on the laptop, and sign in once.
- [ ] **Bring a phone hotspot.** Claude Code needs to reach the API — it will not run
      on a site with no circuit. `docs/unifi-build.html` opens offline in a browser
      and is the field reference if you end up with no signal.
- [ ] **Have the three Wi-Fi passphrases decided and written down.** They are
      deliberately not in this repo — the script reads them from the environment:
      `WIFI_STAFF_PSK`, `WIFI_BARPOS_PSK`, `WIFI_DISPPOS_PSK`.
- [ ] Ethernet port or a USB-C adapter, and a patch cable.

## The job

One building split down the middle: **bar/restaurant** on one half, **dispensary** on
the other. Two independent businesses, one ISP circuit, one gateway. They want a shared
guest SSID and a shared staff SSID that must not become a shared network.

## Hardware (confirmed, purchased)

| Qty | Device | Notes |
|-----|--------|-------|
| 1 | Dream Machine Pro | Ports 1-8 LAN, 9 = RJ45 WAN, 10 = SFP+ WAN, 11 = SFP+ LAN. No PoE |
| 1 | Flex 2.5G PoE | **Only PoE source on site.** 210 W AC adapter ordered — mandatory |
| 2 | Switch 24 (USW-24) | **No PoE.** 24x 1 GbE + 2x 1G SFP uplink |
| 5 | U7 Pro XG | PoE+ / 802.3at, 22 W each, link at 2.5G into the Flex |
| 1 | Power Distribution Pro | Rack PDU, 16 switched outlets. No PoE, **not a UPS** |
| 1 | 5G Backup + 10 GB eSIM | PoE-powered off the Flex, adopted over LAN — no WAN2 port needed |

**No 10G anywhere, deliberately.** Flex uplinks to the UDM Pro at 1 GbE over RJ45.
WAN1 is 1 GbE so the circuit caps the site anyway. No DAC to buy.

**Cameras are out of scope** — third-party system on its own Cradlepoint cellular
circuit, never touches this network.

## Current state — verified 2026-08-26

- UDM Pro was on the bench at the shop, **port 9 → house router**, **port 1 → laptop**
- **Still on its factory LAN.** It answered on `https://192.168.1.1` (443 open) and
  handed the attached machine `192.168.1.129`. `10.0.1.1` did not answer.
- **The setup wizard has not been completed.** Nothing is configured yet.
- Design, config, provisioning script and this handoff are written and committed

If the gateway moves to site before the wizard is run, it will still come up on
`192.168.1.1`. Plug into a LAN port, take a DHCP lease, and go there.

## Immediate next step: the setup wizard

Four decisions that are painful to undo:

1. **Advanced setup**, not the automatic path — you need control of the LAN subnet
2. **LAN subnet → `10.0.1.1/24`** (the MGMT network). Do it now, not after adoption.
   The browser tab will die when this applies — renew DHCP, come back at `https://10.0.1.1`
3. **Auto-Optimize Network → OFF.** It manages its own settings and fights the design
4. **Create a local admin account**, not only ui.com SSO — `provision_unifi.py`
   authenticates against a local admin

Also: real timezone, auto-backup on, name the console for the site.

## Then provision

```bash
export UNIFI_PASSWORD='...'
export WIFI_STAFF_PSK='...' WIFI_BARPOS_PSK='...' WIFI_DISPPOS_PSK='...'

# dry run first — this is the default, nothing is written
python3 scripts/provision_unifi.py --host 10.0.1.1 --username admin

# then apply
python3 scripts/provision_unifi.py --host 10.0.1.1 --username admin --apply
```

Create the AP groups `bar` and `dispensary` in the UI **before** running with `--wlans`.

Firewall zones and policies are deliberately **not** scripted — build them by hand. The
script prints the full worklist at the end of every run.

Back up the site once it looks right.

## Changed since the last handoff

- **GUEST is `10.0.30.0/23`, not /22.** `10.0.30.0/22` is not a valid network boundary —
  it normalises to `10.0.28.0/22` and the controller rejects a DHCP range starting at
  `10.0.30.10`. The /23 spans `10.0.30.0`–`10.0.31.255`, 510 usable. DHCP range now
  ends at `10.0.31.250`.
- **DISP-CAM (VLAN 22) is no longer created.** Network, `Cameras` zone and both camera
  firewall policies are out of `site-config.json`, since surveillance lives on its own
  Cradlepoint. VLAN 22 stays *reserved on paper* — §7 of the design doc still has the
  policy written for the day it ever moves onto this circuit.
- **Guest SSID renamed `Venue Guest` → `Fields Guest`.**
- Design doc, `provisioning.md` and `unifi-build.html` all updated to match.

## Open — decide these on site

1. **The staff SSID is still named `Venue Staff` in the config.** The guest rename went
   through, this one did not. Before applying `--wlans`, decide what a *shared* staff
   SSID across two unaffiliated businesses should be called — "Fields Staff" is only
   right if Fields is the building, not just the bar.
2. **RADIUS or PSK for staff.** The design calls for WPA-Enterprise with dynamic VLAN
   (bar accounts → VLAN 11, dispensary → VLAN 21). The PSK in the config is the
   fallback. If it goes PSK, VLAN 31 must be internet-only — see §5.

## Things a cold session should know

- **UniFi has no importable config file.** `.unf` is an opaque binary,
  `config.gateway.json` is USG-legacy. The API is the only programmatic path.
- **SSH is diagnostic, not provisioning.** UniFi OS regenerates device config on every
  provision cycle and overwrites hand edits.
- **The script must run from a machine on the site LAN.** There is no remote path in.
- **STAFF is at `10.0.40.0/24`, not 10.0.31.x.** The guest /23 spans
  10.0.30.0-10.0.31.255 and would swallow it. VLAN ID is still 31.

## Files

```
docs/unifi-bar-dispensary-design.md   full design, sections 0-10
docs/provisioning.md                  how the script works, what is manual
docs/unifi-build.html                 same design as a field reference page, works offline
config/site-config.json               the design as data — source of truth
scripts/provision_unifi.py            creates VLANs and WLANs via the controller API
```

Published reference page:
https://claude.ai/code/artifact/3e8596c7-6306-4f7b-bb17-26f91a8f4fdf

## Open questions for the client

1. **Is the dispensary one store or one of several?** If several, UniFi Site Magic
   (free) can mesh this site to the others later — the bar's VLANs never enter the
   tunnel. Not applicable to a single site, which is why SD-WAN is not in this design.
2. **Who owns the circuit, the rack, and the UniFi console?** All five APs run off one
   PoE switch in one rack, and UniFi has no per-VLAN tenant admin delegation — whoever
   holds the console can see and change both networks. That is an agreement problem,
   not a config one. See §9 of the design doc.
3. **Does state regulation allow seed-to-sale to share infrastructure with an unrelated
   business?** Surveillance is already clear — it is on its own circuit.

## Still to buy

- **Rack UPS.** The Power Distribution Pro does remote reboot, not battery. A blip
  drops both tenants' POS mid-transaction.

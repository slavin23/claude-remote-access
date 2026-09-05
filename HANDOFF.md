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

## Current state — updated 2026-09-05

The site is much further along than the previous handoff assumed. Gear is installed,
and most of the earlier "next steps" are done:

- **Wizard complete.** Gateway is live at `10.0.1.1`, local admin exists, site is
  named **Fields Cannary**.
- **All 8 networks/VLANs exist and match `config/site-config.json` exactly** —
  including the GUEST `/23` correction. Someone (a prior session or Jason) already
  ran the networks half of `provision_unifi.py`, or built them by hand.
- **Firewall zones and policies are built** — `Bar`, `Dispensary`, `Staff`, `Mgmt`
  zones exist, and `Bar ⇄ Dispensary` is confirmed **blocked in both directions**
  (verified live in the zone matrix, both IPv4/IPv6, all protocols).
- **Both USW-24s are adopted, online, and each home-run to its own UDM Pro port** —
  not daisy-chained. Named `restaurant` (→ UDM Port 1) and `dispo` (→ UDM Port 2).
  Those names already show on the front LCM screens; no rename needed.
- **Port profiles and trunking are done** — see "Completed 2026-09-05" below.
- **Only `Fields Guest` SSID exists.** Staff, BAR-POS, and DISP-POS SSIDs are not
  built yet, and AP groups `bar`/`dispensary` were not found — confirm before
  running `--wlans`.

**Remote access works for hand-configuration.** Everything below was done through
`unifi.ui.com`'s cloud console, from a machine with no LAN route to the site at all.
The "no remote path in" note further down is still correct for one specific thing:
running `scripts/provision_unifi.py` itself, which targets the controller's LAN IP
(`10.0.1.1`) directly and has to run from a machine on-site. The interactive UI does
not have that restriction.

## Completed 2026-09-05 (via unifi.ui.com, no site LAN access)

Port profiles created (`Networks → Port Profiles`):

| Profile | Mode | Native VLAN | Tagged VLANs |
|---|---|---|---|
| `BAR-TRUNK` | Infrastructure | MGMT | BAR-POS, BAR-BACK, BAR-IOT |
| `DISP-TRUNK` | Infrastructure | MGMT | DISP-POS, DISP-BACK |
| `BAR-POS-PORT` | Edge | BAR-POS | none |
| `BAR-BACK-PORT` | Edge | BAR-BACK | none |
| `BAR-IOT-PORT` | Edge | BAR-IOT | none |
| `DISP-POS-PORT` | Edge | DISP-POS | none |
| `DISP-BACK-PORT` | Edge | DISP-BACK | none |

Applied, both ends of each uplink:

- UDM Pro Port 1 + `restaurant` switch Port 1 → `BAR-TRUNK`
- UDM Pro Port 2 + `dispo` switch Port 1 → `DISP-TRUNK`

**Every other port on both switches also got a default profile**, bulk-applied since
nothing else was actually connected to any of them yet (safe — nothing to disrupt):

- `restaurant` ports 2, 4–24 → `BAR-POS-PORT`
- `dispo` ports 2–24 → `DISP-POS-PORT`
- SFP+ 25/26 on both left alone — fiber uplinks, not RJ45 access ports, unused today

**No port on either switch is left on the factory "Allow All" profile anymore.** As
real drops get identified, move each one off `*-POS-PORT` to the profile that
actually matches it (office → `*-BACK-PORT`, bar TVs/menu boards → `BAR-IOT-PORT`).

Verified afterward: all 11 devices stayed Online/Up to date through every change —
no drop on the APs or either switch. (`dispo` briefly showed "Getting Ready" while
pushing 23 port configs at once, then settled — expected, not a fault.)

**Found and partly fixed a live exposure:** a client ("Samsung 1b:bf" — a picture
display TV, per Jason) was plugged into **`restaurant` switch, port 3**, sitting
untagged on **MGMT (VLAN 1)** — the same broadcast domain as the controller, switches,
and APs, because no port profile had ever been applied. It's now on `BAR-IOT-PORT`
(off MGMT), but that's a **stopgap**, not its intended home:

- Jason confirmed the TV is cabled into the wrong switch — it belongs on `dispo`,
  and he'll move the physical cable later.
- Once moved: assign that port on `dispo` to **`DISP-BACK-PORT`** (Jason's choice —
  no dedicated VLAN, simplest option). Do **not** add `DISP-BACK` to `BAR-TRUNK` to
  patch it in early on the `restaurant` switch — that punches a hole in the exact
  separation this build exists for. Leave it on `BAR-IOT-PORT` until the cable moves.
- **Bigger recommendation, not yet built, needs Jason's go-ahead:** `BAR-IOT` and any
  future `DISP-IOT` sit inside the `Bar`/`Dispensary` zones today, and intra-zone
  traffic isn't isolated (`L3 Network Isolation (ACL)` is off) — so a bar TV can
  currently reach the bar POS network. The clean fix is a dedicated zone for
  low-trust display/signage gear (one network per tenant, blocked from every
  internal zone, allowed only to External) — not UniFi's built-in `DMZ` zone, which
  is for something the internet needs to reach inbound, the opposite of what a
  display TV needs. Raise this with Jason before building it.

## The setup wizard — already done, nothing to do here

Earlier drafts of this handoff opened with the four wizard decisions (advanced setup,
LAN subnet, auto-optimize off, local admin). **All of that is done** — confirmed live
2026-09-05: gateway at `10.0.1.1`, local admin exists, site named Fields Cannary.
Leaving this note so a cold session doesn't re-walk the wizard or second-guess the
subnet.

## Then provision — WLANs are the remaining piece

The networks half is already done — all 8 VLANs exist and match `site-config.json`.
Only the WLANs are left, and only `Fields Guest` exists so far.

**Create the AP groups `bar` and `dispensary` in the UI first** — not found as of
2026-09-05. The POS SSIDs are silently skipped without them.

```bash
export UNIFI_PASSWORD='...'
export WIFI_STAFF_PSK='...' WIFI_BARPOS_PSK='...' WIFI_DISPPOS_PSK='...'

# dry run first — this is the default, nothing is written. Re-running against
# networks that already exist is safe: the script skips anything whose name matches.
python3 scripts/provision_unifi.py --host 10.0.1.1 --username admin --wlans

# then apply
python3 scripts/provision_unifi.py --host 10.0.1.1 --username admin --apply --wlans
```

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
3. **Create AP groups `bar` and `dispensary`** before running `--wlans` — not found
   as of 2026-09-05. The POS SSIDs are skipped without them.
4. **Build the remaining SSIDs** — only `Fields Guest` exists so far. Staff, BAR-POS,
   and DISP-POS are still to create.
5. **Move the misplaced picture-display TV** from `restaurant` port 3 to the `dispo`
   switch once its cable is run there, and set that port to `DISP-BACK-PORT`. See
   "Completed 2026-09-05" above for the full story and the signage-zone recommendation
   that's waiting on Jason's go-ahead.
6. **Refine the default port assignment as each drop gets wired.** Every port on both
   switches now has a profile (POS everywhere, as a safe baseline — see "Completed"
   above), but that's not the real map. Move office drops to `*-BACK-PORT` and bar
   TV/menu-board drops to `BAR-IOT-PORT` as they're identified.

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
docs/switch-setup.md                  the two USW-24s: naming, LCM screens, port profiles
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

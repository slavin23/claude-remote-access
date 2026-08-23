# Handoff — UniFi bar/dispensary build

Context primer for a fresh Claude Code session running **locally**, on the laptop that
is physically connected to the gateway. A cloud session cannot reach the UDM Pro; a
local one can.

## Start here

```bash
git clone https://github.com/slavin23/claude-remote-access.git
cd claude-remote-access
git checkout claude/unifi-bar-dispensary-setup-bqharh
claude
```

Opening message to paste:

> Read HANDOFF.md, docs/unifi-bar-dispensary-design.md and docs/provisioning.md.
> I have a UDM Pro on my bench, port 9 to my home router, port 1 to this laptop.
> I'm in the setup wizard. Walk me through it, then provision the VLANs.

---

## The job

One building, split down the middle: **bar/restaurant** on one half, **dispensary** on
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

## Current state

- UDM Pro is on the bench at home, **port 9 → home router**, **port 1 → laptop**
- Sitting in the first-run setup wizard, reachable in Chrome
- Nothing configured yet
- Design, config, and provisioning script are all written and committed

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

Back up the site once it looks right, so the bench build survives the trip.

## Files

```
docs/unifi-bar-dispensary-design.md   full design, sections 0-10
docs/provisioning.md                  how the script works, what is manual
docs/unifi-build.html                 same design as a published reference page
config/site-config.json               the design as data — source of truth
scripts/provision_unifi.py            creates VLANs and WLANs via the controller API
```

Published reference page:
https://claude.ai/code/artifact/3e8596c7-6306-4f7b-bb17-26f91a8f4fdf

## Things a cold session should know

- **UniFi has no importable config file.** `.unf` is an opaque binary,
  `config.gateway.json` is USG-legacy. The API is the only programmatic path.
- **SSH is diagnostic, not provisioning.** UniFi OS regenerates device config on every
  provision cycle and overwrites hand edits.
- **STAFF is at `10.0.40.0/24`, not 10.0.31.x.** The guest /22 spans 10.0.30.0-10.0.33.255
  and would swallow it. VLAN ID is still 31.
- The staff SSID should really be **WPA-Enterprise with dynamic VLAN** (bar accounts →
  VLAN 11, dispensary → VLAN 21). The PSK in the config is the fallback.

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

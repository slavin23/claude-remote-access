# Switch setup — the two USW-24s

One switch per tenant: restaurant/bar on one, dispensary on the other. Both are
**USW-24 (Standard 24), non-PoE**, 24x 1 GbE + 2x 1G SFP, with a **1.3" touchscreen
LCM display** on the front.

**Status as of 2026-09-05: naming, trunking, and a default access-port profile on
every port are all done, remotely via unifi.ui.com. Still open: refine the default
(POS profile everywhere) to match real drops as they're identified, physically move
the TV to `dispo`, and the on-site ping tests.**

## First, the thing that is easy to get wrong

A UniFi switch is not "assigned to a network." It is a layer-2 device that carries
VLANs, and **both switches are managed on MGMT (VLAN 1, 10.0.1.0/24)** — that is how
the controller reaches them.

The tenant separation happens on the **ports**:

- **The uplink trunk carries only that tenant's VLANs.** The dispensary's VLANs never
  traverse the bar's uplink cable, and vice versa.
- **Every access port has a single untagged VLAN.** No port is left on the default
  "All" profile — that is the leak.

This is stronger than the zone firewall alone. The firewall stops routed traffic
between zones; the trunk allow-list means the frames are not on the wire in the first
place.

## Before touching the controller

- [x] **Each switch has its own cable home to the UDM Pro.** Confirmed 2026-09-05 —
      `restaurant` → UDM Pro Port 1, `dispo` → UDM Pro Port 2. Not daisy-chained.
- [x] Which UDM Pro LAN port feeds which switch — see above.
- [x] Both switches online, adopted, provisioned.

## 1. Naming — done, already on the LCM screens

The front display renders the device **Alias**, and the switches were already named
before this session touched anything:

| Switch | Alias in use | UDM Pro port |
|---|---|---|
| Restaurant / bar side | `restaurant` | Port 1 |
| Dispensary side | `dispo` | Port 2 |

These names already show on each switch's LCM screen — no rename needed. (An earlier
draft of this doc proposed `BAR-SW24`/`DISP-SW24`; ignore that, the names above are
what's actually deployed and there's no reason to churn a working alias.)

**Not yet done:**
- **Static IP or DHCP reservation.** Both switches are on dynamic MGMT leases today
  (`restaurant` = `10.0.1.51`, `dispo` = `10.0.1.238` as of 2026-09-05). Fine for now,
  but a lease can change — pin these before calling the build final, so the LCM
  screen's IP stays trustworthy.
- **LCM lock.** Both switches sit in public-facing spaces. The screen is a touchscreen
  that can factory-reset the switch from the front panel — lock it before handover.

## 2. Port profiles — created 2026-09-05

All seven exist in `Settings → Networks → Port Profiles`:

| Profile | Mode | Native VLAN | Tagged VLANs |
|---|---|---|---|
| `BAR-TRUNK` | Infrastructure | MGMT (1) | BAR-POS (10), BAR-BACK (11), BAR-IOT (12) |
| `DISP-TRUNK` | Infrastructure | MGMT (1) | DISP-POS (20), DISP-BACK (21) |
| `BAR-POS-PORT` | Edge | BAR-POS (10) | none (Block All) |
| `BAR-BACK-PORT` | Edge | BAR-BACK (11) | none (Block All) |
| `BAR-IOT-PORT` | Edge | BAR-IOT (12) | none (Block All) |
| `DISP-POS-PORT` | Edge | DISP-POS (20) | none (Block All) |
| `DISP-BACK-PORT` | Edge | DISP-BACK (21) | none (Block All) |

Neither trunk carries GUEST or STAFF — those are wireless VLANs, and the APs home-run
to the Flex, not to these switches. If a tenant ever needs a wired guest jack, add
GUEST to that one tenant's trunk deliberately; don't pre-authorise it on both.

## 3. Uplinks — applied 2026-09-05, both ends

| Device | Port | Profile |
|---|---|---|
| UDM Pro | Port 1 (→ `restaurant`) | `BAR-TRUNK` |
| `restaurant` | Port 1 (uplink) | `BAR-TRUNK` |
| UDM Pro | Port 2 (→ `dispo`) | `DISP-TRUNK` |
| `dispo` | Port 1 (uplink) | `DISP-TRUNK` |

Verified after applying: all 11 devices on the site (both switches, all 5 APs, PDU,
Flex, 5G Backup, gateway) stayed Online/Up to date through every change — no drop.

## 4. Access ports — default applied to every remaining port, 2026-09-05

No physical drop map exists yet, but nothing else was connected either, so every
unused port on both switches was bulk-set to that tenant's primary profile — the
safe baseline the earlier draft of this doc recommended, applied now that it was
confirmed low-risk (nothing live to disrupt):

| Switch | Ports | Profile applied |
|---|---|---|
| `restaurant` | 2, 4–24 (22 ports) | `BAR-POS-PORT` |
| `dispo` | 2–24 (23 ports) | `DISP-POS-PORT` |

Left alone on purpose:
- **Port 1 on both** — already `BAR-TRUNK` / `DISP-TRUNK`, the uplinks.
- **`restaurant` port 3** — the picture-display TV, see below.
- **SFP+ 25/26 on both** — fiber uplink ports, not RJ45 access ports. No profile
  applied; nothing plugs into them today.

Verified after applying: all 11 devices on the site stayed Online/Up to date. `dispo`
briefly showed "Getting Ready" while it pushed 23 port configs, then settled back to
normal — expected, not a fault.

**This is a starting default, not the finished map.** As real drops get identified,
move each one off `*-POS-PORT` to the profile that actually matches it:

- **`restaurant`:** office drops → `BAR-BACK-PORT`, TV/menu-board drops →
  `BAR-IOT-PORT`
- **`dispo`:** office and vault-room drops → `DISP-BACK-PORT`

Anything that ends up genuinely unused once the build is done: **disable the port.**
An empty live jack in a public bar is a way onto the POS VLAN.

### The picture-display TV — still a stopgap

**`restaurant` port 3 had a client — a picture-display TV — sitting untagged on MGMT**
before any of this was done. It's now on `BAR-IOT-PORT` (off MGMT), but it's cabled to
the wrong switch: Jason confirmed it belongs on `dispo`, serving the dispensary, and
he'll move the physical cable later. **Once moved, assign that port on `dispo` to
`DISP-BACK-PORT`** — do not add `DISP-BACK` to `BAR-TRUNK` to patch it in early on
`restaurant`; that punches a hole in the tenant separation for the sake of one
mis-cabled device.

**Bigger question, raised but not resolved:** `BAR-IOT` (and any future `DISP-IOT`)
sits inside the `Bar`/`Dispensary` zone, and intra-zone traffic isn't isolated
(`L3 Network Isolation (ACL)` is off) — so today a bar TV *can* reach the bar POS
network over VLAN routing within the same zone. The cleaner design is a dedicated
zone for low-trust signage/display gear per tenant — blocked from every internal zone,
allowed only to External — not UniFi's built-in `DMZ` zone, which is for something the
internet needs to reach inbound. Not built; needs Jason's sign-off first.

## 5. Label the ports in the controller

`Device → Port Manager → click a port → Name`

Do this while standing there with the cable in hand. Six months from now "Port 7"
means nothing and "KDS — kitchen pass" means everything.

## 6. Verify before calling it done

- [x] Both switches show their alias on the front LCM screen (`restaurant`, `dispo`)
- [x] Both reachable, adopted, provisioned green
- [ ] Static/reserved MGMT IPs set on both switches
- [x] No port anywhere is left on the default "All" profile — confirmed 2026-09-05
- [ ] A laptop on a `BAR-POS-PORT` gets a **10.0.10.x** address
- [ ] A laptop on a `DISP-POS-PORT` gets a **10.0.20.x** address
- [ ] From the bar-side laptop, **ping the dispensary laptop — it must fail**
- [ ] Reverse it and ping back — **must also fail**
- [ ] Unused ports disabled
- [ ] LCM screens locked
- [ ] Back up the site

The two ping tests are the whole build in one check — they need a physical presence
on site with two test laptops, so they're still open. Do them in **both**
directions — a one-way block is a misconfiguration that looks like success.

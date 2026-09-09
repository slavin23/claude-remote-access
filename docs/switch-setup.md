# Switch setup — the two USW-24s

One switch per tenant: restaurant/bar on one, dispensary on the other. Both are
**USW-24 (Standard 24), non-PoE**, 24x 1 GbE + 2x 1G SFP, with a **1.3" touchscreen
LCM display** on the front.

**Status as of 2026-09-09: both switches are online and running the rebuilt design.**
The 2026-09-07 outage is over — see §6 for what actually resolved it, because the
recorded cause and the recorded fix were both partly wrong and that's worth knowing.

This document describes the **rebuilt** design (2026-09-09). Everything before it —
the five-VLAN-per-tenant scheme, the `*-POS-PORT` / `*-BACK-PORT` / `*-IOT-PORT` /
`*-IDLE-PORT` profiles, `BAR-TRUNK` / `DISP-TRUNK` — is **deleted**, not deprecated.
Don't go looking for it in the controller.

## First, the thing that is easy to get wrong

A UniFi switch is not "assigned to a network." It is a layer-2 device that carries
VLANs, and **both switches are managed on MGMT (VLAN 1, 10.0.1.0/24)** — that is how
the controller reaches them.

The tenant separation happens on the **ports**:

- **The uplink trunk carries only that tenant's VLANs** (plus MGMT and OPEN-NET). The
  dispensary's secure VLAN never traverses the bar's uplink cable, and vice versa.
- **Every access port has a single untagged VLAN and blocks all tagged traffic.**
  No port is left on the factory "All" profile — that is the leak.

This is stronger than the zone firewall alone. The firewall stops routed traffic
between zones; the trunk allow-list means the frames are not on the wire in the
first place.

## 1. Naming — on the LCM screens, unchanged

| Switch | Alias in use | Gateway port | Uplink port on switch |
|---|---|---|---|
| Restaurant / bar side | `restaurant` | Port 7 | **Port 24** |
| Dispensary side | `dispo` | Port 8 | **Port 24** |

Both names show on their front LCM screens already. No rename needed.

**Still not done:**
- **Static IP or DHCP reservation.** Both are on dynamic MGMT leases (`dispo` =
  `10.0.1.238` as of 2026-09-09). Pin these before calling the build final, so the
  LCM screen's IP stays trustworthy.
- **LCM lock.** Both sit in public-facing spaces. The touchscreen can factory-reset
  the switch from the front panel. Lock it before handover.

## 2. Port profiles — the five that exist

`Settings → Networks → Port Profiles`. These five are the complete set:

| Profile | Mode | Native VLAN | Tagged VLANs | Used on |
|---|---|---|---|---|
| `BAR-SECURE-TRUNK` | Infrastructure | MGMT (1) | BAR-SECURE (100), OPEN-NET (150) | gateway port 7, `restaurant` port 24 |
| `DISP-SECURE-TRUNK` | Infrastructure | MGMT (1) | DISP-SECURE (200), OPEN-NET (150) | gateway port 8, `dispo` port 24 |
| `BAR-SECURE-PORT` | Edge | BAR-SECURE (100) | Block All | `restaurant` ports 1–12 |
| `DISP-SECURE-PORT` | Edge | DISP-SECURE (200) | Block All | `dispo` ports 1–12 |
| `OPEN-PORT` | Edge | OPEN-NET (150) | Block All | both switches, ports 13–23 |

Neither trunk carries SHARED-SECURE or STAFF — those are wireless-only VLANs, and
the APs home-run to the Flex, not to these switches.

**Note the trunks are asymmetric on purpose.** `BAR-SECURE-TRUNK` carries VLAN 100
but not 200; `DISP-SECURE-TRUNK` carries 200 but not 100. Each tenant's secure VLAN
is physically absent from the other tenant's uplink cable. Both carry OPEN-NET,
because ports 13–23 on both switches serve it.

## 3. The port map

Identical on both switches, which is the point — one rule to remember, not a
per-switch lookup.

| Ports | Profile | What it's for |
|---|---|---|
| **1–12** | `BAR-SECURE-PORT` / `DISP-SECURE-PORT` | That tenant's private network. POS, back office, anything that matters. DHCP from 10.0.100.x / 10.0.200.x. |
| **13–23** | `OPEN-PORT` | Internet-only. **No DHCP server** — every device here needs a hand-assigned static from Jason's plan. Fully firewalled off every internal network. |
| **24** | `BAR-SECURE-TRUNK` / `DISP-SECURE-TRUNK` | The uplink to the gateway. |
| **25–26 (SFP)** | untouched | Fiber, unused. |

Verified live in the controller after applying: `dispo` Native VLAN counts read
`MGMT (3)`, `OPEN-NET (11)`, `DISP-SECURE (12)`, and a laptop on `dispo` port 10
came up on DISP-SECURE — the map is real, not just saved.

### Named drops so far

| Switch | Port | Label | Network |
|---|---|---|---|
| `dispo` | 14 | `ATM1` | OPEN-NET |
| `dispo` | 16 | `ATM2` | OPEN-NET |
| `dispo` | 18 | `ATM3` | OPEN-NET |
| `dispo` | 20 | `ATM4` | OPEN-NET |

Labeled 2026-09-09. The ATMs are a good fit for OPEN-NET: they need to reach their
processor over the internet and nothing on either tenant's network, which is exactly
what the `Open` zone allows and blocks.

**Two caveats on these four, both open as of labeling:**

- **None of the four had link when labeled.** The switch reported `In Use (2)` — port
  10 (a laptop) and port 24 (the uplink) — with all four ATM ports showing Not
  Connected. Cables are in the switch, but nothing on the far end is bringing the
  link up. Check the far-end jack, the ATM's own port, and the patch run.
- **They need static IPs.** OPEN-NET has no DHCP server by design, so an ATM plugged
  in with DHCP expectations will land on a 169.254 address and look broken. Suggested
  assignment, keyed to port number so the address tells you where it's patched:
  `ATM1 10.0.150.14`, `ATM2 .16`, `ATM3 .18`, `ATM4 .20` — mask `255.255.255.0`,
  gateway `10.0.150.1`, DNS `10.0.150.1`.

**Worth deciding:** devices on OPEN-NET can reach each other at layer 2 — same VLAN,
and there's no wired client isolation the way STAFF-WIFI has it at the SSID. Four
ATMs that can see each other is probably not what you want long term. If it matters,
the lever is `Settings → Networks → Device Isolation (ACL)`. Not enabled; raise it
with Jason.

**Why ports 13–23 have no DHCP:** that's deliberate, from Jason. The open network is
for devices that need the internet and nothing else, addressed by hand so there's a
written record of what's on it. A device plugged in there with DHCP expectations will
sit at a 169.254 address and look broken — that's working as designed, give it a
static.

## 4. Gateway ports

| Gateway port | Goes to | Profile |
|---|---|---|
| Port 5 | Flex 2.5G PoE | default (untouched) |
| Port 6 | USP PDU Pro | default (untouched) |
| Port 7 | `restaurant` port 24 | `BAR-SECURE-TRUNK` |
| Port 8 | `dispo` port 24 | `DISP-SECURE-TRUNK` |
| Port 9 | Frontier WAN | — |

**Ports 1 and 2 were reset on 2026-09-09.** They carried the old `BAR-TRUNK` /
`DISP-TRUNK` profiles from when the switches uplinked there. Both are now: profile
off, native VLAN MGMT, **Tagged VLAN Management = Block All**. That last part
mattered — switching the profile off left the old tagged VLAN list (BAR-POS,
BAR-BACK, BAR-IOT) sitting on the port, which would have blocked deleting those
networks. If you ever retire a network and the controller refuses, this is where to
look first.

Port 2 still has an unidentified device on it (`E100-f63 3f:63`, Comcast vendor OUI,
on MGMT). Worth asking Jason what it is — a stray device on the management network
deserves a name.

## 5. Label the ports in the controller

`Device → Port Manager → click a port → Name`

Do this while standing there with the cable in hand. Six months from now "Port 7"
means nothing and "KDS — kitchen pass" means everything.

## 6. The 2026-09-07 outage — how it actually ended

Recorded at the time: both switches went offline when the uplinks moved to port 24,
because port 24 carried a client-only profile that blocked the switch's own
management traffic. The recorded fix was a physical cable swap to port 1 and back.

**Nobody ever performed that swap, and the switches came back anyway.** On 2026-09-09
both showed online with ~1d 18h uptime, uplinked on port 24, `dispo` holding
`10.0.1.238` on MGMT. So either they were never as offline as the controller's
device page claimed — that page kept showing "dispo (Offline), last connected Aug 30"
long after a client on `dispo` port 10 was live and passing traffic — or applying the
new trunk profiles to gateway ports 7 and 8 was enough on its own, since an
Infrastructure-mode trunk passes untagged MGMT and that's all a switch needs to phone
home.

**The lesson worth keeping is not the cable dance.** It's this: before moving an
uplink to a *different* physical port, set that port's profile to the matching trunk
**first**, while the switch is still reachable on its current uplink. Doing both in
one visit is what created the outage. And: don't trust a stale "Offline" label —
cross-check against whether clients behind that device are passing traffic.

## 7. Verify before calling it done

- [x] Both switches show their alias on the front LCM screen (`restaurant`, `dispo`)
- [x] Both reachable, adopted, online — confirmed 2026-09-09, uplinked on port 24
- [x] No port anywhere is left on the default "All" profile
- [x] Ports 1–12 on each switch carry that tenant's secure VLAN — confirmed on `dispo`
      by a live client on port 10 landing on DISP-SECURE
- [ ] Static/reserved MGMT IPs set on both switches
- [ ] A laptop on `restaurant` port 1–12 gets a **10.0.100.x** address
- [ ] A laptop on `dispo` port 1–12 gets a **10.0.200.x** address
- [ ] From the bar-side laptop, **ping the dispensary laptop — it must fail**
- [ ] Reverse it and ping back — **must also fail**
- [ ] A laptop on either switch's port 13–23, given a static 10.0.150.x, reaches the
      internet and **cannot** ping anything on 10.0.100.x / 10.0.200.x / 10.0.1.x
- [ ] From a laptop on ports 1–12, the controller at 10.0.1.1 **is** reachable
      (that's the deliberate Secure→Mgmt allow — Jason's "so I can manage it")
- [ ] Unused ports disabled
- [ ] LCM screens locked
- [ ] Back up the site

The ping tests are the whole build in one check, and they need two laptops on site.
Do them in **both** directions — a one-way block is a misconfiguration that looks
like success.

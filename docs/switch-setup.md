# Switch setup — the two USW-24s

One switch per tenant: restaurant/bar on one, dispensary on the other. Both are
**USW-24 (Standard 24), non-PoE**, 24x 1 GbE + 2x 1G SFP, with a **1.3" touchscreen
LCM display** on the front.

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

- [ ] **Each switch has its own cable home to the UDM Pro.** If they were daisy-chained
      (bar switch → dispensary switch), the isolation is gone no matter what you
      configure. Fix the cabling first.
- [ ] Note which UDM Pro LAN port feeds which switch. You need this for step 3.
- [ ] Both switches show up under **Devices**, adopted and provisioned green.

## 1. Name them — this is what the LCM screen shows

The front display renders the device **Alias**. Set it and the screen follows.

`UniFi Network → Devices → click the switch → Settings (gear) → General → Alias`

| Switch | Alias | Why |
|---|---|---|
| Restaurant / bar side | `BAR-SW24` | Matches the VLAN naming — BAR-POS, BAR-BACK, BAR-IOT |
| Dispensary side | `DISP-SW24` | Matches DISP-POS, DISP-BACK |

Keep it short. It is a 1.3" screen — `BAR-SW24` reads across a rack, "Restaurant
Switch 24 Port" does not. If the people reading it are staff rather than techs, use
`RESTAURANT` and `DISPENSARY` instead and accept the mismatch with the VLAN names.

**Also set on each switch:**
- **Static IP on MGMT**, or a DHCP reservation — `10.0.1.11` (bar) and `10.0.1.12`
  (dispensary) are easy to remember. The LCM screen shows the IP, so a fixed one makes
  the display genuinely useful.
- **LCM display settings** live on the same device Settings page (the exact section
  name moves between Network versions — look for *Display* / *LCM* / *Advanced*).
  Leave the screen **on**, set brightness so it is readable in that room, and consider
  **locking it** so a customer cannot poke at a touchscreen in a public area.

> The LCM screen is a touchscreen and it can factory-reset the switch from the front
> panel. In a bar or a retail floor, lock it.

## 2. Build the port profiles

`Settings → Profiles → Port Profiles → Create New`

**`BAR-TRUNK`** — the uplink for the restaurant switch
- Native / untagged VLAN: **MGMT (1)**
- Tagged VLANs: **BAR-POS (10), BAR-BACK (11), BAR-IOT (12)** — and nothing else
- Explicitly **not** DISP-POS, DISP-BACK, GUEST, STAFF

**`DISP-TRUNK`** — the uplink for the dispensary switch
- Native / untagged VLAN: **MGMT (1)**
- Tagged VLANs: **DISP-POS (20), DISP-BACK (21)** — and nothing else

Do not use "All" or "Allow All" on either. The allow-list *is* the job.

> **Guest and Staff are not on this list on purpose.** Those are wireless VLANs and
> the APs home-run to the Flex, not to these switches. If a tenant ever needs a wired
> guest jack, add GUEST to that one tenant's trunk deliberately — do not pre-authorise
> it.

Then the access profiles, one untagged VLAN each:

| Profile | Untagged VLAN | Used for |
|---|---|---|
| `BAR-POS-PORT` | 10 | POS terminals, KDS, card readers, receipt printers |
| `BAR-BACK-PORT` | 11 | Back-office PC, office printer |
| `BAR-IOT-PORT` | 12 | TVs, menu boards, cooler sensors, music |
| `DISP-POS-PORT` | 20 | POS, seed-to-sale, ID scanners |
| `DISP-BACK-PORT` | 21 | Back office, vault-room PC |

## 3. Apply them

**Both ends of each uplink get the trunk profile** — the UDM Pro port and the switch
port. Miss one end and the link comes up but tagged traffic is silently dropped.

| Device | Port | Profile |
|---|---|---|
| UDM Pro | LAN port feeding the bar switch | `BAR-TRUNK` |
| BAR-SW24 | its uplink port | `BAR-TRUNK` |
| UDM Pro | LAN port feeding the dispensary switch | `DISP-TRUNK` |
| DISP-SW24 | its uplink port | `DISP-TRUNK` |

Then the access ports. Set the **whole switch's remaining ports** to that tenant's
primary profile, then override the individual drops you have identified:

- **BAR-SW24:** all ports → `BAR-POS-PORT`, then move the office drops to
  `BAR-BACK-PORT` and the TV/menu-board drops to `BAR-IOT-PORT`
- **DISP-SW24:** all ports → `DISP-POS-PORT`, then move the office and vault-room
  drops to `DISP-BACK-PORT`

Anything genuinely unused: **disable the port.** An empty live jack in a public bar is
a way onto the POS VLAN.

## 4. Label the ports in the controller

`Device → Ports → click a port → Name`

Do this while you are standing there with the cable in your hand. Six months from now
"Port 7" means nothing and "KDS — kitchen pass" means everything. The port name shows
in the UI and in the topology view.

## 5. Verify before you call it done

- [ ] Both switches show their alias on the **front LCM screen**
- [ ] Both reachable at their fixed MGMT addresses, adopted, provisioned green
- [ ] A laptop on a `BAR-POS-PORT` gets a **10.0.10.x** address
- [ ] A laptop on a `DISP-POS-PORT` gets a **10.0.20.x** address
- [ ] From the bar-side laptop, **ping the dispensary laptop — it must fail**
- [ ] Reverse it and ping back — **must also fail**
- [ ] No port anywhere is left on the default "All" profile
- [ ] Unused ports disabled
- [ ] Back up the site

The two ping tests are the whole build in one check. Do them in **both** directions —
a one-way block is a misconfiguration that looks like success.

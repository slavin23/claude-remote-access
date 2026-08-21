# UniFi Design — Shared Building: Bar/Restaurant + Dispensary

**Site type:** One building, two independent businesses, split down the middle.
**Circuit:** One ISP handoff, UniFi 5G Backup for failover, 10 GB eSIM data pack.
**Wireless:** Shared guest SSID + shared staff SSID across both halves, tenant-private
VLANs behind them.

---

## 0. Power — resolved, and what is still open

**The 210 W AC adapter is ordered.** That was the blocker: the Flex 2.5G PoE is the
only PoE source on this site, and nothing else in the order can power it.

- Dream Machine Pro — no PoE output
- Switch 24 (USW-24) x2 — **no PoE output**, 24x 1 GbE + 2x 1G SFP uplink
- Power Distribution Pro (USP-PDU-Pro) — rack PDU: 16 switched AC outlets, 4 USB-C,
  4 RJ45 management ports. **No PoE output**, and **not a UPS**
- Flex 2.5G PoE — AC adapter **ordered**, unlocks the full 196 W budget

Keep the adapter with the switch. If it ever gets swapped for a PoE feed, the budget
drops to 76 W at best and two access points go dark — and the symptom will look like
flaky APs, not a power problem.

### Still open

| Item | Approx. | Why |
|------|---------|-----|
| Rack UPS | varies | The PDU is remote-reboot, not battery. A blip drops both tenants' POS mid-transaction |
| 3.5" HDD | optional | Only if UniFi Protect gets added to the UDM Pro later |

Neither remaining item blocks the install — they are both things you would rather have
on the truck than order afterward.

---

## 1. Hardware and PoE budget

### As ordered
| Qty | Device | What matters |
|-----|--------|--------------|
| 1 | Dream Machine Pro | 1 GbE + 10G SFP+ WAN · 8× 1 GbE LAN + 1× 10G SFP+ LAN · 3.5" bay · no PoE |
| 1 | Flex 2.5G PoE | 8× 2.5 GbE PoE++ out · 10 GbE RJ45 + 10G SFP+ uplink · 60 Gbps |
| 2 | Switch 24 (USW-24) | 24× 1 GbE, **no PoE** · 2× 1G SFP uplink |
| 5 | U7 Pro XG | 10 GbE uplink · PoE+ (802.3at) · 22 W max · WiFi 7 tri-band |
| 1 | Power Distribution Pro | 16 switched AC outlets · rack power control · not a UPS |
| 1 | UniFi 5G Backup + 10 GB eSIM | PoE-powered · RedCap · ~30–85 Mbps |

### PoE load — all of it lands on the Flex

```
5 x U7 Pro XG @ 22 W       110 W
1 x UniFi 5G Backup        ~15 W
---------------------------------
Total                      125 W
```

| Flex power input | Budget | Verdict |
|---|---|---|
| **210 W AC adapter** | **196 W** | Works — 71 W headroom |
| PoE+++ on uplink | 76 W | Fails — 3 APs, nothing else |
| PoE++ on uplink | 46 W | Fails |
| PoE+ on uplink | 16 W | Fails — not even one AP |

The adapter is ordered, so the site runs on the 196 W row with 71 W of headroom.
Everything else in this document assumes it stays that way.

### Port count — comfortable once powered

| Switch | Used | Spare |
|--------|------|-------|
| Flex 2.5G PoE (8) | 5 APs + 5G Backup = **6** | 2 |
| Switch 24 — bar (24) | POS, KDS, printers, TVs, office | plenty |
| Switch 24 — dispensary (24) | POS, ID scanners, office, NVR | plenty |
| UDM Pro LAN | Flex + 2× Switch 24, all on RJ45 | 5 |

### Two consequences of the non-PoE Switch 24s

1. **All five AP drops must home-run to the rack holding the Flex.** It is the only
   thing that can power them. Confirm no AP run exceeds 100 m from that rack —
   in a building this size it will not, but measure before you pull.
2. **Neither tenant has PoE at their own switch.** VoIP phones, PoE cameras, PoE
   scanners on either side have no power source. See section 7 — this matters for the
   dispensary specifically.

### No 10G anywhere, deliberately

The APs link at 2.5G into the Flex, and **the Flex uplinks to the UDM Pro at 1 GbE**
over RJ45. No SFP+, no DAC, nothing to buy.

That is the right call here. Almost every packet on the wireless side is
internet-bound, and the UDM Pro's WAN1 is a 1 GbE RJ45 port — so the circuit itself
caps the site at 1 Gbps regardless of what the Flex uplink could do. There is no local
wired destination for wireless clients to saturate: the cameras are on their own
Cradlepoint, the POS is cloud, and there is no file server. A 10G uplink would idle.

The one thing that would change this is an internet circuit faster than 1 Gbps. That
would mean moving WAN1 to the UDM Pro's 10G SFP+ port, and the Flex uplink would then
become the site's bottleneck. Revisit it that day, not before.

Cat6 is fine for every run here; Cat6A only if a run is long or bundled tight.

---

## 2. Topology

```
                         ISP handoff
                              |
                        (WAN1, 1 GbE)
                              |
   ┌─────────────── NEUTRAL RACK ────────────────┐
   │  [ Dream Machine Pro ]                      │
   │       |  1 GbE                              │
   │  [ Flex 2.5G PoE ] ── 210W AC adapter       │
   │       |                                     │
   │       ├── 5 x U7 Pro XG   (all home-run)    │
   │       └── UniFi 5G Backup (PoE, GRE/LAN)    │
   │                                             │
   │  [ Power Distribution Pro ]  + UPS          │
   └──────┬──────────────────────────────┬───────┘
      1 GbE                           1 GbE
          |                              |
   [ Switch 24 · BAR ]         [ Switch 24 · DISPENSARY ]
   POS, KDS, printers,         POS, seed-to-sale, ID
   TVs, menu boards,           scanners, office,
   back office                 existing NVR
```

**Physical rule:** each tenant's Switch 24 lives in that tenant's own space, fed by
that tenant's own drops. If the lease changes hands, the cut is one uplink cable.

**The APs are unavoidably shared** — one PoE switch powers all five, and both tenants'
SSIDs broadcast on all of them. That is fine: the separation happens at the VLAN and
firewall layer, not the physical one. But it does mean the AP infrastructure belongs
to whoever owns the rack. See section 9.

---

## 3. VLAN plan

| VLAN | Name | Subnet | Zone | Contents |
|------|------|--------|------|----------|
| 1 | MGMT | 10.0.1.0/24 | Mgmt | UDM Pro, switches, APs, 5G Backup, PDU |
| 10 | BAR-POS | 10.0.10.0/24 | Bar | POS terminals, KDS, card readers, receipt printers |
| 11 | BAR-BACK | 10.0.11.0/24 | Bar | Back-office PC, office printer, scheduling |
| 12 | BAR-IOT | 10.0.12.0/24 | Bar | TVs, digital menu boards, cooler sensors, music |
| 20 | DISP-POS | 10.0.20.0/24 | Dispensary | POS + seed-to-sale (Metrc / Dutchie / Flowhub), ID scanners |
| 21 | DISP-BACK | 10.0.21.0/24 | Dispensary | Back office, vault-room PC |
| 22 | DISP-CAM | 10.0.22.0/24 | Cameras | **Reserved, unused** — surveillance is on its own Cradlepoint, see §7 |
| 30 | GUEST | 10.0.30.0/22 | Guest | Shared public Wi-Fi, both halves |
| 31 | STAFF | 10.0.31.0/24 | Staff | Shared staff Wi-Fi — see section 5 |

Give `GUEST` a **/22, not a /24**. A busy bar on a Friday will chew through 254
addresses with phones that never disassociate. DHCP lease 2–4 hours so it recycles.

---

## 4. Firewall — zone-based (UniFi Network 9+)

Zones: `Mgmt`, `Bar`, `Dispensary`, `Cameras`, `Guest`, `Staff`, `External`.
Start default-deny between zones, open only what breaks.

| From | To | Action | Why |
|------|-----|--------|-----|
| Bar | Dispensary | **BLOCK** | This is the entire point of the build |
| Dispensary | Bar | **BLOCK** | Both directions, written explicitly |
| Guest | any internal | **BLOCK** | Plus client isolation on the SSID |
| Guest | Internet | ALLOW | Rate-limited, see section 8 |
| Staff | any POS | **BLOCK** | Staff phones never touch card networks |
| Cameras | any zone | **BLOCK** | Policy stays written; VLAN 22 is dormant today (§7) |
| Cameras | Internet | **BLOCK** | Same — dormant, ready if the system ever moves onto this circuit |
| Guest / Staff | Mgmt | **BLOCK** | No exceptions |
| Admin device | Mgmt | ALLOW | Single jump host or admin VLAN |

Enable *Block LAN to WLAN multicast/broadcast* everywhere except the bar's TV VLAN,
where Chromecast and AirPlay are deliberately wanted.

---

## 5. SSIDs

Four, and no more. Every extra SSID burns airtime on beacons — in a dense bar that is
a real cost, not a theoretical one.

| SSID | Security | VLAN | Bands | AP group |
|------|----------|------|-------|----------|
| `<Venue> Guest` | Open + captive portal, or WPA2 w/ posted password | 30 | 2.4 + 5 | All 5 |
| `<Venue> Staff` | WPA2/WPA3-Enterprise (RADIUS) | dynamic | 5 + 6 | All 5 |
| `BAR-POS` | WPA3-PSK, strong key, hidden | 10 | 5 only | Bar APs |
| `DISP-POS` | WPA3-PSK, strong key, hidden | 20 | 5 only | Disp APs |

**Wire the POS wherever you physically can** — both Switch 24s have ports to spare.
Those two SSIDs exist for handhelds and tablets, not fixed terminals. Use AP Groups so
each tenant's POS SSID only broadcasts on their half's APs.

### The shared staff SSID — do it with RADIUS
One staff SSID across two unaffiliated businesses puts bar staff phones and dispensary
staff phones in the same broadcast domain by default. Fix it with **dynamic VLAN
assignment**: WPA2/WPA3-Enterprise against the UDM Pro's built-in RADIUS server (or
UniFi Identity), bar accounts returning VLAN 11 and dispensary accounts returning
VLAN 21. Same SSID name, same login prompt, two separate networks behind it.

**If RADIUS is more than the site will maintain:** one PSK, everyone on VLAN 31,
and VLAN 31 gets **internet only** — no POS, no printers, no file shares, nothing on
either tenant's LAN. Less useful, still safe. What you must not ship is a shared staff
PSK with LAN access on both sides.

A captive portal on guest is worth the setup: it gives both tenants a terms-of-use
page, and the dispensary may want an age gate on the splash screen.

---

## 6. RF tuning — bar-specific

- **5 GHz channel width: 40 MHz.** Not 80, not 160. Density beats headline speed.
- **6 GHz: 160 MHz** is fine — clean and short-range, exactly what you want here.
- **Disable low data rates.** 2.4 GHz minimum 12 Mbps, 5 GHz 12–24 Mbps. Single
  biggest fix for sticky clients hanging onto a distant AP.
- **Min RSSI** on, around −72 dBm.
- **Band steering** on. **802.11r** on for the staff SSID, **off** on the POS SSIDs —
  older handheld POS gear roams badly with it.
- **Transmit power manual/medium**, not auto-high. Five APs in one building at full
  power just talk over each other.
- Bar-side hazards: commercial microwaves (2.4 GHz obliteration), the metal back-bar,
  walk-in coolers, ceiling duct and speaker runs. Do not mount an AP above the
  back-bar or inside ductwork.
- Dispensary vault/safe room is usually concrete and steel — assume no coverage inside
  and run a wired drop instead of fighting it.

### Placement — 5 APs
**3 on the bar/restaurant side** (dining floor, bar area, patio/entry) — that is where
the client count is. **2 on the dispensary side** (sales floor and queue,
back-of-house). Each Pro XG covers roughly 1,500 ft², but space them for *capacity*,
not coverage: overlapping cells at lower TX power.

---

## 7. Surveillance — out of scope

Their cameras run on their own **Cradlepoint cellular router**, physically and
logically separate from everything in this design. That resolves the whole section:

- No PoE requirement on the dispensary Switch 24
- No VLAN 22 traffic to route or filter
- No outbound internet policy to write for camera gear
- No sustained camera upload competing with the bar on the shared circuit
- Nothing riding the 5G Backup's 10 GB

It also strengthens the compliance position in §9: the licensee's surveillance
genuinely does not touch the bar's network, or yours.

### Three things still worth doing

**1. Never bridge the Cradlepoint into the LAN.**
The temptation will come — someone wants to view cameras from a back-office PC and
patches the Cradlepoint's LAN port into the Switch 24. Do not let that happen. It drops
an uncontrolled cellular WAN onto the network with its own DHCP server and a second
default gateway, and it quietly undoes the isolation the separate circuit was buying.
If they want desktop viewing, use the vendor's app over the store's normal internet.

**2. Turn on DHCP guard.**
Specify trusted DHCP server addresses on the UniFi networks so a stray router — the
Cradlepoint or anything else someone plugs in — cannot start handing out leases.
Label the camera gear and its patch cables so nobody "tidies" them into the rack.

**3. Keep VLAN 22 reserved but unused.**
Costs nothing. Cellular data plans for a full camera system are expensive, and if the
system ever migrates onto the building's circuit, the VLAN and its firewall policy are
already designed and waiting.

### If it ever does move onto the building circuit

Treat it as a black box behind one port: recorder on VLAN 22, reachable only from
DISP-BACK on named viewing ports, no route to the bar zone or any other internal zone.
Outbound internet allowed only to the vendor's endpoints and NTP — or blocked entirely,
with remote viewing through a WireGuard VPN on the UDM Pro. Recorders of
Hikvision/Dahua lineage have a long CVE history and no business with open internet.

---

## 8. WAN and 5G failover

**How it connects:** the 5G Backup is PoE-powered from the Flex and adopted as a
managed UniFi device. It does **not** need the UDM Pro's WAN2 port — traffic is
carried over the LAN, so no SFP+ RJ45 module is required. Place it for **signal**, not
tidiness: exterior wall or near a window, not buried in the rack.

**The 10 GB eSIM changes the failover policy from a preference into a hard rule.**
RedCap gives 30–85 Mbps, and 10 GB is roughly three hours of one person streaming.
POS traffic, by contrast, is kilobytes per transaction — 10 GB would cover both
tenants' card volume for weeks.

| Traffic | On 5G | Reasoning |
|---|---|---|
| Bar POS | ALLOW | Card transactions must complete |
| Dispensary POS + seed-to-sale | ALLOW | Compliance reporting cannot stall |
| Staff Wi-Fi | ALLOW, capped | Ops messaging only |
| Guest SSID | **EXCLUDE** | Would burn the entire data pack in an afternoon |
| Surveillance remote view | **EXCLUDE** | Recording continues locally regardless |

Set a data-usage alert well below 10 GB. Set per-zone bandwidth limits on the
*primary* circuit too, so a guest streaming 4K does not starve the dispensary's POS.

### Is SD-WAN a fit here?

**No, and you do not need it.**

SD-WAN in UniFi means **Site Magic** — a license-free feature in UniFi Site Manager
that auto-builds IPsec tunnels **between UniFi gateways at different physical sites**,
hub-and-spoke or mesh (20-site cap on mesh). The UDM Pro is supported as either hub or
spoke; a hub needs a public IP, and gateways need firmware 4.1.3 or newer.

That solves a multi-site problem. This is **one building with one gateway** — there is
no second site to connect, so there is nothing for it to do.

What SD-WAN sounds like it would give you — *the network intelligently picks the best
path when the circuit degrades* — is **dual-WAN failover with per-network policy**.
That is a native UDM Pro feature and it is already in this design, above. You do not
need SD-WAN to get "POS fails over to 5G, guest does not." Worth being precise about,
because SD-WAN sounds like the answer and is not.

**Where it would genuinely apply:**

- **If the dispensary is one of several stores.** Very common in this industry. Site
  Magic would mesh this location to their others for shared back-office and
  seed-to-sale access — and the bar's VLANs simply never enter the tunnel, which
  reinforces the separation rather than weakening it. It is free with the gear already
  bought. **Ask whether this is store #1 or store #4.**
- **If they later add a second circuit** and want application-aware steering across
  both. Even then, dual-WAN load balancing on the UDM Pro covers most of it.

Build as designed. Revisit Site Magic the day a second location appears.

**Test the failover before go-live** — unplug WAN1 and watch a card transaction
complete on both sides, then confirm guest traffic did not ride along.

---

## 9. The part that isn't technical

1. **Shared circuit, shared fate.** One outage takes down both businesses. One bill,
   one account holder, one party who can cancel the service. Decide now who owns it.
2. **Shared console, shared visibility.** Whoever owns the UniFi console can see and
   change the other tenant's network. UniFi does not do true per-VLAN tenant admin
   delegation — site admin is site admin. No configuration fixes this. It needs an
   agreement, or a neutral third party holding the owner account with each tenant on a
   limited login.
3. **Shared APs.** All five run off one PoE switch in one rack. The tenant who does not
   own that rack is depending on the one who does for their Wi-Fi.
4. **Compliance may forbid the premise.** Surveillance is already clear — it lives on
   its own Cradlepoint circuit (§7). Seed-to-sale is the remaining question: confirm
   against state regulation *early* that it may share infrastructure with an unrelated
   business. If it may not, the answer is a second circuit and a second gateway.

If a second circuit is at all affordable, **give the dispensary its own** and use the
5G Backup on the bar.

---

## 10. Build checklist

**Before install day**
- [x] ~~Order the **210 W AC adapter** for the Flex~~ — ordered (§0)
- [ ] Order a rack UPS — the PDU is not one (§0)
- [ ] Ask whether the dispensary is a multi-location operator (§8)
- [ ] Label the Cradlepoint and camera patch cables "do not patch" (§7)
- [ ] Confirm who owns the circuit, the rack, and the UniFi console (§9)

**Install**
- [ ] Measure AP runs from the rack — all five must be under 100 m (§1)
- [ ] Cat6/6A to 5 AP locations, both tenant switch locations, POS drops
- [ ] Rack: UDM Pro, Flex + adapter, PDU, UPS
- [ ] Create VLANs and zones, default-deny between tenants first (§3–4)
- [ ] Verify Bar ⇄ Dispensary block from both directions with a real ping test (§4)
- [ ] Stand up RADIUS + dynamic VLAN for the staff SSID (§5)
- [ ] RF tuning pass — after furniture is in, not before (§6)
- [ ] Walk test on a phone with WiFiman, both halves (§6)

**Before handover**
- [ ] Configure failover with guest excluded, set a data alert under 10 GB (§8)
- [ ] Test failover: pull WAN1, complete a card transaction on both sides (§8)
- [ ] Enable DHCP guard with trusted server addresses on every network (§7)
- [ ] Enable auto-backup, set admin accounts, disable unused remote access
- [ ] Label every port and drop at both ends

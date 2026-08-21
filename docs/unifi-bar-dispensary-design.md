# UniFi Design — Shared Building: Bar/Restaurant + Dispensary

**Site type:** One building, two independent businesses, split down the middle.
**Circuit:** One ISP handoff, UniFi 5G Backup for failover.
**Wireless:** Shared guest SSID + shared staff SSID across both halves, tenant-private
SSIDs/VLANs behind them.

---

## 1. Hardware

### Confirmed
| Qty | Device | Notes |
|-----|--------|-------|
| 5 | UniFi U7 Pro XG | 10 GbE RJ45 uplink, **PoE+ (802.3at)**, 22W max, WiFi 7 tri-band |
| 1 | Dream Machine (model TBC) | Gateway + controller |
| 2 | UniFi switch (models TBC) | One per tenant half |
| 1 | UniFi 5G Backup | PoE-powered, RedCap, ~30–85 Mbps real world |

### PoE budget — check this before you order
```
5 x U7 Pro XG        110 W   (22 W each, PoE+ / 802.3at)
1 x UniFi 5G Backup   ~15 W
Dispensary cameras    ~64 W   (8 x ~8 W, if PoE — see §7)
--------------------------------------------
Working total        ~190 W  across two switches
```
Every AP port must be **802.3at (PoE+), not af**. A 30W-per-port af switch will
brown these out under load.

### Port speed
The Pro XG's uplink is 10 GbE. You will not see 10 Gbps of real client traffic in a
bar — 2.5 GbE per AP is genuinely enough — but if you paid for XG, a switch with
2.5G/10G PoE+ ports (e.g. USW Pro Max 24 PoE) is where the money goes. Cat6 is fine
for 10G at these run lengths (<55 m); Cat6A if any run is long or bundled tight.

---

## 2. Topology

```
                    ISP handoff
                         |
                  [ Dream Machine ]---- UniFi 5G Backup (WAN2, PoE)
                     /          \
                    /            \
        [ SW-BAR ]                [ SW-DISP ]
        3 x U7 Pro XG             2 x U7 Pro XG
        Bar POS / KDS             Disp POS / seed-to-sale
        TVs, menu boards          NVR + cameras
```

**Physical rule:** each tenant's switch lives in that tenant's own space, fed by
that tenant's own drops. If the lease changes hands, the cut is one uplink cable,
not a re-pull. The gateway and the ISP demarc belong in neutral/landlord space.

---

## 3. VLAN plan

| VLAN | Name | Subnet | Zone | Contents |
|------|------|--------|------|----------|
| 1 | MGMT | 10.0.1.0/24 | Mgmt | Gateway, switches, APs, 5G Backup |
| 10 | BAR-POS | 10.0.10.0/24 | Bar | POS terminals, KDS, card readers, receipt printers |
| 11 | BAR-BACK | 10.0.11.0/24 | Bar | Back-office PC, office printer, scheduling |
| 12 | BAR-IOT | 10.0.12.0/24 | Bar | TVs, digital menu boards, cooler/temp sensors, music |
| 20 | DISP-POS | 10.0.20.0/24 | Dispensary | POS + seed-to-sale (Metrc / Dutchie / Flowhub), ID scanners |
| 21 | DISP-BACK | 10.0.21.0/24 | Dispensary | Back-office, vault-room PC |
| 22 | DISP-CAM | 10.0.22.0/24 | Cameras | NVR + cameras — isolated, see §7 |
| 30 | GUEST | 10.0.30.0/22 | Guest | Shared public Wi-Fi, both halves |
| 31 | STAFF | 10.0.31.0/24 | Staff | Shared staff Wi-Fi (see §5 for the tenant split) |

Give GUEST a /22. A busy bar on a Friday will chew through a /24 with phones that
never disassociate; set DHCP lease to 2–4 hours so it recycles.

---

## 4. Firewall — zone-based (UniFi Network 9+)

Zones: `Mgmt`, `Bar`, `Dispensary`, `Cameras`, `Guest`, `Staff`, `External`.

| From | To | Action | Why |
|------|-----|--------|-----|
| Bar | Dispensary | **BLOCK** | This is the entire point of the build |
| Dispensary | Bar | **BLOCK** | Both directions, explicitly |
| Guest | any internal zone | **BLOCK** | Plus client isolation on the SSID |
| Guest | External | ALLOW | Rate-limited, see §6 |
| Staff | Bar / Dispensary POS | **BLOCK** | Staff phones never touch card networks |
| Staff | External | ALLOW | |
| Cameras | any zone | **BLOCK** | Cameras talk to the NVR only |
| Cameras | External | **BLOCK** | Only the NVR gets out, for updates/remote view |
| Dispensary | Cameras | ALLOW (NVR only, specific ports) | Licensee viewing |
| Guest / Staff | Mgmt | **BLOCK** | No exceptions |
| Admin device | Mgmt | ALLOW | Single jump host or admin VLAN |

Start from default-deny between zones and open only what breaks. Also turn on
"Block LAN to WLAN multicast/broadcast" except where Chromecast/AirPlay is
deliberately wanted on the bar's TV VLAN.

---

## 5. SSIDs

Keep this to four. Every extra SSID burns airtime on beacons — in a dense bar
that is a real cost, not a theoretical one.

| SSID | Security | VLAN | Bands | AP Group |
|------|----------|------|-------|----------|
| `<Venue> Guest` | Open + captive portal, or WPA2 w/ posted password | 30 | 2.4 + 5 | All 5 APs |
| `<Venue> Staff` | WPA2/WPA3-Enterprise (RADIUS) | dynamic — see below | 5 + 6 | All 5 APs |
| `BAR-POS` | WPA3-PSK, strong key, hidden | 10 | 5 only | Bar APs only |
| `DISP-POS` | WPA3-PSK, strong key, hidden | 20 | 5 only | Dispensary APs only |

**Wire the POS wherever you physically can.** These two SSIDs exist for handhelds
and tablets, not for fixed terminals.

### The shared staff SSID — do it with RADIUS
One staff SSID across two unaffiliated businesses means, by default, bar staff
phones and dispensary staff phones sitting in the same broadcast domain. Fix it
with **dynamic VLAN assignment**: WPA2/WPA3-Enterprise against the gateway's
built-in RADIUS server (or UniFi Identity), with bar staff accounts returning
VLAN 11 and dispensary staff accounts returning VLAN 21. Same SSID name, same
password prompt, two completely separate networks behind it.

Simpler fallback if RADIUS is more than the site will maintain: one PSK, everyone
lands on VLAN 31, and VLAN 31 gets **internet only** — no POS, no printers, no
file shares, nothing on either tenant's LAN. It is less useful but it is safe.
Do not run a shared staff PSK that has LAN access on both sides.

### Guest portal
Captive portal with a terms-of-use click is worth it here: it gives both tenants
a liability page, and the dispensary may want an age gate on the splash screen.

---

## 6. RF tuning — bar-specific

A restaurant is a high-density, high-interference environment. Defaults will
underperform.

- **5 GHz channel width: 40 MHz.** Not 80, not 160. Density beats headline speed.
- **6 GHz: 160 MHz** is fine — it is clean and short-range, which is what you want.
- **Disable low data rates.** Set 2.4 GHz minimum to 12 Mbps and 5 GHz to 12–24 Mbps.
  This is the single biggest fix for sticky clients that hang onto a distant AP.
- **Min RSSI**: enable, around -72 dBm, so phones let go and re-roam.
- **Band steering** on. **802.11r fast roaming** on for the staff SSID, but leave it
  **off** on the POS SSIDs — older handheld POS gear roams badly with it.
- **Transmit power**: manual/medium, not auto-high. Five APs in one building at full
  power just talk over each other.
- Bar-side RF hazards: commercial microwaves (2.4 GHz obliteration), the metal
  back-bar, walk-in coolers, and speaker/duct runs in the ceiling. Do not mount an
  AP above the back-bar or inside ductwork.
- Dispensary vault/safe room is usually concrete and steel — assume no coverage
  inside it and run a wired drop instead.

### Placement (5 APs)
- **3 on the bar/restaurant side** — dining floor, bar area, patio/entry. This is
  where the client count is.
- **2 on the dispensary side** — sales floor / queue area, and back-of-house.
- The Pro XG covers ~1,500 ft² each; spacing for capacity, not just coverage, means
  overlapping cells at lower TX power.

---

## 7. Dispensary cameras and compliance

**Check the state rules before finalizing this section** — they are prescriptive
and they vary.

- Cameras go on VLAN 22, isolated from everything including the bar and the guest
  network. Cameras themselves get **no internet**; only the NVR does.
- Most states mandate 24/7 recording with **30–90 day retention** at a specified
  minimum resolution and frame rate. That is real storage:
  ```
  8 cams @ 4MP / 15fps / H.265  ~=  6-8 Mbps each
  30 days  ~=  ~6 TB
  90 days  ~= ~18 TB
  ```
  A Dream Machine's single drive bay will not do 90 days. Budget a UNVR / UNVR Pro
  with proper drives.
- Many states also require that the surveillance system be accessible **only to the
  licensee**. That is an argument against the bar's owner holding controller
  credentials that can reach it — see §9.

---

## 8. WAN and 5G failover

- The UniFi 5G Backup is PoE-powered off a switch port and configured as WAN2 in
  UniFi Network 10.
- **If the gateway is a UDM Pro:** its WAN2 (port 10) is SFP+ only. There is no
  RJ45 WAN2 — you designate a LAN port as WAN2 in the UI instead.
- **Mount it for signal**, not for tidiness — exterior wall or near a window, not
  buried in the IDF closet.
- **Failover policy matters more than the hardware.** RedCap gives 30–85 Mbps.
  Scope failover so that during an outage:
  - POS on both sides → allowed on 5G
  - Payment/seed-to-sale traffic → allowed
  - Guest SSID → **excluded**, or it will consume the entire backup link
  - Camera remote viewing / cloud upload → excluded
- Set per-zone bandwidth limits (Traffic Rules / smart queues) on the primary
  circuit too, so a guest streaming 4K does not starve the dispensary's POS.
- **Test the failover before go-live.** Unplug the WAN and watch a card transaction
  complete on both sides.

---

## 9. The part that is not technical

Two independent businesses on one circuit and one UniFi console has real
consequences worth putting in writing before the install:

1. **One outage takes down both businesses.** One bill, one account holder, one
   party who can cancel the service. Decide now who owns the circuit.
2. **Whoever owns the UniFi console can see and change the other tenant's
   network.** UniFi does not do true per-VLAN tenant admin delegation — site-level
   admin is site-level admin. There is no configuration that fixes this; it needs
   an agreement, or a neutral third party (you) holding the owner account with each
   tenant getting a limited/view-only login.
3. **The dispensary's compliance posture may not permit shared infrastructure** for
   the camera or seed-to-sale systems. Confirm this against the state rules early —
   if it does not, the answer is a second circuit and a second gateway for the
   dispensary, and the design above collapses into two independent sites that
   happen to share a building.

If a second circuit is at all affordable, **give the dispensary its own** and use
the 5G Backup on the bar. It removes items 1–3 in one move.

---

## 10. Build checklist

- [ ] Confirm Dream Machine model and switch models (PoE budget + port speed, §1)
- [ ] Confirm state camera retention + isolation requirements (§7)
- [ ] Confirm who owns the circuit and the UniFi console (§9)
- [ ] Cat6/6A to all 5 AP locations, both switch locations, NVR, POS drops
- [ ] Create VLANs and zones per §3–4, default-deny between tenants first
- [ ] Verify Bar↔Dispensary block from both directions with an actual ping test
- [ ] Stand up RADIUS + dynamic VLAN for the staff SSID (§5)
- [ ] RF tuning pass per §6 — do this after furniture is in, not before
- [ ] Site survey / walk test on a phone with WiFiman, both halves
- [ ] Configure and **test** 5G failover with guest excluded (§8)
- [ ] Enable auto-backup, set admin accounts, disable unused remote access
- [ ] Run a live card transaction on both sides, on primary and on failover

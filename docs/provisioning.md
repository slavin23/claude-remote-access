# Provisioning

## There is no UniFi config file to upload

Worth stating plainly, because it is the first thing people look for:

- **`.unf` backups are opaque binaries.** Unlike pfSense or Fortinet, you cannot
  author, inspect, or diff a UniFi backup. It is produced by a controller and restored
  to a controller, nothing else.
- **`config.gateway.json` is USG-legacy.** It does not apply to a UDM Pro.
- **The official Integration API does not cover firewall rules, port forwards, or
  routing yet.** Those live only in the classic controller API.

So the closest equivalent to "upload a config" is to drive the controller's REST API.
That is what `scripts/provision_unifi.py` does.

## SSH is not a provisioning path

Worth knowing before someone tries it: UniFi OS keeps network configuration in the
controller's database and regenerates device config on every provision cycle. Anything
hand-edited over SSH on the gateway or a switch **gets overwritten the next time the
controller pushes config**.

That is the whole reason this script talks to the controller API — it writes to the
system of record instead of around it.

SSH is still worth having for diagnosis: device state, live traffic capture, a config
dump, restarting a service. Use it to find out why something is wrong, never to change
what it should be.

The same applies to running this script: it has to run from a machine **on the site
LAN** with a route to the gateway. There is no remote path in.

## What is scripted and what is not

| | Where | Why |
|---|---|---|
| VLANs / networks | **scripted** | Nine networks x ten fields, typed by hand, is where mistakes get made |
| WLANs | **scripted**, best effort | Payload shape shifts between controller versions; verify after |
| Firewall zones + policies | **UI, by hand** | Few objects, security-critical. You want to look at each one |
| RADIUS, AP groups, RF, failover | **UI, by hand** | Judgment calls, not data entry |

The script **never deletes or overwrites**. Anything whose name already exists is
skipped and reported.

## Files

```
config/site-config.json      the design as data — source of truth
scripts/provision_unifi.py   reads it, creates networks and WLANs
```

Passphrases are **not** in the config file. Each WLAN names an environment variable the
script reads at runtime.

## Running it

```bash
export UNIFI_PASSWORD='...'
export WIFI_STAFF_PSK='...'
export WIFI_BARPOS_PSK='...'
export WIFI_DISPPOS_PSK='...'

# dry run — this is the default, nothing is written
python3 scripts/provision_unifi.py --host 10.0.1.1 --username admin

# create the networks
python3 scripts/provision_unifi.py --host 10.0.1.1 --username admin --apply

# networks and WLANs together
python3 scripts/provision_unifi.py --host 10.0.1.1 --username admin --apply --wlans
```

Stdlib only — no `pip install` on a job-site laptop.

### Order of operations

1. Adopt everything and let it finish provisioning.
2. **Create the AP groups `bar` and `dispensary` in the UI first.** The POS WLANs are
   scoped to them and will be skipped if they do not exist.
3. Dry run. Read the output.
4. `--apply` for networks.
5. `--apply --wlans` once the AP groups exist.
6. Build the firewall zones and policies by hand — the script prints the full worklist
   at the end of every run, including dry runs.

### On the TLS warning

A UDM Pro presents a self-signed certificate on its LAN address, so the script does not
verify it by default. That is a local, on-site connection to the device you are
configuring. `--verify-tls` turns verification on if you have installed a real
certificate.

## Correction to the addressing

While building the config I hit two problems with the earlier addressing.

**1. GUEST /22 was not a valid boundary.** `10.0.30.0/22` normalises to `10.0.28.0/22`,
and the controller rejects a DHCP range starting at 10.0.30.10. **GUEST is now
`10.0.30.0/23`** — spans `10.0.30.0`–`10.0.31.255`, 510 usable, still far more than a
/24 for a busy Friday.

**2. STAFF collided with it.** The guest block swallows `10.0.31.0/24`, so **STAFF has
moved to `10.0.40.0/24`.** VLAN ID is still 31; only the subnet changed.

The design doc and the config file both reflect this.

## After it runs

The script does not verify its own work. Before you call it done:

- [ ] Every network shows the right VLAN ID and subnet in the UI
- [ ] DHCP hands out an address on each VLAN from a test client
- [ ] Guest network shows guest isolation enabled
- [ ] WLANs are on the intended VLAN and the intended AP group
- [ ] Firewall zones built, default-deny between them
- [ ] `Bar -> Dispensary` blocked, tested with a ping in **both** directions
- [ ] Back up the site (`Settings > Control Plane > Backups`) once it is right

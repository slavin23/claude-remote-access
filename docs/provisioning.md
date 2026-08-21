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

While building the config I hit a collision in the earlier plan: **GUEST at
`10.0.30.0/22` spans `10.0.30.0`–`10.0.33.255`**, which swallows a STAFF network at
`10.0.31.0/24`.

**STAFF has moved to `10.0.40.0/24`.** VLAN ID is still 31; only the subnet changed.
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

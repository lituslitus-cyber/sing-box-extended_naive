# Podkop Naive sing-box pin

Installer for OpenWRT/Podkop that pins `sing-box` to:

```text
v1.13.12-extended-2.4.0
```

The script downloads the fixed `linux-*-musl.tar.gz` build from `shtorm-7/sing-box-extended`, replaces `/usr/bin/sing-box`, verifies that `naive` outbound is supported, and then applies `moix89/podkop-xhttp-patch`.

It does not install the OpenWRT `.ipk`/`.apk` package and does not touch the `opkg`/`apk` package database.

## Install

On the router:

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install.sh
sh /tmp/install.sh
```

Or copy `install.sh` to the router manually and run:

```sh
sh /tmp/install.sh
```

## What It Does

- Detects router CPU architecture.
- Downloads only the fixed `v1.13.12-extended-2.4.0` release.
- Uses only `linux-*-musl.tar.gz` builds.
- Backs up the existing `/usr/bin/sing-box`.
- Replaces `/usr/bin/sing-box` with the extended binary.
- Checks the installed binary version.
- Runs a real `sing-box check -c` test with a temporary `naive` outbound config.
- Backs up Podkop files before patching.
- Applies `podkop-xhttp-patch`.

## Verify

```sh
sing-box version
podkop global_check
sing-box check -c /etc/sing-box/config.json
```

Expected sing-box version:

```text
1.13.12-extended-2.4.0
```

## Rollback

The installer stores backups in:

```sh
/root/podkop-sing-box-backup
```

To restore the latest saved files:

```sh
sh /tmp/install.sh --rollback
```

Rollback restores:

- `/usr/bin/sing-box`
- `/usr/lib/podkop/sing_box_config_facade.sh`
- `/usr/bin/podkop`

## Notes

The Naive check guarantees that the installed `sing-box` binary accepts a `naive` outbound config. It does not guarantee that a specific Naive server is reachable, because that also depends on the server, network, TLS/SNI, and link parameters.

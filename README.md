# Executable Shell Scripts for /bin/zsh

![Shell](https://img.shields.io/badge/Shell-zsh-blue?logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/License-Freeware-green)
![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey?logo=apple&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active-brightgreen)

## About These Scripts

This repository contains a collection of executable `.sh` scripts tailored for `/bin/zsh`. They are regularly updated and modified to suit various automation tasks.

### Key Features:
- Designed specifically for `/bin/zsh`
- Fully customisable and adaptable
- Authored and maintained with 💻 and ❤️

### Example Usage
Run the scripts directly from your terminal:
```bash
./example_script.sh
```

### Safe macOS Cleanup

`cleanUp.zsh` performs conservative home-directory cleanup by default. Destructive
categories such as user logs, browser history, Docker data, Trash, package
caches, and Xcode artifacts require explicit options.

```zsh
./cleanUp.zsh --dry-run --all-safe
./cleanUp.zsh --developer --package-caches
./cleanUp.zsh --privacy --yes
```

Run `./cleanUp.zsh --help` for all options and retention settings. Do not launch
the script with `sudo`; it requests elevation only for individual protected files.

### Largest first-level directories

`top10.zsh` lists the ten directories with the most immediate children anywhere
beneath the selected path. Its default path for these modes is the macOS root:

```zsh
./top10.zsh entries
./top10.zsh dirs 10 /
./top10.zsh files 10 /Users
```

The output shows full paths plus separate directory and file counts. Hidden
entries are included; symbolic links count as files and are not followed.
Mounted volumes and macOS's duplicate Data-volume view are skipped in a root
scan. Run without `sudo`; inaccessible directories are counted in the summary,
but their contents cannot be counted and may affect the ranking. `size` remains
available for ranking the immediate children of a chosen path by recursive disk
usage. Run `./top10.zsh --help` for the complete interface.

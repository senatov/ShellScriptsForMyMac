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

#!/bin/sh
# Pre-commit secret scan of staged changes.
#
# Forced git color (color.ui/color.diff=always, via `git -c` or any gitconfig)
# makes gitleaks misparse `git diff` output and silently PASS staged secrets.
# GIT_CONFIG_PARAMETERS outranks both `-c` and config files, so force it off.
GIT_CONFIG_PARAMETERS="'color.ui'='never' 'color.diff'='never'" \
  exec gitleaks git --pre-commit --staged --redact --verbose --config .gitleaks.toml

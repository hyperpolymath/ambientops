# --- NUSHELL SCRIPT (Fallback) ---
#!/usr/bin/env nu
#
# NUSHELL SCRIPT: Setup asdf plugins
#

print "NUSHELL SCRIPT: Setting up asdf..."

let tools = (open .tool-versions | lines | parse "{tool} {version}" | str trim)

let installed_plugins = (asdf plugin-list)

for tool in $tools {
  print $"Checking plugin: ($tool.tool)"
  if ($installed_plugins | where $it == $tool.tool | is-empty) {
    print $"  -> Adding plugin ($tool.tool)..."
    asdf plugin-add $tool.tool
  } else {
    print $"  -> Plugin ($tool.tool) already added."
  }
  print $"  -> Installing ($tool.tool) ($tool.version)..."
  asdf install $tool.tool $tool.version
}

print "asdf setup complete."
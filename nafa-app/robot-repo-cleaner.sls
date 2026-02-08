#
# Salt State: robot-repo-cleaner
# Purges all caches and transient data from the development environment.
# Run with: salt-call --local state.apply robot-repo-cleaner
#

# 1. Prune all Podman images, build caches, and volumes
podman_prune_all:
  cmd.run:
    - name: "podman system prune -a -f --volumes"
    - user: $SUDO_USER

# 2. Clear asdf-related caches
asdf_clear_download_cache:
  file.absent:
    - name: /home/{{ grains['user'] }}/.asdf/downloads/

asdf_clear_tmp_cache:
  file.absent:
    - name: /tmp/asdf*

# 3. Clear Elixir/Mix caches
mix_clear_archives:
  file.absent:
    - name: /home/{{ grains['user'] }}/.mix/archives

mix_clear_hex_cache:
  file.absent:
    - name: /home/{{ grains['user'] }}/.mix/hex

# 4. Clear npm cache
npm_clear_cache:
  file.absent:
    - name: /home/{{ grains['user'] }}/.npm/_cacache

# 5. Clear Cargo cache
cargo_clear_registry_cache:
  file.absent:
    - name: /home/{{ grains['user'] }}/.cargo/registry/cache

cargo_clear_git_cache:
  file.absent:
    - name: /home/{{ grains['user'] }}/.cargo/git
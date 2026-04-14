# NEXT_STEPS

1. Immediate next action: Watch `journalctl --user -u ambientops-pulse -f` for one full memory-pressure cycle.
2. Follow-up action: Confirm A2ML envelope growth in `/home/hyper/.local/share/ambientops/pulse/pulse-events.a2ml` under both warning and recovery events.
3. Validation action: Run `~/.local/bin/emergency-room pulse --doctor --state-path ~/.local/share/ambientops/pulse/state.json --a2ml-log-path ~/.local/share/ambientops/pulse/pulse-events.a2ml` in your normal desktop session.
4. Handover/closure action: If stable, proceed with `verify maintenance /var/mnt/eclipse/repos/ambientops`.
5. Timed review action (48h): At `2026-04-14 23:53:06 BST`, verify reminder execution with `systemctl --user status ambientops-pulse-48h-review.service --no-pager`, then rerun `journalctl --user -u ambientops-pulse --since '48 hours ago' --no-pager` and review `/home/hyper/.local/share/ambientops/pulse/pulse-events.a2ml`.

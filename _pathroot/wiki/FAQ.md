# Frequently Asked Questions

*Because everyone starts somewhere, and some of us start further away than others.*

---

## Basic Concepts

### What is `_pathroot` and why is it on my C: drive?

`_pathroot` is a file that tells your system where the devtools live. It's like a treasure map with only one clue:

> "Go to C:\devtools."

Any script or tool can read this file and instantly know where to find the good stuff—your binaries, configs, logs, and more.

---

### What is `_envbase` and why is it inside C:\devtools?

`_envbase` is the local brain of your devtools environment. It contains metadata like:

```json
{
  "env": "devtools",
  "profile": "default",
  "platform": "windows"
}
```

This helps tools know what kind of environment they're in—like whether it's Windows, WSL, or a test profile.

---

### Why do we need both `_pathroot` and `_envbase`?

Because one tells you **where** you are (`_pathroot`), and the other tells you **what** you are (`_envbase`).

| Marker | Analogy |
|--------|---------|
| `_pathroot` | GPS coordinates |
| `_envbase` | Weather report |

---

## Troubleshooting

### What happens if I delete `_pathroot`?

Your tools will get lost. Scripts won't know where to look. Your Head of DevOps will sigh audibly.

**Just don't do it.**

If you did, recreate it with:

```batch
echo C:\devtools > C:\_pathroot
```

---

### What happens if I delete `_envbase`?

Your tools will still find the devtools root, but they won't know what kind of environment they're in.

It's like waking up in a hotel room with no idea what city you're in.

---

## Customization

### Can I rename `_pathroot` to something cooler?

You **can**, but you'll break everything unless you update all your scripts to look for the new name.

Stick with `_pathroot`. It's boring, but it works.

---

### Can I have multiple `_envbase` files?

Yes, but only if your tooling supports it. You could use:

- `_envbase.default`
- `_envbase.test`
- `_envbase.wsl`

Then switch between them with a script. But keep one active at a time unless you like chaos.

---

### Can I move C:\devtools somewhere else?

Yes, but you **must** update `C:\_pathroot` to point to the new location.

Otherwise, your tools will be looking in the wrong place like a dog sniffing the wrong tree.

```batch
:: Move devtools to D:\mytools
move C:\devtools D:\mytools
echo D:\mytools > C:\_pathroot
```

---

## Advanced Topics

### How does this work with WSL?

From WSL, you can access Windows paths via `/mnt/c/`:

```bash
# Read Windows _pathroot from WSL
cat /mnt/c/_pathroot
```

For native Linux environments, you'd create:

```bash
# Linux-native _pathroot
echo "/opt/devtools" | sudo tee /_pathroot
```

---

### Can I use registry keys instead of files?

You could, but files are:

- More portable
- Easier to backup/version
- Visible in file explorers
- Cross-platform compatible

Registry keys would tie you to Windows-only tooling.

---

### How do I integrate with RapidEE?

RapidEE can read `_pathroot` to understand your devtools structure and help manage PATH variables. See [Integration](Integration.md) for details.

---

## Philosophy

### Why "for morons"?

Because the best documentation assumes nothing. If you can explain something to someone with zero context, you truly understand it.

Also, we've all been the moron at some point. No shame in it.

---

### Why is there a cyborg sheepdog on the cover?

Because this system is designed to rescue you from falling into bytecode hell.

And because it's funny.

And because your Head of DevOps deserves joy.

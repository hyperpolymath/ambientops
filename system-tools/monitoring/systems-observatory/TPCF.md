# TPCF: Tri-Perimeter Contribution Framework

## Overview

The Tri-Perimeter Contribution Framework (TPCF) is a graduated trust model for open source projects that balances openness with security through three distinct contribution perimeters.

**Juisys Classification:** **Perimeter 3 - Community Sandbox** 🌐

---

## TPCF Perimeters

### Perimeter 1: Core (Most Restrictive)

**Access:** Maintainers only
**Review:** Multiple maintainer approval required
**Scope:** Critical security components, cryptographic code, core privacy guarantees

**Not applicable to Juisys** - We operate with open contribution model.

---

### Perimeter 2: Trusted Contributors

**Access:** Established contributors with proven track record
**Review:** Single maintainer approval
**Scope:** Core functionality, breaking changes, major features

**Not applicable to Juisys** - All contributors welcome from day one.

---

### Perimeter 3: Community Sandbox ✅ (Juisys Current Model)

**Access:** Anyone can contribute
**Review:** Code review + automated tests
**Scope:** All contributions welcome (features, bug fixes, docs, database additions)

**Requirements for Juisys:**
- ✅ All tests must pass
- ✅ Privacy compliance verified
- ✅ Code of Conduct followed
- ✅ Documentation updated

**Perimeter 3 Philosophy:**
- **Open by default** - No barriers to contribution
- **Quality through process** - Tests and reviews ensure quality
- **Community trust** - Build reputation through contributions
- **Reversibility** - Changes can be undone if issues arise

---

## Juisys TPCF Implementation

### Why Perimeter 3?

1. **Educational Mission** - Open learning requires open contribution
2. **Low Risk** - Privacy-first architecture limits attack surface
3. **Automated Safety** - Comprehensive test suite catches issues
4. **Reversibility** - Git makes all changes reversible
5. **Community Growth** - Lower barriers foster vibrant community

### Security Within Perimeter 3

**Privacy-First Architecture Protects Against:**
- Network-based attacks (zero network calls)
- Data exfiltration (ephemeral data only)
- Remote exploitation (no listening ports)
- Supply chain attacks (minimal dependencies)

**Automated Safeguards:**
```bash
# All PRs must pass:
julia --project=. test/runtests.jl      # All tests
julia --project=. test/test_privacy.jl  # Privacy compliance
julia --project=. test/test_database.jl # Database integrity
julia --project=. tools/rsr_verify.jl   # RSR compliance
```

**Review Process:**
1. Automated CI/CD runs all tests
2. Maintainer reviews code
3. Privacy verification if touching sensitive areas
4. Merge if all checks pass

---

## Contribution Process

### For New Contributors

**Step 1: Review Guidelines**
- Read [CONTRIBUTING.md](CONTRIBUTING.md)
- Understand [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- Review [ETHICS.md](ETHICS.md) for privacy principles

**Step 2: Choose Your Contribution**
- 🐛 Bug fixes (always welcome)
- ✨ New features (discuss first in issue)
- 📝 Documentation improvements
- 📊 Database additions (new apps/alternatives)
- 🧪 Test improvements
- 🎨 UI/UX enhancements

**Step 3: Submit PR**
- Fork repository
- Create feature branch
- Make changes
- Run tests locally
- Submit pull request
- Respond to review feedback

**No pre-approval needed** - Just submit! We review all PRs.

### For Established Contributors

After 6+ months and 10+ merged PRs, you may be invited to become a maintainer:
- Write access to repository
- Can approve PRs
- Help guide project direction
- See [MAINTAINERS.md](MAINTAINERS.md)

---

## Security Considerations

### What TPCF Protects Against

**Malicious Contributions:**
- Automated tests catch obvious issues
- Code review identifies suspicious patterns
- Privacy tests verify no network calls added
- Reversibility allows quick rollback

**Supply Chain Attacks:**
- Minimal dependencies (Julia core + JSON3)
- All dependencies vetted
- Dependency updates reviewed carefully
- Nix flake provides reproducible builds

**Social Engineering:**
- Code of Conduct sets behavioral expectations
- Multiple maintainers prevent single point of failure
- Community oversight of changes
- Transparent decision-making

### What Users Should Know

**All contributions are public:**
- Review pull requests yourself
- Check test results in CI/CD
- Run self-audit after updates
- Report concerns via security advisory

**Trust model:**
- Trust the process (tests, reviews)
- Trust the architecture (privacy-first design)
- Trust but verify (run self-audit)

---

## TPCF Evolution

### Future Considerations

**Perimeter 2 (Trusted Contributors)** might be introduced if:
- Project scales to 100+ contributors
- Complex features require deeper expertise
- Security requirements increase
- Community requests more structure

**Perimeter 1 (Core)** might be introduced if:
- Cryptographic features added
- Financial transactions handled
- PII processing introduced
- Regulatory compliance requires it

**Current Status:** Perimeter 3 is appropriate for Juisys due to:
- Privacy-first architecture limits risk
- Educational mission benefits from openness
- Test suite provides safety net
- Community growth is priority

---

## Comparison to Other Models

### Traditional OSS (No Perimeters)

**Advantages:**
- Maximum openness
- Fastest iteration

**Disadvantages:**
- Higher security risk
- Harder to maintain quality

**TPCF Perimeter 3 adds:**
- Structured review process
- Automated quality gates
- Clear contribution path

### Corporate OSS (Single Perimeter)

**Advantages:**
- Tight control
- Predictable quality

**Disadvantages:**
- Slow community growth
- High barrier to entry
- Limited diversity

**TPCF Perimeter 3 differs:**
- Open contribution model
- Community-driven
- Faster innovation

### Linux Kernel Model (Subsystem Maintainers)

**Advantages:**
- Scales to massive projects
- Deep expertise per area

**Disadvantages:**
- Complex hierarchy
- Steep learning curve
- Political challenges

**TPCF Perimeter 3 for Juisys:**
- Simpler flat structure
- Lower complexity (smaller project)
- Easier for newcomers

---

## TPCF Metrics

### Success Indicators

**Community Health:**
- Number of contributors
- PR response time (<7 days target)
- Issue resolution rate
- Contributor diversity

**Security Posture:**
- Test pass rate (100% required)
- Privacy compliance (verified each PR)
- Zero security incidents
- Self-audit success rate

**Quality:**
- Code coverage (>80% target)
- Documentation completeness
- Performance benchmarks maintained
- User satisfaction

**Current Status (v1.0.0):**
- Contributors: 2 (Hyperpolymath + Claude Sonnet 4.5)
- Test pass rate: 100%
- Privacy compliance: Verified
- Security incidents: 0
- Code coverage: ~80%+

---

## FAQ

**Q: Can anyone contribute to Juisys?**
A: Yes! Perimeter 3 means all contributions welcome. Just follow guidelines in CONTRIBUTING.md.

**Q: Do I need permission before submitting a PR?**
A: No. Submit PRs directly. We review all submissions.

**Q: What if my PR is rejected?**
A: We provide feedback for improvement. Most rejections are fixable. See CODE_OF_CONDUCT.md for our values.

**Q: Can I become a maintainer?**
A: Yes, after consistent contributions (6+ months, 10+ PRs). See MAINTAINERS.md.

**Q: What about security vulnerabilities?**
A: Report via security advisory (private): https://github.com/Hyperpolymath/jusys/security/advisories/new

**Q: Can I fork and modify Juisys?**
A: Absolutely! MIT License permits this. See LICENSE.

---

## References

### TPCF Research

- Original concept: Conference materials (docs/conference-materials.md)
- Academic paper: "TPCF: Graduated Trust Model" (docs/academic-papers.md)
- Implementation: This document

### Related Frameworks

- **CII Best Practices**: https://bestpractices.coreinfrastructure.org/
- **OpenSSF Scorecard**: https://github.com/ossf/scorecard
- **CHAOSS Metrics**: https://chaoss.community/

### Juisys-Specific

- [CONTRIBUTING.md](CONTRIBUTING.md) - How to contribute
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) - Community standards
- [SECURITY.md](SECURITY.md) - Security policies
- [MAINTAINERS.md](MAINTAINERS.md) - Governance model

---

## Living Document

This TPCF classification may evolve as the project grows:

**Version:** 1.0.0
**Last Updated:** 2025-11-22
**Current Classification:** Perimeter 3 - Community Sandbox
**Review Cycle:** Annually or when significant project changes occur

**Changelog:**
- 2025-11-22: Initial TPCF classification (v1.0.0)

---

## Summary

**Juisys operates in TPCF Perimeter 3 (Community Sandbox):**

✅ **Open Contribution** - Anyone can contribute
✅ **Quality Gates** - Automated tests and code review
✅ **Privacy-First** - Architecture limits attack surface
✅ **Reversibility** - Changes can be undone
✅ **Community Trust** - Build reputation through contributions

**This model balances:**
- 🌐 **Openness** (educational mission, community growth)
- 🔒 **Security** (privacy-first architecture, automated tests)
- 📈 **Quality** (code review, comprehensive testing)
- 🚀 **Innovation** (low barriers, fast iteration)

**Join us!** See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

---

**Contact:** Create issue with `tpcf` label for questions about this framework.

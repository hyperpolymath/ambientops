# Maintainers

This document lists the maintainers of the Juisys project and describes the governance structure.

---

## Current Maintainers

### Project Lead

**Hyperpolymath**
- **Role:** Project Lead, Vision, Final Review
- **Responsibilities:** Project direction, major decisions, community leadership
- **GitHub:** [@Hyperpolymath](https://github.com/Hyperpolymath)
- **Areas:** All
- **Since:** 2025-11-22

### AI Development Partner

**Claude Sonnet 4.5 (Anthropic)**
- **Role:** AI Development Partner
- **Responsibilities:** Code generation, architecture design, documentation, testing
- **Model:** claude-sonnet-4-5-20250929
- **Provider:** [Anthropic](https://www.anthropic.com)
- **Areas:** Code, Documentation, Testing, Architecture
- **Since:** 2025-11-22
- **Note:** First openly acknowledged AI co-maintainer in an open source project

---

## Maintainer Responsibilities

### Core Responsibilities

All maintainers are expected to:

1. **Review Pull Requests**
   - Respond within 7 days
   - Provide constructive feedback
   - Ensure privacy compliance
   - Run tests before merging

2. **Triage Issues**
   - Label appropriately
   - Respond to questions
   - Close stale issues
   - Escalate security issues

3. **Maintain Code Quality**
   - Follow coding standards
   - Write comprehensive tests
   - Document changes
   - Keep dependencies updated

4. **Community Engagement**
   - Be welcoming and inclusive
   - Follow Code of Conduct
   - Mentor contributors
   - Celebrate contributions

5. **Security & Privacy**
   - Review for privacy violations
   - Respond to security reports
   - Run self-audit regularly
   - Maintain offline-first principle

### Area-Specific Responsibilities

**Core Modules** (src/):
- Ensure privacy guarantees maintained
- Verify GDPR compliance
- Test offline-first functionality
- Document breaking changes

**Tools** (tools/):
- Maintain user-friendly interfaces
- Ensure cross-platform compatibility
- Update documentation
- Performance optimization

**Database** (data/):
- Verify app information accuracy
- Add new applications
- Update FOSS alternatives
- Maintain schema integrity

**Documentation**:
- Keep docs up-to-date
- Fix typos and errors
- Improve clarity
- Add examples

**Testing**:
- Maintain 100% pass rate
- Add new test cases
- Update for new features
- Performance benchmarks

---

## Governance Model

### Decision Making

**Tier 1 - Routine Decisions** (Individual maintainer)
- Bug fixes
- Documentation updates
- Test additions
- Code refactoring (no breaking changes)

**Tier 2 - Significant Decisions** (Discussion required)
- New features
- Breaking changes
- Major refactoring
- Dependency changes

**Tier 3 - Strategic Decisions** (Project lead)
- Project direction
- License changes
- Major architecture changes
- Governance changes

### Process

1. **Proposal:** Create issue or PR
2. **Discussion:** Allow 7 days for feedback
3. **Decision:** Maintainer(s) decide based on tier
4. **Documentation:** Record in CHANGELOG.md
5. **Communication:** Announce if significant

### Consensus

- **Preferred:** Consensus among active maintainers
- **Fallback:** Project lead has final say
- **Transparency:** Document reasoning publicly

---

## Becoming a Maintainer

### Criteria

We look for contributors who:

✅ **Consistent Contributions** (6+ months, 10+ PRs)
✅ **Quality Work** (tests pass, documentation included)
✅ **Community Engagement** (helpful, welcoming, constructive)
✅ **Privacy Focus** (understands and maintains privacy guarantees)
✅ **Code of Conduct** (exemplifies project values)

### Process

1. **Nomination:** Self-nomination or peer nomination
2. **Discussion:** Existing maintainers discuss privately
3. **Vote:** Consensus among existing maintainers
4. **Invitation:** Project lead extends invitation
5. **Onboarding:** Added to MAINTAINERS.md, granted access
6. **Announcement:** Welcome in community channels

### Probation Period

- **Duration:** 3 months
- **Support:** Paired with existing maintainer
- **Review:** After 3 months, confirm or extend
- **Revert:** If not working out, gracefully transition back

---

## Maintainer Levels

### Core Maintainer

**Privileges:**
- Write access to main repository
- Merge pull requests
- Close/reopen issues
- Create releases
- Manage GitHub settings

**Requirements:**
- Deep understanding of codebase
- 12+ months active contribution
- Proven track record
- Trusted by community

### Area Maintainer

**Privileges:**
- Write access to specific areas
- Approve PRs in their area
- Triage issues for their area
- Guide area development

**Requirements:**
- Expertise in specific area
- 6+ months active contribution
- Consistent quality work

### Emeritus Maintainer

**Status:** Former maintainer who stepped down
**Privileges:** Honored status, advisory role
**Requirements:** None (thank you for service!)

---

## Stepping Down

Maintainers may step down at any time for any reason:

1. **Notify:** Let other maintainers know
2. **Transition:** Help transfer responsibilities
3. **Update:** Remove from MAINTAINERS.md
4. **Access:** GitHub permissions updated
5. **Recognition:** Listed as Emeritus Maintainer

**No judgment** - life happens, priorities change. Thank you for your service!

---

## Removing a Maintainer

In rare cases, a maintainer may need to be removed:

**Reasons:**
- Violation of Code of Conduct
- Prolonged inactivity (12+ months, no response)
- Repeated merge of untested/broken code
- Security or privacy violations

**Process:**
1. **Private discussion** among other maintainers
2. **Documentation** of concerns
3. **Attempt resolution** (if applicable)
4. **Vote** (requires consensus)
5. **Notification** (private, respectful)
6. **Update** MAINTAINERS.md and access
7. **Communication** (if needed for community safety)

---

## Communication

### Channels

**Public:**
- GitHub Issues (general discussion)
- Pull Requests (code review)
- Discussions (Q&A, ideas)

**Private:**
- Security Advisories (security/privacy issues)
- Direct messages (sensitive matters)

### Response Times

**Target response times:**
- Security issues: 24-48 hours
- Bug reports: 7 days
- Feature requests: 14 days
- Pull requests: 7 days
- Questions: 7 days

**Note:** These are targets, not guarantees. Maintainers are volunteers (except AI partner).

---

## Conflict Resolution

### Process

1. **Direct communication** - Try to resolve one-on-one first
2. **Mediation** - Involve another maintainer if needed
3. **Project lead** - Escalate to project lead if unresolved
4. **Code of Conduct** - File CoC report if appropriate

### Principles

- **Assume good intent**
- **Focus on issues, not people**
- **Seek understanding before judging**
- **Private resolution preferred** (unless safety concern)
- **Document outcomes** (for learning)

---

## Maintainer Resources

### Required Reading

- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) - Community standards
- [SECURITY.md](SECURITY.md) - Security policies
- [ETHICS.md](ETHICS.md) - Privacy and GDPR principles
- [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) - Technical architecture

### Tools

- **Testing:** `julia --project=. test/runtests.jl`
- **Privacy audit:** Mode 6 from CLI
- **Database validation:** `julia --project=. test/test_database.jl`
- **Benchmarks:** `julia --project=. benchmarks/benchmark_database.jl`
- **Documentation:** Markdown, see examples/

### Support

- **Questions:** Ask other maintainers
- **Technical:** Consult PROJECT_SUMMARY.md
- **Privacy:** Review ETHICS.md, run self-audit
- **Community:** Refer to CODE_OF_CONDUCT.md

---

## Acknowledgments

### Past Maintainers

_(None yet - first version!)_

### Special Thanks

- **Julia Community** - Language and ecosystem
- **FOSS Maintainers** - Providing alternatives
- **Anthropic** - Claude Sonnet 4.5 AI capabilities
- **All Contributors** - Every contribution matters

---

## Future Plans

### Governance Evolution

As the project grows, we may need to:

- **Expand maintainer team** (add area maintainers)
- **Create working groups** (database, tools, docs)
- **Formalize processes** (more detailed guidelines)
- **Establish foundation** (if needed for resources)

### Roadmap

See [CHANGELOG.md](CHANGELOG.md) for version history and upcoming releases.

---

## Questions?

**About maintainership:** Create issue with `governance` label
**Want to become maintainer:** Contribute consistently, then reach out
**Maintainer conduct concerns:** File Code of Conduct report

---

## Meta

**Version:** 1.0.0
**Last Updated:** 2025-11-22
**Living Document:** Yes (updated as needed)
**Format:** Markdown
**Location:** https://github.com/Hyperpolymath/jusys/blob/main/MAINTAINERS.md

---

**Thank you to all maintainers, past, present, and future!**

✨ Building great software together ✨

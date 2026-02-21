# Tri-Perimeter Contribution Framework (TPCF)

## Overview

The Tri-Perimeter Contribution Framework (TPCF) is a graduated trust model that balances openness with security. It defines three concentric perimeters of access, each with different requirements and privileges.

## The Three Perimeters

### Perimeter 3: Community Sandbox (Public)

**Access Level**: Open to everyone
**Trust Level**: None required
**Default Perimeter**: YES - This is where new contributors start

**What's Included:**
- Public repository access
- Issue submission
- Pull request submission
- Discussion participation
- Documentation improvements
- Test contributions
- Bug reports
- Feature requests

**Requirements:**
- Follow Code of Conduct
- Sign commits (optional but recommended)
- Adhere to contribution guidelines

**Review Process:**
- Standard PR review
- 2 maintainer approvals for code changes
- 1 maintainer approval for docs

**Purpose:**
- Welcome new contributors
- Lower barrier to entry
- Enable community growth
- Demonstrate competence

### Perimeter 2: Proving Grounds (Private/Restricted)

**Access Level**: Trusted contributors
**Trust Level**: Demonstrated competence required
**How to Get Here**: Quality contributions from Perimeter 3

**What's Included:**
- Advanced feature development
- Architecture decisions
- Security-adjacent code
- Performance-critical paths
- Infrastructure changes

**Requirements:**
- 10+ merged PRs from Perimeter 3
- 3+ months active contribution
- Demonstrated understanding of codebase
- No Code of Conduct violations
- Nomination by existing Perimeter 2/1 member

**Privileges:**
- Faster PR review
- Direct commit to development branches
- Access to pre-release features
- Invitation to planning meetings
- Mentor new contributors

**Review Process:**
- 1 maintainer approval for most changes
- Self-merge allowed for minor changes
- Monthly performance review

**Purpose:**
- Develop trusted contributor base
- Reduce review bottlenecks
- Enable faster iteration
- Prepare for maintainer role

### Perimeter 1: Inner Sanctum (Private)

**Access Level**: Core maintainers only
**Trust Level**: Full trust required
**How to Get Here**: Proven track record in Perimeter 2

**What's Included:**
- Security-critical code
- Cryptographic implementations
- Authentication/authorization
- CI/CD secrets management
- Release management
- Vulnerability handling

**Requirements:**
- 6+ months in Perimeter 2
- 50+ merged PRs
- Security awareness demonstrated
- Consensus approval by all existing Perimeter 1 members
- Background in security preferred

**Privileges:**
- Full repository access
- Manage releases
- Security advisory access
- Infrastructure access
- Manage team membership
- Final decision authority

**Responsibilities:**
- Security vulnerability response
- Release coordination
- Team leadership
- Strategic direction
- Community health

**Purpose:**
- Protect critical systems
- Ensure security practices
- Maintain project quality
- Provide leadership

## Advancement Process

### Perimeter 3 → Perimeter 2

1. **Self-Nomination** or **Peer Nomination**
   - Submit nomination issue
   - Link to contributions
   - Explain interest

2. **Review**
   - Existing Perimeter 2/1 members review
   - Check contribution quality
   - Verify Code of Conduct adherence

3. **Vote**
   - Simple majority of Perimeter 2/1 members
   - 7-day voting period
   - Public announcement if approved

4. **Onboarding**
   - Access to Perimeter 2 resources
   - Mentorship assigned
   - Introduction to team

### Perimeter 2 → Perimeter 1

1. **Nomination**
   - Must be nominated by existing Perimeter 1 member
   - Cannot self-nominate

2. **Review**
   - All Perimeter 1 members review
   - Security background check
   - Interview process

3. **Vote**
   - **Consensus required** (all Perimeter 1 must approve)
   - 14-day voting period
   - Public announcement if approved

4. **Onboarding**
   - Security training
   - Infrastructure access
   - Maintainer responsibilities

## Demotion/Removal

### Voluntary Step-Down
- Notify team with 2 weeks notice preferred
- Transfer responsibilities
- Move to emeritus status (maintains recognition)

### Involuntary Removal
- Code of Conduct violations
- Security breaches
- Sustained inactivity (6+ months)
- Loss of trust

**Process:**
1. Private discussion among peers
2. Attempt to resolve
3. Vote if needed (2/3 majority)
4. Notification
5. Access revocation
6. Public announcement (if appropriate)

## Benefits by Perimeter

| Benefit | P3 | P2 | P1 |
|---------|----|----|---|
| Public recognition | ✓ | ✓ | ✓ |
| Listed as contributor | ✓ | ✓ | ✓ |
| Issue/PR submission | ✓ | ✓ | ✓ |
| Write access (dev branches) | ✗ | ✓ | ✓ |
| Write access (main) | ✗ | ✗ | ✓ |
| Security advisory access | ✗ | ✗ | ✓ |
| Release management | ✗ | ✗ | ✓ |
| Team voting rights | ✗ | ✓ | ✓ |
| Mentorship opportunities | ✗ | ✓ | ✓ |
| Strategic decisions | ✗ | ✗ | ✓ |

## Emotional Safety

TPCF is designed to reduce anxiety and increase experimentation:

### For Perimeter 3 (New Contributors)
- **Low stakes**: Mistakes are safe and reversible
- **Clear path**: Know how to advance
- **Supported**: Mentorship available
- **Welcome**: All are encouraged to contribute

### For Perimeter 2 (Trusted Contributors)
- **Responsibility**: Increased trust, but still protected
- **Growth**: Path to leadership clear
- **Feedback**: Regular performance feedback
- **Recognition**: Public acknowledgment of contributions

### For Perimeter 1 (Maintainers)
- **Protected**: Critical systems isolated
- **Distributed**: No single point of failure
- **Sustainable**: Can step down without guilt
- **Empowered**: Final authority on security

## TPCF Metrics

We track:
- **Perimeter distribution**: How many contributors at each level
- **Advancement rate**: How quickly people move between perimeters
- **Contribution quality**: Quality trends by perimeter
- **Emotional temperature**: Anxiety/confidence surveys
- **Diversity**: Demographic representation at each level

## Comparison to Traditional Models

| Model | Open Contribution | Security | Graduated Trust | Emotional Safety |
|-------|-------------------|----------|-----------------|------------------|
| Fully Open (All can commit) | ✓ | ✗ | ✗ | ~~ |
| Fully Closed (Maintainers only) | ✗ | ✓ | ✗ | ✗ |
| Simple Fork-PR Model | ✓ | ~ | ✗ | ~ |
| **TPCF** | **✓** | **✓** | **✓** | **✓** |

## Current Project Status

**Broad Spectrum is currently at Perimeter 3 (Community Sandbox)**

This means:
- ✅ All are welcome to contribute
- ✅ Standard PR review process
- ✅ No access restrictions for code
- ✅ Path to Perimeter 2 clearly defined

As the project matures:
- Security-critical features → Perimeter 1
- Performance-critical paths → Perimeter 2
- General features → Perimeter 3

## FAQs

**Q: Why three perimeters instead of two?**
A: Two perimeters (public/private) create a sharp boundary. Three creates gradual progression and reduces anxiety about "am I good enough?"

**Q: Can I skip Perimeter 2 and go straight to Perimeter 1?**
A: No. The gradual progression is intentional to build trust and experience.

**Q: What if I disagree with the perimeter I'm assigned?**
A: Open a discussion issue. We're happy to explain the reasoning and discuss concerns.

**Q: Is this just gatekeeping?**
A: No. Perimeter 3 is completely open. This protects critical systems while maintaining openness.

**Q: How is this different from "committer" status?**
A: TPCF is more nuanced with three levels and explicit advancement criteria.

**Q: Can organizations have different perimeter policies?**
A: Yes. TPCF is a framework. Adapt it to your needs.

## Resources

- **Code of Conduct**: CODE_OF_CONDUCT.md (includes TPCF section)
- **Contribution Guide**: CONTRIBUTING.md
- **Maintainer Guide**: MAINTAINERS.md
- **Security Policy**: SECURITY.md

## References

TPCF is inspired by:
- Apache Software Foundation's committership model
- Rust's trust levels
- Linux kernel's maintainer hierarchy
- Contributor Covenant's governance models

Original TPCF specification: rhodium-minimal example repository

---

**Questions?** Open a discussion or contact maintainers@hyperpolymath.org

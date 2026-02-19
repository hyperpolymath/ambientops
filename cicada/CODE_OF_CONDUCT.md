# Code of Conduct - CIcaDA

## Our Pledge

In the interest of fostering an open and welcoming environment, we as contributors and maintainers pledge to make participation in our project and our community a harassment-free experience for everyone, regardless of age, body size, disability, ethnicity, sex characteristics, gender identity and expression, level of experience, education, socio-economic status, nationality, personal appearance, race, religion, or sexual identity and orientation.

## Community Code Contribution Principles (CCCP)

This project follows the **Community Code Contribution Principles (CCCP)**, emphasizing:

### Emotional Safety
- **Reversibility**: All contributions are reversible. Mistakes are learning opportunities.
- **No Blame**: Focus on solutions, not fault-finding
- **Psychological Safety**: Safe to ask questions, admit mistakes, propose ideas
- **Anxiety Reduction**: Clear processes, helpful feedback, supportive community

### Technical Excellence
- **Quality Over Speed**: Take time to do it right
- **Security First**: Cryptographic code requires extra care
- **Test Coverage**: All code must include tests
- **Documentation**: Explain the "why," not just the "what"

### Community Values
- **Inclusive Language**: Welcoming to all backgrounds and experience levels
- **Constructive Feedback**: Critique code, not people
- **Knowledge Sharing**: Teaching is as valuable as coding
- **Attribution**: Credit all contributions appropriately

## Our Standards

### Positive Behavior

- Using welcoming and inclusive language
- Being respectful of differing viewpoints and experiences
- Gracefully accepting constructive criticism
- Focusing on what is best for the community
- Showing empathy towards other community members
- Asking for help when needed
- Offering help to others
- Acknowledging and learning from mistakes

### Unacceptable Behavior

- The use of sexualized language or imagery and unwelcome sexual attention or advances
- Trolling, insulting/derogatory comments, and personal or political attacks
- Public or private harassment
- Publishing others' private information without explicit permission
- Blaming individuals for mistakes rather than fixing the problem
- Dismissing security concerns or vulnerabilities
- Other conduct which could reasonably be considered inappropriate in a professional setting

## Tri-Perimeter Contribution Framework (TPCF)

This project operates under **TPCF Perimeter 3: Community Sandbox**

### Perimeter 3: Open Contribution
- **Who**: All community members
- **Access**: Public repository, open issues, pull requests
- **Process**: Submit PR → Review → Merge (with maintainer approval)
- **Guidelines**: Follow CONTRIBUTING.md and this Code of Conduct

### Security-Critical Code (Elevated Review)
Contributions to security-critical paths require:
1. Cryptography expertise verification
2. Security review by maintainer
3. Additional testing and validation
4. Formal verification (where applicable)

Files requiring elevated review:
- `src/keygen/*.jl` - Key generation algorithms
- `src/storage/keystore.jl` - Key material handling
- `src/validation/verify.jl` - Security validation

## Our Responsibilities

Project maintainers are responsible for clarifying the standards of acceptable behavior and are expected to take appropriate and fair corrective action in response to any instances of unacceptable behavior.

Project maintainers have the right and responsibility to remove, edit, or reject comments, commits, code, wiki edits, issues, and other contributions that are not aligned to this Code of Conduct, or to ban temporarily or permanently any contributor for other behaviors that they deem inappropriate, threatening, offensive, or harmful.

## Scope

This Code of Conduct applies within all project spaces, and it also applies when an individual is representing the project or its community in public spaces. Examples of representing a project or community include using an official project e-mail address, posting via an official social media account, or acting as an appointed representative at an online or offline event.

## Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported by contacting the project team at conduct@hyperpolymath.org. All complaints will be reviewed and investigated and will result in a response that is deemed necessary and appropriate to the circumstances. The project team is obligated to maintain confidentiality with regard to the reporter of an incident.

### Enforcement Guidelines

1. **Correction**: Private, written warning with clarity about violation
2. **Warning**: Public warning with consequences for continued behavior
3. **Temporary Ban**: Temporary ban from project interaction
4. **Permanent Ban**: Permanent ban from project community

## Emotional Temperature Monitoring

We track community health through:
- Response time to issues/PRs (target: <48 hours for acknowledgment)
- Tone of code reviews (constructive vs. critical)
- Contributor retention rates
- First-time contributor experience

If you feel emotionally unsafe or anxious, please reach out to conduct@hyperpolymath.org confidentially.

## Attribution

This Code of Conduct is adapted from:
- [Contributor Covenant](https://www.contributor-covenant.org), version 2.0
- Community Code Contribution Principles (CCCP)
- Rhodium Standard Repository (RSR) Framework
- Emotional Temperature Metrics research

## Contact

- General conduct issues: conduct@hyperpolymath.org
- Security concerns: security@hyperpolymath.org
- Maintainer team: See MAINTAINERS.md

## License

This Code of Conduct is licensed under CC BY 4.0.
